module AresMUSH
  class WebApp
    
    helpers do
      def display_damage_severity(severity)
        format_output_for_html FS3Combat.display_severity(severity)
      end
      
      def char_scenes_by_type(char, type)
        char.scenes_starring.select { |s| s.scene_type == type}
      end
      
      def can_manage_char?(char)
        @user && (@user == char || @user.is_admin?)
      end
      
      def profile_image_url(char)
        !char.profile_image.blank? ? "/files/#{char.profile_image}" : char.icon
      end
      
      def subgroup_chars(group_data)
        subgroup = Global.read_config("website", "character_gallery_subgroup") || "Position"
        group_data.group_by { |c| c.group(subgroup) || "" }.sort
      end
    end
    
    get '/chars/?' do
      group = Global.read_config("website", "character_gallery_group") || "Faction"
      @npcs = Character.all.select { |c| c.is_npc? && !c.idled_out?}.group_by { |c| c.group(group) || "" }
      @roster = Character.all.select { |c| c.on_roster? }.group_by { |c| c.group(group) || "" }
      @groups = Chargen.approved_chars.group_by { |c| c.group(group) || "" }.sort
      @page_title = "Characters"
      
      erb :"chars/chars_index"
    end
    
    get '/char/:id/?' do |id|
      @char = Character.find_one_by_name(id)
        
      if (!@char)
        flash[:error] = "Character not found."
        redirect '/chars'
      end
      @page_title = @char.name
      
      case @char.idle_state
      when "Roster"
        @idle_message = "This character is on the roster."
      when "Gone"
        @idle_message = "This character is retired."
      when "Dead"
        @idle_message = "This character is deceased."
      else
        if (@char.is_npc?)
          @idle_message = "This character is a NPC."
        elsif (@char.is_admin?)
          @idle_message = "This character is a game administrator."
        elsif (@char.is_playerbit?)
          @idle_message = "This character is a player bit."
        elsif (!@char.is_approved?)
          @idle_message = "This character is not yet approved."
        else
          @idle_message = nil
        end
      end
            
      erb :"chars/char"
    end
    
    get '/char/:id/source/?' do |id|
      @char = Character.find_one_by_name(id)
      
      if (!@char)
        flash[:error] = "Character not found."
        redirect '/chars'
      end
      
      @page_title = @char.name
      
      erb :"chars/source"
    end
  end
end
