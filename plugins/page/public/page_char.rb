module AresMUSH
  class Character
    attribute :last_paged, :type => DataType::Array, :default => []
    attribute :page_do_not_disturb, :type => DataType::Boolean
    # Emblem of Ea: Deliberate change from stock Ares, which defaults to "%r" (a blank line before every page and
    # OOC remark). Players who want the spacing back can set it with pm/autospace.
    attribute :page_autospace
    # Emblem of Ea: text shown after every page and OOC remark, set with pm/autospace/after.
    attribute :page_autospace_after
    attribute :page_color
    attribute :page_monitor, :type => DataType::Hash, :default => {}

    attribute :hidden_page_threads, :type => DataType::Array, :default => []
        
    # OBSOLETE - use read_tracker instead
    attribute :read_page_threads, :type => DataType::Array, :default => []

    # OBSOLETE - use page_blocks instead
    set :page_ignored, "AresMUSH::Character"


    before_delete :delete_pages

    def page_threads
      PageThread.all.select { |p| p.characters.include?(self) }
    end
    
    def sorted_page_threads
      self.page_threads
         .to_a
         .sort_by { |t| [ Page.is_thread_unread?(t, self) ? 1 : 0, t.last_activity ] }
         .reverse
   end
           
   def has_page_blocked?(char)
     self.is_blocked?(char, "pm")
   end
   
    def delete_pages
      self.page_threads.each { |p| Page.delete_page_thread(p, self) }
    end
    
    def is_monitoring?(char)
      return false if !page_monitor
      page_monitor.has_key?(char.name)
    end
  end
end