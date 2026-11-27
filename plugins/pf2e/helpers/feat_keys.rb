module AresMUSH
  module Pf2e

    # The rows a key on a feat's own data holds, for each feat in play for the holder. A creature has no
    # feats, so it has none.
    #
    #   FeatKeys.rows(holder, 'condition_rules')  # => [ [ 'Vigorous Health', { 'condition' => 'Drained', ... } ] ]
    module FeatKeys
      def self.rows(holder, key)
        return [] if Actors.of(holder).creature?

        Pf2e.feats_in_play(holder).uniq.flat_map do |feat|
          details = Global.read_config('pf2e_feats', feat)

          next [] unless details.is_a?(Hash) && details[key]

          Array(details[key]).map { |row| [ feat, row ] }
        end
      end
    end
  end
end
