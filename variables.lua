-- localize often used functions and strings
content_readers = {
    ["cybersyn-provider-reader"] = {table_name = "cybersyn_provided"},
    ["cybersyn-requester-reader"] = {table_name = "cybersyn_requested"},
    ["cybersyn-delivery-reader"] = {table_name = "cybersyn_deliveries"},
}

require_same_surface = settings.global["cybersyn_content_reader_same_surface"].value

-- get default network from LTN
default_network = settings.global["cybersyn-network-flag"].value

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if not event then return end
  if event.setting == "cybersyn-network-flag" then
    default_network = settings.global["cybersyn-network-flag"].value
  end
  if event.setting == "cybersyn_content_reader_update_interval" then
    storage.update_interval = settings.global["cybersyn_content_reader_update_interval"].value
  end
  if event.setting == "cybersyn_content_reader_same_surface" then
    require_same_surface = settings.global["cybersyn_content_reader_same_surface"].value
  end
end)