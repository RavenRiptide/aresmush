module AresMUSH
  module Pf2e

    class PF2FeatSearchCmd
      include CommandHandler

      attr_accessor :search_type, :search_term

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.search_type = downcase_arg(args.arg1)
        self.search_term = trimmed_list_arg(args.arg2)

      end

      def required_args
        [ self.search_type, self.search_term ]
      end

      def check_search_type 
        valid_types = [ 'name', 
          'traits', 
          'feat_type', 
          'level', 
          'class', 
          'classlevel',
          'ancestry', 
          'skill',
          'description',
          'desc'
        ]

        return nil if valid_types.include? self.search_type
        return t('pf2e.bad_option', :options => valid_types.sort.join, :element => "search type")
      end

      def handle

        if self.search_term[1]
          term = self.search_term[1]
          operator = self.search_term[0]
        else 
          # Operator has default defined in search_feats.
          term = self.search_term[0].upcase
        end

        if self.search_type == 'classlevel' && self.value == nil
          client.emit_failure t('pf2e.feat_search_classlevel_wrong_number_of_variables')
          return
        end

        match = Pf2e.search_feats(self.search_type, term, operator)

        if match.empty?
          client.emit_failure t('pf2e.nothing_to_display', :elements => 'feats')
          return
        end

        list_details = Pf2e.generate_list_details(match)

        paginator = Paginator.paginate(list_details, cmd.page, 3)

        if (paginator.out_of_bounds?)
          client.emit_failure paginator.out_of_bounds_msg
          return
        end

        title = "Feat Search Results (#{self.search_type}=#{operator} #{term})"

        template = PF2eFeatDisplay.new(paginator, title)

        client.emit template.render

      end


    end
  
  end 
end