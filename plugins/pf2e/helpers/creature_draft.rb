module AresMUSH
  module Pf2e

    # A saved creature built a part at a time, in the words of a one-line description (`Described`):
    # `creature/set <name>=ac 19 hp 40`, `=strike claw +9 1d6+4 slashing (agile)`, `=weak fire 5`. A
    # Strike or an ability of a name it already has is replaced; a weakness, resistance, immunity, skill,
    # sense or trait is added to what it has. `unset` takes one off by its name.
    module CreatureDraft

      # The words a figure is written with. Asked for rather than held, because `Described` loads after this.
      def self.figure_words
        Described::FIGURES.flat_map { |figure| figure['words'] }
      end

      # Lists read whole, added to what is there.
      ADDED = { 'immunities' => :list, 'traits' => :list, 'senses' => :list, 'skills' => :hash,
                'weaknesses' => :hash, 'resistances' => :hash }.freeze

      # What `unset` takes off, by the word it is named with: where it is, and how it is named there.
      UNSET = {
        'strike' => [ 'strikes', :named ], 'ranged' => [ 'strikes', :named ], 'melee' => [ 'strikes', :named ],
        'ability' => [ 'actions', :named ],
        'weak' => [ 'weaknesses', :keyed ], 'weakness' => [ 'weaknesses', :keyed ],
        'resist' => [ 'resistances', :keyed ], 'resistance' => [ 'resistances', :keyed ],
        'skill' => [ 'skills', :keyed ], 'skills' => [ 'skills', :keyed ],
        'immune' => [ 'immunities', :listed ], 'immunity' => [ 'immunities', :listed ],
        'trait' => [ 'traits', :listed ], 'traits' => [ 'traits', :listed ],
        'sense' => [ 'senses', :listed ], 'senses' => [ 'senses', :listed ],
        'shield' => [ 'shield', :whole ], 'size' => [ 'size', :whole ], 'rarity' => [ 'rarity', :whole ]
      }.freeze

      def self.set(block, words)
        first = words.to_s.strip.split(/\s+/).first.to_s.downcase

        return figures(block, words) if figure_words.include?(first)

        read = Described.part_of(block.merge('strikes' => [], 'actions' => [], 'shield' => nil).compact, words.to_s.strip)

        read.and_then { |part| Ok.new(:state => merged(block, part)) }
      end

      # The figures named, over those it has: `ac 19 ref 9`. A word that names no figure is refused.
      def self.figures(block, words)
        named = words.to_s.downcase.scan(/([a-z]+)\s*([+-]?\d+)/)
        unknown = named.map(&:first).reject { |word| figure_words.include?(word) }

        return Err.new(:creature_set_figures, 'pf2e.creature_set_figures', 'words' => unknown.join(', ')) if named.empty? || unknown.any?

        held = named.reduce(block) do |so_far, (word, value)|
          *path, last = Described::FIGURES.find { |figure| figure['words'].include?(word) }['at']

          placed(so_far, path, last, value.to_i)
        end

        Ok.new(:state => held)
      end

      # A copy with one figure set, however deep it sits.
      def self.placed(held, path, last, value)
        return held.merge(last => value) if path.empty?

        first, *rest = path
        held.merge(first => placed(Hash(held[first]), rest, last, value))
      end

      # A part read on its own, put into the creature: a Strike or ability replacing its namesake, a list
      # added to.
      def self.merged(block, part)
        out = block.dup

        %w{strikes actions}.each do |field|
          next if Array(part[field]).empty?

          fresh = part[field].last
          kept = Array(block[field]).reject { |one| one['name'].to_s.casecmp?(fresh['name'].to_s) }
          out[field] = kept + [ fresh ]
        end

        ADDED.each do |field, kind|
          next unless part.key?(field) && part[field] != block[field]

          out[field] = kind == :list ? (Array(block[field]) + Array(part[field])).uniq : Hash(block[field]).merge(Hash(part[field]))
        end

        %w{size rarity shield}.each { |field| out[field] = part[field] if part[field] }

        out
      end

      def self.unset(block, words)
        word, _, rest = words.to_s.strip.partition(/\s+/)
        field, how = UNSET[word.downcase]
        wanted = rest.strip

        return nothing(words) unless field

        held = block[field]
        left = case how
               when :named then Array(held).reject { |one| one['name'].to_s.casecmp?(wanted) }
               when :keyed then Hash(held).reject { |key, _| key.to_s.casecmp?(wanted) || key.to_s.casecmp?(Described.slug(wanted)) }
               when :listed then Array(held).reject { |one| one.to_s.casecmp?(wanted) || one.to_s.casecmp?(Described.slug(wanted)) }
               when :whole then nil
               end

        return nothing(words) if left == held || (how == :whole && held.nil?)

        Ok.new(:state => how == :whole ? block.except(field) : block.merge(field => left))
      end

      def self.nothing(words)
        Err.new(:creature_nothing_to_unset, 'pf2e.creature_nothing_to_unset', 'words' => words.to_s.strip)
      end
    end
  end
end
