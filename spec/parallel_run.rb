require 'json'
require 'fileutils'
require 'set'

module AresMUSH
  # CUSTOM CODE ADD FOR EMBLEM OF EA: the db suite in parallel (`rake spec:db:parallel[8]`).
  #
  # A serial run takes about three hours, half of it in eighteen play-through examples of up to 12 minutes
  # each. Here each worker is an ordinary rspec on its own Redis database (14, 13, ... - never 0, the game's,
  # and never 15, a serial run's, so `rake spec:unit` or `spec:db` can run alongside). The examples are
  # shared out longest first, by the times the last run recorded: a file stays whole on one worker unless
  # it is long, and a long file's examples are shared out one by one (`SPEC_IDS_FILE`, read in
  # spec_helper.rb). The workers' results are merged into one summary, and their times kept for next time.
  module SpecParallel
    PATTERN = "spec/**/*_specs.rb,spec/**/*_spec.rb,plugins/**/*_specs.rb,plugins/**/*_spec.rb".freeze
    MAX_WORKERS = 14
    # Redis has 16 databases: 0 is the game's, 15 a serial run's. Worker n (from 0) uses 14 - n.
    def self.database(worker)
      14 - worker
    end

    # What one example is filed under in the times kept: its file and full description. An ID is a
    # position, and moves when an example is added above it.
    def self.key(example)
      "#{example['file_path']}\t#{example['full_description']}"
    end

    # The times in an rspec JSON report, by key.
    def self.timings_from(report)
      Array(report['examples']).to_h { |example| [ key(example), example['run_time'].to_f ] }
    end

    # How long an example is expected to take: its last time, or for one never timed, the middle of the
    # times known.
    def self.estimates(examples, timings)
      known = examples.map { |example| timings[key(example)] }.compact.sort
      guess = known.empty? ? 1.0 : known[known.size / 2]

      examples.to_h { |example| [ example['id'], timings[key(example)] || guess ] }
    end

    # The examples shared between workers: an array of shares, each { 'ids', 'files', 'seconds' }. A file
    # longer than half of one worker's fair share is shared out by example; any other stays whole. Each
    # piece goes to the least loaded worker, longest first, and a worker given nothing is left out.
    def self.plan(examples, timings, workers)
      raise ArgumentError, "between 1 and #{MAX_WORKERS} workers, not #{workers}" unless workers.between?(1, MAX_WORKERS)

      seconds = estimates(examples, timings)
      split_over = seconds.values.sum / (2.0 * workers)

      pieces = examples.group_by { |example| example['file_path'] }.flat_map do |file, list|
        whole = list.sum { |example| seconds[example['id']] }
        parts = whole > split_over && list.size > 1 ? list.map { |example| [ example ] } : [ list ]

        parts.map { |part| { 'file' => file, 'ids' => part.map { |example| example['id'] }, 'seconds' => part.sum { |example| seconds[example['id']] } } }
      end

      shares = Array.new(workers) { { 'ids' => [], 'files' => [], 'seconds' => 0.0 } }

      pieces.sort_by { |piece| [ -piece['seconds'], piece['ids'].first ] }.each do |piece|
        share = shares.min_by.with_index { |one, index| [ one['seconds'], index ] }
        share['ids'].concat(piece['ids'])
        share['files'] |= [ piece['file'] ]
        share['seconds'] += piece['seconds']
      end

      shares.reject { |share| share['ids'].empty? }
    end

    # The workers' results as one: each worker is { 'worker', 'database', 'status', 'log', 'report' },
    # its report the parsed JSON or nil if it wrote none. Every example listed must have been run.
    def self.merge(results, listed_ids)
      examples = results.flat_map { |result| Array(result['report'] && result['report']['examples']).map { |one| one.merge('worker' => result['worker']) } }
      broken = results.select do |result|
        result['report'].nil? || result['report'].dig('summary', 'errors_outside_of_examples_count').to_i.positive? ||
          (result['status'] != 0 && examples.none? { |one| one['worker'] == result['worker'] && one['status'] == 'failed' })
      end

      { 'examples' => examples.size,
        'failures' => examples.select { |one| one['status'] == 'failed' },
        'pending' => examples.count { |one| one['status'] == 'pending' },
        'missing' => listed_ids - examples.map { |one| one['id'] },
        'broken' => broken,
        'passed' => broken.empty? && examples.none? { |one| one['status'] == 'failed' } && (listed_ids - examples.map { |one| one['id'] }).empty? }
    end

    # The summary, as rspec's own reads.
    def self.summary_lines(merged, minutes)
      lines = []

      merged['failures'].each_with_index do |one, index|
        exception = one['exception'] || {}
        lines << "#{index + 1}) #{one['full_description']}"
        lines << "   #{one['file_path']}:#{one['line_number']} (worker #{one['worker']})"
        lines.concat("#{exception['class']}: #{exception['message']}".lines.first(8).map { |line| "   #{line.chomp}" })
        lines << ""
      end

      merged['broken'].each do |result|
        lines << "Worker #{result['worker']} (database #{result['database']}) stopped with status #{result['status']} " \
                 "or errors outside examples. See #{result['log']}."
      end
      lines << "Not run: #{merged['missing'].size} examples listed, e.g. #{merged['missing'].first(5).join(', ')}" if merged['missing'].any?

      lines << format("Finished in %.1f minutes", minutes)
      lines << "#{merged['examples']} examples, #{merged['failures'].size} failures, #{merged['pending']} pending"
      lines
    end

    # The running part, inside the game's container from the aresmush directory.
    class Runner
      def initialize(workers, root = Dir.pwd)
        @workers = workers
        @root = root
        @dir = File.join(root, 'tmp', 'spec_parallel')
        @pids = {}
      end

      def run
        FileUtils.mkdir_p(@dir)
        lock!
        started = now
        examples = list
        timings = File.exist?(timings_path) ? JSON.parse(File.read(timings_path)) : {}
        shares = SpecParallel.plan(examples, timings, @workers)

        say "#{examples.size} examples, #{shares.size} workers#{timings.empty? ? ' (no times kept yet: shared by count)' : ''}"
        shares.each_with_index do |share, worker|
          say format("  worker %d: database %d, %d examples in %d files, about %.0f minutes",
                     worker, SpecParallel.database(worker), share['ids'].size, share['files'].size, share['seconds'] / 60)
        end

        results = work(shares, started)
        merged = SpecParallel.merge(results, examples.map { |example| example['id'] })
        keep_timings(timings, results)

        puts
        SpecParallel.summary_lines(merged, (now - started) / 60).each { |line| puts line }
        say "Logs and reports: #{@dir}"
        merged['passed']
      ensure
        stop_workers
        unlock
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def say(text)
        puts text
        $stdout.flush
      end

      def timings_path
        File.join(@dir, 'timings.json')
      end

      def lock_path
        File.join(@dir, 'lock')
      end

      # One parallel run at a time: two would share worker databases. A lock left by a run that died is
      # taken over.
      def lock!
        File.open(lock_path, File::WRONLY | File::CREAT | File::EXCL) { |file| file.write(Process.pid.to_s) }
        @locked = true
      rescue Errno::EEXIST
        holder = File.read(lock_path).to_i
        alive = holder.positive? && (Process.kill(0, holder) rescue false)
        abort "A parallel spec run (process #{holder}) is already going. Wait for it to finish." if alive

        File.delete(lock_path)
        retry
      end

      def unlock
        File.delete(lock_path) if @locked && File.exist?(lock_path)
      end

      # Every db example, from a dry run, which loads the files but runs no hooks and touches no database.
      def list
        out = File.join(@dir, 'list.json')
        ok = system({ 'SPEC_REDIS_DB' => SpecParallel.database(0).to_s },
                    'bundle', 'exec', 'rspec', '--pattern', PATTERN, '--tag', 'dbtest', '--dry-run',
                    '--format', 'json', '--out', out, :out => File.join(@dir, 'list.log'), :err => [ :child, :out ])
        abort "Listing the examples failed. See #{File.join(@dir, 'list.log')}." unless ok && File.exist?(out)

        JSON.parse(File.read(out))['examples']
      end

      def work(shares, started)
        trap_signals

        shares.each_with_index do |share, worker|
          # Absolute paths: rspec puts `spec/` before a pattern that doesn't start with it or with `/`.
          files = share['files'].map { |file| File.expand_path(file, @root) }.join(',')
          ids = File.join(@dir, "worker_#{worker}.ids")
          File.write(ids, share['ids'].join("\n") + "\n")
          File.delete(report(worker)) if File.exist?(report(worker))

          env = { 'SPEC_REDIS_DB' => SpecParallel.database(worker).to_s, 'SPEC_IDS_FILE' => ids, 'SPEC_EMPTY_AFTER' => '1' }
          @pids[Process.spawn(env, 'bundle', 'exec', 'rspec', '--pattern', files, '--tag', 'dbtest',
                              '--format', 'progress', '--format', 'json', '--out', report(worker),
                              :out => log(worker), :err => [ :child, :out ], :pgroup => true)] = worker
        end

        results = []
        until @pids.empty?
          pid, status = Process.wait2
          worker = @pids.delete(pid)
          next unless worker

          parsed = File.exist?(report(worker)) ? (JSON.parse(File.read(report(worker))) rescue nil) : nil
          counts = parsed ? parsed['summary'] : {}
          say format("worker %d done at %.1f minutes: %s examples, %s failures (%d left)", worker, (now - started) / 60,
                     counts['example_count'] || '?', counts['failure_count'] || '?', @pids.size)
          results << { 'worker' => worker, 'database' => SpecParallel.database(worker), 'status' => status.exitstatus,
                       'log' => log(worker), 'report' => parsed }
        end

        results.sort_by { |result| result['worker'] }
      end

      def report(worker)
        File.join(@dir, "worker_#{worker}.json")
      end

      def log(worker)
        File.join(@dir, "worker_#{worker}.log")
      end

      # Ctrl-C or a kill stops every worker too, rather than leaving them running on their own.
      def trap_signals
        %w{INT TERM}.each do |signal|
          Signal.trap(signal) do
            stop_workers
            exit 130
          end
        end
      end

      def stop_workers
        @pids.each_key do |pid|
          Process.kill('TERM', -pid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end
      end

      # This run's times, over the ones kept: an example a worker didn't report keeps its old time.
      def keep_timings(timings, results)
        fresh = results.map { |result| result['report'] }.compact.map { |report| SpecParallel.timings_from(report) }.reduce({}, :merge)
        File.write(timings_path, JSON.pretty_generate(timings.merge(fresh)))
      end
    end
  end
end
