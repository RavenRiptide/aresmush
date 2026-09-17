require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Foundry's formula language, which we read rather than invent.
    #
    # An effect says what it is worth as an expression - `@actor.level`, `max(1,floor(@actor.level/2))`
    # - and this reads it. Adopting their grammar rather than inventing a shape means a converted feat
    # carries its formula across as data; inventing one means hand-translating two thousand of them,
    # where a wrong sign or a missing floor is a number that looks right and is not.
    #
    # The grammar is closed. Four operators, twelve functions, dotted references and interpolations.
    # No property access on arbitrary objects and no function this does not name, so there is nothing
    # to sandbox.
    describe Formula do

      def ctx(paths = {})
        { 'actor' => { 'level' => 5, 'abilities' => { 'con' => { 'mod' => 3 } } } }.merge(paths)
      end

      describe "arithmetic" do
        it "should read a number" do
          expect(Formula.value('7', ctx)).to eq 7
        end

        it "should add and subtract left to right" do
          expect(Formula.value('10 - 3 + 1', ctx)).to eq 8
        end

        it "should multiply before adding" do
          expect(Formula.value('2 + 3 * 4', ctx)).to eq 14
        end

        it "should divide before subtracting" do
          expect(Formula.value('10 - 6 / 2', ctx)).to eq 7
        end

        it "should respect brackets" do
          expect(Formula.value('(2 + 3) * 4', ctx)).to eq 20
        end

        it "should read a leading minus" do
          expect(Formula.value('-4', ctx)).to eq(-4)
        end

        it "should divide without rounding, so an explicit floor is what rounds" do
          expect(Formula.value('7 / 2', ctx)).to eq 3.5
        end

        # A zero divisor only arises from a reference that resolved to nothing, which `unresolved`
        # reports. Raising would take a sheet render down over one bad path.
        it "should yield nothing rather than raise when the divisor resolved to nothing" do
          expect(Formula.value('@actor.level / @actor.nonsense', ctx)).to eq 0
        end

        it "should still name the path that made it zero" do
          expect(Formula.unresolved('@actor.level / @actor.nonsense', ctx)).to eq [ 'actor.nonsense' ]
        end
      end

      describe "references" do
        it "should read a dotted path off the context" do
          expect(Formula.value('@actor.level', ctx)).to eq 5
        end

        it "should read a deep path" do
          expect(Formula.value('@actor.abilities.con.mod', ctx)).to eq 3
        end

        it "should do arithmetic on a reference" do
          expect(Formula.value('18 + @actor.level', ctx)).to eq 23
        end

        it "should negate a reference" do
          expect(Formula.value('-@actor.level', ctx)).to eq(-5)
        end

        # A path segment may hold hyphens: Foundry has
        # @actor.system.proficiencies.attacks.advanced-firearms-crossbows.rank.
        it "should read a path segment containing hyphens" do
          context = { 'actor' => { 'attacks' => { 'advanced-firearms-crossbows' => 2 } } }

          expect(Formula.value('@actor.attacks.advanced-firearms-crossbows', context)).to eq 2
        end

        # A reference that resolves to nothing is zero, which is what Foundry does - but it is also
        # how a mistyped path hides, so it is reported.
        it "should treat an unknown path as zero" do
          expect(Formula.value('@actor.nonsense', ctx)).to eq 0
        end

        it "should say which paths it could not resolve" do
          expect(Formula.unresolved('@actor.nonsense + @actor.level', ctx)).to eq [ 'actor.nonsense' ]
        end
      end

      describe "functions" do
        it "should floor" do
          expect(Formula.value('floor(@actor.level/2)', ctx)).to eq 2
        end

        it "should ceil" do
          expect(Formula.value('ceil(@actor.level/2)', ctx)).to eq 3
        end

        it "should round" do
          expect(Formula.value('round(5/2)', ctx)).to eq 3
        end

        it "should take the larger of two" do
          expect(Formula.value('max(1,floor(@actor.level/2))', ctx)).to eq 2
        end

        it "should take the smaller of two" do
          expect(Formula.value('min(3,@actor.level)', ctx)).to eq 3
        end

        it "should take max of more than two, which is variadic in the data" do
          expect(Formula.value('max(1,2,9,3)', ctx)).to eq 9
        end

        it "should clamp between bounds" do
          expect(Formula.value('clamp(@actor.level,1,4)', ctx)).to eq 4
        end

        it "should choose with ternary on a true test" do
          expect(Formula.value('ternary(gte(@actor.level,5),10,20)', ctx)).to eq 10
        end

        it "should choose with ternary on a false test" do
          expect(Formula.value('ternary(gte(@actor.level,17),3,2)', ctx)).to eq 2
        end

        it "should compare with each comparison the data uses" do
          expect(Formula.value('gte(2,2)', ctx)).to eq 1
          expect(Formula.value('gt(2,2)', ctx)).to eq 0
          expect(Formula.value('lte(2,2)', ctx)).to eq 1
          expect(Formula.value('lt(1,2)', ctx)).to eq 1
          expect(Formula.value('eq(2,2)', ctx)).to eq 1
          expect(Formula.value('ne(2,2)', ctx)).to eq 0
        end

        # One shipped formula says `clamped(...)`, which is a typo for clamp. Accepting it costs
        # nothing and refusing it would fail an import over someone else's slip.
        it "should accept the data's one misspelling of clamp" do
          expect(Formula.value('clamped(9,1,4)', ctx)).to eq 4
        end
      end

      describe "refusals" do
        it "should refuse a function it does not know rather than guess" do
          expect { Formula.value('system("rm -rf /")', ctx) }.to raise_error(Formula::Invalid, /system/)
        end

        it "should refuse an unbalanced bracket" do
          expect { Formula.value('max(1,2', ctx) }.to raise_error(Formula::Invalid)
        end

        it "should refuse a character outside the grammar" do
          expect { Formula.value('1 ; 2', ctx) }.to raise_error(Formula::Invalid)
        end

        it "should refuse a wrong arity on a fixed-arity function" do
          expect { Formula.value('floor(1,2)', ctx) }.to raise_error(Formula::Invalid, /floor/)
        end

        it "should refuse rather than evaluate ruby" do
          expect { Formula.value('`ls`', ctx) }.to raise_error(Formula::Invalid)
        end
      end

      # The point of checking the corpus in: a construct we have read wrongly fails here, loudly,
      # rather than resolving to zero in front of a player.
      describe "every formula Foundry ships" do
        def corpus
          path = File.join(File.dirname(__FILE__), 'support', 'foundry_formula_corpus.txt')

          File.readlines(path)
              .reject { |line| line.start_with?('#') || line.strip.empty? }
              .map { |line| line.split("\t", 2).last.to_s.strip }
              .reject(&:empty?)
        end

        it "should have a corpus to check against" do
          expect(corpus.size).to be > 600
        end

        it "should parse every one of them" do
          failed = corpus.reject { |formula| Formula.parses?(formula) }

          expect(failed).to eq []
        end
      end
    end
  end
end
