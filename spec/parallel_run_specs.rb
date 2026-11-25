require "aresmush"
require_relative "parallel_run"

module AresMUSH

  # How a parallel db run shares the examples between workers, and how it merges what they report
  # (spec/parallel_run.rb). Plain data: no workers are started.
  describe "the parallel spec run" do

    def example(file, number, description = "does thing #{number}")
      { 'id' => "./#{file}[1:#{number}]", 'file_path' => "./#{file}", 'full_description' => description }
    end

    def timed(examples_and_seconds)
      examples_and_seconds.to_h { |one, seconds| [ SpecParallel.key(one), seconds ] }
    end

    describe "databases" do
      it "should give workers 14 and down, never the game's 0 or a serial run's 15" do
        used = (0...SpecParallel::MAX_WORKERS).map { |worker| SpecParallel.database(worker) }

        expect(used).to eq (1..14).to_a.reverse
      end

      it "should refuse more workers than there are databases, or none" do
        expect { SpecParallel.plan([], {}, 15) }.to raise_error(ArgumentError)
        expect { SpecParallel.plan([], {}, 0) }.to raise_error(ArgumentError)
      end
    end

    describe "sharing" do
      it "should put every example on exactly one worker" do
        examples = (1..5).flat_map { |file| (1..4).map { |number| example("f#{file}_specs.rb", number) } }
        shares = SpecParallel.plan(examples, {}, 3)

        expect(shares.flat_map { |share| share['ids'] }.sort).to eq examples.map { |one| one['id'] }.sort
      end

      it "should keep a short file whole on one worker" do
        short = (1..3).map { |number| example('short_specs.rb', number) }
        long = (1..2).map { |number| example('long_specs.rb', number) }
        times = timed(short.map { |one| [ one, 1 ] } + long.map { |one| [ one, 100 ] })

        shares = SpecParallel.plan(short + long, times, 2)
        holding = shares.select { |share| share['files'].include?('./short_specs.rb') }

        expect(holding.size).to eq 1
      end

      it "should share out a long file's examples between workers, longest first" do
        plays = (1..4).map { |number| example('plays_specs.rb', number) }
        rest = example('rest_specs.rb', 1)
        times = timed([ [ plays[0], 600 ], [ plays[1], 500 ], [ plays[2], 400 ], [ plays[3], 300 ], [ rest, 10 ] ])

        shares = SpecParallel.plan(plays + [ rest ], times, 2)

        expect(shares.map { |share| share['seconds'] }.sort).to eq [ 900.0, 910.0 ]
        expect(shares.map { |share| share['ids'].size }.sum).to eq 5
      end

      it "should guess an example never timed at the middle of the times known" do
        known = (1..3).map { |number| example('a_specs.rb', number) }
        fresh = example('b_specs.rb', 1)
        times = timed([ [ known[0], 2 ], [ known[1], 5 ], [ known[2], 9 ] ])

        expect(SpecParallel.estimates(known + [ fresh ], times)[fresh['id']]).to eq 5
        expect(SpecParallel.estimates([ fresh ], {})[fresh['id']]).to eq 1.0
      end

      it "should find a time by file and description, after the example's position moved" do
        before = example('a_specs.rb', 1, 'plays a party')
        after = example('a_specs.rb', 2, 'plays a party')

        expect(SpecParallel.estimates([ after ], timed([ [ before, 42 ] ]))[after['id']]).to eq 42
      end

      it "should leave out a worker given nothing" do
        expect(SpecParallel.plan([ example('a_specs.rb', 1) ], {}, 4).size).to eq 1
      end
    end

    describe "merging" do
      def report(examples, outside: 0)
        { 'examples' => examples, 'summary' => { 'errors_outside_of_examples_count' => outside } }
      end

      def ran(one, status = 'passed', time = 1.0)
        one.merge('status' => status, 'run_time' => time, 'line_number' => 3)
      end

      it "should pass when every listed example ran and none failed" do
        a = example('a_specs.rb', 1)
        b = example('b_specs.rb', 1)
        results = [ { 'worker' => 0, 'status' => 0, 'report' => report([ ran(a) ]) },
                    { 'worker' => 1, 'status' => 0, 'report' => report([ ran(b, 'pending') ]) } ]

        merged = SpecParallel.merge(results, [ a['id'], b['id'] ])

        expect(merged).to include('examples' => 2, 'pending' => 1, 'missing' => [], 'passed' => true)
      end

      it "should list a failure with its worker" do
        a = example('a_specs.rb', 1)
        failed = ran(a, 'failed').merge('exception' => { 'class' => 'RuntimeError', 'message' => 'boom' })
        merged = SpecParallel.merge([ { 'worker' => 3, 'status' => 1, 'report' => report([ failed ]) } ], [ a['id'] ])

        expect(merged['passed']).to be false
        expect(merged['broken']).to eq []
        expect(SpecParallel.summary_lines(merged, 2.0).join("\n")).to include('(worker 3)', 'RuntimeError: boom', '1 examples, 1 failures')
      end

      it "should fail a worker that wrote no report, or stopped with no failure to show for it" do
        a = example('a_specs.rb', 1)
        b = example('b_specs.rb', 1)
        results = [ { 'worker' => 0, 'status' => 1, 'report' => nil },
                    { 'worker' => 1, 'status' => 1, 'report' => report([ ran(b) ]) } ]

        merged = SpecParallel.merge(results, [ a['id'], b['id'] ])

        expect(merged['broken'].map { |result| result['worker'] }).to eq [ 0, 1 ]
        expect(merged['missing']).to eq [ a['id'] ]
        expect(merged['passed']).to be false
      end

      it "should fail errors outside examples, such as a file that wouldn't load" do
        a = example('a_specs.rb', 1)
        merged = SpecParallel.merge([ { 'worker' => 0, 'status' => 1, 'report' => report([ ran(a) ], :outside => 1) } ], [ a['id'] ])

        expect(merged['passed']).to be false
      end

      it "should keep each example's time by file and description" do
        a = example('a_specs.rb', 1)

        expect(SpecParallel.timings_from(report([ ran(a, 'passed', 7.5) ]))).to eq("./a_specs.rb\tdoes thing 1" => 7.5)
      end
    end
  end
end
