-- Low-impact v2.1: no SDK hooks, no observer, no writes during recording.
local TITLE = "Let me drive oxcart Position Diagnostics"
local r = {active=false,label="teleport",pawns=false,samples={},events={},errors={},files={},sequence=0}
local function safe(key, fn)
    local ok,value=pcall(fn)
    if ok then return value end
    r.errors[key]=tostring(value):sub(1,160)
end
local function field(o,k) return o and safe(k,function() return o[k] end) end
local function get(o,k)
    if not o then return nil end
    return safe(k,function()
        local fn=o[k]
        if type(fn)=="function" then return fn(o) end
        return o:call(k.."()")
    end)
end
local function vec(v)
    if not v then return nil end
    local x,y,z=tonumber(field(v,"x")),tonumber(field(v,"y")),tonumber(field(v,"z"))
    if x and y and z and x==x and y==y and z==z and math.abs(x)+math.abs(y)+math.abs(z)<math.huge then
        return {x=x,y=y,z=z}
    end
end
local function id(o) return o and safe("address",function() return tostring(o:get_address()) end) end
local function scalar(v) local t=type(v);if t=="boolean" or t=="string" or t=="number" then return v end end
local function fields(o,keys)
    local out={};for _,k in ipairs(keys) do out[k]=scalar(field(o,k)) end;return out
end
local function root(t)
    return {scene=vec(get(t,"get_Position")),universal=vec(get(t,"get_UniversalPosition"))}
end
local function object_info(o)
    if not o then return nil end
    return {address=id(o),name=scalar(get(o,"get_Name")),valid=scalar(get(o,"get_Valid"))}
end
local function ground_data(info)
    if not info then return nil end
    return {valid=scalar(field(info,"<IsValid>k__BackingField")),
        position_raw=vec(field(info,"Position")),normal=vec(field(info,"Normal")),
        object=object_info(field(info,"GameObject"))}
end
local function bones(t)
    local key=id(t)
    if not key then return {} end
    local cached=r.joints[key]
    if not cached or os.clock()>=cached.retry then
        local list=get(t,"get_Joints")
        local elements=list and safe("joint_array",function()
            if type(list.get_elements)=="function" then return list:get_elements() end
            if type(list)=="table" then return list end
        end)
        local selected={}
        if type(elements)=="table" then
            for _,joint in pairs(elements) do
                local parent=get(joint,"get_Parent")
                if get(joint,"get_Valid")==true and get(parent,"get_Valid")~=true and #selected<4 then selected[#selected+1]=joint end
            end
        end
        cached={items=selected,retry=os.clock()+(#selected==0 and 2 or 10)};r.joints[key]=cached
    end
    local out={}
    for _,j in ipairs(cached.items) do
        out[#out+1]={name=get(j,"get_Name"),world=vec(get(j,"get_Position")),local_position=vec(get(j,"get_LocalPosition"))}
    end
    if #out==0 then r.errors.joints="No root joints observed; empty cache retries every 2 seconds"
    else r.errors.joints=nil end
    return out
end
local function actor(o,name)
    if not o then return {name=name,missing=true} end
    local t=get(o,"get_Transform")
    local context=field(o,"<PosRotContext>k__BackingField")
    local human=field(o,"<Human>k__BackingField")
    local restorer=field(human,"<CoordRestorerOnOxcart>k__BackingField")
    local terrain=field(o,"<AdjustTerrain>k__BackingField")
    local controller=field(terrain,"MainCharacterController")
    local oncart=field(restorer,"Context")
    local landing=field(o,"<LandingProcessor>k__BackingField")
    local stuck=field(landing,"FallingStuckStopper")
    local fall=field(o,"<FallInfo>k__BackingField")
    local safety=field(o,"<FallPreventerPosRecorder>k__BackingField")
    local prevent=field(o,"<FallPreventer>k__BackingField")
    local floor=get(controller,"get_FloorGameObject")
    return {name=name,address=id(o),root=root(t),joints=bones(t),
        landing_available=landing~=nil,stuck_available=stuck~=nil,fall_available=fall~=nil,safety_available=safety~=nil,
        character_ground=scalar(get(o,"get_IsGround")),
        contacts={ground=scalar(get(controller,"get_Ground")),wall=scalar(get(controller,"get_Wall")),
            ceiling=scalar(get(controller,"get_Ceiling")),jump=scalar(get(controller,"get_Jump")),
            ground_count=scalar(get(controller,"get_NumGroundContactPoints")),wall_count=scalar(get(controller,"get_NumWallContactPoints")),
            ceiling_count=scalar(get(controller,"get_NumCeilingContactPoints")),
            floor=object_info(floor),local_offset=vec(get(controller,"get_LocalOffsetPosition")),
            height=scalar(get(controller,"get_Height")),radius=scalar(get(controller,"get_Radius"))},
        landing=fields(landing,{"<IsKeepGround>k__BackingField","<IsPrevKeepGround>k__BackingField",
            "<IsObjectGround>k__BackingField","<IsLandOnIKPass>k__BackingField","<IsOverSlopeLimitOnNormalMove>k__BackingField"}),
        last_ground_raw=vec(field(landing,"<LastGroundPosition>k__BackingField")),
        last_terrain_ground=ground_data(field(landing,"LastTerrainGroundInfo")),
        cached_ground_position_raw=vec(field(landing,"PositionOfCachedDetectGroundResult")),
        stuck=fields(stuck,{"<IsStopperActive>k__BackingField","TimerStuck","FrameDetectStuck","DistanceStopperActive"}),
        stuck_base_raw=vec(field(stuck,"BasePosition")),
        fall=fields(fall,{"<FallHeight>k__BackingField","<FallHeightOnLanding>k__BackingField",
            "<HeightCheckDamageFromFall>k__BackingField","BaseFallHeight"}),
        highest_air_raw=vec(field(fall,"<HighestPositionOnAir>k__BackingField")),
        base_fall_position_raw=vec(field(fall,"BaseFallHeight")),
        safety=fields(safety,{"IsUnsafe"}),safe_position_raw=vec(field(safety,"<Pos>k__BackingField")),
        fall_prevention=fields(prevent,{"<DistanceToCliffOnPreventFall>k__BackingField","<HeightPreventFall>k__BackingField"}),
        context_position_raw=vec(field(context,"Position")),context=fields(context,{"IsWarp","AngleYDegree"}),
        root_apply_raw=vec(field(o,"PositionOnRootApplyForMeter")),
        after_follow_raw=vec(field(o,"PositionAfterFollowObject")),begin_late_raw=vec(field(o,"PositionBeginLateUpdate")),
        controller_scene=vec(get(controller,"get_Position")),controller_original_raw=vec(get(controller,"get_OriginalPosition")),
        terrain=fields(terrain,{"IsJump","IsMainAdjust","IsSubAdjust","<RequestOverwritePosition>k__BackingField","<AdjustYDisableOverwritePosition>k__BackingField"}),
        terrain_before_raw=vec(field(terrain,"<PositionBeforeSubAdjust>k__BackingField")),
        restorer=fields(restorer,{"IsRestoring","IsStore","CountSinceTeleported","CountSinceGenerated","SecTimerOxcartNotFound","CountToRestore"}),
        restorer_previous_raw=vec(field(restorer,"<PrevPosition>k__BackingField")),
        oncart=fields(oncart,{"HasInfo","IsInside"}),oncart_local=vec(field(oncart,"LocalPos"))}
end
local function read()
    local probe=rawget(_G,"LMD_PositionProbe")
    return probe and safe("probe",probe.read)
end
local function sample()
    local p=read()
    if not p then r.errors.probe="Reload updated controller and recorder";return end
    if p.cart then r.cart=p.cart end
    local cart=r.cart
    local actors={actor(p.player,"player")}
    if r.pawns then
        for i,o in ipairs(p.party or {}) do
            if id(o)~=id(p.player) then actors[#actors+1]=actor(o,"pawn"..i) end
        end
    end
    local slots={}
    local layout=(p.presets or {})[p.preset] or {}
    for i,s in ipairs(layout.slots or {}) do slots[i]=fields(s,{"x","y","z","yaw","useOxAnchor"}) end
    local camera=safe("camera",function() return sdk.get_primary_camera() end)
    local camera_transform=get(camera,"get_Transform") or get(get(camera,"get_GameObject"),"get_Transform")
    return {t=os.clock()-r.started,active=p.active,paused=p.paused,level=p.level,
        position_sync=p.position_sync,position_sync_status=p.position_sync_status,message=p.message,error=p.error,
        reset_fall=p.reset_fall,fall_reset_status=p.fall_reset_status,
        pose_lock=p.pose_lock,blocked_actions=p.blocked_actions,last_blocked_action=p.last_blocked_action,
        pawn_blocked_actions=p.pawn_blocked_actions,pawn_last_blocked_action=p.pawn_last_blocked_action,
        visual_enabled=p.visual_enabled,freeze_player=p.freeze_player,root_offset=vec(p.root_offset),slots=slots,
        cart=cart and {body=root(cart.body),anchor=root(cart.anchor)},
        camera=root(camera_transform),actors=actors}
end
local function export()
    if #r.samples==0 then return end
    local data={meta={schema=2,recorder_version="2.1-contact-landing",label=r.label,rate_hz=2,player_only=not r.pawns,
        phase="post UpdateJointExpression",native_hooks=false,export_during_recording=false,
        coordinate_notes="Scene/universal roots are labelled; *_raw fields have unconfirmed coordinate space. Joint world is scene space.",
        errors=r.errors},samples=r.samples,events=r.events}
    local ok,err=pcall(function()
        assert(json.dump_file(r.path,data)~=false,"dump_file returned false")
    end)
    if ok then r.files[#r.files+1]=r.path;r.pending=false;r.status="Saved: "..r.path
    else r.pending=true;r.status="Export failed; data retained. Retry export: "..tostring(err) end
end
local function stop(reason)
    if not r.active then return end
    r.active=false;r.pending=true;r.events[#r.events+1]={t=os.clock()-r.started,label=reason or "stop"}
end
re.on_application_entry("UpdateJointExpression",function()
    if not r.active or os.clock()<r.next then return end
    r.next=os.clock()+0.5
    local s=safe("sample",sample);if s then r.samples[#r.samples+1]=s end
    if #r.samples>=1200 or os.clock()-r.started>=600 then stop("10 minute limit") end
end)
re.on_frame(function()
    if r.start_pending then
        r.start_pending=false;r.sequence=r.sequence+1;r.started=os.clock();r.next=r.started
        r.samples={};r.events={};r.errors={};r.joints={};r.cart=nil
        r.path="LMD_PositionTrace_"..os.date("%Y%m%d_%H%M%S").."_"..tostring(math.floor(os.clock()*1000)).."_"..r.sequence..".json"
        r.active=true;r.status="Recording in memory (2 Hz); no automatic disk writes"
    end
    if r.stop_pending then r.stop_pending=false;stop() end
    if r.pending and not r.active and not r.export_attempted then r.export_attempted=true;export() end
end)
re.on_draw_ui(function()
    if not imgui.tree_node(TITLE) then return end
    imgui.text("Lightweight v2.1 | contacts / landing / stuck | 2 Hz | saves only after Stop")
    local c,v=imgui.input_text("Scene label",r.label);if c and not r.active and not r.pending then r.label=v end
    c,v=imgui.checkbox("Record pawns (height issue)",r.pawns);if c and not r.active and not r.pending then r.pawns=v end
    if not r.active and not r.pending and imgui.button("Start recording") then r.start_pending=true;r.export_attempted=false end
    if r.active and imgui.button("Stop and export") then r.stop_pending=true end
    if r.active and imgui.button("Mark event") then r.events[#r.events+1]={t=os.clock()-r.started,label=r.label} end
    if r.pending and not r.active and imgui.button("Retry export") then r.export_attempted=false end
    imgui.text("Samples: "..#r.samples.." / 1200")
    if r.status then imgui.text(r.status) end
    imgui.tree_pop()
end)
re.on_script_reset(function() stop("script reset");if r.pending then export() end end)
