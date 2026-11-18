module AresMUSH

  # This plugin loads before the stock events plugin (alphabetical order), so this file may be the
  # first to open Event. ObjectModel is included here as well because its `attribute` is the one
  # that understands `:type`; including it a second time when events.rb opens the class is harmless.
  class Event < Ohm::Model
    include ObjectModel

    # 0 (the value an unset limit reads as) means no limit.
    attribute :max_players, :type => DataType::Integer

    attribute :death_consent, :type => DataType::Boolean
  end
end
