local gn = reframework:get_game_name()
if gn ~= "re2" and gn ~= "re3" then 
    return
end

local re2 = require("utility/RE2")

local cfg = {
    snap_turn_enabled = true,
    snap_turn_back_enabled = true,
    no_camera_recoil = true,
    angle = 45.0,
    tilt_threshold = 0.8,
    recenter_threshold = 0.4,
}

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

local function set_world_rotation(rot)
    camera_system = sdk.get_managed_singleton(sdk.game_namespace("camera.CameraSystem"))
    if not camera_system then return end
    camera_controller = camera_system:call("get_BusyCameraController")
    if not camera_controller then return end
    camera_controller:call("set_CameraRotation", rot)
end

local function math_sign(x)
    if x > 0 then
        return 1
    elseif x < 0 then
        return -1
    else
        return 0
    end
end

local function calculate_turn_quat(angle)
    local turn_angle_rad = math.rad(angle)
    local half_theta = turn_angle_rad / 2
    return Quaternion.new(math.cos(half_theta), 0, math.sin(half_theta), 0)
end

local camera_rot = Quaternion.new(math.rad(90)/2, 0, math.rad(90)/2, 0)
local is_stick_centered = true
local is_stick_centered_y = true

re.on_pre_application_entry("CreateUpdateGroupBehaviorTree", function()
    if not cfg.snap_turn_enabled then
        return
    end
    if not re2.player then
        return 
    end
    if not firstpersonmod:will_be_used() then
        return
    end
    if not vrmod:is_hmd_active() then
        return
    end

    local right_stick_axis = get_right_input_axis()
    local x_axis = right_stick_axis.x
    local y_axis = right_stick_axis.y
    if is_stick_centered then
        if math.abs(x_axis) > cfg.tilt_threshold then
            camera_rot = camera_rot * calculate_turn_quat(cfg.angle * (-math_sign(x_axis)))
            is_stick_centered = false
        end
    elseif math.abs(x_axis) < cfg.recenter_threshold then
        is_stick_centered = true
    end
    if cfg.snap_turn_back_enabled and is_stick_centered then
        if is_stick_centered_y then
            if y_axis < -cfg.tilt_threshold then
                camera_rot = camera_rot * calculate_turn_quat(180)
                is_stick_centered_y = false
            end
        elseif math.abs(y_axis) < cfg.recenter_threshold then
            is_stick_centered_y = true
        end
    end
    set_world_rotation(camera_rot)
end)

-- Zero out recoil camera bounce.
sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("DeviateParam")):get_method("get_CameraRecoli"),
    function(args)
    end,
    function(retval)
        if cfg.no_camera_recoil then
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
        changed, cfg.snap_turn_enabled = imgui.checkbox("Snap Turn Enabled", cfg.snap_turn_enabled)
        if cfg.snap_turn_enabled then
            changed, cfg.angle = imgui.drag_float("Turn Angle", cfg.angle, 1.0, 15.0, 180.0)
            changed, cfg.snap_turn_back_enabled = imgui.checkbox("Snap Turn Back Enabled", cfg.snap_turn_back_enabled)
            changed, cfg.tilt_threshold = imgui.drag_float("Snap Turn Tilt Threshold", cfg.tilt_threshold, 0.05, 0.1, 1.0)
            changed, cfg.recenter_threshold = imgui.drag_float("Snap Turn Recenter Threshold", cfg.recenter_threshold, 0.05, 0.1, 1.0)
        end
        changed, cfg.no_camera_recoil = imgui.checkbox("No Camera Recoil", cfg.no_camera_recoil)
        imgui.tree_pop()
    end
end)
