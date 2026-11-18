module AresMUSH
  module Demographics
    # Emblem of Ea: Custom Ares change. Reads a typed birthdate for set_birthday,
    # which the birthdate command, portal chargen, and portal profile edit all use.
    #
    # Accepts, case-insensitive:
    #   M/D/Y
    #   <month> D Y   or   <month> D, Y   (Ea or RL month name; Ea months line up 1:1 with RL months)
    #
    # A year later than the current IC year is an RL year and is shifted by the
    # ictime year_offset. With year_offset -998, min_age 18 and max_age 1000, valid
    # IC birth years run 28-1010 and valid RL birth years 1026-2008, so the two
    # ranges never overlap. If max_age ever goes above about 1015 they would, and
    # this rule needs rethinking.
    #
    # Returns a Date, or nil when the input can't be read (blank, unknown month,
    # or an impossible day such as Balefire 31).
    def self.parse_birthdate_input(input)
      str = (input || "").to_s.strip
      return nil if str.empty?

      if (str =~ /\A(\d{1,2})\/(\d{1,2})\/(\d{1,4})\z/)
        month, day, year = $1.to_i, $2.to_i, $3.to_i
      elsif (str =~ /\A([a-z]+)\s+(\d{1,2}),?\s+(\d{1,4})\z/i)
        day, year = $2.to_i, $3.to_i
        month = Demographics.birthdate_month_number($1)
        return nil if !month
      else
        return nil
      end

      if (year > ICTime.ictime.year)
        year = year + Global.read_config("ictime", "year_offset").to_i
      end

      Date.new(year, month, day)
    rescue ArgumentError
      nil
    end

    # 1-12 for an Ea or RL month name, or nil.
    def self.birthdate_month_number(name)
      name = name.downcase
      ea_months = (Global.read_config("ictime", "month_names") || []).map { |m| m.downcase }
      index = ea_months.index(name)
      return index + 1 if index

      rl_months = Date::MONTHNAMES.compact.map { |m| m.downcase }
      index = rl_months.index(name)
      index ? index + 1 : nil
    end
  end
end
