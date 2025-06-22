data:extend({
  {
    type = "int-setting",
    name = "cybersyn_content_reader_update_interval",
    order = "aa",
    setting_type = "runtime-global",
    default_value = 30,
    minimum_value = 1,
    maximum_value = 216000, -- 1h
  },
  {
    type = "bool-setting",
    name = "cybersyn_content_reader_same_surface",
    order = "aa",
    setting_type = "runtime-global",
    default_value = false
  }
})