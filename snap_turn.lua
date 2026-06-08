local gn = reframework:get_game_name()
if gn ~= "re2" and gn ~= "re3" then 
    return
end

local re2 = require("utility/RE2")

local cfg = {
    snap_turn_back_enabled = true,
    snap_turn_angle = 45.0,
    recenter_threshold = 0.4,
    tilt_threshold = 0.8,
    zero_pitch = true,
    no_camera_recoil = true,
}

local cfg_path = "re2_vr/snap_turn_config.json"

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

local function should_apply_snap_turn()
    return vrmod:is_hmd_active()
end

local jackdominator_rtt = nil
local jackdominator_td = sdk.find_type_definition(sdk.game_namespace("JackDominator"))
local jacked_method = jackdominator_td:get_method("get_Jacked")

local function is_jacked(go)
    jackdominator_rtt = jackdominator_rtt or sdk.typeof(sdk.game_namespace("JackDominator"))
    local jd = go:call("getComponent(System.Type)", jackdominator_rtt)
    if not jd then return false end
    return jacked_method:call(jd)
end

sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("camera.TwirlerCameraControllerRoot")):get_method("updateYaw"),
    function(args)
        if not should_apply_snap_turn() then return end
        -- Block native stick turn input.
        args[3] = sdk.float_to_ptr(0.0)
    end,
    function(retval)
        return retval
    end
)

sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("camera.TwirlerCameraControllerRoot")):get_method("updatePitch"),
    function(args)
        if not should_apply_snap_turn() or not cfg.zero_pitch then return end
        local this = sdk.to_managed_object(args[2])
        if this == nil then return end
        this:call("setPitch", 0.0)
    end,
    function(retval)
        return retval
    end
)

sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("camera.TwirlerCameraControllerRoot")):get_method("setPitch"),
    function(args)
        if not should_apply_snap_turn() or not cfg.zero_pitch then return end
        args[3] = sdk.float_to_ptr(0.0)
    end,
    function(retval)
        return retval
    end
)

local gamepad_singleton_t = sdk.find_type_definition("via.hid.GamePad")

local function get_right_input_axis()
    if vrmod:is_using_controllers() then
        local axis = vrmod:get_right_stick_axis()
        return axis
    end

    local gamepad_singleton = sdk.get_native_singleton("via.hid.GamePad")
    if not gamepad_singleton then return Vector2f.new(0, 0) end

    local pad = sdk.call_native_func(gamepad_singleton, gamepad_singleton_t, "get_LastInputDevice")
    if not pad then return Vector2f.new(0, 0) end

    return pad:get_AxisR()
end

local function math_sign(x)
    return x > 0 and 1 or (x < 0 and -1 or 0)
end

local is_stick_reset = true

local function get_stick_turn_rad()
    local axis = get_right_input_axis()
    local x = axis.x
    local y = axis.y
    if is_stick_reset then
        if math.abs(x) > cfg.tilt_threshold then
            is_stick_reset = false
            return math.rad(math_sign(x) * cfg.snap_turn_angle)
        end
        if cfg.snap_turn_back_enabled and y < -cfg.tilt_threshold and math.abs(x) < cfg.recenter_threshold then
            is_stick_reset = false
            return math.rad(180.0)
        end
    end
    if math.abs(x) < cfg.recenter_threshold and math.abs(y) < cfg.recenter_threshold then
        is_stick_reset = true
    end
    return 0.0
end

sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("camera.TwirlerCameraControllerRoot")):get_method("setYaw"),
    function(args)
        if not should_apply_snap_turn() or not re2.player or is_jacked(re2.player) then return end
        stick_turn_rad = get_stick_turn_rad()
        args[3] = sdk.float_to_ptr(sdk.to_float(args[3]) - stick_turn_rad)
    end,
    function(retval)
        return retval
    end
)

-- Zero out recoil camera bounce.
sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("DeviateParam")):get_method("get_CameraRecoli"),
    function(args)
    end,
    function(retval)
        if cfg.no_camera_recoil and should_apply_snap_turn() then
            local camera_recoil_param=sdk.to_managed_object(retval)
            camera_recoil_param:set_field("Yaw", 0.0)
            camera_recoil_param:set_field("Pitch", 0.0)
        end
        return retval
    end
)

re.on_draw_ui(function()
    local changed = false
    if imgui.tree_node("Snap Turn") then
        changed, cfg.snap_turn_angle = imgui.drag_float("Snap Turn Angle", cfg.snap_turn_angle, 15.0, 15.0, 90.0)
        changed, cfg.snap_turn_back_enabled = imgui.checkbox("Tild Down to Turn Back Enabled", cfg.snap_turn_back_enabled)
        changed, cfg.tilt_threshold = imgui.drag_float("Snap Turn Tilt Threshold", cfg.tilt_threshold, 0.05, 0.1, 1.0)
        changed, cfg.recenter_threshold = imgui.drag_float("Snap Turn Recenter Threshold", cfg.recenter_threshold, 0.05, 0.1, 1.0)
        changed, cfg.no_camera_recoil = imgui.checkbox("No Camera Recoil in VR", cfg.no_camera_recoil)
        changed, cfg.zero_pitch = imgui.checkbox("Set Pitch to Zero", cfg.zero_pitch)
        imgui.tree_pop()
    end
end)
