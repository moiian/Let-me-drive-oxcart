-- NPC/distance monitoring is read-only. Explicit driver combat/FSM/teleport/exit tests
-- delegate a one-shot animation request to the driving mod's debug bridge.
local TITLE, CONFIG = "aelinore debug tool", "NPCAnimationMonitor.json" -- Keep existing NPC ID config.
local function read(fn) local ok, value = pcall(fn); if ok then return value end end
local function valid(actor) return actor and read(function() return actor:get_Valid() end) == true end
local function parse_id(text)
    local id = tonumber(text)
    if not id or id ~= id or id < 0 or id > 4294967295 or id % 1 ~= 0 then return nil end
    return id
end
local saved = read(function() return json.load_file(CONFIG) end)
local id_text = type(saved) == "table" and tostring(saved.id or "963132753") or "963132753"
local target_id = parse_id(id_text) or 963132753
local enabled, actor, next_sample, next_lookup = true, nil, 0, 0
local snapshot = { status = "Waiting for first sample", actions = {}, motions = {} }
local history, previous_signature = {}, nil
local distance_enabled, distance_status, distance_body, next_body_lookup = false, "Distance monitor OFF", nil, 0
-- Independent, read-only probe for temporary NPC party membership.
local escort = {enabled=false,id_text="1261971841",id=1261971841,
    status="Monitor OFF",history={}}
local function sample_escort(now)
    local nm=sdk.get_managed_singleton("app.NPCManager")
    local ch=nm and nm:getCharacter(escort.id)
    if not valid(ch) then
        escort.status="NPC not loaded/found; approach the NPC and check Character ID"
        escort.signature=nil
        return
    end
    local actual=read(function() return ch.CharacterID end)
    if actual and actual~=escort.id then escort.status="Lookup returned a different Character ID";return end
    local td=sdk.find_type_definition("app.NPCUtil")
    assert(td,"NPCUtil unavailable")
    local function query(signature,argument)
        local ok,value=pcall(function()
            local method=td:get_method(signature)
            assert(method,"Method unavailable: "..signature)
            assert(argument,"Argument unavailable")
            local result=method:call(nil,argument)
            assert(type(result)=="boolean","Expected Boolean, got "..tostring(result))
            return result
        end)
        return ok and tostring(value) or ("UNAVAILABLE: "..tostring(value):sub(1,200))
    end
    local by_character=query("isAccompanyPLParty(app.Character)",ch)
    local holder=read(function() return nm:getNPCHolder(escort.id) end)
    local by_holder=query("isAccompanyPLParty(app.NPCHolder)",holder)
    local name=read(function() return ch:get_GameObject():get_Name() end) or "unknown"
    escort.status=string.format("Character ID: %s | %s\nFollow player party (Character): %s\nFollow player party (NPCHolder): %s",
        tostring(escort.id),name,by_character,by_holder)
    local signature=by_character.." / "..by_holder
    if escort.signature~=signature then
        escort.signature=signature
        escort.history[#escort.history+1]=string.format("%.1fs | Character / Holder: %s",now,signature)
        if #escort.history>12 then table.remove(escort.history,1) end
    end
end
local front_offset = rawget(_G,"AelinoreCartFrontOffset")
if not front_offset then
    local stored = read(function() return json.load_file("OxcartFrontProbe.json") end)
    front_offset = {x=0,y=0,z=1.5}
    for _,key in ipairs({"x","y","z"}) do
        local n = type(stored)=="table" and tonumber(stored[key])
        if n and n==n and math.abs(n)<=10 then front_offset[key]=n end
    end
    _G.AelinoreCartFrontOffset = front_offset
end
local function format_distance(result)
    local text=string.format("Player / cart center: %.3f\nPlayer / cart front (driver): %.3f | %s",
        result.center_distance,result.distance,result.model)
    if type(result.forward_distance)=="number" then
        local side=result.forward_distance>0 and "FRONT" or (result.forward_distance<0 and "REAR" or "CENTER")
        text=text..string.format("\nSigned forward from center: %+.3f | %s (+ front / - rear)",result.forward_distance,side)
        text=text..string.format("\nSigned forward from driver point: %+.3f (+ ahead / - behind) | hotkey forward 0..3: %s\nSigned lateral from center: %+.3f (+ right / - left)\nHorizontal projection; height does not change front/rear",
            result.front_forward_distance,tostring(result.front_forward_distance>=0 and result.front_forward_distance<=3),result.lateral_distance)
    else text=text.."\nSigned distance unavailable; reload the updated LMD script" end
    return text
end
local function sample_distance(now)
    local bridge=rawget(_G,"LMD_CartFrontProbe")
    if bridge then
        local result=bridge.read()
        distance_status=result and format_distance(result)
            or "No connected cart/player available for takeover"
        return
    end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local human = cm and cm["<ManualPlayer>k__BackingField"]
    if not valid(human) then distance_body = nil; distance_status = "Player unavailable"; return end
    if now >= next_body_lookup or not valid(distance_body) then
        next_body_lookup = now + 1
        distance_body = nil
        local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"),
            sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
        local nm = sdk.get_managed_singleton("app.NPCManager")
        local ox = nm and nm.OxcartManager and nm.OxcartManager._RaidAttack_CachedGameObject
        local reference = valid(ox) and ox:get_Transform():get_Position() or human:get_Transform():get_Position()
        local nearest = valid(ox) and 12 or 50
        for _, model in ipairs({"gm80_042", "gm80_052", "gm81_004"}) do
            for suffix = -1, 10 do
                local name = suffix == -1 and model or string.format("%s_%02d", model, suffix)
                local go = scene and scene:call("findGameObject(System.String)", name)
                if valid(go) then
                    local distance = (go:get_Transform():get_Position() - reference):length()
                    if distance < nearest then distance_body, nearest = go, distance end
                end
            end
        end
    end
    if not valid(distance_body) then distance_status = "No nearby cart body found"; return end
    local transform=distance_body:get_Transform()
    local p=transform:get_Position()
    local nm=sdk.get_managed_singleton("app.NPCManager")
    local ox=nm and nm.OxcartManager and nm.OxcartManager._RaidAttack_CachedGameObject
    local oxp=valid(ox) and ox:get_Transform():get_Position()
    local dx,dz
    if oxp then dx,dz=oxp.x-p.x,oxp.z-p.z else
        local axis=transform:get_AxisZ();dx,dz=axis.x,axis.z
    end
    local length=math.sqrt(dx*dx+dz*dz)
    if length<0.001 then
        local axis=transform:get_AxisZ();dx,dz=axis.x,axis.z
        length=math.sqrt(dx*dx+dz*dz)
    end
    assert(length>=0.001,"Cannot determine cart front direction")
    dx,dz=dx/length,dz/length
    local target=Vector3f.new(p.x+dz*front_offset.x+dx*front_offset.z,p.y+front_offset.y,
        p.z-dx*front_offset.x+dz*front_offset.z)
    local distance = (human:get_Transform():get_Position() - target):length()
    local center_distance=(human:get_Transform():get_Position()-p):length()
    local hp=human:get_Transform():get_Position()
    local forward=(hp.x-p.x)*dx+(hp.z-p.z)*dz
    distance_status = format_distance({center_distance=center_distance,distance=distance,
        model=distance_body:get_Name(),forward_distance=forward,
        front_forward_distance=forward-front_offset.z,
        lateral_distance=(hp.x-p.x)*dz-(hp.z-p.z)*dx})
    if not oxp then distance_status=distance_status.."\nFront direction fallback: cart AxisZ (ox unavailable)" end
end
-- Independent pawn-height diagnostics. No actor/controller/animation writes.
local height={enabled=false,rows={},tracks={},actors={},next_lookup=0,
    status="Monitor OFF",samples={},marks={},next_log={},next_save=0}
local function height_save()
    if not height.path then return end
    local ok,err=pcall(function()
        json.dump_file(height.path,{version=1,started=height.started,
            samples=height.samples,marks=height.marks,status=height.status})
    end)
    height.log_status=ok and ("Saved: reframework/data/"..height.path) or ("Save failed: "..tostring(err))
end
local function height_record(on)
    if not on then height_save();height.recording=false;return end
    height.enabled=true;height.recording=true;height.samples={};height.marks={};height.next_log={}
    height.started=os.date("%Y-%m-%d %H:%M:%S");height.start_clock=os.clock()
    height.path="PawnHeight-"..os.date("%Y%m%d-%H%M%S")..".json"
    height.next_save=0;height_save()
end
local function height_lookup(now)
    if now<height.next_lookup then return end
    height.next_lookup=now+1
    local pm=sdk.get_managed_singleton("app.PawnManager")
    local found,seen={},{}
    local function add(pawn)
        local ch=pawn and pawn:get_CachedCharacter()
        if not valid(ch) then return end
        local key=tostring(ch:get_address())
        if not seen[key] then seen[key]=true;found[#found+1]=ch end
    end
    if pm then
        add(pm:get_MainPawn())
        local list=pm:get_PartyPawnList()
        if list then for i=0,list:get_Count()-1 do add(list._items and list._items[i] or list:get_Item(i)) end end
    end
    height.actors=found
    for key in pairs(height.tracks) do if not seen[key] then height.tracks[key]=nil end end
    height.body=nil
    local cm=sdk.get_managed_singleton("app.CharacterManager")
    local player=cm and cm["<ManualPlayer>k__BackingField"]
    if not valid(player) then return end
    local origin=player:get_Transform():get_Position()
    local scene=sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"),
        sdk.find_type_definition("via.SceneManager"),"get_CurrentScene()")
    local nearest=50
    for _,model in ipairs({"gm80_042","gm80_052","gm81_004"}) do
        for suffix=-1,10 do
            local name=suffix==-1 and model or string.format("%s_%02d",model,suffix)
            local go=scene and scene:call("findGameObject(System.String)",name)
            if valid(go) then
                local distance=(go:get_Transform():get_Position()-origin):length()
                if distance<nearest then height.body=go;nearest=distance end
            end
        end
    end
end
local function height_sample(phase)
    if not height.enabled then return end
    local now=os.clock()
    local ok,err=pcall(function()
        height_lookup(now)
        local body=valid(height.body) and height.body:get_Transform()
        local bp=body and body:get_Position()
        local up=body and body:get_AxisY()
        local rows={}
        for i,ch in ipairs(height.actors) do
            if valid(ch) then
                local transform=ch:get_Transform()
                local p=transform:get_Position()
                local key=tostring(ch:get_address())
                local track=height.tracks[key] or {window={},previous={}}
                height.tracks[key]=track
                local rel
                if bp and up then
                    local len=math.sqrt(up.x*up.x+up.y*up.y+up.z*up.z)
                    if len>0.0001 then rel=((p.x-bp.x)*up.x+(p.y-bp.y)*up.y+(p.z-bp.z)*up.z)/len end
                end
                local bones={}
                local rig=read(function() return transform:get_Joints():get_elements() end)
                for _,joint in pairs(rig or {}) do
                    if valid(joint) and not valid(read(function() return joint:get_Parent() end)) then
                        local jp=read(function() return joint:get_Position() end)
                        if jp then bones[#bones+1]={name=tostring(read(function() return joint:get_Name() end) or "root"),y=jp.y,offset=jp.y-p.y} end
                    end
                end
                table.sort(bones,function(a,b) return a.name<b.name end)
                local previous=track.previous[phase]
                local row={pawn=i,key=key,name=tostring(read(function() return ch:get_GameObject():get_Name() end) or key),
                    x=p.x,y=p.y,z=p.z,relative_height=rel,bones=bones,
                    delta_y=previous and p.y-previous.y or 0,
                    delta_relative=previous and rel and previous.relative_height and rel-previous.relative_height or nil}
                track.previous[phase]={y=p.y,relative_height=rel}
                track.window[#track.window+1]={t=now,y=p.y,rel=rel,bone=bones[1] and bones[1].offset}
                while #track.window>720 or (#track.window>0 and now-track.window[1].t>2) do table.remove(track.window,1) end
                local function span(field)
                    local lo,hi
                    for _,v in ipairs(track.window) do if v[field] then lo=math.min(lo or v[field],v[field]);hi=math.max(hi or v[field],v[field]) end end
                    return lo and hi-lo or nil
                end
                row.range_y=span("y");row.range_relative=span("rel");row.range_bone_offset=span("bone")
                rows[#rows+1]=row
            end
        end
        height.rows=rows
        height.status=string.format("%s | %d pawns | Cart: %s | 2-second ranges",phase,#rows,
            body and tostring(height.body:get_Name()) or "UNAVAILABLE (relative height omitted)")
        if height.recording and now>=(height.next_log[phase] or 0) then
            height.next_log[phase]=now+0.1
            height.samples[#height.samples+1]={t=now-height.start_clock,phase=phase,rows=rows,
                cart=bp and {x=bp.x,y=bp.y,z=bp.z,up={x=up.x,y=up.y,z=up.z}} or nil}
            if #height.samples>3600 then table.remove(height.samples,1) end
        end
    end)
    if not ok then height.rows={};height.status="Height read unavailable: "..tostring(err):sub(1,250) end
    if height.recording and now>=height.next_save then height.next_save=now+5;height_save() end
end
re.on_application_entry("UpdateJointExpression",function() height_sample("UpdateJointExpression") end)
re.on_application_entry("PrepareRendering",function() height_sample("PrepareRendering") end)
-- Scalar metadata only. Incremental reads use the same MotionInfo API as Emote
-- Dogma's resource-name listing; never load banks or request/change motions.
local motion_names = {}
local function clear_names() motion_names = {} end
local function usable_id(id)
    return type(id) == "number" and id >= 0 and id < 4294967295 and id % 1 == 0
end
local function motion_count(motion, bank)
    if not motion then return nil, "Motion object missing" end
    local ok, value = pcall(function() return motion:getMotionCount(bank) end)
    if ok and tonumber(value) then return tonumber(value) end
    local first = ok and ("Unexpected count: " .. tostring(value)) or tostring(value)
    ok, value = pcall(function() return motion:call("getMotionCount(System.UInt32)", bank) end)
    if ok and tonumber(value) then return tonumber(value) end
    return nil, first .. " | explicit call: " .. tostring(value)
end
local function resolve_names(motion, items, backing_motion)
    local wanted, order = {}, {}
    for _, item in ipairs(items) do
        if usable_id(item.bank) and usable_id(item.id) then
            if not wanted[item.bank] then wanted[item.bank] = {}; order[#order + 1] = item.bank end
            wanted[item.bank][item.id] = true
            if not motion_names[item.bank] then
                -- Emote Dogma lists metadata on <Motion>k__BackingField, while
                -- get_Motion() is the proven source of playing layer IDs here.
                local source = backing_motion and "backing" or "getter"
                local count, err = motion_count(backing_motion or motion, item.bank)
                if not count and backing_motion and backing_motion ~= motion then
                    local fallback_error
                    count, fallback_error = motion_count(motion, item.bank)
                    source = "getter"
                    if not count then err = "backing: " .. tostring(err) .. " | getter: " .. tostring(fallback_error) end
                end
                if type(count) == "number" and count >= 0 then
                    motion_names[item.bank] = { names = {}, index = 0, count = math.min(count, 20000), source = source }
                else
                    motion_names[item.bank] = { names = {}, index = 0, count = 0,
                        error = tostring(err or ("Invalid count " .. tostring(count))) }
                end
            end
        end
    end
    local info, budget = nil, 24 -- At most 24 metadata entries per 4 Hz sample.
    while budget > 0 do
        local progressed = false
        for _, bank in ipairs(order) do
            local cache = motion_names[bank]
            local unresolved = false
            for id in pairs(wanted[bank]) do
                if not cache or not cache.names[id] then unresolved = true; break end
            end
            if budget > 0 and unresolved and cache and not cache.error and cache.index < cache.count then
                if not info then info = read(function() return sdk.create_instance("via.motion.MotionInfo", true) end) end
                if not info then return end
                local ok, err = pcall(function()
                    local metadata_motion = cache.source == "backing" and backing_motion or motion
                    metadata_motion:call("getMotionInfoByIndex(System.UInt32, System.UInt32, via.motion.MotionInfo)", bank, cache.index, info)
                    local id, name = info:get_MotionID(), info:get_MotionName()
                    if usable_id(id) and type(name) == "string" and name ~= "" then cache.names[id] = name end
                end)
                if not ok then cache.error = tostring(err) end
                cache.index = cache.index + 1
                budget, progressed = budget - 1, true
            end
        end
        if not progressed then break end
    end
    for _, item in ipairs(items) do
        local cache = motion_names[item.bank]
        if not usable_id(item.id) or not usable_id(item.bank) then
            item.name_status = "No active motion (-1)"
        elseif cache then
            item.name = cache.names[item.id]
            item.metadata_error = cache.error
            item.name_status = cache.error and "Metadata read unavailable"
                or (cache.index < cache.count and ("Resolving names " .. cache.index .. "/" .. cache.count))
                or "Name not exposed by this bank"
        else item.name_status = "Motion metadata unavailable" end
    end
end
local function apply_id()
    local id = parse_id(id_text)
    if not id then snapshot.status = "Invalid ID: enter a decimal or 0x hexadecimal Character ID"; return end
    target_id, actor, next_sample, next_lookup = id, nil, 0, 0
    clear_names()
    history, previous_signature = {}, nil
    snapshot = { status = "Looking up NPC", actions = {}, motions = {} }
    read(function() json.dump_file(CONFIG, { id = tostring(id) }) end)
end
local function sample(now)
    if not valid(actor) then
        actor = nil
        clear_names()
        if now >= next_lookup then
            next_lookup = now + 1
            actor = read(function()
                local manager = sdk.get_managed_singleton("app.NPCManager")
                return manager and manager:getCharacter(target_id)
            end)
        end
    end
    if not valid(actor) then
        snapshot = { status = "NPC not loaded/found; approach the NPC and check its Character ID", actions = {}, motions = {} }
        return
    end
    local character_id = read(function() return actor.CharacterID end)
    if character_id and character_id ~= target_id then
        actor = nil
        clear_names()
        snapshot = { status = "Lookup returned a different Character ID", actions = {}, motions = {} }
        return
    end
    local current = { status = "NPC found (4 samples/s)", actions = {}, motions = {},
        object_name = read(function() return actor:get_GameObject():get_Name() end) }
    local manager = read(function() return actor["<ActionManager>k__BackingField"] or actor:get_ActionManager() end)
    local list = manager and read(function() return manager.CurrentActionList end)
    for layer = 0, 7 do
        local node = list and read(function() return list[layer] end)
        local name = node and read(function() return node.Name or node:call("get_Name()") end)
        if name then current.actions[#current.actions + 1] = { layer = layer, name = tostring(name) } end
    end
    local motion = read(function() return actor:get_Motion() end)
    for layer = 0, 3 do
        local node = motion and read(function() return motion:getLayer(layer) end)
        if node then
            local bank = read(function() return node:get_MotionBankID() end)
            local id = read(function() return node:get_MotionID() end)
            if bank ~= nil or id ~= nil then current.motions[#current.motions + 1] = { layer = layer, bank = bank, id = id } end
        end
    end
    local backing_motion = read(function() return actor["<Motion>k__BackingField"] end)
    current.motion_source = backing_motion and "Metadata: Character.Motion backing field (getter fallback)" or "Metadata: get_Motion() (no backing field)"
    current.motion_type = read(function() return (backing_motion or motion):get_type_definition():get_full_name() end)
    if motion then resolve_names(motion, current.motions, backing_motion) end
    local parts = {}
    for _, action in ipairs(current.actions) do parts[#parts + 1] = action.layer .. ":" .. action.name end
    for _, item in ipairs(current.motions) do
        if usable_id(item.id) then
            parts[#parts + 1] = "M" .. item.layer .. ":" .. tostring(item.bank) .. "/" .. tostring(item.id)
                .. (item.name and (" " .. item.name) or "")
        end
    end
    local signature = table.concat(parts, " | ")
    if signature ~= "" and signature ~= previous_signature then
        history[#history + 1] = string.format("%.1fs  %s", now, signature)
        if #history > 12 then table.remove(history, 1) end
        previous_signature = signature
    end
    snapshot = current
end
re.on_application_entry("LateUpdateBehavior", function()
    height_sample("LateUpdateBehavior")
    local now = os.clock()
    if now < next_sample then return end
    next_sample = now + 0.25
    if escort.enabled then
        local ok,err=pcall(sample_escort,now)
        if not ok then escort.status="Read unavailable: "..tostring(err):sub(1,300) end
    end
    if distance_enabled then
        local ok, err = pcall(sample_distance, now)
        if not ok then distance_body = nil; distance_status = "Distance read unavailable: " .. tostring(err) end
    end
    if not enabled then return end
    local ok, err = pcall(sample, now)
    if not ok then actor = nil; snapshot.status = "Read unavailable: " .. tostring(err) end
end)
local driver_report_status
re.on_draw_ui(function()
    if not imgui.tree_node(TITLE) then return end
    if imgui.tree_node("Pawn height monitor (read-only)") then
        local changed,on=imgui.checkbox("Monitor party pawn height",height.enabled)
        if changed then height.enabled=on;if not on then height_record(false) end end
        if imgui.button(height.recording and "Stop pawn height recording" or "Start pawn height recording") then height_record(not height.recording) end
        if height.recording and imgui.button("Mark pawn height jitter") then
            height.marks[#height.marks+1]={t=os.clock()-height.start_clock,label="Observed height jitter"};height_save()
        end
        if imgui.button("Clear pawn height ranges") then height.tracks={} end
        imgui.text(height.status)
        imgui.text("Reads only; no OJR/LMD dependency. Nearest cart within 50 units; keep other carts away.")
        imgui.text("Delta: same update phase. Range: all sampled phases over 2s. Bone offset: bone world Y minus actor Y.")
        local function num(v) return type(v)=="number" and string.format("%+.4f",v) or "N/A" end
        for _,row in ipairs(height.rows) do
            imgui.text(string.format("Pawn %d | %s | %s\nActor Y: %s | Cart-local height: %s\nDelta Y: %s | Delta local: %s\nRange Y: %s | Range local: %s | Range bone offset: %s",
                row.pawn,row.name,row.key,num(row.y),num(row.relative_height),num(row.delta_y),num(row.delta_relative),
                num(row.range_y),num(row.range_relative),num(row.range_bone_offset)))
            for _,bone in ipairs(row.bones) do imgui.text("Root joint "..bone.name.." | Y: "..num(bone.y).." | Offset Y: "..num(bone.offset)) end
        end
        if height.log_status then imgui.text(height.log_status) end
        imgui.tree_pop()
    end
    if imgui.tree_node("Driver combat / FSM") then
        local bridge=rawget(_G,"LMD_DriverDebug")
        if bridge and bridge.combat_read then
            local data=bridge.combat_read() or {}
            local function label(value) if value==nil then return "unavailable" end return tostring(value) end
            imgui.text("Driver ID: "..tostring(data.driver_id or "unavailable"))
            imgui.text("Driver FSM Enabled (actual): "..label(data.driver_fsm))
            imgui.text("Driver ActionManager FSM Enabled: "..label(data.driver_action_fsm))
            imgui.text("Driver battle (Human): "..label(data.driver_battle))
            imgui.text("Player battle (Human): "..label(data.player_battle))
            local changed,on=imgui.checkbox("Freeze driver FSM",data.freeze_enabled~=false)
            if changed then bridge.combat_set("freeze",on) end
            for _,name in ipairs({"isDriverBattleMode","isAnyoneBattleMode"}) do
                local flags=data.flags or {}
                local c,v=imgui.checkbox("Force true: "..name,flags[name]==true)
                if c then bridge.combat_set(name,v) end
                imgui.text(name.." | last natural: "..label((data.native or {})[name]).." | effective: "..label(data[name]))
                local status=(data.hooks or {})[name]
                if status and status~=true then imgui.text("Unavailable: "..tostring(status)) end
            end
            imgui.text("Overrides affect cart battle checks; Human states may remain unchanged.")
            if data.automatic_battle then imgui.text("Takeover protection: isAnyoneBattleMode forced true (until reset/unload)") end
            if imgui.button("Teleport driver 500 units behind cart (once)") and bridge.teleport_driver then bridge.teleport_driver() end
            if data.driver_position then imgui.text("Driver root: "..data.driver_position) end
            if data.driver_distance then imgui.text(string.format("Driver / cart root distance: %.2f",data.driver_distance)) end
            if data.message then imgui.text(data.message) end
            if data.error then imgui.text(data.error) end
            if imgui.button("Clear combat overrides / unfreeze driver") then bridge.combat_reset() end
        else imgui.text("Load Let me drive oxcart for driver tests") end
        imgui.tree_pop()
    end
    if imgui.tree_node("Native driver-seat interaction") then
        local bridge=rawget(_G,"LMD_DriverDebug")
        local data=bridge and bridge.native_seat_read and read(bridge.native_seat_read)
        if data then
            for _,entry in ipairs({{"scan","Inspect empty driver point"},{"enter","Let me drive"},{"exit","Exit native driver seat"},
                {"npc_exit","Request native driver exit (NPC)"}}) do
                if imgui.button(entry[2]) then bridge.native_seat_command(entry[1]) end
            end
            imgui.text(data.status)
            if bridge.native_pawns_command and imgui.button("Let pawns sit") then bridge.native_pawns_command(true) end
            if bridge.native_pawns_exit and imgui.button("Release pawn anchors") then bridge.native_pawns_exit() end
            local pawns=bridge.native_pawns_read and read(bridge.native_pawns_read)
            if pawns then
                imgui.text(pawns.status)
                for _,row in ipairs(pawns.rows or {}) do
                    imgui.text("Pawn "..row.pawn.." | Point "..tostring(row.point).." | "..tostring(row.status))
                end
            end
            if bridge.pawn_trace_control then
                if imgui.button("Start main pawn boarding trace") then bridge.pawn_trace_control(true) end
                if imgui.button("Stop main pawn boarding trace") then bridge.pawn_trace_control(false) end
                local trace=read(bridge.pawn_trace_read)
                if trace then imgui.text(trace.status) end
            end
            for _,row in ipairs(data.rows or {}) do
                imgui.text("Point "..row.point.." | Seat "..tostring(row.seat_no).." | CharacterType "..tostring(row.character_mask)
                    .." | Native driver "..tostring(row.native_is_driver)
                    .." | Enabled "..tostring(row.native_enabled)
                    .." | Selectable "..tostring(row.driver_candidate))
            end
        else imgui.text("Load Let me drive oxcart native branch") end
        imgui.tree_pop()
    end
    if imgui.tree_node("Native seated animation test") then
        local bridge=rawget(_G,"LMD_DriverDebug")
        local data=bridge and bridge.seat_motion_read and read(bridge.seat_motion_read)
        if data then
            if imgui.button("Start seat animation trace (60s)") then bridge.seat_motion_command("start") end
            if imgui.button("Stop seat animation trace") then bridge.seat_motion_command("stop") end
            imgui.text("Read-only seat/rig recording. execJack test disabled.")
            imgui.text(data.status)
            if data.native_loop then imgui.text("Last native seat state: "..data.native_loop) end
            if data.path then imgui.text("LOG: "..data.path) end
        else imgui.text("Load Let me drive oxcart for seat animation tests") end
        imgui.tree_pop()
    end
    if imgui.tree_node("Long-trip diagnostics") then
        local bridge=rawget(_G,"LMD_DriverDebug")
        local data=bridge and bridge.road_read and read(bridge.road_read)
        if data then
            if imgui.button(data.active and "Stop road recording" or "Start road recording") then
                bridge.road_control(not data.active)
            end
            if data.active and imgui.button("Mark recent black screen") then bridge.road_mark() end
            imgui.text(data.status)
        else imgui.text("Load Let me drive oxcart for road recording") end
        imgui.tree_pop()
    end
    if imgui.tree_node("Driver diagnostics") then
        local changed,on=imgui.checkbox("Record driver on takeover (5 seconds)",rawget(_G,"AelinoreDriverDebugEnabled")==true)
        if changed then _G.AelinoreDriverDebugEnabled=on end
        local bridge=rawget(_G,"LMD_DriverDebug")
        local data=bridge and read(bridge.read)
        if bridge and bridge.test_native_exit then
            if imgui.button("Test native DrivingSeat.freeGetOff (once)") then
                local _,status=bridge.test_native_exit();driver_report_status=status
            end
        end
        if bridge and bridge.test_interaction_cleanup then
            for _,name in ipairs({"cancelInteract","endGimmickAction"}) do
                if imgui.button("Test driver "..name.." (once + probes)") then
                    local _,status=bridge.test_interaction_cleanup(name);driver_report_status=status
                end
            end
        end
        if bridge and bridge.test_driver_passenger then
            if imgui.button("Test driver as passenger (after freeGetOff)") then
                local _,status=bridge.test_driver_passenger();driver_report_status=status
            end
        end
        if bridge and bridge.test_exit then
            for _,id in ipairs({3513,3514}) do
                if imgui.button("Test driver exit animation 0/"..id) then
                    local _,status=bridge.test_exit(id);driver_report_status=status
                end
            end
        end
        if bridge and bridge.start then
            if data and data.lifecycle and data.actor then
                if imgui.button("Stop native driver recording") then local _,status=bridge.stop();driver_report_status=status end
                for _,stage in ipairs({"Driver not seated","Driver seated","Cart driving"}) do
                    if imgui.button("Mark: "..stage) then bridge.mark(stage) end
                end
            elseif imgui.button("Start native driver recording") then
                local _,status=bridge.start();driver_report_status=status
            end
        end
        imgui.text(data and data.result or "Enable recording, then take control")
        if data then
            if imgui.button("Save driver report") then
                if bridge.save then
                    local ok,status=bridge.save("manual save")
                    driver_report_status=status
                else
                    local ok,err=pcall(function()
                        json.dump_file("AelinoreDriverDebug.json",{result=data.result,lines=data.lines,methods=data.methods})
                    end)
                    driver_report_status=ok and "Saved: reframework/data/AelinoreDriverDebug.json" or ("Driver report save failed: "..tostring(err))
                end
            end
            if driver_report_status then imgui.text(driver_report_status) end
            if data.log_status and data.log_status~=driver_report_status then imgui.text(data.log_status) end
            local lines=data.lines or {}
            for i=math.max(1,#lines-23),#lines do imgui.text(lines[i]) end
            imgui.text("Driver action requests captured: "..tostring(#(data.events or {})))
            if imgui.tree_node("Candidate native methods (read-only)") then
                for _,name in ipairs(data.methods or {}) do imgui.text(name) end
                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end
    if imgui.tree_node("Oxcart distance") then
    local distance_changed, distance_value = imgui.checkbox("Monitor player / cart body distance", distance_enabled)
    if distance_changed then
        distance_enabled, next_sample, next_body_lookup, distance_body = distance_value, 0, 0, nil
        if not distance_enabled then distance_status = "Distance monitor OFF" end
    end
    imgui.text(distance_status)
    imgui.text("Front: toward the ox (stationary OK). Z forward / Y up / X sideways.")
    imgui.text("Default forward offset 1.5 is adjustable, not a measured body boundary.")
    for _,key in ipairs({"x","y","z"}) do
        local changed,value=imgui.slider_float("Front point "..key,front_offset[key],-10,10)
        if changed and value==value then
            front_offset[key]=math.max(-10,math.min(10,value))
            read(function() json.dump_file("OxcartFrontProbe.json",front_offset) end)
        end
    end
    imgui.tree_pop()
    end
    if imgui.tree_node("Escort NPC membership (read-only)") then
        local changed,value=imgui.input_text("Escort NPC Character ID",escort.id_text)
        if changed then escort.id_text=value end
        if imgui.button("Apply escort NPC ID") then
            local id=parse_id(escort.id_text)
            if id then
                escort.id=id;escort.history={};escort.signature=nil
                escort.status="Target changed; enable monitor to sample";next_sample=0
            else escort.status="Invalid Character ID" end
        end
        local changed,value=imgui.checkbox("Monitor escort membership (read-only)",escort.enabled)
        if changed then
            escort.enabled=value;next_sample=0
            if not value then escort.status="Monitor OFF" end
        end
        imgui.text("Default test target: Ulrika (ch310073). No LMD/Emote Dogma dependency.")
        imgui.text("True = accompanying player party; false = not accompanying; UNAVAILABLE = read failed.")
        imgui.text(escort.status)
        for i=#escort.history,1,-1 do imgui.text(escort.history[i]) end
        if imgui.button("Clear escort membership history") then escort.history={};escort.signature=nil end
        imgui.tree_pop()
    end
    if imgui.tree_node("NPC animation") then
    local changed, text = imgui.input_text("NPC Character ID", id_text)
    if changed then id_text = text end
    if imgui.button("Apply NPC ID") then apply_id() end
    local toggle, value = imgui.checkbox("Monitor NPC (read-only)", enabled)
    if toggle then enabled = value end
    imgui.text("Target Character ID: " .. tostring(target_id))
    imgui.text(snapshot.status)
    if snapshot.object_name then imgui.text("GameObject: " .. snapshot.object_name) end
    imgui.text("High-level current actions (FSM; e.g. SitOnChairActions):")
    imgui.text("A request name is not always retained as the current action.")
    if #snapshot.actions == 0 then imgui.text("No readable current action") end
    for _, item in ipairs(snapshot.actions) do imgui.text("Layer " .. item.layer .. ": " .. item.name) end
    imgui.text("Playing motion names (resolved from this NPC's loaded banks):")
    if snapshot.motion_source then imgui.text(snapshot.motion_source) end
    if snapshot.motion_type then imgui.text("Motion object type: " .. snapshot.motion_type) end
    if imgui.button("Refresh motion names") then clear_names(); next_sample = 0 end
    if #snapshot.motions == 0 then imgui.text("No readable current motion") end
    for _, item in ipairs(snapshot.motions) do
        imgui.text("Layer " .. item.layer .. ": " .. (item.name or item.name_status or "Name unavailable"))
        if usable_id(item.id) then
            imgui.text("  Bank " .. tostring(item.bank) .. " / Motion " .. tostring(item.id))
        end
        if item.metadata_error then imgui.text("  Read error: " .. item.metadata_error:sub(1, 400)) end
    end
    if imgui.tree_node("Recent changes (last 12)") then
        for i = #history, 1, -1 do imgui.text(history[i]) end
        if imgui.button("Clear change history") then history = {} end
        imgui.tree_pop()
    end
    imgui.tree_pop()
    end
    imgui.tree_pop()
end)
re.on_script_reset(function()
    height_record(false);height.enabled=false
    escort.enabled=false;escort.history={};escort.signature=nil
    local bridge=rawget(_G,"LMD_DriverDebug")
    if bridge and bridge.combat_cleanup then bridge.combat_cleanup() end
    actor = nil; distance_body = nil; _G.AelinoreDriverDebugEnabled=nil; clear_names()
end)
