;(function()
local previous_gm=ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']
local previous_singleton,previous_type=sdk.get_managed_singleton,sdk.find_type_definition
local previous_dump=json.dump_file
-- Isolate earlier seat/drive tests from the automatic pawn staging integration.
local real_stage,real_pawn_command=driver_debug_bridge.native_pawns_stage,driver_debug_bridge.native_pawns_command
driver_debug_bridge.native_pawns_stage=function() return {} end
driver_debug_bridge.native_pawns_command=function() return true end
local interacting,active=false,nil
local requests,exits,refs=0,0,0
local expected_exit_actor=human
local seat={}
local driver_mapping_available,driver_points_enabled=true,true
local left_enabled=false
local data={mask=8,get_field=function(self,key) return key=='CharacterType' and self.mask or 'driver_joint' end,
    set_field=function(self,key,value) assert(key=='CharacterType');self.mask=value end}
local io=object('native_io')
function io:call(method,point,ch)
    if method=='get_IsRegistered()' or method=='get_IsUpdatedAfterRegisterd()' then return true end
    if method=='getNumInteractPoint()' then return 6 end
    if method=='isInteractEnable(System.UInt32, app.Character)' then return point==1 and data.mask==9 end
    assert(method=='endInteractForSystem(System.UInt32, app.Character)' and point==1 and ch==expected_exit_actor,method)
    exits=exits+1
end
local result={value=0,get_field=function(self) return self.value end,
    add_ref=function() refs=refs+1 end,release=function() refs=refs-1 end}
local mgr={call=function(_,method,a,point,ch)
    if method=='isInteracting(app.Character)' then return interacting end
    if method=='getActiveInteract(app.Character)' then return active end
    assert(method=='requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)'
        and a==io and point==1 and ch==human,method)
    requests=requests+1;return result
end}
local gm=object('native_cart')
gm.InteractiveObject=io
gm.NonDriverSeatNoList={call=function(_,method) return method=='get_Count()' and 1 or 1 end}
gm.InteractiveObjectDataList={get_element=function(_,i) return i==1 and data or
    {get_field=function(_,key) return key=='CharacterType' and 1 or 'other_joint' end} end}
function gm:get_type_definition() return {get_method=function() return {get_num_params=function() return 0 end} end} end
function gm:call(method,i)
    if method=='get_DrivingSeat' then return seat end
    if method=='getSeatNo(System.UInt32)' then return i-2 end
    if method=='IsDriver(System.UInt32)' then
        if not driver_mapping_available then error('IsDriver unavailable') end
        return i<2
    end
    if method=='isInteractEnable(System.UInt32)' then return (i~=0 or left_enabled) and (i>=2 or driver_points_enabled) end
    if method=='getInteractChara(System.UInt32)' then return nil end
    error(method)
end
sdk.get_managed_singleton=function(name) return name=='app.InteractManager' and mgr or previous_singleton(name) end
sdk.find_type_definition=function(name)
    if name=='app.InteractManager.InteractRequestResultType' then
        return {get_field=function() return {get_data=function() return 1 end} end}
    end
    return previous_type(name)
end
json.dump_file=function() end
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=gm
state.active=false;is_paused=false
local position,warps,falls,fsm=human.pos,human.test_controller.warps,human.test_fall.reset_calls,human.machine.enabled
local function command(value)
    assert(driver_debug_bridge.native_seat_command(value));clock=clock+0.2;driver_debug_bridge.native_seat_tick()
end
command('scan')
assert(#driver_debug_bridge.native_seat_read().rows==6 and requests==0 and data.mask==8,driver_debug_bridge.native_seat_read().status)
local rows=driver_debug_bridge.native_seat_read().rows
assert(rows[1].native_is_driver and not rows[1].driver_candidate and rows[2].driver_candidate
    and rows[2].seat_no==-1 and not rows[3].driver_candidate,'Native negative-seat driver mapping failed')
left_enabled=true;command('scan')
rows=driver_debug_bridge.native_seat_read().rows
assert(rows[1].driver_candidate and rows[2].driver_candidate and driver_debug_bridge.native_seat_read().status:find('point 0',1,true),
    'Two native driver entrances were treated as ambiguous')
left_enabled=false
driver_mapping_available=false;command('enter')
assert(requests==0 and data.mask==8 and not driver_debug_bridge.native_seat_busy(),'Unreadable mapping guessed point')
driver_mapping_available=true;driver_points_enabled=false;command('enter')
assert(requests==0 and data.mask==8 and not driver_debug_bridge.native_seat_busy(),'No driver entrance used passenger fallback')
driver_points_enabled=true
seat.SitChara=driver;command('enter')
assert(requests==0 and not driver_debug_bridge.native_seat_busy(),'Occupied seat accepted')
seat.SitChara=nil;command('enter')
assert(requests==1 and data.mask==9 and refs==1,'Driver Player bit/request missing')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Denied request leaked mask/lease')
result.value=0;command('enter')
interacting=true;active={Point={Object=io,PointNo=1}};seat.SitChara=human
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(driver_debug_bridge.native_seat_read().status:find('CONFIRMED',1,true),'Native binding not confirmed')
assert(state.native_drive and not state.active and #state.seats==0 and bus.owner==TITLE,
    'Native driving reused legacy seat ownership')
local function drive(keys)
    input={keyboard=0,stick=0}
    for k,v in pairs(keys or {}) do input[k]=v end
    driver_debug_bridge.native_drive_tick(0.1)
end
for i=1,6 do drive({up=true}) end
assert(state.native_drive.drive.level==4 and ox.am.CurrentActionList[0].Name=='Dash','Native acceleration/clamp failed')
for i=1,6 do drive({down=true}) end
assert(state.native_drive.drive.level==1 and ox.am.CurrentActionList[0].Name=='Wait','Native deceleration/clamp failed')
drive({keyboard=1})
assert(cow['set_TargetFrontAngleDeg(System.Single)']~=heading
    and cow['set_TargetMoveAngleDeg(System.Single)']==cow['set_TargetFrontAngleDeg(System.Single)'],
    'Native steering did not control cow angles')
local angle=cow['set_TargetFrontAngleDeg(System.Single)']
is_paused=true;input={up=true,keyboard=-1,stick=0};callbacks.LateUpdateBehavior()
assert(state.native_drive.drive.level==1 and cow['set_TargetFrontAngleDeg(System.Single)']==angle,'Paused driving moved cow')
is_paused=false;input={up=true,keyboard=0,stick=0};clock=clock+0.2;callbacks.LateUpdateBehavior()
assert(state.native_drive.drive.level==2 and not state.active and #state.seats==0,'Native input fell through legacy constraints')
drive({stand=true})
assert(exits==0 and state.native_drive,'Native A exit was intercepted')
assert(not pcall(acquire),'Manual acquisition overlaps native ownership')
active.Point.PointNo=2;command('exit');assert(exits==0,'Exited unrelated passenger interaction')
active.Point.PointNo=1;command('exit');assert(exits==1 and data.mask==9,'Mask restored before engine exit')
interacting=false;seat.SitChara=nil;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Exit cleanup failed')
command('enter');clock=clock+16;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Timeout cleanup failed')
command('enter');interacting=true;active={Point={Object=io,PointNo=1}};seat.SitChara=human
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
local exit_count=exits
seat.SitChara=nil;drive()
assert(not state.native_drive and exits==exit_count and data.mask==9 and ox.am.CurrentActionList[0].Name=='Wait',
    'Native departure inserted an exit command or restored mask prematurely')
interacting=false;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and refs==0 and bus.owner==nil and not driver_debug_bridge.native_seat_busy(),'Natural exit leaked driving lease')
local driver_position,driver_warps=driver.pos,driver.test_controller.warps
local driver_falls,driver_fsm=driver.test_fall.reset_calls,driver.machine.enabled
seat.Status=2;seat.SitChara=driver;interacting=true;active={Point={Object=io,PointNo=2}}
command('npc_exit')
assert(exits==exit_count and data.mask==8,'NPC wrong-point exit was called')
active.Point.PointNo=1;expected_exit_actor=driver
is_paused=true;assert(driver_debug_bridge.native_seat_command('npc_exit'))
driver_debug_bridge.native_seat_tick();assert(exits==exit_count,'Paused NPC exit executed')
is_paused=false;driver_debug_bridge.native_seat_tick()
assert(exits==exit_count+1 and data.mask==8 and not state.native_drive,'NPC system exit not isolated')
seat.SitChara=nil;seat.Status=0;interacting=false
for i=1,81 do clock=clock+0.25;driver_debug_bridge.native_seat_tick() end
assert(exits==exit_count+1 and not driver_debug_bridge.native_seat_busy()
    and #driver_debug_bridge.native_seat_read().npc.samples>=80,'NPC observation repeated exit or never finished')
assert(driver.pos==driver_position and driver.test_controller.warps==driver_warps
    and driver.test_fall.reset_calls==driver_falls and driver.machine.enabled==driver_fsm,
    'NPC test added teleport/FSM/fall operations')
local old_io_call,old_mgr_call,old_gm_call=io.call,mgr.call,gm.call
local old_array=gm.InteractiveObjectDataList
driver_debug_bridge.native_pawns_stage,driver_debug_bridge.native_pawns_command=real_stage,real_pawn_command
local occupied,pawn_active,pawn_data={},{},{}
local pawn_requests=0
local pawn_exits=0
local not_sitting={}
gm.InteractSeatList={get_type_definition=function() return {get_method=function() return {get_num_params=function() return 0 end} end} end,
    call=function(_,method,index)
        if method=='get_Count' then return 4 end
        local actor=occupied[index+2]
        return {TargetChara=actor,State=3,
            get_type_definition=function() return {get_method=function() return {get_num_params=function() return 0 end} end} end,
            call=function(_,name) if name=='get_IsSitState' then return actor~=nil and not not_sitting[actor] end end}
    end}
for point=0,5 do
    pawn_data[point]={mask=point==2 and 1 or 10,
        get_field=function(self) return self.mask end,set_field=function(self,_,value) self.mask=value end}
end
gm.InteractiveObjectDataList={get_element=function(_,point) return pawn_data[point] end}
function gm:call(method,point)
    if method=='getInteractChara(System.UInt32)' then return occupied[point] end
    return old_gm_call(self,method,point)
end
function io:call(method,point,ch)
    if method=='isInteractEnable(System.UInt32, app.Character)' then return point>=2 end
    if method=='endInteractForSystem(System.UInt32, app.Character)' and point>=2 then
        pawn_exits=pawn_exits+1;occupied[point]=nil;pawn_active[ch]=nil;return
    end
    return old_io_call(self,method,point,ch)
end
function mgr:call(method,ch,point,actor)
    if method=='isInteracting(app.Character)' then return pawn_active[ch]~=nil end
    if method=='getActiveInteract(app.Character)' then return pawn_active[ch] end
    assert(method=='requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)' and ch==io
        and ((actor==pawns[1] and point==2) or (actor~=pawns[1] and point>=3)) and not occupied[point],
        'Pawn point allocation or occupancy mismatch')
    occupied[point]=actor;pawn_active[actor]={Point={Object=io,PointNo=point}};pawn_requests=pawn_requests+1
    return {get_field=function() return 0 end,add_ref=function() refs=refs+1 end,release=function() refs=refs-1 end}
end
local pawn_before={}
for i,ch in ipairs(pawns) do pawn_before[i]={pos=ch.pos,warps=ch.test_controller.warps,fall=ch.test_fall.reset_calls,fsm=ch.machine.enabled} end
assert(driver_debug_bridge.native_pawns_command());driver_debug_bridge.native_pawns_tick()
local pawn_view=driver_debug_bridge.native_pawns_read()
assert(pawn_requests==3 and #pawn_view.rows==3 and pawn_data[2].mask==3,'Main pawn Point 2 permission missing')
local expected_pawn_points={2,3,4}
for i,row in ipairs(pawn_view.rows) do
    assert(row.point==expected_pawn_points[i] and row.status:find('CONFIRMED',1,true),'Seat-swap probe used wrong seat')
    assert(row.role==(i==1 and 'main' or 'hired'),'Pawn role missing in allocation LOG')
end
assert(driver_debug_bridge.native_pawns_command(true));driver_debug_bridge.native_pawns_tick()
assert(pawn_requests==3 and pawn_exits==0,'Repeat request disturbed seated pawns')
occupied,pawn_active={},{};clock=clock+0.3;driver_debug_bridge.native_pawns_tick()
assert(refs==0 and pawn_data[2].mask==1 and pawn_requests==3,'Pawn release cleanup failed')
-- Reproduce the user's reload case: two hired pawns already occupy points
-- 3/4. The main pawn must select 5, never the empty Player-only point 2.
occupied[3],occupied[4]=pawns[2],pawns[3]
pawn_active[pawns[2]]={Point={Object=io,PointNo=3}}
pawn_active[pawns[3]]={Point={Object=io,PointNo=4}}
assert(driver_debug_bridge.native_pawns_command());driver_debug_bridge.native_pawns_tick()
pawn_view=driver_debug_bridge.native_pawns_read()
assert(pawn_view.rows[1].point==2 and pawn_requests==4 and pawn_data[2].mask==3
    and pawn_view.rows[2].point==3 and pawn_view.rows[3].point==4,'Existing passengers starved main pawn or used player-only seat')
occupied,pawn_active={},{};clock=clock+0.3;driver_debug_bridge.native_pawns_tick()
assert(refs==0,'Retry leaked result references')
-- One-shot true relocation, then automatic native passenger requests.
local staged_before={}
for i,ch in ipairs(pawns) do staged_before[i]={warps=ch.test_controller.warps,fall=ch.test_fall.reset_calls,fsm=ch.machine.enabled} end
local drive_q={cart={ox=ox,cow=cow,body=body},ch=human}
driver_debug_bridge.native_drive_begin(drive_q)
driver_debug_bridge.native_pawns_tick()
for i,ch in ipairs(pawns) do
    assert(ch.test_controller.warps==staged_before[i].warps+1
        and ch.test_fall.reset_calls==staged_before[i].fall+1 and ch.machine.enabled==staged_before[i].fsm,
        'Native takeover staging missing physics sync or modified FSM')
end
local stage_rows=driver_debug_bridge.native_seat_read().staging
assert(#stage_rows==3 and stage_rows[1].target and stage_rows[3].target,'Staging evidence missing')
assert(pawn_requests==7,'Native driver takeover did not automatically request three passenger seats')
-- A failed/not-yet-sitting pawn may be retried without disturbing the two
-- truly seated pawns. Native exit and teleport each happen exactly once.
local main_retry_warps=pawns[1].test_controller.warps
local hired_retry_warps=pawns[2].test_controller.warps
not_sitting[pawns[1]]=true
assert(driver_debug_bridge.native_pawns_command(true));driver_debug_bridge.native_pawns_tick()
assert(pawn_requests==8 and pawn_exits==1 and pawns[1].test_controller.warps==main_retry_warps+1
    and pawns[2].test_controller.warps==hired_retry_warps,'Failed pawn retry disturbed seated pawns or never re-requested')
not_sitting[pawns[1]]=nil
clock=clock+0.3;driver_debug_bridge.native_pawns_tick()
for i,ch in ipairs(pawns) do assert(ch.test_controller.warps==staged_before[i].warps+(i==1 and 2 or 1),'Staging repeated during boarding') end
local stable_warps=pawns[1].test_controller.warps
real_stage(drive_q.cart)
assert(pawns[1].test_controller.warps==stable_warps,'Already-interacting pawn was teleported')
driver_debug_bridge.native_drive_end(drive_q)
local distance_position=human.pos
local dx,dz=cart_forward(drive_q.cart)
human.pos=vec(body.pos.x+dx*(front_offset.z+11),body.pos.y,body.pos.z+dz*(front_offset.z+11))
clock=clock+0.3;driver_debug_bridge.native_pawns_tick()
assert(pawn_exits==4 and pawn_data[2].mask==1 and refs==0,'Front-distance auto exit or main mask restore failed')
clock=clock+0.3;driver_debug_bridge.native_pawns_tick()
assert(pawn_exits==4,'Distance exit repeated every frame')
human.pos=distance_position
assert(driver_debug_bridge.native_pawns_command(true));driver_debug_bridge.native_pawns_tick()
assert(pawn_requests==11,'Boarding could not be repeated after distance exit')
driver_debug_bridge.native_pawns_exit();driver_debug_bridge.native_pawns_tick()
assert(pawn_exits==7 and refs==0 and pawn_data[2].mask==1,'Manual native pawn exit failed')
occupied,pawn_active={},{};clock=clock+0.3;driver_debug_bridge.native_pawns_tick()
-- Reset the read-only baseline after the intentional one-shot relocations.
for i,ch in ipairs(pawns) do pawn_before[i]={pos=ch.pos,warps=ch.test_controller.warps,fall=ch.test_fall.reset_calls,fsm=ch.machine.enabled} end
-- The boarding tracer must observe only the main pawn and preserve hook calls.
local function trace_seat(actor)
    return {TargetChara=actor,State=2,
        get_type_definition=function() return {get_method=function() return {get_num_params=function() return 0 end} end} end,
        call=function(_,method) if method=='get_IsSitState' then return true end end}
end
local trace_seats={trace_seat(pawns[1]),trace_seat(pawns[2])}
gm.InteractSeatList={get_type_definition=function() return {get_method=function() return {get_num_params=function() return 0 end} end} end,
    call=function(_,method,index) if method=='get_Count' then return 2 else return trace_seats[index+1] end end}
local saved_dump=json.dump_file
local trace_payload,trace_saves,trace_paths=nil,0,{}
json.dump_file=function(path,value) trace_payload=value;trace_saves=trace_saves+1;trace_paths[#trace_paths+1]=path end
driver_debug_bridge.pawn_trace_control(true);driver_debug_bridge.pawn_trace_tick()
assert(driver_debug_bridge.pawn_trace_read().active and trace_saves==1,'Main pawn trace did not start/save')
local request_hook=hooks['requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)']
assert(request_hook({nil,mgr,io,5,pawns[1]})==nil,'Trace hook changed native execution')
request_hook({nil,mgr,io,3,pawns[2]})
driver_debug_bridge.pawn_trace_action(pawns[1].am,'SitOnChairActions',0,1)
driver_debug_bridge.pawn_trace_action(pawns[2].am,'OtherPawnAction',0,1)
clock=clock+5.1;driver_debug_bridge.pawn_trace_tick()
assert(trace_saves==2 and #trace_payload.samples[1].pawns==1
    and trace_payload.samples[1].pawns[1].actor==address(pawns[1]),'Trace recorded hired pawns')
assert(#trace_payload.samples[1].seats==1 and trace_payload.samples[1].seats[1].is_sitting==true,
    'Trace missed native sitting state or recorded hired pawn seat')
local request_events,action_events=0,0
for _,event in ipairs(trace_payload.events) do
    if event.name=='requestInteractFromAI' then request_events=request_events+1;assert(event.detail.pawn==1) end
    if event.name=='action_request' then action_events=action_events+1;assert(event.detail.node=='SitOnChairActions') end
end
assert(request_events==1 and action_events==1 and pawn_requests==11,'Trace recorded other actors or mutated native requests')
driver_debug_bridge.pawn_trace_control(false);driver_debug_bridge.pawn_trace_tick()
assert(not driver_debug_bridge.pawn_trace_read().active and trace_payload.reason=='stopped','Trace stop not flushed')
local first_path=trace_paths[#trace_paths]
driver_debug_bridge.pawn_trace_control(true);driver_debug_bridge.pawn_trace_tick()
assert(trace_paths[#trace_paths]~=first_path,'Separate traces overwrite earlier file')
driver_debug_bridge.pawn_trace_close()
assert(trace_payload.reason=='reset','Trace reset failed to save')
json.dump_file=saved_dump
gm.InteractSeatList=nil
print('PASS: main-pawn-only boarding trace, read-only hooks, sampling, five-second checkpoint, unique runs and stop/reset save')
for i,ch in ipairs(pawns) do local before=pawn_before[i]
    assert(ch.pos==before.pos and ch.test_controller.warps==before.warps and ch.test_fall.reset_calls==before.fall
        and ch.machine.enabled==before.fsm,'Native pawn seating forced actor state')
end
io.call,mgr.call,gm.call=old_io_call,old_mgr_call,old_gm_call
gm.InteractiveObjectDataList=old_array
-- Occupied native driver entry performs one NPC system exit, waits for actual
-- release, then submits the player request. It never teleports the NPC.
driver_debug_bridge.native_pawns_close()
local base_mgr_call=mgr.call
local npc_still_interacting=true
function mgr:call(method,a,point,ch)
    if a==driver and method=='isInteracting(app.Character)' then return npc_still_interacting end
    if a==driver and method=='getActiveInteract(app.Character)' then return {Point={Object=io,PointNo=1}} end
    return base_mgr_call(self,method,a,point,ch)
end
expected_exit_actor=driver;seat.SitChara=driver;result.value=0
local exits_before,requests_before=exits,requests
command('enter')
assert(exits==exits_before+1 and requests==requests_before and driver_debug_bridge.native_seat_busy(),
    'Occupied driver seat did not chain a one-shot NPC exit')
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(exits==exits_before+1 and requests==requests_before,'NPC exit repeated while waiting')
npc_still_interacting=false;seat.SitChara=nil
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(requests==requests_before+1,'Player entry not submitted after NPC exit')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(refs==0 and not driver_debug_bridge.native_seat_busy(),'Chained entry cleanup leaked')
mgr.call=base_mgr_call;expected_exit_actor=human
assert(human.pos==position and human.test_controller.warps==warps and human.test_fall.reset_calls==falls
    and human.machine.enabled==fsm,'Native entry wrote forced player state')
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=previous_gm
sdk.get_managed_singleton,sdk.find_type_definition=previous_singleton,previous_type
json.dump_file=previous_dump
print('PASS: driver exit/entry chain, main Pawn Point 2, repeat missing-pawn boarding, seated skips, manual/distance exits and native driving')
end)()
