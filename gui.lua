--[[ Copyright (c) 2024 Danbopes
 * Part of Cybersyn Content Reader
 *
 * See LICENSE.md in the project directory for license information.
--]]

local flib_gui = require("__flib__.gui")
require('variables')
require('utils')
local gui = {}

-- Constants for GUI element names
local NETWORK_SELECTOR = "network_selector"
local NETWORK_ID_FIELD = "network_id_field"
local SIGNAL_DISPLAY = "signal_display"

local function handle_network_switch(event)
    if event.name == defines.events.on_gui_elem_changed or event.name == defines.events.on_gui_text_changed then
        local player = game.get_player(event.player_index)
        if not player then return end
        local ref = storage.guis[player.index]
        if not ref then return end

        local signal = ref[NETWORK_SELECTOR].elem_value
        local network_id = tonumber(ref[NETWORK_ID_FIELD].text) or default_network

        local combinator = ref.context
        if not combinator or not combinator.valid then return end

        local behavior = combinator.get_control_behavior()
        if not behavior then return end

        local section = behavior.get_section(1)
        if section then
            section.filters = {
                {
                    value = signal,
                    min = network_id
                }
            }
        end
    end
end

-- Handle opening the combinator GUI
local function on_gui_opened(event)
    if not event.entity then return end
    if not content_readers[event.entity.name] then return end
  
    local player = game.get_player(event.player_index)
    if not player then return end
  
    player.opened = nil
  
    -- Create the GUI
    gui.create_gui(player, event.entity)

end

local function handle_close(event)
    if not event.element then return end
  
    local player = game.get_player(event.player_index)
    if not player then return end
  
    -- Remove the GUI
    local ref = storage.guis[player.index]
    if ref then
      ref.window.destroy()
      player.play_sound({ path = "entity-close/cybersyn-combinator" })
      storage.guis[player.index] = nil
    end
end
  
  -- Handle closing the combinator GUI
local function on_gui_closed(event)
    if not event.element or event.element.name ~= "cybersyn_content_reader_gui" then return end
  
    local player = game.get_player(event.player_index)
    if not player then return end
  
    -- Remove the GUI
    local ref = storage.guis[player.index]
    if ref then
      ref.window.destroy()
      player.play_sound({ path = "entity-close/cybersyn-combinator" })
      storage.guis[player.index] = nil
    end
end

-- Create the GUI for a combinator
function gui.create_gui(player, combinator)
    -- Remove any existing GUI
    local existing_frame = player.gui.screen.cybersyn_content_reader_gui
    if existing_frame then
        existing_frame.destroy()
    end

    -- Get current signal and value
    local slot = get_first_signal(combinator) or {}
    local current_signal = slot.value or nil
    local current_id = slot.min or default_network

    local refs, main_window = flib_gui.add(player.gui.screen, {
        type = "frame",
        name = "cybersyn_content_reader_gui",
        direction = "vertical",
        children = {
            {
                type = "flow",
                name = "titlebar",
                children = {
                    {
                        type = "label",
                        style = "frame_title",
                        caption = { "entity-name." .. combinator.name },
                        elem_mods = { ignored_by_interaction = true },
                    },
                    { type = "empty-widget", style = "flib_titlebar_drag_handle", elem_mods = { ignored_by_interaction = true } },
                    {
                        type = "sprite-button",
                        style = "frame_action_button",
                        tooltip = { "gui.close-instruction" },
                        mouse_button_filter = { "left" },
                        sprite = "utility/close",
                        hovered_sprite = "utility/close",
                        name = combinator.name,
                        handler = handle_close,
                    },
                }
            },
            {
                type = "frame",
                style = "inside_deep_frame",
                direction = "vertical",
                children = {
                    type = "frame",
                    style = "cybersyn_content_reader_network_selector_frame",
                    children = {
                        {
                            type = "label",
                            caption = "Network Signal:",
                        },
                        {
                            type = "choose-elem-button",
                            name = NETWORK_SELECTOR,
                            elem_type = "signal",
                            signal = current_signal,
                            handler = handle_network_switch,
                        },
                        {
                            type = "label",
                            caption = "Network ID:",
                            style_mods = {
                                vertical_align = "center",
                            },
                        },
                        {
                            type = "textfield",
                            name = NETWORK_ID_FIELD,
                            style_mods = {
                                width = 100,
                            },
                            numeric = true,
                            allow_negative = true,
                            text = tostring(current_id),
                            handler = handle_network_switch,
                        }
                    }
                }
            },
            {
                type = "frame",
                style = "inside_shallow_frame_with_padding",
                direction = "vertical",
                children = {
                    {
                        type = "label",
                        caption = "Signals:",
                        style = "subheader_caption_label",
                        style_mods = {
                            bottom_padding = 4,
                        }
                    },
                    {
                        type = "frame",
                        style = "deep_frame_in_shallow_frame",
                        children = {
                            {
                                type = "table",
                                name = SIGNAL_DISPLAY,
                                style = "slot_table",
                                direction = "vertical",
                                column_count = 8,
                                style_mods = {
                                    right_padding = 0,
                                }
                            }
                        }
                    }
                }
            }
        }
    })

    refs.titlebar.drag_target = main_window
    main_window.force_auto_center()

    storage.guis[player.index] = {
        context = combinator,
        window = main_window,
        [NETWORK_SELECTOR] = refs[NETWORK_SELECTOR],
        [NETWORK_ID_FIELD] = refs[NETWORK_ID_FIELD],
        [SIGNAL_DISPLAY] = refs[SIGNAL_DISPLAY],
    }

    -- Signal display
    -- local signal_frame = main_window.add{
    --     type = "frame",
    --     name = SIGNAL_DISPLAY,
    --     style = "cybersyn_content_reader_signal_display",
    --     direction = "vertical"
    -- }

    -- Update the signal display
    gui.update_signal_display(player, combinator)

    player.opened = main_window
end

-- Update the signal display with current signals
---@param player LuaPlayer
---@param combinator LuaEntity
function gui.update_signal_display(player, combinator)
    local ref = storage.guis[player.index]
    if not ref then return end

    --- @type LuaGuiElement
    local signal_frame = ref[SIGNAL_DISPLAY]
    if not signal_frame or not signal_frame.valid then return end

    signal_frame.clear()

    local behavior = combinator.get_control_behavior() ---@type LuaConstantCombinatorControlBehavior
    if not behavior then return end

    local section = behavior.get_section(2)
    if not section then return end

    --local columns = 10

    -- Display signals as icon buttons with count below
    --local flow = signal_frame.add{
    --    type = "flow",
	--	{
	--		type = "frame",
	--		style = "deep_frame_in_shallow_frame",
	--		style_mods = { height = 200 },
	--		ref = { "inventory", "frame" },
	--		{
	--			type = "scroll-pane",
	--			style = "ltnm_slot_table_scroll_pane",
	--			style_mods = { width = 40 * columns + 12, minimal_height = 400 },
	--			vertical_scroll_policy = "auto-and-reserve-space",
	--			-- vertical_scroll_policy = "always",
	--			ref = { "inventory", "scroll_pane" },
	--			{
	--				type = "table",
	--				name = "inventory_table",
	--				style = "slot_table",
	--				column_count = columns,
	--				ref = { "inventory", "table" }
	--			},
	--		},
	--	},
    --}
    
    for _, signal in pairs(section.filters) do
        if signal.value then
            local item_prototype = prototypes[signal.value.type][signal.value.name]
            local caption = format_signal_count(signal.min)
            local button = signal_frame.add({
                type = "sprite-button",
                sprite = signal.value.type .. "/" .. signal.value.name,
                style = "flib_slot_button_default",
                tooltip = {
                    "",
                    item_prototype.localised_name,
                },
                number = signal.min,
                -- children = {
                --     {
                --         type = "label",
                --         style = "cybersyn_content_reader_label_signal_count_inventory",
                --         ignored_by_interaction = true,
                --         caption = caption,
                --     },
                -- }
            })
            button.number = signal.min
        end
    end
end

function gui.on_init()
    storage.guis = {}
    -- Register event handlers
    -- script.on_event(defines.events.on_gui_elem_changed, gui.on_gui_elem_changed)
    -- script.on_event(defines.events.on_gui_text_changed, gui.on_gui_text_changed)
end

flib_gui.add_handlers({
    ["comb_closed"] = handle_close,
    ["comb_network_switch"] = handle_network_switch,
})
flib_gui.handle_events()

script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_gui_closed, on_gui_closed)

return gui