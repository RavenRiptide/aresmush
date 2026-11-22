module AresMUSH
  module Pf2e
    module Familiar

      # What a player may type for their familiar's name, species and form. Name and species are the only
      # free text, so they are held to letters and a few marks: that keeps out MUSH codes (`%r`, `%x`),
      # escapes, control and invisible characters, and every character a command splits its arguments on
      # (`/ = , ( ) # ;`). Each returns Ok carrying the cleaned text, or an Err saying why.
      module Details

        NAME_MIN = 2
        NAME_MAX = 30
        SPECIES_MAX = 40

        # A name is one word, as a character's is (`Character.check_name`: A to Z, apostrophes and hyphens),
        # without the digits a character's may have, so nothing reads as an encounter's combatant number.
        # A letter first, so nothing reads as punctuation.
        NAME_ALLOWED = /\A[A-Za-z][A-Za-z'\-]*\z/.freeze

        # A species may be several words, in any alphabet: "black cat", "chouette effraie".
        ALLOWED = /\A\p{L}[\p{L}\p{M} '\-.]*\z/u.freeze

        # Restricted entries that are MUSH targeting words, which only matter as a whole name: "Here-Kitty"
        # and a "here" species are fine.
        TARGETING = %w{me here}.freeze

        def self.clean(raw)
          raw.to_s.unicode_normalize(:nfc).strip.gsub(/\s+/, ' ')
        rescue ArgumentError, Encoding::CompatibilityError
          ''
        end

        def self.text(raw, max, what)
          cleaned = clean(raw)

          return Err.new(:familiar_text_empty, 'pf2e.familiar_text_empty', 'what' => what) if cleaned.empty?
          return Err.new(:familiar_text_long, 'pf2e.familiar_text_long', 'what' => what, 'max' => max) if cleaned.length > max
          return Err.new(:familiar_text_chars, 'pf2e.familiar_text_chars', 'what' => what) unless cleaned.match?(ALLOWED)

          Ok.new(:state => cleaned)
        end

        # The restricted entry one of the words uses, if any: "Althea's Cat" and "Althea's" use Althea, and
        # "Kor-Wing" uses Kor.
        def self.restricted_word(cleaned, restricted)
          entries = Array(restricted).map { |entry| entry.to_s.downcase } - TARGETING
          words = cleaned.downcase.split(/[\s\-.]+/).map { |word| word.sub(/'s\z/, '').delete("'") }

          entries.find { |entry| words.include?(entry) }
        end

        def self.restricted
          Global.read_config('names', 'restricted') || []
        end

        def self.name(raw, restricted: self.restricted, taken: ->(named) { Login.name_taken?(named) })
          cleaned = clean(raw)

          return Err.new(:familiar_text_empty, 'pf2e.familiar_text_empty', 'what' => 'name') if cleaned.empty?
          return Err.new(:familiar_name_chars, 'pf2e.familiar_name_chars') unless cleaned.match?(NAME_ALLOWED)
          return Err.new(:familiar_name_short, 'pf2e.familiar_name_short', 'min' => NAME_MIN) if cleaned.length < NAME_MIN
          return Err.new(:familiar_text_long, 'pf2e.familiar_text_long', 'what' => 'name', 'max' => NAME_MAX) if cleaned.length > NAME_MAX

          found = Ok.new(:state => cleaned)

          if Array(restricted).any? { |entry| entry.to_s.casecmp?(cleaned) }
            return Err.new(:familiar_name_restricted, 'pf2e.familiar_name_restricted', 'name' => cleaned)
          end

          word = restricted_word(cleaned, restricted)
          return Err.new(:familiar_word_restricted, 'pf2e.familiar_word_restricted', 'word' => word.capitalize) if word
          return Err.new(:familiar_name_taken, 'pf2e.familiar_name_taken', 'name' => cleaned) if taken.call(cleaned)

          found
        end

        def self.species(raw, restricted: self.restricted)
          found = text(raw, SPECIES_MAX, 'species')
          return found if found.err?

          word = restricted_word(found.state, restricted)
          return Err.new(:familiar_word_restricted, 'pf2e.familiar_word_restricted', 'word' => word.capitalize) if word

          found
        end

        def self.forms
          Array(Global.read_config('pf2e', 'familiar_forms')).map(&:to_s)
        end

        def self.form(raw, forms: self.forms)
          wanted = clean(raw).downcase
          found = forms.find { |one| one.casecmp?(wanted) }

          return Ok.new(:state => found) if found

          Err.new(:familiar_form_unknown, 'pf2e.familiar_form_unknown', 'forms' => forms.join(', '))
        end
      end
    end
  end
end
