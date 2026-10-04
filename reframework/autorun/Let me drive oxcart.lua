-- Let me drive oxcart: independent manual-driving controller.
-- Game type/method names are runtime identifiers, not bundled mod dependencies.
local TITLE = "Let me drive oxcart"
local CONFIG = "LetMeDriveOxcart.json"
local bus = rawget(_G, "DD2_OxcartControl") or { version = 1 }
_G.DD2_OxcartControl = bus
local state = { active = false, level = 1, axis = 0, error = nil, seats = {}, protected = {} }
local modes = { "Wait", "Walk", "Run", "Dash" }
local settings = { sensitivity = 45, preset = 1, presets = {
    { name = "Driver and passengers", slots = {
        { x = 0, y = 0.65, z = -1.7, yaw = 0 },
        { x = 0.85, y = 0.23, z = -3.35, yaw = 90 },
        { x = -0.85, y = 0.23, z = -3.35, yaw = -90 },
        { x = 0.85, y = 0.23, z = -4.1, yaw = 90 },
    } },
} }
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function attempt(fn) local ok, value = pcall(fn); if ok then return value end end
local function valid(obj) return obj and attempt(function() return obj:get_Valid() end) == true end
local function address(obj) return obj and attempt(function() return obj:get_address() end) end
local function singleton(name) return sdk.get_managed_singleton(name) end
local function save() json.dump_file(CONFIG, settings) end
local saved = attempt(function() return json.load_file(CONFIG) end)
if type(saved) == "table" then
    settings.sensitivity = clamp(tonumber(saved.sensitivity) or 45, 5, 180)
    -- Validate persisted layouts before allowing them to write actor transforms.
    if type(saved.presets) == "table" and #saved.presets > 0 then
        local layouts = {}
        for _, layout in ipairs(saved.presets) do
            if type(layout) == "table" and type(layout.slots) == "table" and #layout.slots == 4 then
                local copy = { name = tostring(layout.name or "Layout"), slots = {}, pawns_customized = layout.pawns_customized == true }
                local complete = true
                for i, slot in ipairs(layout.slots) do
                    if type(slot) ~= "table" then complete = false; break end
                    copy.slots[i] = {}
                    for _, key in ipairs({ "x", "y", "z", "yaw" }) do
                        local n = tonumber(slot[key])
                        if not n or n ~= n or math.abs(n) > 1000 then complete = false; break end
                        copy.slots[i][key] = n
                    end
                    for _, key in ipairs({ "anim", "useOxAnchor", "randomIdle", "useDirectMotion", "freezeFsm", "bankID", "motionID" }) do
                        local value = slot[key]
                        if type(value) == "string" or type(value) == "boolean" or type(value) == "number" then copy.slots[i][key] = value end
                    end
                end
                if complete then layouts[#layouts + 1] = copy end
            end
        end
        if #layouts > 0 then settings.presets = layouts end
    end
    settings.preset = clamp(math.floor(tonumber(saved.preset) or 1), 1, #settings.presets)
end

local function player()
    local cm = singleton("app.CharacterManager")
    return cm and cm["<ManualPlayer>k__BackingField"]
end
local function discover()
    local nm = singleton("app.NPCManager")
    local om = nm and nm.OxcartManager
    local go = om and om._RaidAttack_CachedGameObject
    if not valid(go) then return nil end
    local ox = go:call("getComponent(System.Type)", sdk.typeof("app.Character"))
    if not valid(ox) then return nil end
    local ch = ox.EnemyCtrl and ox.EnemyCtrl.Ch2
    local parts = ch and ch["<CachedConnectParts>k__BackingField"]
    local cow = parts and parts.CowChara
    if not valid(cow) then return nil end
    local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"),
        sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
    if not scene then return nil end
    local best, nearest = nil, 12
    for _, model in ipairs({ "gm80_042", "gm80_052", "gm81_004" }) do
        for suffix = -1, 10 do
            local name = suffix == -1 and model or string.format("%s_%02d", model, suffix)
            local body = scene:call("findGameObject(System.String)", name)
            if valid(body) then
                local transform = body:get_Transform()
                local distance = (transform:get_Position() - ox:get_Transform():get_Position()):length()
                if distance < nearest then best, nearest = transform, distance end
            end
        end
    end
    if not best then return nil end
    local anchor, child = best, best:get_Child()
    while child do
        if child:get_GameObject():get_Name():find("MoveFloor", 1, true) then anchor = child; break end
        child = child:get_Next()
    end
    local status = om:getStatus(ox:get_CharaID())
    local driver = status and attempt(function() return nm:getCharacter(status:call("getCurrentDriver")) end)
    return { ox = ox, cow = cow, body = best, anchor = anchor, driver = driver, status = status }
end
local function paused()
    local gui = singleton("app.GuiManager")
    if not gui then return true end
    return attempt(function() return gui:call("isPausedGUI()") end) == true
        or attempt(function() return gui:call("get_IsLoadGui()") end) == true
        or gui["<IsDispPhotoModeAll>k__BackingField"] == true
end
local function fsm(actor)
    local human = actor["<Human>k__BackingField"]
    return human and human.Fsm or actor:get_ActionManager().Fsm
end
local function action(actor, name, requested_priority)
    local am = actor["<ActionManager>k__BackingField"] or actor:get_ActionManager()
    assert(am, "ActionManager unavailable")
    state.issuing = true
    local priority = requested_priority or (name == "SitOnChairActions" and 1 or 0)
    local ok, err = pcall(function() am:call("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", priority, name, 0) end)
    state.issuing = false
    if not ok then error(err) end
end
local function hold(actor)
    local machine = fsm(actor)
    assert(machine, "Actor FSM unavailable")
    local was = machine:call("get_Enabled()")
    assert(type(was) == "boolean", "Cannot capture original FSM state")
    local record = { actor = actor, machine = machine, enabled = was }
    machine:call("set_Enabled(System.Boolean)", false)
    return record
end
local function unhold(record)
    if record and record.machine and valid(record.actor) then attempt(function() record.machine:call("set_Enabled(System.Boolean)", record.enabled) end) end
end
local function party()
    local pm = singleton("app.PawnManager")
    local list, seen = {}, {}
    local function add(pawn)
        local actor = pawn and pawn:get_CachedCharacter()
        local id = address(actor)
        if valid(actor) and not seen[id] and #list < 3 then seen[id] = true; list[#list + 1] = actor end
    end
    if pm then
        add(pm:get_MainPawn())
        local members = pm:get_PartyPawnList()
        if members then
            for i = 0, members:get_Count() - 1 do add(members._items and members._items[i] or members:get_Item(i)) end
        end
    end
    return list
end
local function offset_position(anchor, slot)
    local p, x, y, z = anchor:get_Position(), anchor:get_AxisX(), anchor:get_AxisY(), anchor:get_AxisZ()
    return Vector3f.new(p.x + x.x * slot.x + y.x * slot.y + z.x * slot.z,
        p.y + x.y * slot.x + y.y * slot.y + z.y * slot.z,
        p.z + x.z * slot.x + y.z * slot.y + z.z * slot.z)
end
local function capture_offset(anchor, actor)
    local delta = actor:get_Transform():get_Position() - anchor:get_Position()
    local function dot(axis) return delta.x * axis.x + delta.y * axis.y + delta.z * axis.z end
    return { x = dot(anchor:get_AxisX()), y = dot(anchor:get_AxisY()), z = dot(anchor:get_AxisZ()), yaw = 0 }
end
local function pose(record, slot, visual_only)
    if not valid(record.actor) then return end
    local transform = record.actor:get_Transform()
    local anchor = slot.useOxAnchor and state.cart.ox:get_Transform() or state.cart.anchor
    local p = offset_position(anchor, slot)
    -- Player FSM stays live. A character warp updates its gameplay controller
    -- and model together; Transform-only writes can leave those out of sync.
    if record.player and not visual_only then
        record.actor:call("warp(via.vec3, app.CharacterWarpOption)", p, nil)
    end
    transform:set_Position(p)
    local a = math.rad(slot.yaw)
    local x, z = anchor:get_AxisX(), anchor:get_AxisZ()
    transform:lookAt(Vector3f.new(p.x + x.x * math.sin(a) + z.x * math.cos(a),
        p.y + x.y * math.sin(a) + z.y * math.cos(a), p.z + x.z * math.sin(a) + z.z * math.cos(a)), anchor:get_AxisY())
end
local release
local function release_seats()
    for _, record in ipairs(state.seats) do
        unhold(record)
        if not record.player and valid(record.actor) then attempt(function() action(record.actor, "Wait") end) end
    end
    state.seats = {}
end
local function inherit_passengers(cart)
    local layout = settings.presets[settings.preset]
    if layout.pawns_customized then return end
    local passengers = bus.journey and bus.journey.passenger_layout and bus.journey.passenger_layout()
    if not passengers then
        -- Optional config import also works with Journey disabled/uninstalled.
        local config = attempt(function() return json.load_file("OxcartsJourneyRedux.json") end)
        local name = cart and cart.body:get_GameObject():get_Name() or ""
        local family = name:find("gm80_052", 1, true) and "Wealthy"
            or name == "gm80_042_00" and "Normal" or "Rainy"
        local presets = type(config) == "table" and type(config.Presets) == "table"
            and (config.Presets[family] or config.Presets.Normal)
        if type(presets) == "table" then
            for _, preset in ipairs(presets) do
                if preset.enabled ~= false then passengers = preset.pawns; break end
            end
        end
    end
    if type(passengers) ~= "table" then return end
    for i = 1, 3 do
        local spec = passengers[i]
        if type(spec) == "table" and tonumber(spec.x) and tonumber(spec.y) and tonumber(spec.z) then
            local slot = { yaw = math.deg(math.atan(spec.lookX or 0, spec.lookZ or 1)) }
            for _, key in ipairs({ "x", "y", "z", "anim", "useOxAnchor", "randomIdle", "useDirectMotion", "freezeFsm", "bankID", "motionID" }) do
                slot[key] = spec[key]
            end
            layout.slots[i + 1] = slot
        end
    end
    save()
end
local function animate(record, slot)
    if slot.useDirectMotion then
        record.actor:get_Motion():getLayer(0):call("changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)",
            slot.bankID or 0, slot.motionID or 0, 0, 12, 1, 1)
    else
        action(record.actor, slot.anim or "SitOnChairActions", 1)
    end
end
local function arrange()
    release_seats()
    -- Never freeze the player's FSM or replace its native seated action.
    state.seats[1] = { actor = state.player, player = true, slot = 1 }
    local layout = settings.presets[settings.preset]
    for i, actor in ipairs(party()) do
        local slot = layout.slots[i + 1]
        local record = { actor = actor, slot = i + 1 }
        animate(record, slot)
        if slot.freezeFsm ~= false then record = hold(actor); record.slot = i + 1 end
        record.next_idle = os.clock() + 15
        state.seats[#state.seats + 1] = record
    end
end
release = function(reason)
    local cart = state.cart
    state.active = false
    if cart and valid(cart.ox) then attempt(function() action(cart.ox, "Wait") end) end
    if valid(state.player) then
        attempt(function()
            state.player:call("warp(via.vec3, app.CharacterWarpOption)", state.player:get_Transform():get_Position(), nil)
            action(state.player, "Wait")
        end)
    end
    release_seats()
    if state.driver then
        if cart and valid(cart.body:get_GameObject()) then attempt(function() pose(state.driver, state.driver.original) end) end
        unhold(state.driver)
    end
    state.driver, state.cart, state.player = nil, nil, nil
    state.protected, state.axis, state.heading = {}, 0, nil
    if bus.owner == TITLE then bus.owner, bus.heartbeat = nil, nil end
    if state.ojr_claimed and bus.journey and bus.journey.resume then attempt(bus.journey.resume) end
    state.ojr_claimed = false
    state.message = reason or "Control released; navigation recovery is not guaranteed"
end
local function acquire()
    if state.active then release(); return end
    assert(not paused(), "Close the paused game menu before taking control")
    assert(not bus.owner, "Another controller owns this cart")
    assert(not rawget(_G, "OJR_SeatBindings") or bus.journey,
        "Installed Oxcarts Journey Redux needs the compatibility build")
    local cart, human = discover(), player()
    assert(cart and valid(human), "No nearby connected oxcart/player")
    assert((human:get_Transform():get_Position() - cart.body:get_Position()):length() <= 8, "Approach within 8 units of the cart")
    local origin = capture_offset(cart.anchor, human)
    inherit_passengers(cart)
    if bus.journey and bus.journey.suspend then
        state.ojr_claimed = true
        bus.journey.suspend()
    end
    state.cart, state.player, state.level = cart, human, 1
    settings.presets[settings.preset].slots[1].x = origin.x
    settings.presets[settings.preset].slots[1].y = origin.y
    settings.presets[settings.preset].slots[1].z = origin.z
    bus.owner, bus.heartbeat, state.active = TITLE, os.clock(), true
    if valid(cart.driver) and cart.driver ~= human then
        state.driver = hold(cart.driver)
        state.driver.original = capture_offset(cart.anchor, cart.driver)
        action(cart.driver, "Wait")
        pose(state.driver, { x = 3.5, y = 0, z = -2, yaw = 0 })
    end
    action(cart.ox, "Wait")
    state.heading = tonumber(cart.cow["<PosRotContext>k__BackingField"]:call("get_AngleYDeg()"))
    assert(state.heading, "Cow heading unavailable")
    arrange()
    state.message = "Manual control active"
end
local function command(fn)
    local ok, err = pcall(fn)
    if not ok then state.error = tostring(err); release("Control released after error"); log.error("[" .. TITLE .. "] " .. state.error) end
end
local function shift(delta)
    if not state.active then return end
    state.level = clamp(state.level + delta, 1, #modes)
    action(state.cart.ox, modes[state.level])
end

-- Direct HID polling: no borrowed hotkey library or action-flag mouse constants.
local function enum(name)
    local result, def = {}, sdk.find_type_definition(name)
    if def then for _, field in ipairs(def:get_fields()) do if field:is_static() then result[field:get_name()] = field:get_data(nil) end end end
    return result
end
local keys, pads = enum("via.hid.KeyboardKey"), enum("via.hid.GamePadButton")
local previous, input = {}, { keyboard = 0, stick = 0 }
local function poll()
    local kb = sdk.call_native_func(sdk.get_native_singleton("via.hid.Keyboard"), sdk.find_type_definition("via.hid.Keyboard"), "get_Device")
    local gp = sdk.call_native_func(sdk.get_native_singleton("via.hid.Gamepad"), sdk.find_type_definition("via.hid.GamePad"), "get_MergedDevice")
    local bits = gp and gp:call("get_Button") or 0
    local function down(name) return kb and keys[name] and kb:call("isDown", keys[name]) == true end
    local function pad(name) local n = pads[name]; return n and n ~= 0 and (bits & n) == n end
    local now = {
        take = down("G") or pad("RTrigBottom"), sit = down("E") or pad("RLeft"),
        stand = down("F") or pad("Cancel"), up = pad("RTrigTop"), down = pad("LTrigTop"),
    }
    local modifier = down("LShift") or pad("LTrigBottom")
    if modifier then
        now.up = now.up or down("Alpha1") or pad("LUp")
        now.down = now.down or down("Alpha2") or pad("LLeft")
        now.sit = now.sit or down("Alpha3") or pad("LRight")
        now.stand = now.stand or down("Alpha4") or pad("LDown")
    end
    -- Resolve real mouse button enum names through reflection.
    local mouse_type = sdk.find_type_definition("via.hid.Mouse")
    local mouse = mouse_type and sdk.get_native_singleton("via.hid.Mouse")
    if mouse then
        local device = sdk.call_native_func(mouse, mouse_type, "get_Device")
        if device then
            now.up = now.up or attempt(function() return device:call("isDown", state.mouse_left) end) == true
            now.down = now.down or attempt(function() return device:call("isDown", state.mouse_right) end) == true
        end
    end
    -- Keyboard fallbacks remain available if a title build lacks the mouse API.
    now.up, now.down = now.up or down("W"), now.down or down("S")
    for name, value in pairs(now) do input[name] = value and not previous[name] end
    previous = now
    input.keyboard = (down("D") and 1 or 0) - (down("A") and 1 or 0)
    input.stick = gp and tonumber(attempt(function() return gp:call("get_AxisL()").x end)) or 0
    if not input.stick or input.stick ~= input.stick then input.stick = 0 end
    input.stick = clamp(input.stick, -1, 1)
    if attempt(function() return reframework:is_drawing_ui() end) == true then
        input = { keyboard = 0, stick = 0 }
    end
end
local mouse_buttons = enum("via.hid.MouseButton")
state.mouse_left = mouse_buttons.L or mouse_buttons.Left or mouse_buttons.LeftButton
state.mouse_right = mouse_buttons.R or mouse_buttons.Right or mouse_buttons.RightButton
re.on_application_entry("UpdateHID", function()
    local ok, err = pcall(poll)
    if not ok then
        input = { keyboard = 0, stick = 0 }
        state.error = "Input unavailable: " .. tostring(err)
    end
end)

local last = os.clock()
re.on_application_entry("LateUpdateBehavior", function()
    local now = os.clock()
    local dt = clamp(now - last, 0, 0.1); last = now
    if state.active then bus.heartbeat = now end
    if paused() then
        input.take, input.up, input.down, input.sit, input.stand = false, false, false, false, false
        return
    end
    command(function()
        local toggle = input.take or state.toggle_pending
        state.toggle_pending = false
        if toggle then acquire() end
        if not state.active then return end
        local cart = state.cart
        if not valid(cart.ox) or not valid(cart.cow) or not valid(cart.body:get_GameObject()) or not valid(state.player)
            or player() ~= state.player then release("Cart/player changed"); return end
        local live_go = singleton("app.NPCManager").OxcartManager._RaidAttack_CachedGameObject
        if address(live_go) ~= address(cart.ox:get_GameObject()) then release("Active cart changed"); return end
        local distance = (state.player:get_Transform():get_Position() - cart.body:get_Position()):length()
        if distance > 20 then release("Player left the cart"); return end
        if cart.status and (cart.status:call("isBroken_OxCart()") or cart.status:call("isDead_Ox()")) then release("Cart destroyed"); return end
        if input.stand then release("Driver stood up"); return end
        if input.sit then
            settings.preset = settings.preset % #settings.presets + 1
            -- Changing the passenger layout must not move the driver seat.
            local old = capture_offset(cart.anchor, state.player)
            local seat = settings.presets[settings.preset].slots[1]
            seat.x, seat.y, seat.z = old.x, old.y, old.z
            inherit_passengers(cart); save(); arrange()
        end
        if input.up then shift(1) elseif input.down then shift(-1) end
        local layout = settings.presets[settings.preset]
        for _, record in ipairs(state.seats) do
            pose(record, layout.slots[record.slot])
        end
        local change = dt / 0.15
        state.axis = state.axis + clamp(input.keyboard - state.axis, -change, change)
        local axis = state.axis
        if input.keyboard == 0 and math.abs(axis) < 0.001 then
            local stick = input.stick
            axis = math.abs(stick) <= 0.15 and 0 or (stick < 0 and -1 or 1) * (math.abs(stick) - 0.15) / 0.85
        end
        local cow = cart.cow
        if math.abs(axis) > 0.001 then
            local heading = tonumber(cow["<PosRotContext>k__BackingField"]:call("get_AngleYDeg()"))
            state.heading = (heading - axis * settings.sensitivity * dt + 180) % 360 - 180
        end
        cow:call("set_TargetFrontAngleDeg(System.Single)", state.heading)
        cow:call("set_TargetMoveAngleDeg(System.Single)", state.heading)
        local am = cart.ox["<ActionManager>k__BackingField"]
        local current = am and am.CurrentActionList and am.CurrentActionList[0]
        if current and current.Name ~= modes[state.level] then action(cart.ox, modes[state.level]) end
        state.protected = {}
        for _, actor in ipairs({ state.player, cart.ox, cart.cow }) do state.protected[address(actor:get_GameObject())] = true end
        state.protected[address(cart.body:get_GameObject())] = true
        for _, pawn in ipairs(party()) do state.protected[address(pawn:get_GameObject())] = true end
        if state.driver then state.driver.machine:call("set_Enabled(System.Boolean)", false) end
    end)
    input.take, input.up, input.down, input.sit, input.stand = false, false, false, false, false
end)
re.on_frame(function()
    if not state.active then return end
    bus.heartbeat = os.clock()
    command(function()
        if not valid(state.cart.body:get_GameObject()) or player() ~= state.player then release("Cart/player unloaded"); return end
        local gui = singleton("app.GuiManager")
        if gui and attempt(function() return gui:call("get_IsLoadGui()") end) == true then return end
        if valid(state.player) and (state.player:get_Transform():get_Position() - state.cart.body:get_Position()):length() > 20 then
            release("Player left the cart"); return
        end
        local layout = settings.presets[settings.preset]
        for _, record in ipairs(state.seats) do
            local slot = layout.slots[record.slot]
            pose(record, slot, true)
            if not paused() and record.machine then record.machine:call("set_Enabled(System.Boolean)", false) end
            if not record.player and not paused() and slot.randomIdle and os.clock() >= record.next_idle then
                local nodes = { "SitOnChairActions", "LivSitChairCrosslegs", "LivSitChairLean", "LivSitChairBook01" }
                local idle = {}
                for key, value in pairs(slot) do idle[key] = value end
                idle.anim, idle.useDirectMotion = nodes[math.random(#nodes)], false
                animate(record, idle)
                record.next_idle = os.clock() + 15 + math.random() * 25
            end
        end
    end)
end)

local function hook(type_name, signature, before)
    local def = sdk.find_type_definition(type_name)
    local method = def and def:get_method(signature)
    if method then sdk.hook(method, before, function(ret) return ret end)
    else log.warn("[" .. TITLE .. "] Missing optional hook: " .. signature) end
end
hook("app.ActionManager", "requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", function(args)
    if not state.active or state.issuing or paused() then return end
    local am = sdk.to_managed_object(args[2])
    if address(am:get_GameObject()) ~= address(state.cart.ox:get_GameObject()) then return end
    if (sdk.to_int64(args[5]) & 0xffffffff) ~= 0 then return end
    local node = sdk.to_managed_object(args[4]):ToString()
    for _, name in ipairs(modes) do
        if node == name then return sdk.PreHookResult.SKIP_ORIGINAL end
    end
end)
hook("app.HitController", "updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)", function(args)
    if not state.active then return end
    local info = sdk.to_managed_object(args[3])
    local receiver = info and info["<DamageGameObject>k__BackingField"]
    if not receiver then return end
    local protected = state.protected[address(receiver)]
    if not protected and valid(receiver) then
        local name = receiver:get_Name() or ""
        if name:match("^gm80_042") or name:match("^gm80_052") or name:match("^gm81_004")
            or name:match("^sm80_074") or name:match("^sm80_051") or name:match("^sm80_052") then
            protected = (receiver:get_Transform():get_Position() - state.cart.body:get_Position()):length() <= 12
        end
    end
    if protected then info.Damage = info.Damage * 0.01 end
end)
hook("app.MainCameraController", "switchCamera(app.CameraDefine.ControlType, app.CameraSwitchInterpParam, app.PostEffectSetting, app.CameraDefine.ToPlayerCameraOption)", function(args)
    if state.active and sdk.to_int64(args[3]) == 12 then return sdk.PreHookResult.SKIP_ORIGINAL end
end)
re.on_script_reset(function() release("Scripts reset") end)
re.on_config_save(save)
re.on_draw_ui(function()
    if not imgui.tree_node(TITLE) then return end
    imgui.text(state.active and ("Driving: " .. modes[state.level]) or "Approach a cart; press G / RT to take control")
    imgui.text("A/D or left stick: steer | Mouse left/right (W/S fallback), RB/LB: accelerate/decelerate")
    imgui.text("E / X: cycle seating | F / B or G / RT: release control")
    if imgui.button(state.active and "Release control" or "Take control") then state.toggle_pending = true end
    if state.message then imgui.text(state.message) end
    if state.error then imgui.text("Last error: " .. state.error) end
    local changed, value = imgui.slider_float("Steering sensitivity (degrees/s)", settings.sensitivity, 5, 180)
    if changed then settings.sensitivity = value; save() end
    if imgui.tree_node("Driving seat presets") then
        local names = {}
        for i, preset in ipairs(settings.presets) do names[i] = preset.name end
        local selected, index = imgui.combo("Active layout", settings.preset, names)
        if selected then settings.preset = index; save() end
        if imgui.button("Add layout from current preset") then
            local old, copy = settings.presets[settings.preset], { name = "Layout " .. (#settings.presets + 1), slots = {}, pawns_customized = true }
            for i, slot in ipairs(old.slots) do
                copy.slots[i] = {}
                for key, value in pairs(slot) do copy.slots[i][key] = value end
            end
            settings.presets[#settings.presets + 1] = copy; settings.preset = #settings.presets; save()
        end
        local layout = settings.presets[settings.preset]
        local rename, name = imgui.input_text("Layout name", layout.name)
        if rename then layout.name = name; save() end
        for i, slot in ipairs(layout.slots) do
            if imgui.tree_node(i == 1 and "Player driver" or "Pawn " .. (i - 1)) then
                for _, key in ipairs({ "x", "y", "z", "yaw" }) do
                    local c, n = imgui.drag_float(key .. "##" .. i, slot[key], key == "yaw" and 1 or 0.01, key == "yaw" and -180 or -10, key == "yaw" and 180 or 10)
                    if c then
                        slot[key] = n
                        if i > 1 then layout.pawns_customized = true end
                        save()
                    end
                end
                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end
    imgui.tree_pop()
end)
