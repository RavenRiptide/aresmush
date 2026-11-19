module AresMUSH
  module EaEvents

    # The tier table and the wiki page that explains it, for the level range fields on the
    # portal's create and edit event pages. Those pages label the range as it's picked, before
    # anything is saved, so they need the same tiers the game labels with. The death-consent wiki
    # page rides along for the death-consent field's hint on the same pages.
    class EventLevelTiersRequestHandler
      def handle(request)
        {
          tiers: EaEvents.level_tiers,
          cap: EaEvents.level_cap,
          wiki_page: Global.read_config("eaevents", "tiers_wiki_page"),
          wiki_title: Global.read_config("eaevents", "tiers_wiki_title"),
          death_consent_wiki_page: EaEvents.death_consent_wiki_page,
          death_consent_wiki_title: EaEvents.death_consent_wiki_title
        }
      end
    end
  end
end
