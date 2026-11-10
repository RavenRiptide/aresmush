require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Which sections of a sheet exist, and whether this character has one.
    #
    # The sheet commands each carried their own copy of the list once, and they disagreed about
    # which sections existed and which needed the character to cast.
    describe Sheet do

      def caster
        double(:magic => double, :pf2_baseinfo_locked => true, :is_admin? => false, :name => 'Caster')
      end

      def mundane
        double(:magic => nil, :pf2_baseinfo_locked => true, :is_admin? => false, :name => 'Fighter')
      end

      describe :sections do
        it "should include every section a player can be shown" do
          expect(Sheet.sections).to include('all', 'info', 'attributes', 'skills', 'feats', 'features', 'languages', 'magic', 'combat')
        end

        # PF2e's Remaster renamed ability scores to attributes; there is no alias for the old word.
        it "should not recognise the old ability section" do
          expect(Sheet.section?('ability')).to be false
        end

        it "should recognise a section" do
          expect(Sheet.section?('combat')).to be true
        end

        it "should not recognise a word that is not one" do
          expect(Sheet.section?('banana')).to be false
        end
      end

      describe :available do
        it "should allow a section with nothing to require" do
          expect(Sheet.available(mundane, 'skills')).to be_ok
        end

        it "should refuse a section that is not one" do
          outcome = Sheet.available(mundane, 'banana')

          expect(outcome).to be_err
          expect(outcome.code).to eq :bad_section
        end

        it "should refuse the magic section to a character who does not cast" do
          outcome = Sheet.available(mundane, 'magic')

          expect(outcome).to be_err
          expect(outcome.code).to eq :not_caster
        end

        it "should allow the magic section to a caster" do
          expect(Sheet.available(caster, 'magic')).to be_ok
        end

        it "should refuse any section on a sheet that does not exist yet" do
          unlocked = double(:magic => nil, :pf2_baseinfo_locked => false, :is_admin? => false, :name => 'New')
          outcome = Sheet.available(unlocked, 'skills')

          expect(outcome).to be_err
          expect(outcome.code).to eq :no_sheet_yet
        end

        it "should refuse an admin's sheet, which does not exist" do
          admin = double(:magic => nil, :pf2_baseinfo_locked => true, :is_admin? => true, :name => 'Staff')
          outcome = Sheet.available(admin, 'skills')

          expect(outcome).to be_err
          expect(outcome.code).to eq :admin_no_sheet
        end

        # Order matters: an admin has no sheet at all, so that is the answer even for a section
        # they would otherwise fail on for a different reason.
        it "should say a sheet does not exist before saying a section is unavailable" do
          admin = double(:magic => nil, :pf2_baseinfo_locked => true, :is_admin? => true, :name => 'Staff')

          expect(Sheet.available(admin, 'magic').code).to eq :admin_no_sheet
        end
      end
    end
  end
end
