module AresMUSH
  module FS3Combat
    def self.find_action_klass(name)
      case name
      when "aim"
        AimAction
      when "attack"
        AttackAction
      when "escape"
        EscapeAction
      when "explode"
        ExplodeAction
      when "fullauto"
        FullautoAction
      when "pass"
        PassAction
      when "rally"
        RallyAction
      when "reload"
        ReloadAction
      when "treat"
        TreatAction
      when "subdue"
        SubdueAction
      when "suppress"
        SuppressAction
      else
        nil
      end
    end
    
    def self.reset_for_new_turn(combatant)
      # Reset aim if they've done anything other than aiming. 
      if (combatant.is_aiming? && combatant.action_klass != "AimAction")
        combatant.log "Reset aim for #{combatant.name}."
        combatant.update(aim_target: nil)
      end
      
      if (!combatant.is_subdued?)
        combatant.update(subdued_by: nil)
      end
      
      combatant.update(posed: false)
      combatant.update(recoil: 0)
      FS3Combat.reset_stress(combatant)
      
      FS3Combat.check_for_ko(combatant)
      combatant.update(freshly_damaged: false)
      
      if (combatant.is_ko && combatant.is_npc?)
        FS3Combat.leave_combat(combatant.combat, combatant)
      end
    end
    
    def self.reset_stress(combatant)
      return if combatant.stress == 0

      composure = Global.read_config("fs3combat", "composure_ability")
      roll = combatant.roll_ability(composure)
      new_stress = [0, combatant.stress - roll - 1].max
      combatant.log "#{combatant.name} resetting stress.  roll=#{roll} old=#{combatant.stress} new=#{new_stress}."
      combatant.update(stress: new_stress)
    end
    
    def self.check_for_ko(combatant)
      combatant.log "Checking for KO: #{combatant.name} #{combatant.freshly_damaged} #{combatant.is_ko} #{combatant.total_damage_mod}"
      return if (!combatant.freshly_damaged || combatant.is_ko || combatant.total_damage_mod > -1.0)
      roll = FS3Combat.make_ko_roll(combatant)
      
      if (roll <= 0)
        combatant.update(is_ko: true)
        combatant.update(action_klass: nil)
        combatant.update(action_args: nil)
        combatant.combat.emit t('fs3combat.is_koed', :name => combatant.name)
      end
    end
      
    def self.check_for_unko(combatant)
      return if !combatant.is_ko
      roll = FS3Combat.make_ko_roll(combatant)
      
      if (roll > 0)
        combatant.update(is_ko: false)
        combatant.combat.emit t('fs3combat.is_no_longer_koed', :name => combatant.name)
      end
    end
    
    def self.make_ko_roll(combatant)
      pc_mod = combatant.is_npc? ? 0 : 3
      
      if (combatant.is_in_vehicle?)
        vehicle = combatant.vehicle
        toughness = FS3Combat.vehicle_stat(vehicle.vehicle_type, "toughness")
        combatant.log "#{combatant.name} vehicle checking KO. tough=#{toughness} mod=#{combatant.total_damage_mod}."
        roll = FS3Skills::Api.one_shot_die_roll(toughness + combatant.total_damage_mod + pc_mod)[:successes]
      else
        toughness = Global.read_config("fs3combat", "composure_ability")
        combatant.log "#{combatant.name} checking KO. mod=#{combatant.total_damage_mod}."
        roll = combatant.roll_ability(toughness, pc_mod + combatant.total_damage_mod)
      end
      
      roll
    end
        
    def self.ai_action(combat, client, combatant)
      if (combatant.is_subdued?)
        FS3Combat.set_action(client, nil, combat, combatant, FS3Combat::EscapeAction, "")
      elsif (!FS3Combat.check_ammo(combatant, 1))
        FS3Combat.set_action(client, nil, combat, combatant, FS3Combat::ReloadAction, "")
      else
        target = combat.active_combatants.select { |t| t.team != combatant.team }.shuffle.first
        if (target)
          weapon_type = FS3Combat.weapon_stat(combatant.weapon, "weapon_type")
          case weapon_type
          when "Explosive"
            action_klass = FS3Combat::ExplodeAction
          when "Suppressive"
            action_klass = FS3Combat::SuppressAction
          else
            action_klass = FS3Combat::AttackAction
          end
          FS3Combat.set_action(client, nil, combat, combatant, action_klass, target.name)
        end
      end   
    end
    
    def self.set_action(client, enactor, combat, combatant, action_klass, args)
      action = action_klass.new(combatant, args)
      combatant.update(action_klass: action_klass)
      combatant.update(action_args: args)
      error = action.prepare
      if (error)
        client.emit_failure error
        return
      end
      combat.emit "#{action.print_action}", FS3Combat.npcmaster_text(combatant.name, enactor)
    end
    
    def self.determine_damage(combatant, hitloc, weapon, armor = 0, crew_hit = false)
      random = rand(100)
      
      lethality = FS3Combat.weapon_stat(weapon, "lethality")
      
      case FS3Combat.hitloc_severity(combatant, hitloc, crew_hit)
      when "Critical"
        severity = 20
      when "Vital"
        severity = 0
      else
        severity = -10
      end
      
      special = combatant.damage_lethality_mod
      npc = combatant.is_npc? ? 30 : 0
      
      total = random + severity + lethality - armor + special
      
      if (total < 30)
        damage = "GRAZE"
      elsif (total < 70)
        damage = "FLESH"
      elsif (total <100)
        damage = "IMPAIR"
      else
        damage = "INCAP"
      end
      
      combatant.log "Determined damage: loc=#{hitloc} sev=#{severity} wpn=#{weapon}" +
      " lth=#{lethality} special=#{special} arm=#{armor} rand=#{random} total=#{total} dmg=#{damage}"
      
      damage
    end
    
    def self.determine_armor(combatant, hitloc, weapon, attacker_net_successes)
      vehicle = combatant.vehicle
      if (vehicle)
        armor = vehicle.armor
      else
        armor = combatant.armor
      end
      
      # Not wearing armor at all.
      return 0 if !armor
      
      pen = FS3Combat.weapon_stat(weapon, "penetration")
      protect = FS3Combat.armor_stat(armor, "protection")[hitloc]
            
      # Armor doesn't cover this hit location
      return 0 if !protect

      pen_roll = FS3Skills::Api.one_shot_die_roll(pen)[:successes]
      protect_roll = FS3Skills::Api.one_shot_die_roll(protect)[:successes]
      
      margin = pen_roll + attacker_net_successes - protect_roll
      if (margin > 2)
        protection = 0
      elsif (margin < -2)
        protection = 100
      else
        protection = rand(50)
      end
      
      combatant.log "Determined armor: loc=#{hitloc} weapon=#{weapon} net=#{attacker_net_successes}" +
      " pen=#{pen} pen_roll=#{pen_roll} protect=#{protect} protect_roll=#{protect_roll} result=#{protection}"
      
      protection
    end
    
    def self.stopped_by_cover?(attacker_net_successes, combatant)
      case attacker_net_successes
      when 0, 1
        cover_chance = 50
      when 2
        cover_chance = 25
      else
        cover_chance = 0
      end
      
      roll = rand(100) 
      result = roll > cover_chance
            
      combatant.log "Determined cover: net=#{attacker_net_successes}" +
            " chance=#{cover_chance} roll=#{roll} result=#{result}"
      
      result
    end
    
    # Returns { hit: true/false, attacker_net_successes: #, message: explains miss reason }
    def self.determine_attack_margin(combatant, target, mod = 0, called_shot = nil)
      weapon = combatant.weapon
      attack_roll = FS3Combat.roll_attack(combatant, mod - combatant.recoil)
      defense_roll = FS3Combat.roll_defense(target, weapon)
      
      attacker_net_successes = attack_roll - defense_roll
      stopped_by_cover = target.stance == "Cover" ? FS3Combat.stopped_by_cover?(attacker_net_successes, combatant) : false
      hit = false
      
      if (attack_roll <= 0)
        message = t('fs3combat.attack_missed', :name => combatant.name, :target => target.name, :weapon => weapon)
      elsif (attacker_net_successes < 0)
        message = t('fs3combat.attack_dodged', :name => combatant.name, :target => target.name, :weapon => weapon)
      elsif (stopped_by_cover)
        message = t('fs3combat.attack_hits_cover', :name => combatant.name, :target => target.name, :weapon => weapon)
      elsif (called_shot && (attacker_net_successes < 1))
        message = t('fs3combat.attack_near_miss', :name => combatant.name, :target => target.name, :weapon => weapon)
      else
        hit = true
      end
      
      combatant.log "Attack Margin: mod=#{mod} called=#{called_shot} " +
      " attack=#{attack_roll} defense=#{defense_roll} hit=#{hit} cover=#{stopped_by_cover} result=#{message}"
      
      
      {
        message: message,
        hit: hit,
        attacker_net_successes: attacker_net_successes
      }
    end
      
    def self.attack_target(combatant, target, mod = 0, called_shot = nil, crew_hit = false)
      # If targeting a passenger, adjust target to the pilot instead.  Unless of course there isn't one.
      if (target.riding_in && target.riding_in.pilot)
        target = target.riding_in.pilot
      end
      
      margin = FS3Combat.determine_attack_margin(combatant, target, mod, called_shot)

      # Update recoil after determining the attack success but before returning out for a miss
      recoil = FS3Combat.weapon_stat(combatant.weapon, "recoil")
      combatant.update(recoil: combatant.recoil + recoil)

      return [margin[:message]] if !margin[:hit]
    
      weapon = combatant.weapon
      
      attacker_net_successes = margin[:attacker_net_successes]
            
      FS3Combat.resolve_attack(combatant.name, target, weapon, attacker_net_successes, called_shot, crew_hit)
    end
    
    
    def self.resolve_attack(attacker_name, target, weapon, attacker_net_successes = 0, called_shot = nil, crew_hit = false)
      hitloc = FS3Combat.determine_hitloc(target, attacker_net_successes, called_shot, crew_hit)
      armor = FS3Combat.determine_armor(target, hitloc, weapon, attacker_net_successes)
        
      if (armor >= 100)
        message = t('fs3combat.attack_stopped_by_armor', :name => attacker_name, :weapon => weapon, :target => target.name, :hitloc => hitloc) 
        return [message]
      end
                  
      reduced_by_armor = armor > 0 ? t('fs3combat.reduced_by_armor') : ""
          
      damage = FS3Combat.determine_damage(target, hitloc, weapon, armor, crew_hit)
          
      is_stun = FS3Combat.weapon_is_stun?(weapon)
      desc = "#{weapon} - #{hitloc}"

      target.inflict_damage(damage, desc, is_stun, crew_hit)
      target.update(freshly_damaged: true)
            
      target.add_stress(1)
      
      messages = []
      
      messages << t('fs3combat.attack_hits', 
                    :name => attacker_name, 
                    :weapon => weapon,
                    :target => target.name,
                    :hitloc => hitloc,
                    :armor => reduced_by_armor,
                    :damage => FS3Combat.display_severity(damage)) 

      messages.concat FS3Combat.resolve_possible_crew_hit(target, hitloc, damage)
      messages
    end
    
    def self.resolve_possible_crew_hit(target, hitloc, damage)
      messages = []
      return [] if (!target.is_in_vehicle?)
      vehicle = target.vehicle
      crew_hitlocs = FS3Combat.hitloc_chart(target)["crew_areas"]
      
      return [] if (!crew_hitlocs.include?(hitloc))

      people = vehicle.passengers.to_a
      people << vehicle.pilot
      
      people.each do |p|
        case damage
        when "GRAZE"
          shrapnel = 0
        when "FLESH"
          shrapnel = rand(1)
        when "IMPAIR"
          shrapnel = rand(3)
        when "INCAP"
          shrapnel = rand(5)
        end
                
        target.log "Crew area hit. #{p.name} shrapnel=#{shrapnel}"
        shrapnel.times.each do |s|
          messages.concat FS3Combat.resolve_attack(t('fs3combat.crew_hit'), p, "Shrapnel", 0, nil, true)
        end
      end
      
      messages
    end
  end
end