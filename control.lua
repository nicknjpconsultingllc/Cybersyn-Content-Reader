--[[ Copyright (c) 2018 Optera
 * Part of LTN Content Reader
 *
 * See LICENSE.md in the project directory for license information.
--]]

local gui = require('gui')
require('utils')
require('variables')

function append_item(t, station, item_hash, count, network_name, network_mask)
  if network_name == nil then
    network_name = station.network_name
  end
  if network_mask == nil then
    network_mask = station.network_mask
  end

  if not station.entity_stop or not station.entity_stop.valid then
    return
  end

  local surface = station.entity_stop.surface_index

  if not network_name then
    network_name = "__all"
  end

  if network_name == "signal-each" then
    for network_name, network_mask in pairs(network_mask) do
      append_item(t, station, item_hash, count, network_name, network_mask)
    end
    return
  end

  if not t[surface] then
    t[surface] = {}
  end

  if not t[surface][network_name] then
    t[surface][network_name] = {}
  end

  if not t[surface][network_name][network_mask] then
    t[surface][network_name][network_mask] = {}
  end

  if t[surface][network_name][network_mask][item_hash] == nil then
    t[surface][network_name][network_mask][item_hash] = count
  else
    t[surface][network_name][network_mask][item_hash] = t[surface][network_name][network_mask][item_hash] + count
  end
end

-- Check if Cybersyn data has changed
function HasCybersynDataChanged(new_provided, new_requested, new_deliveries)
  -- Simple comparison - if any of the tables have different content, consider it changed
  local function table_equals(t1, t2)
    if type(t1) ~= type(t2) then return false end
    if type(t1) ~= "table" then return t1 == t2 end
    
    for k, v in pairs(t1) do
      if not table_equals(v, t2[k]) then return false end
    end
    for k, v in pairs(t2) do
      if not table_equals(v, t1[k]) then return false end
    end
    return true
  end
  
  return not table_equals(new_provided, storage.cybersyn_provided) or
         not table_equals(new_requested, storage.cybersyn_requested) or
         not table_equals(new_deliveries, storage.cybersyn_deliveries)
end

function InitSignals()
  local stations = remote.call("cybersyn", "read_global", "stations")

  local inventory_provided = {}
  local inventory_requested = {}
  local inventory_in_transit = {}

  for _, station in pairs(stations) do
		local comb1_signals, _ = get_signals(station)
		if comb1_signals then
			for _, v in pairs(comb1_signals) do
				local item = v.signal
				local count = v.count
				local item_type = v.signal.type or "item"
				local item_hash = hash_signal(item)

				if item.type ~= "virtual" then
					if station.is_p and count > 0 then
            append_item(inventory_provided, station, item_hash, count)
					end
					if station.is_r and count < 0 then
						local r_threshold = station.item_thresholds and station.item_thresholds[item.name] or
							item_type == "fluid" and station.r_fluid_threshold or
							station.r_threshold
						if station.is_stack and item_type == "item" then
							r_threshold = r_threshold * prototypes.item[item.name].stack_size
						end

						if -count >= r_threshold then
              append_item(inventory_requested, station, item_hash, count)
						end
					end
				end
			end
		end

		local deliveries = station.deliveries
		if deliveries then
			for cc_item_hash, count in pairs(deliveries) do
        -- Need to rehash to ours which includes the item type
        local item_name, quality = unhash_cc_signal(cc_item_hash)
        local type = prototypes.item[item_name] == nil and "fluid" or "item"
        local item_hash = hash_signal({ name = item_name, quality = quality, type = type })
				if count > 0 then
          append_item(inventory_in_transit, station, item_hash, count)
				end
			end
		end
	end

  -- Only update if data has actually changed
  if HasCybersynDataChanged(inventory_provided, inventory_requested, inventory_in_transit) then
    storage.cybersyn_provided = inventory_provided
    storage.cybersyn_requested = inventory_requested
    storage.cybersyn_deliveries = inventory_in_transit
    return true -- Indicate that data changed
  end
  
  return false -- Indicate that data didn't change
end

-- Handle Cybersyn dispatcher updates
function OnCybersynDispatcherUpdated(event)
  -- Update the signals immediately when Cybersyn updates
  local data_changed = InitSignals()
  
  -- Only update combinators if data actually changed
  if data_changed then
    for i = #storage.content_combinators, 1, -1 do
      local combinator = storage.content_combinators[i]
      if combinator.valid then
        Update_Combinator(combinator)
      else
        table.remove(storage.content_combinators, i)
      end
    end
  end
end

-- Force update all combinators immediately
function ForceUpdateAllCombinators()
  local data_changed = InitSignals()
  if data_changed then
    for i = #storage.content_combinators, 1, -1 do
      local combinator = storage.content_combinators[i]
      if combinator.valid then
        Update_Combinator(combinator)
      else
        table.remove(storage.content_combinators, i)
      end
    end
  end
end

-- spread out updating combinators
function OnTick(event)
  -- global.update_interval LTN update interval are synchronized in OnDispatcherUpdated
  local offset = event.tick % storage.update_interval
  local cc_count = #storage.content_combinators
  local data_changed = false
  
  if offset == 0 then
    data_changed = InitSignals()
  end
  
  -- Only update combinators if data changed or if we're doing the regular tick update
  if data_changed or offset == 0 then
    for i=cc_count - offset, 1, -1 * storage.update_interval do
      -- log( "("..tostring(event.tick)..") on_tick updating "..i.."/"..cc_count )
      local combinator = storage.content_combinators[i]
      if combinator.valid then
        Update_Combinator(combinator)
      else
        table.remove(storage.content_combinators, i)
        if #storage.content_combinators == 0 then
          script.on_event(defines.events.on_tick, nil)
        end
      end
    end
  end
end

---@param combinator LuaEntity
function Update_Combinator(combinator)
  -- get network id from combinator parameters
  local first_signal = get_first_signal(combinator)
  local selected_network_id = default_network
  local selected_network_name = "__all"

  if first_signal and first_signal.value then
    selected_network_name = first_signal.value.name
    selected_network_id = first_signal.min
  end

  ---@type LogisticFilter[]
  local signals = {}
  local index = 1

  -- for many signals performance is better to aggregate first instead of letting factorio do it
  local items = {}
  local reader = content_readers[combinator.name]
  if reader then
    for surface_index, surface_data in pairs(storage[reader.table_name]) do
      if not require_same_surface or combinator.surface_index == surface_index then
        for network_name, network_data in pairs(surface_data) do
          if selected_network_name == "__all" or network_name == selected_network_name then
            for network_mask, item_data in pairs(network_data) do
              if bit32.btest(selected_network_id, network_mask) then
                for item, count in pairs(item_data) do
                  items[item] = (items[item] or 0) + count
                end
              end
            end
          end
        end
      end
    end
  end

  -- generate signals from aggregated item list
  for item, count in pairs(items) do
    local itype, iname, iquality = unhash_signal(item)
    if itype and iname and (itype == "item" and prototypes.item[iname] or itype == "fluid" and prototypes.fluid[iname]) then
      if count >  2147483647 then count =  2147483647 end
      if count < -2147483648 then count = -2147483648 end
      signals[#signals+1] = {
        value = { type=itype, quality=iquality, name=iname },
        min = count
      }
      index = index+1
    end
  end

  ---@type LuaConstantCombinatorControlBehavior
  local b = combinator.get_control_behavior()

  while b.sections_count < 2 do
    b.add_section()
  end

  b.get_section(2).filters = signals

  -- Update GUI for all players viewing this combinator
  for _, player in pairs(game.players) do
    local frame = storage.guis[player.index]
    if frame and frame.context == combinator then
      gui.update_signal_display(player, combinator)
    end
  end
end

-- Handle Cybersyn station events
function OnCybersynStationCreated(event)
  -- When a new Cybersyn station is created, update all combinators
  ForceUpdateAllCombinators()
end

function OnCybersynStationRemoved(event)
  -- When a Cybersyn station is removed, update all combinators
  ForceUpdateAllCombinators()
end

-- add/remove event handlers
--- @param event EventData.on_built_entity
function OnEntityCreated(event)
  local entity = event.entity
  if content_readers[entity.name] then
    table.insert(storage.content_combinators, entity)

    -- Immediately update the new combinator
    InitSignals() -- Always call InitSignals to ensure data is available
    Update_Combinator(entity)

    if #storage.content_combinators == 1 then
      script.on_event(defines.events.on_tick, OnTick)
    end
  end
end

function OnEntityRemoved(event)
  local entity = event.entity
  if content_readers[entity.name] then
    for i=#storage.content_combinators, 1, -1 do
      if storage.content_combinators[i].unit_number == entity.unit_number then
        table.remove(storage.content_combinators, i)
      end
    end

    if #storage.content_combinators == 0 then
			script.on_event(defines.events.on_tick, nil)
    end
  end
end

-- Register Cybersyn events when the mod is loaded
function RegisterCybersynEvents()
  -- Try different possible event names that Cybersyn might use
  local cybersyn_events = {
    "cybersyn_dispatcher_updated",
    "on_cybersyn_dispatcher_updated", 
    "cybersyn-network-updated",
    "on_cybersyn_network_updated"
  }
  
  local event_registered = false
  for _, event_name in pairs(cybersyn_events) do
    local success, event_id = pcall(function() return remote.call("cybersyn", event_name) end)
    if success and event_id then
      script.on_event(event_id, OnCybersynDispatcherUpdated)
      event_registered = true
      break
    end
  end
  
  -- Try to register Cybersyn station events
  local cybersyn_station_events = {
    "cybersyn_station_created",
    "on_cybersyn_station_created",
    "cybersyn_station_removed", 
    "on_cybersyn_station_removed"
  }
  
  for _, event_name in pairs(cybersyn_station_events) do
    local success, event_id = pcall(function() return remote.call("cybersyn", event_name) end)
    if success and event_id then
      if event_name:find("created") then
        script.on_event(event_id, OnCybersynStationCreated)
      elseif event_name:find("removed") then
        script.on_event(event_id, OnCybersynStationRemoved)
      end
    end
  end
  
  return event_registered
end

---- Initialisation  ----
do
  local function init_globals()
    storage.cybersyn_stops = storage.cybersyn_stops or {}
    storage.cybersyn_provided = storage.cybersyn_provided or {}
    storage.cybersyn_requested = storage.cybersyn_requested or {}
    storage.cybersyn_deliveries = storage.cybersyn_deliveries or {}
    storage.content_combinators = storage.content_combinators or {}
    storage.update_interval = settings.global["cybersyn_content_reader_update_interval"].value
  end

  local function register_events()
    -- register game events
    script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, OnEntityCreated)
    script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, OnEntityRemoved)
    
    -- Register Cybersyn events
    local event_registered = RegisterCybersynEvents()
    
    if #storage.content_combinators > 0 then
      script.on_event(defines.events.on_tick, OnTick)
    end
    
    return event_registered
  end

  local function register_events_with_fallback()
    -- register game events
    script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, OnEntityCreated)
    script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, OnEntityRemoved)
    
    -- Register Cybersyn events
    local event_registered = RegisterCybersynEvents()
    
    -- If no Cybersyn events are available, use a more frequent tick-based update
    if not event_registered then
      -- Reduce update interval for better responsiveness when Cybersyn events aren't available
      storage.update_interval = math.min(storage.update_interval, 15)
    end
    
    if #storage.content_combinators > 0 then
      script.on_event(defines.events.on_tick, OnTick)
    end
  end

  script.on_init(function()
    init_globals()
    gui.on_init()
    register_events_with_fallback()
    
    -- Try to register Cybersyn events after a delay in case Cybersyn loads after this mod
    script.on_nth_tick(60, function()
      RegisterCybersynEvents()
    end)
  end)

  script.on_configuration_changed(function(data)
    init_globals()
  end)

  script.on_load(function(data)
    register_events()
  end)
  
  -- Add console command for debugging
  commands.add_command("cybersyn-content-reader-update", "Force update all Cybersyn content reader combinators", function(command)
    ForceUpdateAllCombinators()
    if command.player_index then
      local player = game.get_player(command.player_index)
      if player then
        player.print("Cybersyn content reader combinators updated.")
      end
    end
  end)
end