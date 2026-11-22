module AresMUSH
  module Pf2e

    # The picture of a character's familiar or pet that their profile's Familiar tab shows. The player
    # chooses it on the portal's Edit page from the files in their character's folder, as they choose a
    # profile image, and it needs no staff approval.
    module FamiliarPicture

      # Anyone with a familiar or a pet may choose one, before approval as well as after: the profile shows
      # it once the familiar is approved.
      def self.allowed?(char)
        !Familiar.main_source(char).nil?
      end

      # The chosen picture's path, or nil when there is none or its file is no longer in their folder.
      def self.path(char)
        chosen = char.pf2_familiar_image.to_s
        return nil if chosen.empty?

        files(char).include?(chosen) ? chosen : nil
      end

      # Their files, as paths under the uploads folder.
      def self.files(char)
        Array(Profile.character_page_files(char)).map { |file| file.sub(AresMUSH.website_uploads_path, '').sub(%r{\A/}, '') }
      end

      # What the Edit page needs: whether to draw the tab, what the familiar is called, and the picture chosen.
      def self.edit_fields(char)
        return nil unless allowed?(char)

        details = Familiar.approved_record(char) || Familiar.details(char)
        chosen = path(char)

        { name: details['name'].presence, pet: Familiar::Choices.plain_pet?(char),
          image: chosen ? Website.get_file_info(chosen) : nil }
      end

      # Chooses the picture by its file name in their folder, or clears it when the name is blank.
      def self.choose!(char, name)
        name = name.to_s.strip
        return Err.new(:no_familiar, 'pf2e.familiar_picture_no_familiar') unless allowed?(char)

        if name.empty?
          char.update(:pf2_familiar_image => nil)
          return Ok.new(:state => nil)
        end

        wanted = File.join(Profile.character_page_folder(char), name.downcase)
        found = files(char).find { |file| file.casecmp?(wanted) }
        return Err.new(:not_their_file, 'pf2e.familiar_picture_not_found', 'file' => name, 'name' => char.name) unless found

        char.update(:pf2_familiar_image => found)
        Ok.new(:state => found)
      end
    end
  end
end
