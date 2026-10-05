-- Let me drive oxcart: independent manual-driving controller.
-- Game type/method names are runtime identifiers, not bundled mod dependencies.
local TITLE = "Let me drive oxcart"
local CONFIG = "LetMeDriveOxcart.json"
local bus = rawget(_G, "DD2_OxcartControl") or { version = 1 }
_G.DD2_OxcartControl = bus
-- A previous failed reset may have left this script's lease behind.
if bus.owner == TITLE then bus.owner, bus.heartbeat = nil, nil end
local state = { active = false, level = 1, axis = 0, error = nil, seats = {}, protected = {}, behavior_frame = 0 }
local modes = { "Wait", "Walk", "Run", "Dash" }
local settings = { sensitivity = 45, debug_player_freeze = false,
    debug_player_pose_lock = true,
    debug_player_position_sync = true,
    debug_player_reset_fall = true,
    preset = 1, presets = {
    { name = "Driver and passengers", slots = {
        { x = -0.071, y = 0.920, z = 0.274, yaw = 178, randomIdle = true },
        { x = 0.85, y = 0.23, z = -3.35, yaw = 90 },
        { x = -0.85, y = 0.23, z = -3.35, yaw = -90 },
        { x = 0.85, y = 0.23, z = -4.1, yaw = 90 },
    } },
} }
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function root_offset(value, lo, hi)
    local n = tonumber(value) or 0
    if n ~= n or math.abs(n) == math.huge then n = 0 end
    return clamp(n, lo, hi)
end
local function copy_player_visual(value, fallback)
    value = type(value) == "table" and value or fallback or {}
    local offset = type(value.offset) == "table" and value.offset or {}
    return { enabled = value.enabled == true, offset = {
        x = root_offset(offset.x, -10, 10),
        y = root_offset(offset.y, -10, 10),
        z = root_offset(offset.z, -10, 10),
    } }
end
local function current_visual() return settings.presets[settings.preset].player_visual end
local function copy_camera(value,fallback)
    value=type(value)=="table" and value or fallback or {}
    local function bounded(n,default,lo,hi)
        n=tonumber(n) or default
        if n~=n or math.abs(n)==math.huge then n=default end
        return clamp(n,lo,hi)
    end
    return {fov_enabled=value.fov_enabled==true,fov=bounded(value.fov,60,20,120),
        distance_enabled=value.distance_enabled==true,distance=bounded(value.distance,1,0,10)}
end
local function current_camera() return settings.presets[settings.preset].camera end
local front_offset = rawget(_G, "AelinoreCartFrontOffset")
if not front_offset then
    local stored
    local ok, value = pcall(function() return json.load_file("OxcartFrontProbe.json") end)
    if ok and type(value) == "table" then stored = value end
    front_offset = {x=0,y=0,z=1.5}
    for _, key in ipairs({"x","y","z"}) do
        if stored and tonumber(stored[key]) then front_offset[key] = root_offset(stored[key], -10, 10) end
    end
    _G.AelinoreCartFrontOffset = front_offset
end
local families = { "Normal", "Rainy", "Wealthy" }
local family_names = { "Normal oxcart", "Rainproof oxcart", "Luxury oxcart" }
local function copy_layout(source, name, family)
    local result = { name = name, family = family, enabled = true,
        pawns_customized = source.pawns_customized, slots = {}, player_visual = copy_player_visual(source.player_visual),
        camera=copy_camera(source.camera) }
    for i, slot in ipairs(source.slots) do
        result.slots[i] = {}
        for key, value in pairs(slot) do result.slots[i][key] = value end
    end
    return result
end
local function default_layout(family)
    local layout = copy_layout(settings.presets[1], family .. " - Default", family)
    layout.pawns_customized, layout.default_family = true, family
    local rainy = family == "Rainy"
    layout.player_visual = { enabled = true, offset = rainy and { x = -2.102, y = -0.411, z = -5.688 }
        or { x = 0.126, y = 0.174, z = -4.044 } }
    layout.slots = {
        { x = rainy and -0.051 or 0.029, y = 0.920, z = rainy and 0.334 or 0.274, yaw = 178, anim = "SitOnChairActions", randomIdle = true },
        { x = 0.850, y = 0.230, z = -3.350, yaw = 90, anim = "SitOnChairActions", randomIdle = true },
        { x = -0.850, y = 0.230, z = -3.350, yaw = -90, anim = "SitOnChairActions", randomIdle = true },
        { x = -0.850, y = 0.230, z = -2.500, yaw = -90, anim = "SitOnChairActions", randomIdle = true },
    }
    if family == "Wealthy" then
        -- Separate editable starting layout; no driver-seat measurement supplied yet.
        layout.slots[2] = { x = 0.45, y = 0.23, z = -3.15, yaw = 180, anim = "SitOnChairActions", randomIdle = true }
        layout.slots[3] = { x = -0.5, y = 0.23, z = -1.2, yaw = 0, anim = "SitOnChairActions", randomIdle = true }
        layout.slots[4] = { x = 0.5, y = 0.23, z = -1.25, yaw = 0, anim = "SitOnChairActions", randomIdle = true }
    end
    return layout
end
local function attempt(fn) local ok, value = pcall(fn); if ok then return value end end
local function valid(obj) return obj and attempt(function() return obj:get_Valid() end) == true end
local function address(obj) return obj and attempt(function() return obj:get_address() end) end
local function position_observer(phase, actor, target)
    local observer = rawget(_G, "LMD_PositionObserver")
    if observer then pcall(observer, phase, actor, target) end
end
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
                local copy = { name = tostring(layout.name or "Layout"), slots = {}, pawns_customized = layout.pawns_customized == true,
                    player_visual = layout.player_visual, camera=layout.camera, family = layout.family, enabled = layout.enabled ~= false,
                    default_family = layout.default_family }
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
-- Older configs stored this experiment globally. Seed each layout independently
-- with that value so upgrading preserves the current camera/body arrangement.
local legacy_visual = type(saved) == "table" and {
    enabled = saved.debug_player_visual_seat, offset = saved.player_root_offset,
} or nil
local legacy_camera=type(saved)=="table" and {fov_enabled=saved.camera_fov_enabled,fov=saved.camera_fov,
    distance_enabled=saved.camera_distance_enabled,distance=saved.camera_distance} or nil
for _, layout in ipairs(settings.presets) do
    layout.player_visual = copy_player_visual(layout.player_visual, legacy_visual)
    layout.camera=copy_camera(layout.camera,legacy_camera)
end
-- One-time migration from the old capture-on-takeover seat rule.
if type(saved) ~= "table" or saved.player_seat_rule ~= 1 then
    for _, layout in ipairs(settings.presets) do
        local slot = layout.slots[1]
        slot.x, slot.y, slot.z, slot.yaw = -0.071, 0.920, 0.274, 178
        slot.useOxAnchor = false
    end
end
settings.player_seat_rule = 1
-- Migrate the experiment once: existing saved FSM=ON must not silently keep
-- the known-blackout mode enabled. Later manual debug choices remain intact.
if type(saved) ~= "table" or saved.player_pose_lock_rule ~= 1 then
    settings.debug_player_freeze = false
    settings.debug_player_pose_lock = true
end
settings.player_pose_lock_rule = 1
local family_cursor = {}
for _, family in ipairs(families) do
    local value = type(saved) == "table" and type(saved.family_cursor) == "table" and tonumber(saved.family_cursor[family])
    if value and value == value and math.abs(value) ~= math.huge then family_cursor[family] = math.floor(value) end
end
settings.family_cursor = family_cursor
for i, layout in ipairs(settings.presets) do
    if layout.family ~= "Rainy" and layout.family ~= "Wealthy" then layout.family = "Normal" end
    layout.enabled = true -- All layouts of the matching family participate in cycling.
    if layout.slots[1].randomIdle == nil then layout.slots[1].randomIdle = true end
    if layout.enabled and not family_cursor[layout.family] then family_cursor[layout.family] = i end
end
if type(saved) ~= "table" or saved.cart_family_rule ~= 1 then
    -- Keep old layouts intact; add the newly supplied measured defaults once.
    for _, family in ipairs(families) do
        settings.presets[#settings.presets + 1] = default_layout(family)
        family_cursor[family] = #settings.presets
    end
    if type(saved) ~= "table" then
        table.remove(settings.presets, 1)
        for _, family in ipairs(families) do family_cursor[family] = family_cursor[family] - 1 end
    end
    settings.preset = family_cursor.Normal
end
settings.cart_family_rule = 1
family_cursor[settings.presets[settings.preset].family] = settings.preset
local function cart_family(cart)
    local name = attempt(function() return cart.body:get_GameObject():get_Name() end) or ""
    if name:find("gm80_052", 1, true) then return "Wealthy" end
    if name == "gm80_042_00" then return "Normal" end
    if name:find("gm80_042", 1, true) then return "Rainy" end
    return "Normal"
end
local function choose_family(family, cycle)
    local candidates = {}
    for i, layout in ipairs(settings.presets) do
        if layout.family == family and layout.enabled then candidates[#candidates + 1] = i end
    end
    if #candidates == 0 then
        settings.presets[#settings.presets + 1] = default_layout(family)
        candidates[1] = #settings.presets
    end
    local selected = family_cursor[family]
    for n, i in ipairs(candidates) do
        if i == (cycle and settings.preset or selected) then
            selected = cycle and candidates[n % #candidates + 1] or i
            break
        end
    end
    local found = false
    for _, i in ipairs(candidates) do if i == selected then found = true end end
    settings.preset = found and selected or candidates[1]
    family_cursor[family], state.family = settings.preset, family
end
local function select_family(cart, cycle) choose_family(cart_family(cart), cycle) end

local function player()
    local cm = singleton("app.CharacterManager")
    return cm and cm["<ManualPlayer>k__BackingField"]
end
local DRIVER_IDS = { 963132753, 2619751808 } -- Nick; ch300680 (user-confirmed driver).
local function find_nearby_driver(manager, registered, body)
    local function distance(actor)
        if not valid(actor) then return math.huge end
        return attempt(function() return (actor:get_Transform():get_Position()-body:get_Position()):length() end) or math.huge
    end
    if distance(registered) <= 12 then return registered end
    local found, nearest = nil, 12.00001
    for _, id in ipairs(DRIVER_IDS) do
        local candidate = attempt(function() return manager:getCharacter(id) end)
        local range = distance(candidate)
        if range <= 12 and range < nearest then found, nearest = candidate, range end
    end
    return found
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
    driver = find_nearby_driver(nm, driver, best)
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
local function hold(actor, deferred)
    local machine = fsm(actor)
    assert(machine, "Actor FSM unavailable")
    local was = machine:call("get_Enabled()")
    assert(type(was) == "boolean", "Cannot capture original FSM state")
    local record = { actor = actor, machine = machine, enabled = was }
    if deferred then record.freeze_after = state.behavior_frame + 1
    else machine:call("set_Enabled(System.Boolean)", false) end
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
local function cart_forward(cart)
    local p,ox=cart.body:get_Position(),cart.ox:get_Transform():get_Position()
    local dx,dz=ox.x-p.x,ox.z-p.z
    local length=math.sqrt(dx*dx+dz*dz)
    if length<0.001 then
        local axis=cart.body:get_AxisZ();dx,dz=axis.x,axis.z
        length=math.sqrt(dx*dx+dz*dz)
    end
    assert(length>=0.001,"Cannot determine cart front direction")
    dx,dz=dx/length,dz/length
    return dx,dz
end
local function front_distance(cart, human)
    local p=cart.body:get_Position()
    local dx,dz=cart_forward(cart)
    local point=Vector3f.new(p.x+dz*front_offset.x+dx*front_offset.z,
        p.y+front_offset.y,p.z-dx*front_offset.x+dz*front_offset.z)
    return (human:get_Transform():get_Position() - point):length()
end
local function passenger_seated(cart, human)
    -- Native controller seat occupancy, independent of ticket ownership or pose.
    -- Optional OJR bindings cover its custom player seating without requiring OJR.
    local bindings = rawget(_G,"OJR_SeatBindings")
    if type(bindings) == "table" then
        for _, seat in pairs(bindings) do
            if type(seat) == "table" and seat.char == human then return true end
        end
    end
    local ok, seated = pcall(function()
        local controller = cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
        return controller and controller:call("isPlayerSit()")
    end)
    if ok and type(seated) == "boolean" then return seated end
    return nil -- Unknown is not a verified standing passenger.
end
local driver_debug = {lines={},methods={},events={},enums={}}

local driver_log_sequence=0
local function save_driver_report(reason)
    if #driver_debug.lines==0 then return end
    if not driver_debug.log_path then
        driver_log_sequence=driver_log_sequence+1
        driver_debug.log_path="AelinoreDriverDebug_"..os.date("%Y%m%d_%H%M%S").."_"
            ..tostring(math.floor(os.clock()*1000)).."_"..driver_log_sequence..".log"
    end
    -- One bounded write when recording ends; only scalar snapshots and names,
    -- never managed actors, controllers or binding objects. JSON-formatted LOG.
    local ok,err=pcall(function()
        json.dump_file(driver_debug.log_path,{version=1,reason=reason or "manual save",
            mode=driver_debug.mode or (driver_debug.lifecycle and "native driver lifecycle" or "takeover 5 seconds"),
            result=driver_debug.result,lines=driver_debug.lines,methods=driver_debug.methods,
            events=driver_debug.events,enums=driver_debug.enums})
    end)
    driver_debug.log_status=ok and ("Saved: reframework/data/"..driver_debug.log_path)
        or ("Driver LOG save failed: "..tostring(err))
    return ok,driver_debug.log_status
end
local function driver_debug_get(object,name)
    return attempt(function()
        local method=object and object:get_type_definition():get_method(name)
        if method and method:get_num_params()==0 then return object:call(name) end
    end)
end
local function driver_sample(label, actor)
    local ok,value=pcall(function()
        if not valid(actor) then return label .. ": driver unavailable" end
        local p=actor:get_Transform():get_Position()
        local name=attempt(function()
            local list=actor:get_ActionManager().CurrentActionList
            local count=driver_debug_get(list,"get_Count")
            if tonumber(count)==0 then return nil end
            return list[0].Name
        end)
        local controller=attempt(function() return actor["<AdjustTerrain>k__BackingField"].MainCharacterController:call("get_Position()") end)
        local context=attempt(function() return actor["<PosRotContext>k__BackingField"].Position end)
        local extra=controller and string.format(" | controller %.2f %.2f %.2f",controller.x,controller.y,controller.z) or " | controller unreadable"
        extra=extra..(context and string.format(" | context Y %.2f",context.y) or " | context unreadable")
        if driver_debug.cart then
            local status=driver_debug.cart.status
            local force=driver_debug_get(status,"get_QuestForceSitDownDriver")
            local id=driver_debug_get(status,"getCurrentDriver")
            local wrapper=driver_debug_get(status,"getDriver")
            local id_text=attempt(function() return id:ToString() end) or tostring(id)
            extra=extra.." | forceSit="..tostring(force).." | driverID="..id_text
                .." | driverRef="..tostring(wrapper and address(wrapper) or "none/unreadable")
            local ai=driver_debug_get(status,"get_oxcartAI")
            local ai_force=driver_debug_get(ai,"get_ForceSitDriver")
            local actor_id=attempt(function() return actor:get_CharaID():ToString() end)
                or tostring(attempt(function() return actor:get_CharaID() end) or "unavailable")
            local wrapper_id=attempt(function() return wrapper.CharaID:ToString() end)
                or tostring(attempt(function() return wrapper.CharaID end) or "unavailable")
            extra=extra.." | AI.forceSit="..tostring(ai_force).." | selectedID="..actor_id.." | wrapperID="..wrapper_id
            for _,field in ipairs({"DriverActionReq","DriverActionNow","_forced_interact_wait","_forced_interact_bool",
                "_questForceSatDownDriver"}) do
                local value=attempt(function() return ai[field] end)
                extra=extra.." | "..field.."="..tostring(value)
            end
            local decision=attempt(function() return ai.driverDecision end)
            attempt(function()
                local fields=decision:get_type_definition():get_fields()
                for i,field in ipairs(fields) do
                    if i>24 then break end
                    local key=field:get_name()
                    local value=attempt(function() return decision[key] end)
                    if type(value)=="boolean" or type(value)=="number" or type(value)=="string" then
                        extra=extra.." | decision."..key.."="..tostring(value)
                    end
                end
            end)
        end
        local motion=attempt(function() return actor:get_Motion():getLayer(0) end)
        if motion then
            local bank=attempt(function() return motion:get_MotionBankID() end)
            local id=attempt(function() return motion:get_MotionID() end)
            extra=extra.." | motion="..tostring(bank).."/"..tostring(id)
        end
        if driver_debug.driving_seat then
            local seat=driver_debug.driving_seat
            local occupant=attempt(function() return seat.SitChara end)
            extra=extra.." | seat.Status="..tostring(attempt(function() return seat.Status end))
                .." | seat.SitChara="..tostring(address(occupant) or "none")
                .." | seat.matchesDriver="..tostring(occupant~=nil and address(occupant)==address(actor))
                .." | seat.isSit="..tostring(driver_debug_get(seat,"isSit"))
                .." | seat.isSitting="..tostring(driver_debug_get(seat,"isSitting"))
                .." | seat.IsInteract="..tostring(driver_debug_get(seat,"get_IsInteract"))
                .." | seat.ConstParent="..tostring(address(attempt(function() return seat.ConstParent end)) or "none")
            for _,record in ipairs({{name="driver",actor=actor},{name="player",actor=player()}}) do
                local human=attempt(function() return record.actor["<Human>k__BackingField"] end)
                local restorer=attempt(function() return human["<CoordRestorerOnOxcart>k__BackingField"] end)
                if restorer then
                    for _,field in ipairs({"IsRestoring","IsStore","CountToRestore","CountSinceTeleported"}) do
                        extra=extra.." | "..record.name..".restore."..field.."="..tostring(attempt(function() return restorer[field] end))
                    end
                    local context=attempt(function() return restorer.Context end)
                    extra=extra.." | "..record.name..".ride.HasInfo="..tostring(attempt(function() return context.HasInfo end))
                        .." | "..record.name..".ride.IsInside="..tostring(attempt(function() return context.IsInside end))
                end
            end
        end
        return string.format("%s: X %.2f Y %.2f Z %.2f | %s",label,p.x,p.y,p.z,name and tostring(name) or "action unavailable")..extra
    end)
    driver_debug.lines[#driver_debug.lines+1]=ok and value or (label..": "..tostring(value))
    if #driver_debug.lines>(driver_debug.lifecycle and 2500 or 24) then table.remove(driver_debug.lines,1) end
end
local function begin_driver_debug(cart,lifecycle)
    if driver_debug.lifecycle and driver_debug.actor and not lifecycle then
        driver_sample("MARK: manual takeover requested during native trace",driver_debug.actor); return
    end
    if not lifecycle and not rawget(_G,"AelinoreDriverDebugEnabled") then return end
    if driver_debug.actor then save_driver_report("superseded by another takeover") end
    driver_debug.lines,driver_debug.methods,driver_debug.events,driver_debug.enums={},{},{},{}
    driver_debug.log_path,driver_debug.log_status,driver_debug.result=nil,nil,nil
    driver_debug.mode,driver_debug.end_reason=nil,nil
    driver_debug.driving_seat=nil
    driver_debug.checkpoint_at=nil
    driver_debug.cart=cart
    driver_debug.lifecycle=lifecycle==true
    driver_debug.started=os.clock()
    driver_debug.actor,driver_debug.until_time,driver_debug.next_sample=cart.driver,os.clock()+(lifecycle and 600 or 5),0
    driver_sample(lifecycle and "MARK: native lifecycle recording started" or "before visual offset",cart.driver)
    attempt(function()
        local ai=driver_debug_get(cart.status,"get_oxcartAI")
        local def=ai:get_type_definition()
        for _,name in ipairs({"DriverActionReq","DriverActionNow"}) do
            local enum_type=def:get_field(name):get_type()
            driver_debug.enums[#driver_debug.enums+1]=name.." TYPE "..enum_type:get_full_name()
            for _,field in ipairs(enum_type:get_fields()) do
                if field:is_static() then
                    local value=field:get_data(nil)
                    if type(value)=="number" or type(value)=="boolean" or type(value)=="string" then
                        driver_debug.enums[#driver_debug.enums+1]=name.."."..field:get_name().."="..tostring(value)
                    end
                end
            end
        end
    end)
    local candidates={cart.status,driver_debug_get(cart.status,"get_oxcartAI"),driver_debug_get(cart.status,"getDriver"),
        cart.driver,cart.driver and attempt(function() return cart.driver:get_ActionManager() end)}
    for _,object in pairs(candidates) do
        attempt(function()
            local def=object:get_type_definition()
            local type_name=def:get_full_name()
            local binding_object=type_name=="app.OxcartAI" or type_name=="app.OxcartNPC"
            for _,method in ipairs(def:get_methods()) do
                local name=method:get_name()
                if binding_object or name:lower():find("driver") or name:lower():find("ride") or name:lower():find("seat")
                    or name:lower():find("oxcart") or name:lower():find("getoff") or name:lower():find("sit") then
                    if #driver_debug.methods<160 then
                        local count=attempt(function() return method:get_num_params() end)
                        local ret=attempt(function() return method:get_return_type():get_full_name() end)
                        driver_debug.methods[#driver_debug.methods+1]=def:get_full_name().."."..name
                            .." | args="..tostring(count).." | return="..tostring(ret)
                    end
                end
            end
            if binding_object then
                for _,field in ipairs(def:get_fields()) do
                    if #driver_debug.methods<200 then
                        driver_debug.methods[#driver_debug.methods+1]=type_name.." FIELD "..field:get_name()
                    end
                end
            end
        end)
    end
end
_G.LMD_DriverDebug={read=function() return driver_debug end,save=save_driver_report}
local driver_debug_bridge = _G.LMD_DriverDebug
-- Native direction: an isolated driver-seat interaction, not manual seating.
;(function()
    local pending,owned,view=nil,nil,{status="Native driver-seat test idle",rows={}}
    local serial=0
    local function record(message)
        if view.status==message then return end
        view.status=message
        view.events=view.events or {}
        view.events[#view.events+1]={t=os.clock(),message=message}
        if #view.events>80 then table.remove(view.events,1) end
        if not view.path then
            serial=serial+1
            view.path="AelinoreNativeSeat_"..os.date("%Y%m%d_%H%M%S").."_"..math.floor(os.clock()*1000).."_"..serial..".log"
        end
        pcall(function() json.dump_file(view.path,{status=view.status,rows=view.rows,events=view.events}) end)
    end
    local function clear()
        if owned then
            if driver_debug_bridge.native_drive_end then attempt(function() driver_debug_bridge.native_drive_end(owned) end) end
            if owned.changed and valid(owned.gm) then
                attempt(function() owned.data:set_field("CharacterType",owned.old_mask) end)
            end
            if owned.result then attempt(function() owned.result:release() end) end
        end
        owned=nil
    end
    local function item(array,index)
        return attempt(function() return array:get_element(index) end)
            or attempt(function() return array:call("get_Item(System.Int32)",index) end)
            or attempt(function() return array._items[index] end)
    end
    local function scan()
        assert(not state.active,"Release manual control before native interaction")
        local cart=discover()
        local ch=player()
        assert(cart and valid(ch),"Approach a loaded oxcart")
        local gm=cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
        assert(valid(gm),"Native cart component unavailable")
        local seat=driver_debug_get(gm,"get_DrivingSeat")
        assert(seat,"Native DrivingSeat unavailable")
        assert(not seat.SitChara,"Driver seat occupied or still bound; nothing requested")
        local io=gm.InteractiveObject
        assert(valid(io) and io:call("get_IsRegistered()")
            and io:call("get_IsUpdatedAfterRegisterd()"),"Native cart interaction is not registered/updated")
        local mgr=singleton("app.InteractManager")
        assert(mgr and not mgr:call("isInteracting(app.Character)",ch),"Player is already interacting")
        local candidates={}
        local mapping_readable=true
        view.rows={}
        local n=tonumber(io:call("getNumInteractPoint()"))
        assert(n and n>0 and n<=32,"Unexpected interaction point count")
        for i=0,n-1 do
            local seat_no=attempt(function() return tonumber(gm:call("getSeatNo(System.UInt32)",i)) end)
            local data=item(gm.InteractiveObjectDataList,i)
            local mask=attempt(function() return tonumber(data:get_field("CharacterType")) end)
            local occupant=attempt(function() return gm:call("getInteractChara(System.UInt32)",i) end)
            -- Seat numbers are not interaction point numbers. Driver points may
            -- map to negative seats and may have separate left/right entrances.
            local is_driver=attempt(function() return gm:call("IsDriver(System.UInt32)",i) end)
            if type(is_driver)~="boolean" then mapping_readable=false end
            local enabled=attempt(function() return gm:call("isInteractEnable(System.UInt32)",i) end)
            local candidate=is_driver==true and enabled==true and data~=nil and mask~=nil and not occupant
            view.rows[#view.rows+1]={point=i,seat_no=seat_no,character_mask=mask,
                parent_joint=attempt(function() return tostring(data:get_field("ParentJointName")) end),
                occupant=address(occupant),native_is_driver=is_driver,native_enabled=enabled,driver_candidate=candidate}
            if candidate then candidates[#candidates+1]={point=i,data=data,mask=mask,occupant=occupant} end
        end
        assert(mapping_readable,"Native IsDriver mapping unreadable; no point guessed")
        assert(#candidates>0,"No enabled empty native driver entrance; no passenger point used")
        -- Both sides lead to DrivingSeat; use native point order, never a
        -- passenger point or a seat-number heuristic. Log every alternative.
        local selected=candidates[1]
        assert(selected.data and selected.mask and not selected.occupant,"Driver point unavailable/occupied")
        return {cart=cart,ch=ch,gm=gm,seat=seat,io=io,mgr=mgr,point=selected.point,
            data=selected.data,old_mask=selected.mask,started=os.clock()}
    end
    driver_debug_bridge.native_seat_read=function() return view end
    driver_debug_bridge.native_seat_busy=function() return owned~=nil or pending~=nil end
    driver_debug_bridge.native_seat_command=function(command)
        if command~="scan" and command~="enter" and command~="exit" then return false end
        if pending then return false end
        pending=command
        return true
    end
    driver_debug_bridge.native_seat_tick=function()
        if paused() then return end
        if pending then
            local command=pending;pending=nil
            local ok,err=pcall(function()
                if command=="exit" then
                    assert(owned,"No native test interaction owned")
                    local active=owned.mgr:call("getActiveInteract(app.Character)",owned.ch)
                    assert(active and active.Point and address(active.Point.Object)==address(owned.io)
                        and tonumber(active.Point.PointNo)==owned.point,"Player active point does not match this test")
                    if driver_debug_bridge.native_drive_end then driver_debug_bridge.native_drive_end(owned) end
                    owned.io:call("endInteractForSystem(System.UInt32, app.Character)",owned.point,owned.ch)
                    owned.exiting=true;owned.exit_at=os.clock()
                    record("Native exit requested; waiting for engine completion")
                    return
                end
                assert(not owned,"Exit the existing native test first")
                view.path=nil;view.events={};view.rows={}
                local q=scan()
                record("Resolved empty driver point "..q.point.." via native IsDriver")
                if command=="scan" then return end
                owned=q
                local mask=q.old_mask | 1 -- Player bit; preserve all native flags.
                if mask~=q.old_mask then
                    q.changed=true;q.data:set_field("CharacterType",mask)
                    assert(tonumber(q.data:get_field("CharacterType"))==mask,"Player mask write did not take effect")
                end
                assert(q.io:call("isInteractEnable(System.UInt32, app.Character)",q.point,q.ch),
                    "Native driver point still rejects player after Player flag; no bypass/fallback")
                q.result=q.mgr:call("requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)",q.io,q.point,q.ch)
                assert(q.result,"Native request returned no result")
                q.result:add_ref()
                record("Native request submitted for driver point "..q.point.."; awaiting acceptance and binding")
            end)
            if not ok then
                record("Native test failed: "..tostring(err))
                -- A failed exit must not discard ownership of an active interaction.
                if command~="exit" then clear() end
            end
        end
        if not owned then return end
        if not valid(owned.gm) or not valid(owned.ch) then record("Actor/cart unloaded");clear();return end
        if os.clock()<(owned.poll_at or 0) then return end
        owned.poll_at=os.clock()+0.1
        local ok,err=pcall(function()
            local interacting=owned.mgr:call("isInteracting(app.Character)",owned.ch)
            if owned.bound then
                if not interacting then record("Native interaction ended; restoring Player flag");clear();return end
                if owned.exiting and os.clock()-owned.exit_at>10 and not owned.exit_warned then
                    owned.exit_warned=true;record("Native exit still pending; original interaction retained")
                end
                return
            end
            local value=tonumber(owned.result:get_field("ResultType"))
            local enum=sdk.find_type_definition("app.InteractManager.InteractRequestResultType")
            local denied=enum:get_field("Denied"):get_data(nil)
            if value==tonumber(denied) then record("Native request denied; restoring Player flag");clear();return end
            local active=owned.mgr:call("getActiveInteract(app.Character)",owned.ch)
            local seat_matches=address(owned.seat.SitChara)==address(owned.ch)
            if interacting and seat_matches and active and active.Point
                and address(active.Point.Object)==address(owned.io) and tonumber(active.Point.PointNo)==owned.point then
                owned.bound=true
                if driver_debug_bridge.native_drive_begin then driver_debug_bridge.native_drive_begin(owned) end
                record("CONFIRMED: native driver seat; driving controls enabled; no forced pose/position/FSM/fall writes")
            elseif os.clock()-owned.started>15 then
                record("No confirmed driver binding after 15 seconds; requesting cleanup")
                -- If the engine has started an interaction, request its own exit.
                if interacting and active and active.Point and address(active.Point.Object)==address(owned.io)
                    and tonumber(active.Point.PointNo)==owned.point then
                    owned.io:call("endInteractForSystem(System.UInt32, app.Character)",owned.point,owned.ch)
                    owned.bound=true;owned.exiting=true;owned.exit_at=os.clock()
                else clear() end
            end
        end)
        if not ok then record("Native observation failed: "..tostring(err)) end
    end
    driver_debug_bridge.native_seat_close=function()
        pending=nil
        if owned and valid(owned.ch) and valid(owned.gm) then
            attempt(function()
                local active=owned.mgr:call("getActiveInteract(app.Character)",owned.ch)
                if active and active.Point and address(active.Point.Object)==address(owned.io)
                    and tonumber(active.Point.PointNo)==owned.point then
                    owned.io:call("endInteractForSystem(System.UInt32, app.Character)",owned.point,owned.ch)
                end
            end)
        end
        clear()
    end
end)()
;(function()
    local session,request,sequence=nil,nil,0
    local function vector(p) return p and {x=p.x,y=p.y,z=p.z} or nil end
    local function identity(actor)
        return {actor=address(actor),
            game_object=attempt(function() return address(actor:get_GameObject()) end),
            name=attempt(function() return tostring(actor:get_GameObject():get_Name()) end),
            character_id=attempt(function()
                local id=actor:get_CharaID()
                return attempt(function() return id:ToString() end) or tostring(id)
            end)}
    end
    local function actor_snapshot(actor)
        if not valid(actor) then return {available=false} end
        local result={available=true,identity=identity(actor)}
        result.position=attempt(function() return vector(actor:get_Transform():get_Position()) end)
        result.controller=attempt(function() return vector(actor["<AdjustTerrain>k__BackingField"].MainCharacterController:call("get_Position()")) end)
        result.context=attempt(function() return vector(actor["<PosRotContext>k__BackingField"].Position) end)
        result.fall={}
        attempt(function()
            local fall=actor["<FallInfo>k__BackingField"]
            for i,field in ipairs(fall:get_type_definition():get_fields()) do
                if i>32 then break end
                local name=field:get_name()
                local value=attempt(function() return fall[name] end)
                if type(value)=="number" or type(value)=="boolean" then result.fall[name]=value
                else
                    local position=attempt(function()
                        if type(value.x)=="number" and type(value.y)=="number" and type(value.z)=="number" then return vector(value) end
                    end)
                    if position then result.fall[name]=position end
                end
            end
        end)
        result.restore={}
        attempt(function()
            local restorer=actor["<Human>k__BackingField"]["<CoordRestorerOnOxcart>k__BackingField"]
            for _,name in ipairs({"IsRestoring","IsStore","CountToRestore","CountSinceTeleported"}) do
                result.restore[name]=restorer[name]
            end
        end)
        return result
    end
    local function flush(reason)
        if not session then return end
        local path=session.prefix.."_"..string.format("%04d",session.part)..".log"
        local ok,err=pcall(function()
            json.dump_file(path,{version=1,reason=reason,started=session.started_wall,
                samples=session.samples,events=session.events,prehistory=session.ring})
        end)
        session.status=ok and ("Saved: "..path) or ("LOG save failed: "..tostring(err))
        if ok then session.part=session.part+1;session.samples={};session.events={} end
        session.next_save=os.clock()+10
    end
    local function event(name,detail,urgent)
        if not session or #session.events>=200 then return end
        session.events[#session.events+1]={t=os.clock()-session.started,name=name,detail=detail}
        if urgent then flush(name) end
    end
    driver_debug_bridge.road_control=function(on) request=on and "start" or "stop" end
    driver_debug_bridge.road_mark=function() if session then event("black_screen_manual_delayed",nil,true) end end
    driver_debug_bridge.road_read=function()
        return {active=session~=nil,status=session and session.status or "Recording off"}
    end
    driver_debug_bridge.road_damage=function(info)
        if not session or not info then return end
        local receiver=info["<DamageGameObject>k__BackingField"]
        if not valid(receiver) then return end
        local name=attempt(function() return receiver:get_Name() end) or "unknown"
        local p=attempt(function() return receiver:get_Transform():get_Position() end)
        if p and (p-session.cart.body:get_Position()):length()<=15 then
            event("damage_before_reduction",{receiver=name,damage=tonumber(info.Damage)})
        end
    end
    driver_debug_bridge.road_native=function(name,object)
        if not session then return end
        if name=="executeBreak" then
            local gm=attempt(function() return session.cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"] end)
            if address(object)==address(gm) and address(gm) then event(name,nil,true) end
        else
            local actors={{role="player",actor=session.player},{role="ox",actor=session.cart.ox},{role="cow",actor=session.cart.cow}}
            local matched,roles=nil,{}
            for _,entry in ipairs(actors) do
                local actor=entry.actor
                local restorer=attempt(function() return actor["<Human>k__BackingField"]["<CoordRestorerOnOxcart>k__BackingField"] end)
                if address(restorer) and address(restorer)==address(object) then
                    matched=actor;roles[#roles+1]=entry.role
                end
            end
            if matched then
                -- Keep all aliases when ox/cow refer to the same actor/restorer.
                local key=name..tostring(address(object))
                if not session.throttle[key] or os.clock()>=session.throttle[key] then
                    session.throttle[key]=os.clock()+1
                    local detail=identity(matched)
                    detail.roles,detail.restorer=roles,address(object)
                    event(name,detail)
                end
            end
        end
    end
    driver_debug_bridge.road_poll=function()
        if request then
            local pending=request;request=nil
            if pending=="stop" then flush("manual stop");session=nil;return end
            if session then flush("restart");session=nil end
            local ok,cart=pcall(discover)
            if not ok or not cart or not valid(player()) then return end
            sequence=sequence+1
            session={cart=cart,player=player(),started=os.clock(),started_wall=os.date("%Y-%m-%d %H:%M:%S"),
                prefix="AelinoreRoadTrace_"..os.date("%Y%m%d_%H%M%S").."_"..math.floor(os.clock()*1000).."_"..sequence,
                part=1,samples={},events={},ring={},throttle={},next_sample=0,next_save=os.clock()+10,status="Recording"}
            event("start",nil,true)
        end
        if not session then return end
        if not valid(session.cart.body:get_GameObject()) or not valid(session.player)
            or os.clock()-session.started>3600 then flush("unloaded or one hour limit");session=nil;return end
        if os.clock()>=session.next_sample then
            session.next_sample=os.clock()+0.25
            local native=state.native_drive
            local sample={t=os.clock()-session.started,active=state.active or native~=nil,
                control_route=native and "native" or (state.active and "non-native" or "none"),
                level=native and native.drive.level or state.level,
                player=actor_snapshot(session.player),ox=actor_snapshot(session.cart.ox),cow=actor_snapshot(session.cart.cow),
                driver=actor_snapshot(session.cart.driver),pawns={},
                cart_position=attempt(function() return vector(session.cart.body:get_Position()) end),
                broken=driver_debug_get(session.cart.status,"isBroken_OxCart"),
                dead_ox=driver_debug_get(session.cart.status,"isDead_Ox")}
            for i,actor in ipairs(party()) do sample.pawns[i]=actor_snapshot(actor) end
            local gm=attempt(function() return session.cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"] end)
            sample.cart_flags={}
            for _,name in ipairs({"IsRequestBreak","ForceRolloverRate","StateNow","PrevState"}) do
                local value=attempt(function() return gm[name] end)
                if type(value)=="number" or type(value)=="boolean" then sample.cart_flags[name]=value end
            end
            session.samples[#session.samples+1]=sample;session.ring[#session.ring+1]=sample
            if #session.ring>120 then table.remove(session.ring,1) end
        end
        if os.clock()>=session.next_save then flush("10 second checkpoint") end
    end
    driver_debug_bridge.road_close=function() flush("script reset");session=nil;request=nil end
end)()
driver_debug_bridge.start=function()
    if state.active then return false,"Release manual control before tracing native driver" end
    local ok,cart=pcall(discover)
    if not ok or not cart or not valid(cart.driver) then return false,"Approach a cart with a nearby loaded driver first" end
    begin_driver_debug(cart,true)
    driver_debug.result="Native lifecycle recording (4 samples/s, max 10 minutes)"
    return true,driver_debug.result
end
driver_debug_bridge.stop=function()
    local ok,status=save_driver_report("native lifecycle stopped")
    driver_debug.actor,driver_debug.cart,driver_debug.driving_seat=nil,nil,nil
    driver_debug.exit_pending=nil
    return ok,status
end
driver_debug_bridge.mark=function(stage)
    if driver_debug.lifecycle and valid(driver_debug.actor) then
        driver_sample("MARK +"..string.format("%.2fs",os.clock()-driver_debug.started)..": "..stage,driver_debug.actor)
    end
end
driver_debug_bridge.test_exit=function(id)
    if id~=3513 and id~=3514 then return false,"Unsupported driver exit test ID" end
    if state.active then return false,"Release manual control before testing native driver exit" end
    local ok,cart=pcall(discover)
    if not ok or not cart or not valid(cart.driver) then return false,"No nearby loaded driver/cart" end
    driver_debug.exit_pending={cart=cart,id=id}
    driver_debug.result="Driver exit test queued; close any paused game menu"
    return true,driver_debug.result
end
driver_debug_bridge.test_native_exit=function()
    if state.active then return false,"Release manual control before testing freeGetOff" end
    local ok,cart=pcall(discover)
    if not ok or not cart or not valid(cart.driver) then return false,"No nearby loaded driver/cart" end
    if driver_debug.exit_pending then return false,"A driver test is already queued" end
    driver_debug.exit_pending={cart=cart,native=true}
    driver_debug.result="Native freeGetOff test queued; no teleport/freeze/battle changes"
    return true,driver_debug.result
end
driver_debug_bridge.finish_native_exit=function()
    if state.active then return false,"Release manual control before ending driver interaction" end
    local ok,cart=pcall(discover)
    if not ok or not cart or not valid(cart.driver) then return false,"No nearby loaded driver/cart" end
    if driver_debug.exit_pending then return false,"A driver test is already queued" end
    driver_debug.exit_pending={cart=cart,native=true,finish=true}
    driver_debug.result="DrivingSeat.end test queued; wait until the exit animation has finished"
    return true,driver_debug.result
end
-- Read-only probes accompany each isolated mutation; no managed references in LOG.
local function probe_driver_interaction(actor,label)
    driver_sample(label,actor)
    local function emit(value)
        driver_debug.events[#driver_debug.events+1]=label.." | "..value
    end
    local agent=driver_debug_get(actor,"get_AISituationAgent")
    emit("agent="..tostring(address(agent) or "unavailable"))
    local tasks=driver_debug_get(agent,"getCurrentTaskList")
    local count=tonumber(driver_debug_get(tasks,"get_Count"))
    emit("tasks.count="..tostring(count or "unavailable"))
    for i=0,math.min(count or 0,12)-1 do
        local task=attempt(function() return tasks:call("get_Item(System.Int32)",i) end)
        local typename=attempt(function() return task:get_type_definition():get_full_name() end)
        local state=attempt(function() return task._State end)
        local data=attempt(function() return task.TaskData:get_type_definition():get_full_name() end)
        emit("task["..i.."]="..tostring(typename).." state="..tostring(state).." data="..tostring(data))
    end
    attempt(function()
        for _,field in ipairs(actor:get_type_definition():get_fields()) do
            if field:get_type():get_full_name()=="app.AdjustJack" then
                local jack=actor[field:get_name()]
                emit("AdjustJack="..tostring(address(jack) or "none"))
                for _,name in ipairs({"<ExecJackRequest>k__BackingField","<ExecPlayMotionRequest>k__BackingField",
                    "<JackOwner>k__BackingField","LockObj"}) do
                    emit(name.."="..tostring(address(attempt(function() return jack[name] end)) or "none"))
                end
            end
        end
    end)
end
driver_debug_bridge.test_interaction_cleanup=function(name)
    if name~="cancelInteract" and name~="endGimmickAction" then return false,"Unsupported cleanup test" end
    if state.active then return false,"Release manual control before driver cleanup test" end
    if driver_debug.exit_pending then return false,"A driver test is already queued" end
    local ok,cart=pcall(discover)
    if not ok or not cart or not valid(cart.driver) then cart=driver_debug.cart end
    if not cart or not valid(cart.driver) then return false,"No loaded driver/cart" end
    driver_debug.exit_pending={cart=cart,cleanup=name}
    driver_debug.result=name.." queued; no seat.end/teleport/FSM/battle/Wait changes"
    return true,driver_debug.result
end
driver_debug_bridge.test_driver_passenger=function()
    if state.active then return false,"Release manual control before enabling driver passenger test" end
    if driver_debug.exit_pending then return false,"A driver test is already queued" end
    local ok,cart=pcall(discover)
    if not ok or not cart or not valid(cart.driver) then return false,"No nearby loaded driver/cart" end
    driver_debug.exit_pending={cart=cart,passenger=true}
    driver_debug.result="Driver passenger test queued; freeGetOff must already be complete"
    return true,driver_debug.result
end
local function poll_driver_debug()
    if driver_debug_bridge.native_seat_tick then attempt(driver_debug_bridge.native_seat_tick) end
    if driver_debug_bridge.road_poll then attempt(driver_debug_bridge.road_poll) end
    if driver_debug.exit_pending and not paused() then
        local job=driver_debug.exit_pending
        driver_debug.exit_pending=nil
        local ok,err=pcall(function()
            assert(not state.active,"Release manual control before testing native driver exit")
            assert(valid(job.cart.driver) and valid(job.cart.ox) and valid(job.cart.body:get_GameObject()),"Driver/cart unloaded")
            assert((job.cart.driver:get_Transform():get_Position()-job.cart.body:get_Position()):length()<=12,"Driver no longer nearby")
            if job.passenger then
                driver_debug_bridge.native_exit_guard(job.cart)
                local gm=attempt(function() return job.cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"] end)
                local seat=driver_debug_get(gm,"get_DrivingSeat")
                assert(seat and tonumber(seat.Status)==5,"Use freeGetOff before driver passenger test")
                assert(address(attempt(function() return seat.SitChara end))==address(job.cart.driver),"Seat driver mismatch")
                begin_driver_debug(job.cart,true)
                driver_debug.driving_seat=seat
                driver_debug.mode="driver passenger follow test"
                driver_debug.end_reason="driver passenger observation complete"
                driver_debug.checkpoint_at=os.clock()+10
                state.test_passenger_driver=job.cart.driver
                state.test_passenger_cart=address(job.cart.body:get_GameObject())
                probe_driver_interaction(job.cart.driver,"PASSENGER TEST ARMED")
                driver_debug.result="Driver will sit in the cart on next takeover; FSM stays running"
                save_driver_report("driver passenger test armed")
                return
            end
            if job.cleanup then
                driver_debug_bridge.native_exit_guard(job.cart)
                local gm=attempt(function() return job.cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"] end)
                local seat=driver_debug_get(gm,"get_DrivingSeat")
                assert(seat,"DrivingSeat unavailable")
                local occupant=attempt(function() return seat.SitChara end)
                assert(not occupant or address(occupant)==address(job.cart.driver),"Seat belongs to another character")
                assert(tonumber(seat.Status)==5 or (not occupant and tonumber(seat.Status)==0),
                    "Use freeGetOff and finish exit animation before cleanup test")
                local agent=driver_debug_get(job.cart.driver,"get_AISituationAgent")
                local method=agent and agent:get_type_definition():get_method(job.cleanup)
                assert(method and method:get_num_params()==0
                    and method:get_return_type():get_full_name()=="System.Void","Cleanup signature unavailable")
                if driver_debug.actor~=job.cart.driver or not driver_debug.lifecycle then begin_driver_debug(job.cart,true) end
                driver_debug.driving_seat=seat
                driver_debug.mode="native driver interaction cleanup"
                driver_debug.end_reason="driver cleanup observation complete"
                driver_debug.until_time=os.clock()+600
                probe_driver_interaction(job.cart.driver,"BEFORE "..job.cleanup)
                save_driver_report("before "..job.cleanup)
                local success,failure=pcall(function() agent:call(job.cleanup.."()") end)
                driver_debug.events[#driver_debug.events+1]="CALL "..job.cleanup..": "..(success and "returned" or tostring(failure))
                probe_driver_interaction(job.cart.driver,"AFTER "..job.cleanup)
                driver_debug.result=job.cleanup..(success and " returned; inspect LOG before driving" or " failed: "..tostring(failure))
                save_driver_report("after "..job.cleanup)
                driver_debug.checkpoint_at=os.clock()+10
                return
            end
            if job.native then
                assert(driver_debug_bridge.native_exit_guard,"Native exit guard unavailable")
                driver_debug_bridge.native_exit_guard(job.cart)
                local gm=attempt(function() return job.cart.ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"] end)
                local seat=driver_debug_get(gm,"get_DrivingSeat")
                assert(seat,"DrivingSeat unavailable")
                local occupant=attempt(function() return seat.SitChara end)
                assert(valid(occupant) and address(occupant) and address(occupant)==address(job.cart.driver),
                    "DrivingSeat.SitChara is not the selected driver; nothing called")
                local method_name=job.finish and "end" or "freeGetOff"
                if job.finish then
                    assert(tonumber(seat.Status)==5,"Driver seat is not FreeGetOff; nothing called")
                end
                local method=seat:get_type_definition():get_method(method_name)
                assert(method and method:get_num_params()==0
                    and method:get_return_type():get_full_name()=="System.Void",method_name.." signature unavailable")
                begin_driver_debug(job.cart,true)
                driver_debug.driving_seat=seat
                driver_debug.mode="native DrivingSeat."..method_name.." test"
                driver_debug.end_reason=job.finish and "native seat-end observation complete" or "20 second native freeGetOff test complete"
                driver_debug.until_time=os.clock()+(job.finish and 600 or 20)
                driver_sample("before "..method_name,job.cart.driver)
                driver_debug.events[#driver_debug.events+1]="TEST: one-shot DrivingSeat."..method_name.."() on matched driver"
                seat:call(method_name.."()")
                driver_sample("immediately after "..method_name,job.cart.driver)
                driver_debug.result="Called DrivingSeat."..method_name.." once; observing "..(job.finish and "10 minutes" or "20 seconds")
                if job.finish then save_driver_report("seat-end immediate snapshot") end
                return
            end
            local motion=job.cart.driver:get_Motion()
            local layer=motion and motion:getLayer(0)
            assert(layer,"Driver motion layer unavailable")
            begin_driver_debug(job.cart,true)
            driver_debug.mode="driver exit animation test 0/"..job.id
            driver_debug.end_reason="20 second driver exit test complete"
            driver_debug.until_time=os.clock()+20
            driver_debug.events[#driver_debug.events+1]="TEST: one-shot changeMotion Bank 0 / Motion "..job.id
            layer:call("changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)",
                0,job.id,0,12,1,1)
            driver_debug.result="Played Bank 0 / Motion "..job.id.." once; observing 20 seconds (no unbind/teleport/FSM writes)"
            driver_sample("immediately after test animation",job.cart.driver)
        end)
        if not ok then
            driver_debug.result="Driver exit test failed: "..tostring(err)
            save_driver_report("driver exit test failed")
            driver_debug.actor,driver_debug.cart,driver_debug.driving_seat=nil,nil,nil
        end
    end
    if not driver_debug.actor then
        if driver_debug.cart then save_driver_report("driver unavailable"); driver_debug.cart=nil end
        return
    end
    local now=os.clock()
    if driver_debug.lifecycle and (not valid(driver_debug.actor)
        or not driver_debug.cart or not valid(driver_debug.cart.ox)
        or not valid(driver_debug.cart.body:get_GameObject())) then
        save_driver_report("native driver/cart unloaded")
        driver_debug.actor,driver_debug.cart,driver_debug.driving_seat=nil,nil,nil; return
    end
    if (not driver_debug.lifecycle and not rawget(_G,"AelinoreDriverDebugEnabled")) or now>driver_debug.until_time then
        save_driver_report(driver_debug.end_reason or (driver_debug.lifecycle and "10 minute limit reached"
            or (rawget(_G,"AelinoreDriverDebugEnabled") and "5 seconds complete" or "recording disabled")))
        driver_debug.actor,driver_debug.cart,driver_debug.driving_seat=nil,nil,nil; return
    end
    if now>=driver_debug.next_sample then
        driver_debug.next_sample=now+0.25
        driver_sample(string.format("+%.2fs",now-driver_debug.started),driver_debug.actor)
    end
    if driver_debug.checkpoint_at and now>=driver_debug.checkpoint_at then
        probe_driver_interaction(driver_debug.actor,"CHECKPOINT")
        save_driver_report("10 second cleanup checkpoint")
        driver_debug.checkpoint_at=now+10
    end
end

-- Native follow distance uses CameraManager._DistanceOffset (game option scale,
-- not metres). API identification: xyzkljl1/MyDD2Mod/CameraDistance. No FOV or
-- actor-root changes; restore the exact captured setting after ownership ends.
local camera_override = {}
local fov_override = {}
local function restore_camera_fov()
    if fov_override.camera then
        local ok,err=pcall(function() fov_override.camera:call("set_FOV",fov_override.original) end)
        state.fov_status=ok and "FOV restored" or ("FOV restore unavailable: "..tostring(err))
        fov_override.camera,fov_override.original=nil,nil
    end
end
local function update_camera_fov()
    local camera_settings=current_camera()
    if not (state.active or state.native_drive) or not camera_settings.fov_enabled or paused() then restore_camera_fov(); return end
    if fov_override.suspended then return end
    local camera=sdk.get_primary_camera and sdk.get_primary_camera()
    if not camera then restore_camera_fov(); state.fov_status="Primary camera unavailable"; return end
    if fov_override.camera and fov_override.camera~=camera then
        restore_camera_fov(); fov_override.suspended=true
        state.fov_status="Camera changed; FOV suspended until next takeover"; return
    end
    if not fov_override.camera then
        local def=camera:get_type_definition()
        if not def or not def:get_method("get_FOV") or not def:get_method("set_FOV") then
            state.fov_status="FOV getter/setter unavailable"; return
        end
        local original=tonumber(camera:call("get_FOV"))
        if not original or original~=original or original<=5 or original>=180 then
            state.fov_status="Unsupported FOV units/value"; return
        end
        fov_override.camera,fov_override.original=camera,original
    end
    camera:call("set_FOV",camera_settings.fov)
    state.fov_status="FOV override active"
end
local function restore_camera_distance()
    if camera_override.manager then
        local ok,err=pcall(function() camera_override.manager._DistanceOffset=camera_override.original end)
        state.camera_status=ok and "Camera distance restored" or ("Distance restore unavailable: "..tostring(err))
        camera_override.manager,camera_override.original=nil,nil
    end
end
local function update_camera_distance()
    local camera_settings=current_camera()
    if not (state.active or state.native_drive) or not camera_settings.distance_enabled or paused() then restore_camera_distance(); return end
    if camera_override.suspended then return end
    local manager=singleton("app.CameraManager")
    if not manager then restore_camera_distance(); state.camera_status="CameraManager unavailable"; return end
    if camera_override.manager and camera_override.manager~=manager then
        restore_camera_distance(); camera_override.suspended=true
        state.camera_status="CameraManager changed; distance suspended until next takeover"; return
    end
    if not camera_override.manager then
        local def=manager:get_type_definition()
        if not def or not def:get_field("_DistanceOffset") then
            state.camera_status="Native distance field unavailable"; return
        end
        local original=tonumber(manager._DistanceOffset)
        if not original or original~=original or math.abs(original)==math.huge then
            state.camera_status="Native distance value unavailable"; return
        end
        camera_override.manager,camera_override.original=manager,original
    end
    if manager._DistanceOffset~=camera_settings.distance then manager._DistanceOffset=camera_settings.distance end
    state.camera_status="Camera distance override active"
end
re.on_application_entry("PrepareRendering",function()
    local fov_ok,fov_err=pcall(update_camera_fov)
    if not fov_ok then
        restore_camera_fov(); fov_override.suspended=true
        state.fov_status="FOV unavailable: "..tostring(fov_err)
    end
    local ok,err=pcall(update_camera_distance)
    if not ok then
        restore_camera_distance(); camera_override.suspended=true
        state.camera_status="Camera distance unavailable: "..tostring(err)
    end
end)
local front_probe = {read=function()
    local human, cart = player(), state.active and state.cart or discover()
    if not valid(human) or not cart then return nil end
    return {distance=front_distance(cart,human),model=cart.body:get_GameObject():get_Name()}
end}
_G.LMD_CartFrontProbe = front_probe
local function restore_player_visual()
    local previous = state.player_visual
    state.player_visual = nil
    if previous then
        for _, entry in ipairs(previous) do
            attempt(function()
                if valid(entry.joint) then entry.joint:set_LocalPosition(entry.position) end
            end)
        end
    end
end
local function synchronize_seat_position(record, transform)
    -- Transform uses scene coordinates. PosRotContext requires via.Position
    -- in universal coordinates; never pass the seat's scene vec3 to setPos.
    local context = record.actor["<PosRotContext>k__BackingField"]
    local terrain = record.actor["<AdjustTerrain>k__BackingField"]
    local controller = terrain and terrain.MainCharacterController
    assert(context and controller, "Seat position sync: context/controller unavailable")
    context:call("setPos(via.Position)", transform:get_UniversalPosition())
    -- CharacterController.warp() has NO parameters. It resynchronizes its
    -- physical position from its owning object's transform, not a Character warp.
    -- Keep capsule geometry/local offset and collision flags unchanged.
    controller:call("warp()")
    local p, physical = transform:get_Position(), controller:call("get_Position()")
    if physical then
        local dx, dy, dz = p.x-physical.x, p.y-physical.y, p.z-physical.z
        record.position_sync_status = string.format("Sync requested | controller/root gap %.3f | Y gap %.3f",
            math.sqrt(dx*dx+dy*dy+dz*dz), dy)
    else
        record.position_sync_status = "Sync requested; controller readback unavailable"
    end
    if record.player then state.position_sync_status = record.position_sync_status end
end
local function restore_driver_visual()
    local previous=state.driver_visual
    state.driver_visual=nil
    for _,entry in ipairs(previous or {}) do
        attempt(function()
            if valid(entry.joint) then entry.joint:set_LocalPosition(entry.position) end
        end)
    end
end
local function driver_ride_stage(cart,driver)
    local name=attempt(function() return tostring(driver:get_ActionManager().CurrentActionList[0].Name):lower() end)
    if name and (name:find("oxcart",1,true) or name:find("ride",1,true)
        or name:find("sit",1,true)) then return true end
    local layer=attempt(function() return driver:get_Motion():getLayer(0) end)
    local bank=layer and tonumber((attempt(function() return layer:get_MotionBankID() end)))
    local motion=layer and tonumber((attempt(function() return layer:get_MotionID() end)))
    -- Observed native boarding/seat/exit motions occupy this ox-ride range.
    -- AI SitWait alone is NOT proof of seating: it persists during native walking.
    if bank==0 and motion and motion>=3500 and motion<=3526 then return true end
    local ai=driver_debug_get(cart.status,"get_oxcartAI")
    local now=tonumber((attempt(function() return ai.DriverActionNow end)))
    local req=tonumber((attempt(function() return ai.DriverActionReq end)))
    if now==2 or now==3 or req==2 or req==3 then return true end
    if bank and motion and motion>=0 and motion<4294967295 then return false end
    if name and (name:find("locomotion",1,true) or name:find("walk",1,true)
        or name:find("wait",1,true) or name:find("idle",1,true)) then return false end
    return nil -- Unknown stage: use visual displacement, never force a bound root.
end
local driver_combat={enabled=false,next_at=0,flags={},hooks={},native={},view={},freeze_records={},rules={},waits={},entries={},retry_at={}}
-- Temporary isolation while testing native freeGetOff + exit animation.
local driver_native_exit_testing=true
local function prepare_driver_visual(cart,human)
    state.visual_driver=nil
    local driver=cart.driver
    if not valid(driver) or driver==human then
        driver_debug.result="No valid non-player driver"; return false
    end
    if (driver:get_Transform():get_Position()-cart.body:get_Position()):length()>12 then
        driver_debug.result="Driver farther than 12"; return false
    end
    if driver_native_exit_testing then
        driver_debug.result="Driver left untouched for native exit testing"
        return false
    end
    state.visual_drivers=state.visual_drivers or {}
    local key=address(driver)
    -- A previously displaced skeleton remains displaced, including after release.
    if state.visual_drivers[key] then
        local record=state.visual_drivers[key]
        if driver_debug_bridge.freeze_enabled~=false and not record.machine and driver_ride_stage(cart,driver)==true then
            local held=driver_combat.freeze_records[key] or hold(driver,false)
            driver_combat.freeze_records[key]=nil
            record.machine,record.enabled=held.machine,held.enabled
        end
        state.visual_driver=driver
        driver_combat.evacuate(cart,driver)
        return true
    end
    local transform,origin=driver:get_Transform(),cart.body:get_Position()
    local position=transform:get_Position()
    local dx,dz=cart_forward(cart)
    local target=Vector3f.new(origin.x-dx*50,position.y,origin.z-dz*50)
    local ride_stage=driver_ride_stage(cart,driver)
    if ride_stage==false then
        local terrain=driver["<AdjustTerrain>k__BackingField"]
        if not driver["<PosRotContext>k__BackingField"] or not terrain or not terrain.MainCharacterController then
            driver_debug.result="Driver teleport skipped: position components unavailable"; return false
        end
        transform:set_Position(target)
        synchronize_seat_position({actor=driver},transform)
        local fall=driver["<FallInfo>k__BackingField"]
        if fall then
            fall:call("resetBaseHeight(via.Position)",transform:get_UniversalPosition())
            fall:call("resetFallHeight()")
        end
        driver_debug.result="Unseated driver teleported once; no return on release"
    else
        state.visual_driver=driver
        local record={actor=driver}
        if ride_stage==true and driver_debug_bridge.freeze_enabled~=false then
            record=driver_combat.freeze_records[key] or hold(driver,false)
            driver_combat.freeze_records[key]=nil
        end
        record.delta=Vector3f.new(origin.x,origin.y+1000,origin.z)-position
        state.visual_drivers[key]=record
        driver_combat.evacuate(cart,driver)
        driver_debug.result="Boarding/driving driver visually displaced; no return on release"
    end
    return true
end
local function apply_driver_visual()
    restore_driver_visual()
    state.driver_visual={}
    for key,record in pairs(state.visual_drivers or {}) do
        if not valid(record.actor) then state.visual_drivers[key]=nil
        else
            local first=#state.driver_visual+1
            local ok,err=pcall(function()
                local transform=record.actor:get_Transform()
                local cart=state.cart
                if state.active and state.visual_driver==record.actor and cart
                    and valid(cart.body:get_GameObject()) and valid(cart.ox) then
                    local origin,position=cart.body:get_Position(),transform:get_Position()
                    local dx,dz=cart_forward(cart)
                    record.delta=Vector3f.new(origin.x,origin.y+1000,origin.z)-position
                end
                local joints=transform:get_Joints()
                assert(joints,"Driver skeleton joints unavailable")
                local count=0
                for _,joint in pairs(joints:get_elements()) do
                    if valid(joint) and not valid(joint:get_Parent()) then
                        count=count+1
                        local local_position,world_position=joint:get_LocalPosition(),joint:get_Position()
                        state.driver_visual[#state.driver_visual+1]={
                            joint=joint,position=Vector3f.new(local_position.x,local_position.y,local_position.z),
                        }
                        joint:set_Position(Vector3f.new(world_position.x+record.delta.x,
                            world_position.y+record.delta.y,world_position.z+record.delta.z))
                    end
                end
                assert(count>0,"Driver skeleton has no independent root joint")
            end)
            if not ok then
                for i=#state.driver_visual,first,-1 do
                    local entry=state.driver_visual[i]
                    attempt(function() if valid(entry.joint) then entry.joint:set_LocalPosition(entry.position) end end)
                    state.driver_visual[i]=nil
                end
                unhold(record)
                state.visual_drivers[key]=nil
                if state.visual_driver==record.actor then state.visual_driver=nil end
                driver_debug.result="Driver visual offset unavailable: "..tostring(err)
            end
        end
    end
    if #state.driver_visual==0 then state.driver_visual=nil end
end
-- Debug overrides are scoped to one selected cart and never alter OJR.
driver_debug_bridge.native_exit_guard=function(cart)
    local driver=cart.driver
    assert(not state.active,"Release manual control before testing freeGetOff")
    assert(not (state.visual_drivers and state.visual_drivers[address(driver)])
        and not driver_combat.freeze_records[address(driver)],"Driver has existing visual/freeze modifications; reload scripts and save first")
    local battle_override=false
    for _,value in pairs(driver_combat.flags) do if value then battle_override=true end end
    assert(not battle_override and not next(driver_combat.rules)
        and not next(driver_combat.waits),"Existing battle/Wait overrides; clear or reload scripts/save before native test")
    assert(fsm(driver):call("get_Enabled()") == true,"Driver FSM is disabled; test requires normal native state")
end
driver_debug_bridge.freeze_enabled=false
function driver_combat.cleanup()
    driver_combat.flags,driver_combat.native,driver_combat.pending={}, {}, nil
    driver_combat.enabled=false
    driver_combat.target=nil
    driver_combat.actor=nil
    driver_combat.message=nil
    driver_combat.next_at=0
    driver_combat.rules,driver_combat.waits={},{}
    for _,record in pairs(driver_combat.freeze_records) do unhold(record) end
    driver_combat.freeze_records={}
    for _,record in pairs(state.visual_drivers or {}) do
        if record.machine then unhold(record);record.machine=nil end
    end
end
function driver_combat.install(status,name)
    if not status or os.clock()<(driver_combat.retry_at[name] or 0) then return end
    local ok,err=pcall(function()
        assert(thread and thread.get_hook_storage,"Hook storage unavailable")
        local method=status:get_type_definition():get_method(name)
        assert(method and method:get_num_params()==0,"Zero-argument method unavailable")
        assert(method:get_return_type():get_name()=="Boolean","Not a Boolean method")
        local entry=method:get_function()
        assert(entry and sdk.to_int64(entry)~=0,"Function entry not ready")
        local key=name..":"..tostring(entry)
        if driver_combat.entries[key] then driver_combat.hooks[name]=true; return end
        local storage_key="lmd_battle_"..key
        sdk.hook(method,function(args)
            local object=sdk.to_managed_object(args[2])
            local object_address=object and address(object)
            local rule=object_address and driver_combat.rules[object_address]
            local force=object_address==driver_combat.target and driver_combat.flags[name]==true
            if name=="isAnyoneBattleMode" and rule and valid(rule.driver) and valid(rule.ox) then force=true end
            thread.get_hook_storage()[storage_key]={address=object_address,force=force}
            if force then return sdk.PreHookResult.SKIP_ORIGINAL end
        end,function(ret)
            local call=thread.get_hook_storage()[storage_key]
            if call and call.force then return sdk.to_ptr(1) end
            if call and call.address==driver_combat.target and driver_combat.target then
                driver_combat.native[name]=sdk.to_int64(ret)~=0
            end
            return ret
        end,true) -- Hook the stable entry itself instead of following an initialization JMP.
        driver_combat.entries[key]=true
        driver_combat.hooks[name]=true
    end)
    if not ok then
        driver_combat.hooks[name]=tostring(err)
        driver_combat.retry_at[name]=os.clock()+1
    else driver_combat.retry_at[name]=nil end
end
function driver_combat.wait_active(ox)
    local record=valid(ox) and driver_combat.waits[address(ox:get_GameObject())]
    return record and os.clock()<record.until_time
end
function driver_combat.stop_one_second(cart)
    if not cart or not valid(cart.ox) then return end
    driver_combat.waits[address(cart.ox:get_GameObject())]={ox=cart.ox,until_time=os.clock()+1}
    action(cart.ox,"Wait")
end
function driver_combat.evacuate(cart,driver)
    local key=cart.status and address(cart.status)
    if key then
        driver_combat.rules[key]={status=cart.status,driver=driver,ox=cart.ox}
        driver_combat.enabled=true
        driver_combat.install(cart.status,"isAnyoneBattleMode")
        driver_combat.stop_one_second(cart)
    end
end
function driver_combat.update_waits()
    if paused() then return end
    for key,record in pairs(driver_combat.waits) do
        if not valid(record.ox) or os.clock()>=record.until_time then driver_combat.waits[key]=nil
        else action(record.ox,"Wait") end
    end
end
driver_debug_bridge.combat_read=function()
    driver_combat.enabled=true
    return driver_combat.view
end
driver_debug_bridge.combat_set=function(name,value)
    if name~="isDriverBattleMode" and name~="isAnyoneBattleMode" and name~="freeze" then return false end
    driver_combat.enabled=true
    driver_combat.pending=driver_combat.pending or {}
    driver_combat.pending[name]=value==true
    return true
end
driver_debug_bridge.combat_cleanup=driver_combat.cleanup
driver_debug_bridge.combat_reset=function()
    driver_combat.enabled=true
    driver_combat.pending={clear=true}
end
driver_debug_bridge.teleport_driver=function()
    driver_combat.enabled=true
    driver_combat.pending=driver_combat.pending or {}
    driver_combat.pending.teleport=true
end
function driver_combat.poll()
    if (not driver_combat.enabled and not next(driver_combat.rules)) or paused() then return end
    if not driver_combat.pending and os.clock()<driver_combat.next_at then return end
    driver_combat.next_at=os.clock()+0.25
    for key,rule in pairs(driver_combat.rules) do
        if not valid(rule.driver) or not valid(rule.ox) then driver_combat.rules[key]=nil
        else driver_combat.install(rule.status,"isAnyoneBattleMode") end
    end
    local cart=state.active and state.cart or discover()
    local driver=cart and cart.driver
    local status=cart and cart.status
    local target=status and address(status) or nil
    if target~=driver_combat.target then
        driver_combat.flags,driver_combat.native={},{}
        driver_combat.target=target
        driver_combat.actor=nil
    end
    if valid(driver) then driver_combat.actor=driver
    elseif target and valid(driver_combat.actor) then driver=driver_combat.actor end
    local pending=driver_combat.pending;driver_combat.pending=nil
    if pending then
        for name,value in pairs(pending) do
            if name=="clear" then
                driver_combat.cleanup()
                driver_debug_bridge.freeze_enabled=false
            elseif name=="teleport" then
                assert(cart and valid(driver) and driver~=player(),"No nearby NPC driver")
                local transform=driver:get_Transform()
                local terrain=driver["<AdjustTerrain>k__BackingField"]
                assert(driver["<PosRotContext>k__BackingField"] and terrain and terrain.MainCharacterController,
                    "Driver position components unavailable")
                local origin,position=cart.body:get_Position(),transform:get_Position()
                local dx,dz=cart_forward(cart)
                transform:set_Position(Vector3f.new(origin.x-dx*500,position.y,origin.z-dz*500))
                synchronize_seat_position({actor=driver},transform)
                local fall=driver["<FallInfo>k__BackingField"]
                if fall then
                    fall:call("resetBaseHeight(via.Position)",transform:get_UniversalPosition())
                    fall:call("resetFallHeight()")
                end
                driver_combat.message="One-shot physical driver teleport: 500 units behind cart"
            elseif name=="freeze" then
                driver_debug_bridge.freeze_enabled=value
                if not value then
                    for _,record in pairs(driver_combat.freeze_records) do unhold(record) end
                    driver_combat.freeze_records={}
                    for _,record in pairs(state.visual_drivers or {}) do
                        if record.machine then unhold(record);record.machine=nil end
                    end
                elseif valid(driver) then
                    local record=state.visual_drivers and state.visual_drivers[address(driver)]
                    if record then
                        if not record.machine then
                            local held=hold(driver,false);record.machine,record.enabled=held.machine,held.enabled
                        end
                    elseif not driver_combat.freeze_records[address(driver)] then
                        driver_combat.freeze_records[address(driver)]=hold(driver,false)
                    end
                end
            elseif status then
                driver_combat.install(status,name)
                -- Retain requested flags even when an entry is not ready; install retries later.
                driver_combat.flags[name]=value
                if name=="isAnyoneBattleMode" and value then driver_combat.stop_one_second(cart) end
            end
        end
    end
    local function battle(actor)
        if not valid(actor) then return nil end
        return attempt(function() return actor["<Human>k__BackingField"]:call("get_IsBattleMode()") end)
    end
    local view={driver_id=valid(driver) and tostring(driver:get_CharaID()) or "unavailable",
        driver_battle=battle(driver),player_battle=battle(player()),
        driver_fsm=valid(driver) and attempt(function() return fsm(driver):call("get_Enabled()") end),
        driver_action_fsm=valid(driver) and attempt(function() return driver:get_ActionManager().Fsm:call("get_Enabled()") end),
        freeze_enabled=driver_debug_bridge.freeze_enabled,flags=driver_combat.flags,
        hooks=driver_combat.hooks,native=driver_combat.native,message=driver_combat.message,
        automatic_battle=target and driver_combat.rules[target]~=nil or false}
    if valid(driver) then
        local p=driver:get_Transform():get_Position()
        view.driver_position=string.format("X %.2f / Y %.2f / Z %.2f",p.x,p.y,p.z)
        if cart then view.driver_distance=(p-cart.body:get_Position()):length() end
    end
    for _,name in ipairs({"isDriverBattleMode","isAnyoneBattleMode"}) do
        if status then driver_combat.install(status,name) end
        view[name]=driver_debug_get(status,name)
    end
    driver_combat.view=view
end
local function pose(record, slot, align_to_display)
    if not valid(record.actor) then return end
    local transform = record.actor:get_Transform()
    local anchor = slot.useOxAnchor and state.cart.ox:get_Transform() or state.cart.anchor
    local position_slot = slot
    if record.player and current_visual().enabled and not align_to_display then
        anchor = state.cart.anchor
        local offset = current_visual().offset
        -- Enforce the same finite bounds for saved values and live writes.
        position_slot = {
            x = -0.071 + root_offset(offset.x, -10, 10),
            y = 0.920 + root_offset(offset.y, -10, 10),
            z = -0.856 + root_offset(offset.z, -10, 10),
        }
    end
    local p = offset_position(anchor, position_slot)
    position_observer("seat_before", record.actor, p)
    transform:set_Position(p)
    local a = math.rad(slot.yaw)
    local x, z = anchor:get_AxisX(), anchor:get_AxisZ()
    transform:lookAt(Vector3f.new(p.x + x.x * math.sin(a) + z.x * math.cos(a),
        p.y + x.y * math.sin(a) + z.y * math.cos(a), p.z + x.z * math.sin(a) + z.z * math.cos(a)), anchor:get_AxisY())
    if (record.player or record.pawn) and settings.debug_player_position_sync then synchronize_seat_position(record, transform) end
    if (record.player or record.pawn) and state.active and settings.debug_player_reset_fall then
        -- A forced seat descending with the cart must not retain an old fall
        -- reference. Use universal via.Position, not the scene-space seat vec3.
        -- Do not change landing/contact flags or request another animation.
        local fall = record.actor["<FallInfo>k__BackingField"]
        assert(fall, "Seat fall reset: FallInfo unavailable")
        fall:call("resetBaseHeight(via.Position)", transform:get_UniversalPosition())
        fall:call("resetFallHeight()")
        record.fall_reset_status = "Fall reference and accumulated height reset while seat is controlled"
        if record.player then state.fall_reset_status = record.fall_reset_status end
    end
    position_observer("seat_after", record.actor, p)
end
local release
local function release_seats(align_player)
    if align_player and (current_visual().enabled or state.player_visual) then
        -- Bring the gameplay/camera root to the visible seat before removing
        -- the display translation. Layout changes must not perform this handoff.
        attempt(function()
            if not state.cart or not valid(state.cart.body:get_GameObject()) then return end
            for _, record in ipairs(state.seats) do
                if record.player and valid(record.actor) then
                    pose(record, settings.presets[settings.preset].slots[record.slot], true)
                end
            end
        end)
    end
    restore_player_visual()
    for _, record in ipairs(state.seats) do
        unhold(record)
        if not record.player and valid(record.actor) then attempt(function() action(record.actor, "Wait") end) end
    end
    state.seats = {}
end
local function apply_player_visual()
    restore_player_visual()
    if not state.active or not current_visual().enabled or not valid(state.player) then return end
    local transform = state.player:get_Transform()
    local joints = transform:get_Joints()
    assert(joints, "Player skeleton joints unavailable")
    local entries = joints:get_elements()
    local roots = {}
    for _, joint in pairs(entries) do
        if valid(joint) and not valid(joint:get_Parent()) then roots[#roots + 1] = joint end
    end
    assert(#roots > 0, "Player skeleton has no independent root joint")
    local slot = settings.presets[settings.preset].slots[1]
    local target = offset_position(state.cart.anchor, slot)
    local delta = target - transform:get_Position()
    position_observer("visual_before", state.player, target)
    state.player_visual = {}
    for _, joint in ipairs(roots) do
        local local_position = joint:get_LocalPosition()
        local world_position = joint:get_Position()
        -- Keep the current animation pose; change only its root translation.
        state.player_visual[#state.player_visual + 1] = {
            joint = joint, position = Vector3f.new(local_position.x, local_position.y, local_position.z),
        }
        joint:set_Position(Vector3f.new(world_position.x + delta.x, world_position.y + delta.y, world_position.z + delta.z))
    end
    state.visual_status = "Applied to " .. #roots .. " player skeleton root(s)"
    position_observer("visual_after", state.player, target)
end
local function inherit_passengers(cart)
    local layout = settings.presets[settings.preset]
    if layout.pawns_customized then return end
    local passengers = bus.journey and bus.journey.passenger_layout and bus.journey.passenger_layout()
    if not passengers then
        -- Optional config import also works with Journey disabled/uninstalled.
        local config = attempt(function() return json.load_file("OxcartsJourneyRedux.json") end)
        local family = cart_family(cart)
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
    if slot.useDirectMotion then record.pose_node = nil
    else record.pose_node = slot.anim or "SitOnChairActions" end
    if record.machine then
        record.machine:call("set_Enabled(System.Boolean)", true)
        record.freeze_after = state.behavior_frame + 1
    end
    if slot.useDirectMotion then
        record.actor:get_Motion():getLayer(0):call("changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)",
            slot.bankID or 0, slot.motionID or 0, 0, 12, 1, 1)
    else
        action(record.actor, slot.anim or "SitOnChairActions", 1)
    end
end
local function arrange()
    -- A preset change is not a release: Wait(priority 0) and Sit(priority 1)
    -- in the same frame can leave the higher-priority Wait pending in-game.
    restore_player_visual()
    local previous_seats = state.seats
    local retained = {}
    local function seat_record(actor)
        for _, record in ipairs(previous_seats) do
            if address(record.actor) == address(actor) then retained[record] = true; return record end
        end
        return hold(actor, true)
    end
    state.seats = {}
    -- Request the configured starting pose with FSM running; random idles may
    -- subsequently update it. Pose lock follows the currently requested pose.
    local driver_seat = seat_record(state.player)
    driver_seat.player, driver_seat.slot = true, 1
    state.seats[1] = driver_seat
    local layout = settings.presets[settings.preset]
    animate(driver_seat, layout.slots[1])
    driver_seat.next_idle = os.clock() + 15
    for i, actor in ipairs(party()) do
        local slot = layout.slots[i + 1]
        -- Capture the original FSM state for cleanup, but never freeze pawns.
        -- Old preset freezeFsm flags do not override the running-FSM seat rule.
        local record = seat_record(actor)
        record.pawn, record.slot = true, i + 1
        state.seats[#state.seats + 1] = record
        animate(record, slot)
        record.next_idle = os.clock() + 15
    end
    if valid(state.test_passenger_driver) and state.cart
        and state.test_passenger_cart==address(state.cart.body:get_GameObject())
        and state.test_passenger_driver~=state.player then
        local record=seat_record(state.test_passenger_driver)
        -- Reuse pawn seat physics/protection, but this NPC is not added to the party.
        record.pawn,record.driver_passenger=true,true
        record.custom_slot={x=0.85,y=0.23,z=-2.5,yaw=90,anim="SitOnChairActions",randomIdle=false}
        state.seats[#state.seats+1]=record
        animate(record,record.custom_slot)
        record.next_idle=os.clock()+15
    end
    for _, record in ipairs(previous_seats) do
        if not retained[record] then
            unhold(record)
            if record.pawn and valid(record.actor) then attempt(function() action(record.actor, "Wait") end) end
        end
    end
end
local function constrain_seats(position_only)
    local layout = settings.presets[settings.preset]
    for _, record in ipairs(state.seats) do
        if valid(record.actor) then
            local slot = record.custom_slot or layout.slots[record.slot]
            pose(record, slot)
            if not position_only then
                if record.machine then
                    if record.pawn or (record.player and not settings.debug_player_freeze) then
                        record.machine:call("set_Enabled(System.Boolean)", true)
                    elseif state.behavior_frame >= record.freeze_after then
                        record.machine:call("set_Enabled(System.Boolean)", false)
                    end
                end
                if slot.randomIdle and os.clock() >= record.next_idle then
                    local nodes = { "SitOnChairActions", "LivSitChairCrosslegs", "LivSitChairLean", "LivSitChairBook01" }
                    local idle = {}
                    for key, value in pairs(slot) do idle[key] = value end
                    idle.anim, idle.useDirectMotion = nodes[math.random(#nodes)], false
                    animate(record, idle)
                    record.next_idle = os.clock() + 15 + math.random() * 25
                end
            end
        end
    end
end
local function restore_hotbar()
    -- No UI fields were changed: the next native draw resumes automatically.
    state.hotbar_status = "Skill bar: native drawing restored"
end
local function should_draw_hotbar(element)
    if not (state.active or state.native_drive) then return true end
    local go = element and element:call("get_GameObject")
    if go and go:call("get_Name") == "ui010201" then
        state.hotbar_status = "Skill bar: hidden while driving"
        return false
    end
    return true
end
if re.on_pre_gui_draw_element then
    re.on_pre_gui_draw_element(function(element)
        -- Suppress only this HUD draw. No GUIBase/Root/text access or UI mutation.
        local ok, draw = pcall(should_draw_hotbar, element)
        if not ok then
            state.hotbar_status = "Skill bar hide unavailable: " .. tostring(draw)
            return true
        end
        return draw
    end)
else
    state.hotbar_status = "Skill bar hide unavailable: GUI draw callback missing"
end
release = function(reason)
    position_observer("release_begin", state.player)
    local cart = state.cart
    local was_active = state.active
    state.active = false
    restore_camera_distance()
    camera_override.suspended=nil
    restore_camera_fov()
    fov_override.suspended=nil
    -- Keep the last skeleton offset after release; do not return the driver.
    state.visual_driver=nil
    state.binding_capture = nil
    restore_hotbar()
    -- Release ownership BEFORE touching any potentially unloaded game object.
    if bus.owner == TITLE then bus.owner, bus.heartbeat = nil, nil end
    if cart and valid(cart.ox) then attempt(function() action(cart.ox, "Wait") end) end
    attempt(function() release_seats(true) end)
    state.seats = {}
    state.test_passenger_driver,state.test_passenger_cart=nil,nil
    -- Capture once, after camera/root has been handed back to the visible body,
    -- before normal movement/falling resumes. Universal coordinates survive scene shifts.
    if was_active then
        state.return_point = nil
        if valid(state.player) and player() == state.player then
            attempt(function()
                state.return_point = { position = state.player:get_Transform():get_UniversalPosition(),
                    actor_address = address(state.player) }
            end)
        end
    end
    if valid(state.player) then
        attempt(function() action(state.player, "Wait") end)
    end
    state.driver, state.cart, state.player = nil, nil, nil
    state.protected, state.axis, state.heading = {}, 0, nil
    if state.ojr_claimed and bus.journey and bus.journey.resume then attempt(bus.journey.resume) end
    state.ojr_claimed = false
    state.toggle_pending, state.freeze_setting_changed, state.layout_changed = false, false, false
    state.message = reason or "Control released; navigation recovery is not guaranteed"
    position_observer("release_end", player())
end
local function return_to_release_position()
    assert(not state.active, "Release control before returning")
    local saved, human = state.return_point, player()
    assert(saved, "No release position recorded")
    assert(valid(human) and address(human) == saved.actor_address, "Recorded player is no longer available")
    local transform = human:get_Transform()
    local fall = human["<FallInfo>k__BackingField"]
    assert(fall and human["<PosRotContext>k__BackingField"]
        and human["<AdjustTerrain>k__BackingField"]
        and human["<AdjustTerrain>k__BackingField"].MainCharacterController, "Player position components unavailable")
    restore_player_visual()
    transform:set_UniversalPosition(saved.position)
    synchronize_seat_position({actor=human,player=true}, transform)
    fall:call("resetBaseHeight(via.Position)", transform:get_UniversalPosition())
    fall:call("resetFallHeight()")
    action(human, "Wait")
    state.message = "Returned to the last release position"
end
local function acquire()
    assert(not (driver_debug_bridge.native_seat_busy and driver_debug_bridge.native_seat_busy()),
        "Native driver-seat test owns the player; use its Exit button, not manual Take control")
    local function phase(name)
        state.takeover_phase = name
        if log.info then log.info("[" .. TITLE .. "] takeover: " .. name) end
    end
    if state.active then release(); return end
    phase("begin; skill-bar draw suppression")
    assert(not paused(), "Close the paused game menu before taking control")
    assert(not bus.owner, "Another controller owns this cart")
    assert(not rawget(_G, "OJR_SeatBindings") or bus.journey,
        "Installed Oxcarts Journey Redux needs the compatibility build")
    local cart, human = discover(), player()
    phase("cart/player discovered")
    assert(cart and valid(human), "No nearby connected oxcart/player")
    assert((human:get_Transform():get_Position() - cart.body:get_Position()):length() <= 8, "Approach within 8 units of the cart")
    select_family(cart, false)
    inherit_passengers(cart)
    phase("cart-family preset selected")
    if bus.journey and bus.journey.suspend then
        state.ojr_claimed = true
        bus.journey.suspend()
    end
    state.cart, state.player, state.level = cart, human, 1
    state.player_blocked_actions, state.player_last_blocked_action = 0, nil
    state.pawn_blocked_actions, state.pawn_last_blocked_action = 0, nil
    bus.owner, bus.heartbeat, state.active = TITLE, os.clock(), true
    phase("ownership acquired")
    begin_driver_debug(cart)
    local move_ok,moved = pcall(prepare_driver_visual,cart,human)
    if not move_ok then driver_debug.result="Driver visual offset unavailable: "..tostring(moved); moved=false end
    phase(moved and "native driver displacement applied" or "native driver displacement skipped")
    action(cart.ox, "Wait")
    state.heading = tonumber(cart.cow["<PosRotContext>k__BackingField"]:call("get_AngleYDeg()"))
    assert(state.heading, "Cow heading unavailable")
    phase("ox heading captured; arranging seats")
    arrange()
    phase("seat animations requested")
    save()
    phase("takeover complete")
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

-- Direct keyboard/gamepad HID polling; mouse input is not used for driving.
local function enum(name)
    local result, def = {}, sdk.find_type_definition(name)
    if def then for _, field in ipairs(def:get_fields()) do if field:is_static() then result[field:get_name()] = field:get_data(nil) end end end
    return result
end
local keys, pads = enum("via.hid.KeyboardKey"), enum("via.hid.GamePadButton")
local default_bindings = {
    near_take = { keyboard = "E", gamepad = "RLeft" },
    sit = { keyboard = "E", gamepad = "RLeft" },
    stand = { keyboard = "Space", gamepad = "Decide" },
    up = { keyboard = "W", gamepad = "RTrigTop" },
    down = { keyboard = "S", gamepad = "LTrigTop" },
}
settings.bindings = {}
local binding_enums = { keyboard = keys, gamepad = pads }
for name, defaults in pairs(default_bindings) do
    settings.bindings[name] = {}
    for device, key in pairs(defaults) do
        local stored = type(saved) == "table" and type(saved.bindings) == "table" and saved.bindings[name]
        stored = type(stored) == "table" and stored[device]
        settings.bindings[name][device] = (stored == "None" or binding_enums[device][stored]) and stored or key
    end
end
-- Correct the previous release's default shoulder ordering once; user bindings
-- other than that exact old default pair remain untouched.
if type(saved) == "table" and saved.shoulder_binding_rule ~= 1
    and settings.bindings.up.gamepad == "LTrigTop" and settings.bindings.down.gamepad == "RTrigTop" then
    settings.bindings.up.gamepad, settings.bindings.down.gamepad = "RTrigTop", "LTrigTop"
end
settings.shoulder_binding_rule = 1
local previous, input = {}, { keyboard = 0, stick = 0 }
local binding_choices = {}
for device, values in pairs(binding_enums) do
    local choices = { "None" }
    for name, value in pairs(values) do
        if value ~= 0 and name ~= "None" and name ~= "All" then choices[#choices + 1] = name end
    end
    table.sort(choices, function(a, b) if a == b then return false elseif a == "None" then return true elseif b == "None" then return false end return a < b end)
    binding_choices[device] = choices
end
local function poll()
    local kb = sdk.call_native_func(sdk.get_native_singleton("via.hid.Keyboard"), sdk.find_type_definition("via.hid.Keyboard"), "get_Device")
    local gp = sdk.call_native_func(sdk.get_native_singleton("via.hid.Gamepad"), sdk.find_type_definition("via.hid.GamePad"), "get_MergedDevice")
    local bits = gp and gp:call("get_Button") or 0
    local function down(name) return kb and keys[name] and kb:call("isDown", keys[name]) == true end
    local function pad(name) local n = pads[name]; return n and n ~= 0 and (bits & n) == n end

    if state.binding_capture then
        local capture, pressed = state.binding_capture, {}
        for _, name in ipairs(binding_choices[capture.device]) do
            local code = binding_enums[capture.device][name]
            if name ~= "None" and code and code ~= 0 then
                if capture.device == "keyboard" then pressed[name] = down(name)
                elseif capture.device == "gamepad" then pressed[name] = pad(name)
                end
            end
        end
        -- Seed from held inputs first; the click opening capture cannot bind itself.
        if capture.previous then
            for _, name in ipairs(binding_choices[capture.device]) do
                if pressed[name] and not capture.previous[name] then
                    settings.bindings[capture.action][capture.device] = name
                    state.binding_capture, state.rebind_block = nil, true
                    save(); break
                end
            end
        end
        capture.previous = pressed
        previous, input = {}, { keyboard = 0, stick = 0 }
        return
    end
    local now = {}
    for name, binding in pairs(settings.bindings) do
        now[name] = down(binding.keyboard) or pad(binding.gamepad)
    end

    if state.rebind_block then
        local held = false
        for _, value in pairs(now) do if value then held = true end end
        previous = now
        input = { keyboard = 0, stick = 0 }
        if not held then state.rebind_block = false end
        return
    end
    for name, value in pairs(now) do input[name] = value and not previous[name] end
    previous = now
    input.keyboard = (down("D") and 1 or 0) - (down("A") and 1 or 0)
    input.stick = gp and tonumber(attempt(function() return gp:call("get_AxisL()").x end)) or 0
    if not input.stick or input.stick ~= input.stick then input.stick = 0 end
    input.stick = clamp(input.stick, -1, 1)
    if attempt(function() return reframework:is_drawing_ui() end) == true then
        input = { keyboard = 0, stick = 0, near_take = not state.active and input.near_take }
    end
end
re.on_application_entry("UpdateHID", function()
    local ok, err = pcall(poll)
    if not ok then
        input = { keyboard = 0, stick = 0 }
        state.error = "Input unavailable: " .. tostring(err)
    end
end)

local last = os.clock()
-- Separate native driving lease: never sets state.active or creates seat
-- records, so the legacy player/pawn constraints and action guards stay off.
;(function()
    driver_debug_bridge.native_drive_begin=function(q)
        assert(not state.active and not bus.owner,"Another controller owns this cart")
        local heading=tonumber(q.cart.cow["<PosRotContext>k__BackingField"]:call("get_AngleYDeg()"))
        assert(heading,"Native driving cow heading unavailable")
        select_family(q.cart,false)
        q.drive={level=1,axis=0,heading=heading}
        state.native_drive=q
        bus.owner,bus.heartbeat=TITLE,os.clock()
        camera_override.suspended,fov_override.suspended=nil,nil
        action(q.cart.ox,"Wait")
        state.message="Native driving: Wait"
    end
    driver_debug_bridge.native_drive_end=function(q)
        if state.native_drive~=q then return end
        state.native_drive=nil;q.drive=nil
        if bus.owner==TITLE then bus.owner,bus.heartbeat=nil,nil end
        if valid(q.cart.ox) then attempt(function() action(q.cart.ox,"Wait") end) end
        restore_camera_distance();restore_camera_fov();restore_hotbar()
        state.message="Native driving stopped; seat exit handled by the game"
    end
    driver_debug_bridge.native_drive_tick=function(dt)
        local q=state.native_drive
        if not q then return end
        local cart,d=q.cart,q.drive
        local active=q.mgr:call("getActiveInteract(app.Character)",q.ch)
        if not valid(q.ch) or player()~=q.ch or not valid(cart.ox) or not valid(cart.cow)
            or not valid(cart.body:get_GameObject()) then
            driver_debug_bridge.native_seat_close();return
        end
        if address(q.seat.SitChara)~=address(q.ch) or not active or not active.Point
            or address(active.Point.Object)~=address(q.io) or tonumber(active.Point.PointNo)~=q.point then
            -- Native A/exit owns its animation and trajectory. Stop only cow
            -- control; do not insert another endInteract or player Wait.
            driver_debug_bridge.native_drive_end(q)
            q.exiting=true;q.exit_at=os.clock();return
        end
        if cart.status and (cart.status:call("isBroken_OxCart()") or cart.status:call("isDead_Ox()")) then
            driver_debug_bridge.native_drive_end(q)
            driver_debug_bridge.native_seat_command("exit");return
        end
        bus.heartbeat=os.clock()
        -- Stand/A belongs to the game's native interaction, not this loop.
        if state.toggle_pending then
            state.toggle_pending=false
            driver_debug_bridge.native_drive_end(q)
            driver_debug_bridge.native_seat_command("exit");return
        end
        if input.up then d.level=clamp(d.level+1,1,#modes)
        elseif input.down then d.level=clamp(d.level-1,1,#modes) end
        local change=dt/0.15
        d.axis=d.axis+clamp(input.keyboard-d.axis,-change,change)
        local axis=d.axis
        if input.keyboard==0 and math.abs(axis)<0.001 then
            local stick=input.stick
            axis=math.abs(stick)<=0.15 and 0 or (stick<0 and -1 or 1)*(math.abs(stick)-0.15)/0.85
        end
        if math.abs(axis)>0.001 then
            local heading=tonumber(cart.cow["<PosRotContext>k__BackingField"]:call("get_AngleYDeg()"))
            d.heading=(heading-axis*settings.sensitivity*dt+180)%360-180
        end
        cart.cow:call("set_TargetFrontAngleDeg(System.Single)",d.heading)
        cart.cow:call("set_TargetMoveAngleDeg(System.Single)",d.heading)
        local current=cart.ox["<ActionManager>k__BackingField"].CurrentActionList[0]
        if not current or current.Name~=modes[d.level] then action(cart.ox,modes[d.level]) end
        state.message="Native driving: "..modes[d.level]
    end
end)()
re.on_application_entry("LateUpdateBehavior", function()
    poll_driver_debug()
    local wait_ok,wait_err=pcall(driver_combat.update_waits)
    if not wait_ok then driver_combat.view.error=tostring(wait_err) end
    local combat_ok,combat_err=pcall(driver_combat.poll)
    if not combat_ok then driver_combat.view.error=tostring(combat_err) end
    local now = os.clock()
    local dt = clamp(now - last, 0, 0.1); last = now
    if state.active then bus.heartbeat = now end
    if state.active then
        command(function()
            local cart = state.cart
            if not cart or not valid(cart.ox) or not valid(cart.cow) or not valid(cart.body:get_GameObject())
                or not valid(state.player) or player() ~= state.player then
                release("Game session/cart unloaded")
            end
        end)
    end
    if state.freeze_setting_changed then
        state.freeze_setting_changed = false
        command(function()
            local record = state.seats[1]
            if state.active and record and record.player and record.machine and valid(record.actor) then
                if settings.debug_player_freeze then
                    record.freeze_after = state.behavior_frame + 2
                else
                    record.machine:call("set_Enabled(System.Boolean)", true)
                end
            end
        end)
    end
    local near_take = input.near_take
    input.near_take = false
    if paused() then
        local gui = singleton("app.GuiManager")
        if gui and attempt(function() return gui:call("get_IsLoadGui()") end) == true then
            state.return_point, state.return_pending = nil, nil
        end
        if state.active and gui and gui["<IsDispPhotoModeAll>k__BackingField"] == true
            and attempt(function() return gui:call("get_IsLoadGui()") end) ~= true then
            command(function()
                if valid(state.cart.body:get_GameObject()) then constrain_seats(true) end
            end)
        end
        input.take, input.up, input.down, input.sit, input.stand = false, false, false, false, false
        return
    end
    state.behavior_frame = state.behavior_frame + 1

    -- Consume shared input in the native route; never fall through to acquire,
    -- arrange, constrain_seats, player visual offsets or preset pose requests.
    if driver_debug_bridge.native_seat_busy() then
        local ok,err=pcall(driver_debug_bridge.native_drive_tick,dt)
        if not ok then
            state.error="Native driving: "..tostring(err)
            attempt(driver_debug_bridge.native_seat_close)
        end
        input={keyboard=0,stick=0};state.toggle_pending=false
        return
    end

    if state.return_pending then
        state.return_pending = false
        command(return_to_release_position)
        input.take, input.up, input.down, input.sit, input.stand = false, false, false, false, false
        return
    end
    command(function()
        local toggle = state.toggle_pending
        state.toggle_pending = false
        if toggle then acquire()
        elseif near_take and not state.active then
            local human, cart = player(), discover()
            local seated = valid(human) and cart and passenger_seated(cart,human)
            if valid(human) and cart and seated == false and front_distance(cart, human) < 2 then
                acquire()
                input.sit, input.stand, input.up, input.down = false, false, false, false
            elseif seated == true then
                -- Let OJR's own seat/preset key handle this edge; do not suspend it.
            elseif valid(human) and cart and seated == nil then
                state.message = "Passenger seat state unavailable; use the menu to take control"
            else state.message = "Near takeover requires a connected cart and front-point distance < 2"
            end
        end
        if not state.active then return end
        local cart = state.cart
        if not valid(cart.ox) or not valid(cart.cow) or not valid(cart.body:get_GameObject()) or not valid(state.player)
            or player() ~= state.player then release("Cart/player changed"); return end
        local live_go = singleton("app.NPCManager").OxcartManager._RaidAttack_CachedGameObject
        if address(live_go) ~= address(cart.ox:get_GameObject()) then release("Active cart changed"); return end
        local distance = (state.player:get_Transform():get_Position() - cart.body:get_Position()):length()
        if distance > 20 then release("Player left the cart"); return end
        if cart.status and (cart.status:call("isBroken_OxCart()") or cart.status:call("isDead_Ox()")) then release("Cart destroyed"); return end
        if input.stand then release(""); return end
        if input.sit then
            select_family(cart, true)
            inherit_passengers(cart); save(); arrange()
        end
        if state.layout_changed then state.layout_changed = false; arrange() end
        if input.up then shift(1) elseif input.down then shift(-1) end
        constrain_seats(false)
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
        local wanted=driver_combat.wait_active(cart.ox) and "Wait" or modes[state.level]
        if current and current.Name ~= wanted then action(cart.ox,wanted) end
        state.protected = {}
        for _, actor in ipairs({ state.player, cart.ox, cart.cow }) do state.protected[address(actor:get_GameObject())] = true end
        state.protected[address(cart.body:get_GameObject())] = true
        for _, pawn in ipairs(party()) do state.protected[address(pawn:get_GameObject())] = true end
    end)
    input.take, input.up, input.down, input.sit, input.stand = false, false, false, false, false
end)
re.on_frame(function()
    -- Rendering callback only renews the ownership lease; no actor mutations.
    if state.active or state.native_drive then bus.heartbeat = os.clock() end
end)
-- Undo the display offset before gameplay/animation evaluation, then reapply
-- after joint expressions. Never move the player's actor root for display.
re.on_pre_application_entry("UpdateBehavior", function()
    restore_player_visual()
    restore_driver_visual()
end)
re.on_application_entry("UpdateJointExpression", function()
    local ok, err = pcall(apply_player_visual)
    if not ok then
        restore_player_visual()
        state.visual_status = "Unavailable: " .. tostring(err)
    end
    local driver_ok,driver_err=pcall(apply_driver_visual)
    if not driver_ok then
        restore_driver_visual()
        state.visual_driver=nil
        driver_debug.result="Driver visual offset unavailable: "..tostring(driver_err)
    end
end)

local function hook(type_name, signature, before)
    local def = sdk.find_type_definition(type_name)
    local method = def and def:get_method(signature)
    if method then sdk.hook(method, before, function(ret) return ret end)
    else log.warn("[" .. TITLE .. "] Missing optional hook: " .. signature) end
end
hook("app.Gm80_042","executeBreak(System.Boolean)",function(args)
    attempt(function() driver_debug_bridge.road_native("executeBreak",sdk.to_managed_object(args[2])) end)
end)
for _,name in ipairs({"onWarp","restoreCoord"}) do
    hook("app.CoordRestorerOnOxcart",name,function(args)
        attempt(function() driver_debug_bridge.road_native(name,sdk.to_managed_object(args[2])) end)
    end)
end
for _,native_name in ipairs({"forceSitDown","InterractSeatForce"}) do
    hook("app.OxcartAI",native_name,function(args)
        if not driver_debug.actor or not driver_debug.cart then return end
        pcall(function()
            local object=sdk.to_managed_object(args[2])
            local ai=driver_debug_get(driver_debug.cart.status,"get_oxcartAI")
            if object and ai and address(object)==address(ai) then
                local events=driver_debug.events
                events[#events+1]=string.format("+%.3fs OxcartAI.%s arg1(raw)=%s",
                    os.clock()-driver_debug.started,native_name,tostring(sdk.to_int64(args[3])))
                if #events>2000 then table.remove(events,1) end
            end
        end)
        -- Observation only: preserve both native execution and return value.
    end)
end
hook("app.ActionManager", "requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", function(args)
    -- Observe requests before the manual-driving guard. Native seating may not
    -- retain a readable current action, but its requested name can be captured.
    if driver_debug.actor and valid(driver_debug.actor) then
        pcall(function()
            local manager=sdk.to_managed_object(args[2])
            if manager and address(manager:get_GameObject())==address(driver_debug.actor:get_GameObject()) then
                local node=sdk.to_managed_object(args[4]):ToString()
                local event=string.format("+%.3fs requestActionCore priority=%s layer=%s node=%s source=%s",
                    os.clock()-driver_debug.started,tostring(sdk.to_int64(args[3])),
                    tostring(sdk.to_int64(args[5])),node,state.issuing and "mod" or "external/native")
                local events=driver_debug.events
                events[#events+1]=event
                if #events>2000 then table.remove(events,1) end
            end
        end)
    end
    -- Cover the AI's short battle-entry Run even with manual control released.
    local request_am=sdk.to_managed_object(args[2])
    if request_am and (sdk.to_int64(args[5]) & 0xffffffff)==0 then
        local waiting=driver_combat.waits[address(request_am:get_GameObject())]
        if waiting and os.clock()<waiting.until_time then
            local node=sdk.to_managed_object(args[4]):ToString()
            if node=="Walk" or node=="Run" or node=="Dash" then return sdk.PreHookResult.SKIP_ORIGINAL end
        end
    end
    if not state.active or state.issuing then return end
    local am = sdk.to_managed_object(args[2])
    if not am then return end
    if (sdk.to_int64(args[5]) & 0xffffffff) ~= 0 then return end
    local node = sdk.to_managed_object(args[4]):ToString()
    local actor_address = address(am:get_GameObject())
    if settings.debug_player_pose_lock then
        for _, seated in ipairs(state.seats) do
            if (seated.player or seated.pawn) and valid(seated.actor)
                and actor_address == address(seated.actor:get_GameObject()) then
                if node ~= seated.pose_node then
            -- Leave the FSM, contact processing and higher animation layers
            -- running. Block only external primary-action replacements.
                    seated.blocked_actions = (seated.blocked_actions or 0) + 1
                    seated.last_blocked_action = tostring(node):sub(1, 160)
                    local prefix = seated.player and "player" or "pawn"
                    state[prefix .. "_blocked_actions"] = (state[prefix .. "_blocked_actions"] or 0) + 1
                    state[prefix .. "_last_blocked_action"] = seated.last_blocked_action
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
                return
            end
        end
    end
    if paused() or actor_address ~= address(state.cart.ox:get_GameObject()) then return end
    for _, name in ipairs(modes) do
        if node == name then return sdk.PreHookResult.SKIP_ORIGINAL end
    end
end)
hook("app.HitController", "damageProc(app.HitController.DamageInfo)", function(args)
    if not state.active then return end
    local info = sdk.to_managed_object(args[3])
    local receiver = info and info["<DamageGameObject>k__BackingField"]
    if not valid(receiver) then return end
    local receiver_address = address(receiver)
    -- Only seat-bound actors are immune; cart damage keeps its own multiplier.
    for _, record in ipairs(state.seats) do
        local actor_object = valid(record.actor) and attempt(function() return record.actor:get_GameObject() end)
        if actor_object and address(actor_object) == receiver_address then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end
end)
hook("app.HitController", "updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)", function(args)
    attempt(function() driver_debug_bridge.road_damage(sdk.to_managed_object(args[3])) end)
    if state.native_drive then
        local info=sdk.to_managed_object(args[3])
        local receiver=info and info["<DamageGameObject>k__BackingField"]
        local cart=state.native_drive.cart
        if valid(receiver) and (address(receiver)==address(cart.body:get_GameObject())
            or address(receiver)==address(cart.ox:get_GameObject()) or address(receiver)==address(cart.cow:get_GameObject())) then
            info.Damage=info.Damage*0.01
        end
        return
    end
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
re.on_script_reset(function()
    attempt(driver_debug_bridge.native_seat_close)
    attempt(driver_debug_bridge.road_close)
    if driver_debug.actor then save_driver_report("script reset before recording completed") end
    driver_combat.cleanup()
    restore_driver_visual()
    for _,record in pairs(state.visual_drivers or {}) do unhold(record) end
    state.visual_drivers={}
    release("Scripts reset")
    state.return_point, state.return_pending = nil, nil
    if rawget(_G,"LMD_CartFrontProbe") == front_probe then _G.LMD_CartFrontProbe = nil end
    driver_debug.actor,driver_debug.cart,driver_debug.driving_seat=nil,nil,nil
    driver_debug.exit_pending=nil
    if rawget(_G,"LMD_DriverDebug")==driver_debug_bridge then _G.LMD_DriverDebug=nil end
end)
re.on_config_save(save)
-- Optional diagnostic reader: no mutations and no managed values are written
-- to disk by this controller. The independent recorder owns serialization.
_G.LMD_PositionProbe = {
    version = 1,
    read = function()
        return { active = state.active, level = modes[state.level], frame = state.behavior_frame,
            player = player(), bound_player = state.player, cart = state.cart,
            party = party(), seats = state.seats, presets = settings.presets, preset = settings.preset,
            visual_enabled = current_visual().enabled, visual_status = state.visual_status,
            freeze_player = settings.debug_player_freeze, root_offset = current_visual().offset,
            position_sync = settings.debug_player_position_sync, position_sync_status = state.position_sync_status,
            reset_fall = settings.debug_player_reset_fall, fall_reset_status = state.fall_reset_status,
            pose_lock = settings.debug_player_pose_lock, blocked_actions = state.player_blocked_actions,
            last_blocked_action = state.player_last_blocked_action,
            pawn_blocked_actions = state.pawn_blocked_actions, pawn_last_blocked_action = state.pawn_last_blocked_action,
            visual_records = state.player_visual, paused = paused(), error = state.error, message = state.message }
    end,
}
re.on_draw_ui(function()
    if not imgui.tree_node(TITLE) then return end
    if imgui.tree_node("General settings") then
        if imgui.button((state.active or state.native_drive) and "Release control" or "Take control") then state.toggle_pending = true end
        if not state.active and state.return_point then
            if imgui.button("Return to last release position") then
                state.return_pending = true
                state.message = "Return queued; close the paused game menu to apply"
            end
        end
        if state.message and state.message ~= "" then imgui.text(state.message) end
        if state.error then imgui.text("Last error: " .. state.error) end
        local changed,value=imgui.slider_float("Steering sensitivity (degrees/s)",settings.sensitivity,5,180)
        if changed then settings.sensitivity=value; save() end
        imgui.tree_pop()
    end
    if imgui.tree_node("Keybind settings") then
        if imgui.begin_table("Driving keybinds",3,1) then
            imgui.table_next_row()
            for _,label in ipairs({"Action","Gamepad","Keyboard"}) do
                imgui.table_next_column(); imgui.table_header(label)
            end
            for _,row in ipairs({{"near_take","Take control"},{"sit","Sit / cycle preset"},
                {"stand","Stand / release control"},{"up","Accelerate"},{"down","Decelerate"}}) do
                local binding=settings.bindings[row[1]]
                imgui.table_next_row()
                imgui.table_next_column(); imgui.text(row[2])
                for _,device in ipairs({"gamepad","keyboard"}) do
                    imgui.table_next_column()
                    local id=row[1].."_"..device
                    local capture=state.binding_capture
                    if capture and capture.action==row[1] and capture.device==device then
                        imgui.button("Press next input...##"..id)
                    elseif imgui.button(binding[device].."##"..id) then
                        state.binding_capture={action=row[1],device=device}
                        previous,input={},{keyboard=0,stick=0}
                    end
                end

            end
            imgui.end_table()
        end
        local capture = state.binding_capture
        if capture then
            local id = capture.action .. "_" .. capture.device
            imgui.text("Waiting for next " .. capture.device .. " input (release held keys first)")
            if imgui.button("Cancel mapping##" .. id) then state.binding_capture, state.rebind_block = nil, true end
            imgui.same_line()
            if imgui.button("Unbind##" .. id) then
                settings.bindings[capture.action][capture.device] = "None"
                state.binding_capture, state.rebind_block = nil, true; save()
            end
        end
        if imgui.button("Restore default driving keys") then
            for name, defaults in pairs(default_bindings) do
                settings.bindings[name] = {}
                for device, key in pairs(defaults) do settings.bindings[name][device] = key end
            end
            state.binding_capture, state.rebind_block = nil, true
            previous, input = {}, { keyboard = 0, stick = 0 }; save()
        end
        imgui.tree_pop()
    end
    if imgui.tree_node("Driving seat presets") then
        local family = state.active and state.family or settings.presets[settings.preset].family
        local family_index = 1
        for i, value in ipairs(families) do if family == value then family_index = i end end
        local family_changed, family_index_new = imgui.combo("Cart type", family_index, family_names)
        if family_changed and families[family_index_new] then
            if not state.active then
                choose_family(families[family_index_new], false); save()
                family = settings.presets[settings.preset].family
            end -- While driving, only the actual cart's family is allowed.
        end
        local names, indices, current = {}, {}, 1
        for i, preset in ipairs(settings.presets) do
            if preset.family == family and preset.enabled then
                names[#names + 1], indices[#indices + 1] = preset.name, i
                if i == settings.preset then current = #names end
            end
        end
        local selected, index = imgui.combo("Active layout", current, names)
        if selected and indices[index] then
            settings.preset = indices[index]
            family_cursor[family] = settings.preset
            state.layout_changed = state.active
            save()
        end
        if imgui.button("Add layout from current preset") then
            local old = settings.presets[settings.preset]
            local copy = copy_layout(old, "Layout " .. (#settings.presets + 1), family)
            copy.pawns_customized = true
            settings.presets[#settings.presets + 1] = copy; settings.preset = #settings.presets
            family_cursor[copy.family], state.layout_changed = settings.preset, state.active; save()
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
                if i == 1 then
                    local camera=layout.camera
                    local fov_toggle,fov_on=imgui.checkbox("Override FOV",camera.fov_enabled)
                    if fov_toggle then camera.fov_enabled=fov_on; if not fov_on then restore_camera_fov() end; save() end
                    local fov_changed,fov=imgui.slider_float("FOV (degrees)",camera.fov,20,120)
                    if fov_changed then camera.fov=copy_camera({fov=fov}).fov; save() end
                    local toggle,on=imgui.checkbox("Override camera distance",camera.distance_enabled)
                    if toggle then camera.distance_enabled=on; if not on then restore_camera_distance() end; save() end
                    local edited,distance=imgui.slider_float("Camera distance",camera.distance,0,10)
                    if edited then camera.distance=copy_camera({distance=distance}).distance; save() end
                    local visual = layout.player_visual
                    local c, enabled = imgui.checkbox("Camera offset", visual.enabled)
                    if c then visual.enabled = enabled; save() end
                    if visual.enabled then
                        for _, axis in ipairs({"x","y","z"}) do
                            local changed, n = imgui.slider_float("Camera " .. axis, visual.offset[axis], -10, 10)
                            if changed then visual.offset[axis] = root_offset(n, -10, 10); save() end
                        end
                    end
                end
                local direct_changed, direct = imgui.checkbox("Use Bank/Motion IDs##" .. i, slot.useDirectMotion == true)
                if direct_changed then slot.useDirectMotion = direct; if i > 1 then layout.pawns_customized = true end; state.layout_changed = state.active; save() end
                if slot.useDirectMotion then
                    for _, key in ipairs({ "bankID", "motionID" }) do
                        local c, n = imgui.drag_int(key .. "##" .. i, slot[key] or 0, 1, 0, 99999)
                        if c then slot[key] = n; if i > 1 then layout.pawns_customized = true end; state.layout_changed = state.active; save() end
                    end
                else
                    local c, anim = imgui.input_text("Action name##" .. i, slot.anim or "SitOnChairActions")
                    if c then slot.anim = anim ~= "" and anim or "SitOnChairActions"; if i > 1 then layout.pawns_customized = true end; state.layout_changed = state.active; save() end
                end
                do
                    local c, idle = imgui.checkbox("Random sitting idles##" .. i, slot.randomIdle == true)
                    if c then slot.randomIdle = idle; if i > 1 then layout.pawns_customized = true end; save() end
                end
                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end
    imgui.tree_pop()
end)
