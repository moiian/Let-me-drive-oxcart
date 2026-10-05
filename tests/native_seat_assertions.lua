;(function()
local previous_gm=ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']
local previous_singleton,previous_type=sdk.get_managed_singleton,sdk.find_type_definition
local previous_dump=json.dump_file
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
local occupied,pawn_active,pawn_data={},{},{}
local pawn_requests=0
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
    return old_io_call(self,method,point,ch)
end
function mgr:call(method,ch,point,actor)
    if method=='isInteracting(app.Character)' then return pawn_active[ch]~=nil end
    if method=='getActiveInteract(app.Character)' then return pawn_active[ch] end
    assert(method=='requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)' and ch==io
        and point>=3 and not occupied[point],'Pawn used player-only point or collided')
    occupied[point]=actor;pawn_active[actor]={Point={Object=io,PointNo=point}};pawn_requests=pawn_requests+1
    return {get_field=function() return 0 end,add_ref=function() refs=refs+1 end,release=function() refs=refs-1 end}
end
local pawn_before={}
for i,ch in ipairs(pawns) do pawn_before[i]={pos=ch.pos,warps=ch.test_controller.warps,fall=ch.test_fall.reset_calls,fsm=ch.machine.enabled} end
assert(driver_debug_bridge.native_pawns_command());driver_debug_bridge.native_pawns_tick()
local pawn_view=driver_debug_bridge.native_pawns_read()
assert(pawn_requests==3 and #pawn_view.rows==3 and pawn_data[2].mask==1,'Native pawn allocation changed player-only mask')
for i,row in ipairs(pawn_view.rows) do
    assert(row.point==i+2 and row.status:find('CONFIRMED',1,true),'Pawn binding used wrong seat')
end
assert(not driver_debug_bridge.native_pawns_command(),'Repeated seating duplicated requests')
occupied,pawn_active={},{};clock=clock+0.3;driver_debug_bridge.native_pawns_tick()
assert(refs==0 and pawn_data[2].mask==1 and pawn_requests==3,'Pawn release cleanup failed')
-- Reproduce the user's reload case: two hired pawns already occupy points
-- 3/4. The main pawn must select 5, never the empty Player-only point 2.
occupied[3],occupied[4]=pawns[2],pawns[3]
pawn_active[pawns[2]]={Point={Object=io,PointNo=3}}
pawn_active[pawns[3]]={Point={Object=io,PointNo=4}}
assert(driver_debug_bridge.native_pawns_command());driver_debug_bridge.native_pawns_tick()
pawn_view=driver_debug_bridge.native_pawns_read()
assert(pawn_view.rows[1].point==5 and pawn_requests==4 and pawn_data[2].mask==1
    and pawn_view.rows[2].point==3 and pawn_view.rows[3].point==4,'Existing passengers starved main pawn or used player-only seat')
occupied,pawn_active={},{};clock=clock+0.3;driver_debug_bridge.native_pawns_tick()
assert(refs==0,'Retry leaked result references')
for i,ch in ipairs(pawns) do local before=pawn_before[i]
    assert(ch.pos==before.pos and ch.test_controller.warps==before.warps and ch.test_fall.reset_calls==before.fall
        and ch.machine.enabled==before.fsm,'Native pawn seating forced actor state')
end
io.call,mgr.call,gm.call=old_io_call,old_mgr_call,old_gm_call
gm.InteractiveObjectDataList=old_array
assert(human.pos==position and human.test_controller.warps==warps and human.test_fall.reset_calls==falls
    and human.machine.enabled==fsm,'Native entry wrote forced player state')
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=previous_gm
sdk.get_managed_singleton,sdk.find_type_definition=previous_singleton,previous_type
json.dump_file=previous_dump
print('PASS: native driving and one-shot NPC system exit, wrong-point/pause guards, 20-second observation, no forced actor writes')
end)()
