module AresMUSH
  module Pf2e

    # Handles merging the current character data with any pending advancement choices during advancement to allow other choices to be made, as per pen and paper.

    def self.preview_repertoire(char)
      magic = char.magic
      repertoire = Marshal.load(Marshal.dump(magic&.repertoire || {}))

      advancement = char.pf2_advancement || {}
      pending_rep = advancement['repertoire'] || {}
      return repertoire unless pending_rep.is_a?(Hash) && !pending_rep.empty?

      charclass = char.pf2_base_info['charclass']
      class_rep = repertoire[charclass] || {}

      pending_rep.each_pair do |level, spells|
        existing = Array(class_rep[level])
        additions = Array(spells).reject { |s| s.to_s.strip.empty? || s.to_s.downcase == 'open' }
        class_rep[level] = (existing + additions).uniq
      end

      repertoire[charclass] = class_rep
      repertoire
    end

    def self.preview_skill_prof(char, skill_name)
      current_prof = Pf2eSkills.get_skill_prof(char, skill_name)
      progression = Global.read_config('pf2e', 'prof_progression') || []
      return current_prof if progression.empty?

      advancement = char.pf2_advancement || {}
      pending = []
      pending += Array(advancement['raise skill'])
      pending += Array(advancement['raise skill choice'])

      normalized = pending.select { |s| !s.to_s.strip.empty? && s.to_s.downcase != 'open' }
                          .map { |s| s.to_s.downcase }

      raise_count = normalized.count(skill_name.to_s.downcase)
      return current_prof if raise_count.zero?

      index = progression.index(current_prof) || 0
      target_index = [index + raise_count, progression.length - 1].min

      progression[target_index]
    end

    def self.preview_feat_names(char)
      current = char.pf2_feats.values.flatten.map { |f| f.to_s.upcase }

      advancement = char.pf2_advancement || {}
      pending_feats = advancement['feats'] || {}

      pending = pending_feats.values.flatten
                          .map { |f| f.to_s.upcase }
                          .reject { |f| f.empty? || f == 'OPEN' }

      (current + pending).uniq
    end

  end
end