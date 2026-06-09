local gn = reframework:get_game_name()
if gn ~= "re2" and gn ~= "re3" then 
    return
end

local cfg = {
    turn_speed_multiplier = 1.0,
}

local cfg_path = "re2_vr/turn_speed_multiplier_config.json"

local function load_cfg()
    local loaded_cfg = json.load_file(cfg_path)

    if loaded_cfg == nil then
        json.dump_file(cfg_path, cfg)
        return
    end

    for k, v in pairs(loaded_cfg) do
        cfg[k] = v
    end
end

load_cfg()

re.on_config_save(function()
    json.dump_file(cfg_path, cfg)
end)

sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("camera.TwirlerCameraControllerRoot")):get_method("updateYaw"),
    function(args)
        args[3] = sdk.float_to_ptr(cfg.turn_speed_multiplier * sdk.to_float(args[3]))
    end,
    function(retval)
        return retval
    end
)

sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("camera.TwirlerCameraControllerRoot")):get_method("updatePitch"),
    function(args)
        args[3] = sdk.float_to_ptr(cfg.turn_speed_multiplier * sdk.to_float(args[3]))
    end,
    function(retval)
        return retval
    end
)

re.on_draw_ui(function()
    local changed = false
    if imgui.tree_node("Turn Speed Adjustment") then
        changed, cfg.turn_speed_multiplier = imgui.drag_float("Turn Speed Multiplier", cfg.turn_speed_multiplier, 0.05, 0.1, 20.0)
        imgui.tree_pop()
    end
end)
