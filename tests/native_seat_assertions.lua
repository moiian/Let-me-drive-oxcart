;(function()
local previous_gm=ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']
local previous_singleton,previous_type=sdk.get_managed_singleton,sdk.find_type_definition
local previous_dump=json.dump_file
local function assert_native_facing(ch,anchor,slot,actor_rotation)
    local q=ch.test_joint.rotation
    if ch==human then
        assert(q.x==0 and q.y==0 and q.z==0 and q.w==1,'Player native rotation changed')
        return
    end
    local up=vec(2*(q.x*q.y-q.w*q.z),1-2*(q.x*q.x+q.z*q.z),2*(q.y*q.z+q.w*q.x))
    local back=vec(2*(q.x*q.z+q.w*q.y),2*(q.y*q.z-q.w*q.x),1-2*(q.x*q.x+q.y*q.y))
    local x,y,z=anchor:get_AxisX(),anchor:get_AxisY(),anchor:get_AxisZ()
    local sign=y.y<0 and -1 or 1
    local a=math.rad(slot.yaw)
    for _,key in ipairs({'x','y','z'}) do
        assert(math.abs(up[key]-y[key]*sign)<0.001,'Pawn tilt does not match deck up')
        assert(math.abs(-back[key]-(x[key]*math.sin(a)+z[key]*math.cos(a)))<0.001,
            'Pawn visible forward does not match preset')
    end
end
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
local passenger_test_state=false
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
local left_data={mask=10,get_field=function(self,key) return key=='CharacterType' and self.mask or 'driver_joint' end,
    set_field=function(self,key,value) assert(key=='CharacterType');self.mask=value end}
gm.InteractiveObjectDataList={get_element=function(_,i) return i==0 and left_data or i==1 and data or
    {get_field=function(_,key) return key=='CharacterType' and 1 or 'other_joint' end} end}
function gm:get_type_definition() return {get_method=function() return {get_num_params=function() return 0 end} end} end
function gm:call(method,i)
    if method=='isPlayerSit()' then return passenger_test_state end
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
local unseated_warps=driver.test_controller.warps
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
assert(driver.test_controller.warps==unseated_warps,'Invalid driver entrance teleported nearby NPC')
driver_points_enabled=true
seat.SitChara=driver;command('enter')
assert(requests==0 and not driver_debug_bridge.native_seat_busy(),'Occupied seat accepted')
seat.SitChara=nil;command('enter')
assert(requests==1 and data.mask==9 and left_data.mask==10 and refs==1,'Player flag/request missing or other entrance changed')
assert(driver.test_controller.warps==unseated_warps+1 and math.abs(driver.pos.z-body.pos.z)==50,
    'Nearby unseated driver was not physically relocated once behind cart')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and left_data.mask==10 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Denied request leaked mask/lease')
result.value=0;command('enter')
interacting=true;active={Point={Object=io,PointNo=1}};seat.SitChara=human
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(driver_debug_bridge.native_seat_read().status:find('CONFIRMED',1,true),'Native binding not confirmed')
assert(state.native_drive and not state.active and #state.seats==0 and bus.owner==TITLE,
    'Native driving reused legacy seat ownership')
assert(not driver_debug_bridge.native_seat_command('enter') and state.native_drive,
    'Repeated entry disrupted existing native ownership')
local original_camera=copy_camera(current_camera())
local previous_primary=sdk.get_primary_camera
local camera_transform=object('camera',vec(7,8,9))
camera_transform.set_Position=function() error('Driving must not write camera position') end
local camera={fov=60,get_GameObject=function() return camera_transform end,
    get_type_definition=function() return {get_method=function() return true end} end,
    call=function(self,name,value) if name=='get_FOV' then return self.fov end;self.fov=value end}
local camera_manager={_DistanceOffset=1,get_type_definition=function() return {get_field=function() return true end} end}
local camera_singleton=sdk.get_managed_singleton
sdk.get_primary_camera=function() return camera end
sdk.get_managed_singleton=function(name) if name=='app.CameraManager' then return camera_manager end;return camera_singleton(name) end
current_camera().fov_enabled=true;current_camera().fov=80
current_camera().distance_enabled=true;current_camera().distance=3
callbacks.PrepareRendering()
assert(camera.fov==60 and camera_manager._DistanceOffset==1 and camera_transform.pos.x==7,
    'Camera overrides applied before boarding delay')
local original_ready=state.native_drive.ready_at
driver_debug_bridge.native_boarding_pause(2)
assert(state.native_drive.ready_at==original_ready+2 and state.native_entry_ready_at==original_ready+2,
    'Pause did not preserve five seconds of game-time boarding')
-- Keep the later timing checks relative to the delayed gate.
clock=clock+2
local function drive(keys)
    input={keyboard=0,stick=0}
    for k,v in pairs(keys or {}) do input[k]=v end
    driver_debug_bridge.native_drive_tick(0.1)
end
drive({up=true})
assert(state.native_drive.drive.level==1 and ox.am.CurrentActionList[0].Name=='Wait','Boarding wait accepted acceleration')
clock=clock+5.1
callbacks.PrepareRendering()
assert(camera.fov==80 and camera_manager._DistanceOffset==3 and camera_transform.pos.x==7
    and camera_transform.pos.y==8 and camera_transform.pos.z==9,'Delayed FOV/distance overrides missing or camera position changed')
callbacks.PrepareRendering()
assert(camera_transform.pos.x==7,'Rendering changed camera position')
pre_callbacks.UpdateBehavior()
assert(camera_transform.pos.x==7 and human.pos==position,'Camera restoration changed player root')
local original_gui_field=gui['<IsDispPhotoModeAll>k__BackingField']
gui['<IsDispPhotoModeAll>k__BackingField']=true;is_paused=true
local player_action=human.am.CurrentActionList[0].Name
clock=clock+50
callbacks.PrepareRendering()
local photo_target=native_display_position(state.native_drive.cart.anchor,settings.presets[settings.preset].slots[1])
assert(human.test_joint:get_Position().y==photo_target.y and human.pos==position,
    'Photo mode did not apply skeleton-only player preset')
assert_native_facing(human,state.native_drive.cart.anchor,settings.presets[settings.preset].slots[1])
assert(camera.fov==60 and camera_manager._DistanceOffset==1 and camera_transform.pos.x==7,
    'Photo mode applied driving camera parameters')
assert(human.am.CurrentActionList[0].Name==player_action,'Photo mode issued a sitting animation')
pre_callbacks.UpdateBehavior();callbacks.PrepareRendering()
assert(human.test_joint:get_Position().y==photo_target.y,'Photo pre-render fallback lost skeleton preset')
gui['<IsDispPhotoModeAll>k__BackingField']=original_gui_field;is_paused=false;last=clock
callbacks.PrepareRendering()
assert(camera.fov==80 and camera_manager._DistanceOffset==3 and camera_transform.pos.x==7,
    'Driving camera did not resume after photo mode')
pre_callbacks.UpdateBehavior()
print('PASS: photo-mode skeleton presets without animation/actor-root/camera writes; driving camera resumes on exit')
local preset_before=settings.preset
local ready_before=state.native_drive.ready_at
settings.presets[#settings.presets+1]=copy_layout(settings.presets[preset_before],'Native cycle test','Normal')
drive({sit=true})
assert(settings.preset~=preset_before and state.native_drive.ready_at==ready_before and native_camera_ready(),
    'Preset cycle did not apply or restarted camera delay')
settings.preset=preset_before;family_cursor.Normal=preset_before;table.remove(settings.presets)
for i=1,6 do drive({up=true}) end
assert(state.native_drive.drive.level==4 and ox.am.CurrentActionList[0].Name=='Dash','Native acceleration/clamp failed')
for i=1,6 do drive({down=true}) end
assert(state.native_drive.drive.level==1 and ox.am.CurrentActionList[0].Name=='Wait','Native deceleration/clamp failed')
drive({keyboard=1})
assert(cow['set_TargetFrontAngleDeg(System.Single)']~=heading
    and cow['set_TargetMoveAngleDeg(System.Single)']==cow['set_TargetFrontAngleDeg(System.Single)'],
    'Native steering did not control cow angles')
local angle=cow['set_TargetFrontAngleDeg(System.Single)']
last=clock
is_paused=true;input={up=true,keyboard=-1,stick=0};callbacks.LateUpdateBehavior()
assert(state.native_drive.drive.level==1 and cow['set_TargetFrontAngleDeg(System.Single)']==angle,'Paused driving moved cow')
is_paused=false;input={up=true,keyboard=0,stick=0};clock=clock+0.2;callbacks.LateUpdateBehavior()
assert(state.native_drive.drive.level==2 and not state.active and #state.seats==0,'Native input fell through legacy constraints')
drive({stand=true})
assert(exits==0 and state.native_drive,'Native A exit was intercepted')
assert(not pcall(acquire),'Manual acquisition overlaps native ownership')
active.Point.PointNo=2;command('exit');assert(exits==0,'Exited unrelated passenger interaction')
active.Point.PointNo=1;command('exit');assert(exits==1 and data.mask==9 and left_data.mask==10,'Mask restored before engine exit')
interacting=false;seat.SitChara=nil;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and left_data.mask==10 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Exit cleanup failed')
assert(camera.fov==60 and camera_manager._DistanceOffset==1 and camera_transform.pos.x==7,
    'Native exit leaked camera settings')
settings.presets[settings.preset].camera=original_camera
sdk.get_primary_camera=previous_primary;sdk.get_managed_singleton=camera_singleton
command('enter');clock=clock+16;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and left_data.mask==10 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Timeout cleanup failed')
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
local damage_hook=hooks['damageProc(app.HitController.DamageInfo)']
local damage_update=hooks['updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)']
local end_hook=hooks['endInteract(app.Character)']
local action_hook=hooks['requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)']
assert(driver_debug_bridge.native_pawn_context(pawns[1]) and not driver_debug_bridge.native_pawn_context(human),
    'Native pawn scope excludes seated pawn or includes player')
assert(damage_hook({nil,nil,{['<DamageGameObject>k__BackingField']=pawns[1]}})=='skip'
    and damage_hook({nil,nil,{['<DamageGameObject>k__BackingField']=human}})==nil,'Pawn immunity affected player')
local info={Damage=100,['<DamageGameObject>k__BackingField']=pawns[2]}
assert(damage_update({nil,nil,info})=='skip' and info.Damage==0,'Native pawn damage was not blocked')
status.broken=true
assert(damage_hook({nil,nil,{['<DamageGameObject>k__BackingField']=pawns[1]}})==nil,
    'Destroyed cart kept pawn protection/lock')
status.broken=false
assert(end_hook({nil,mgr,pawns[1]})=='skip' and end_hook({nil,mgr,human})==nil,'Seat lock affected player')
not_sitting[pawns[1]]=true
assert(end_hook({nil,mgr,pawns[1]})==nil
    and damage_hook({nil,nil,{['<DamageGameObject>k__BackingField']=pawns[1]}})==nil,'Boarding pawn was locked/protected too early')
not_sitting[pawns[1]]=nil
driver_debug_bridge.native_visual_tick()
for i,ch in ipairs(pawns) do
    local slot=settings.presets[settings.preset].slots[i+1]
    local target=offset_position(body,slot)
    assert(ch.test_joint:get_Position().x==target.x and ch.test_joint:get_Position().z==target.z
        and ch.pos==pawn_before[i].pos and ch.test_controller.warps==pawn_before[i].warps,
        'Preset moved actor root instead of skeleton')
    assert_native_facing(ch,body,slot)
end
pre_callbacks.UpdateBehavior()
local pivot=pawns[1].test_joint
local origin=pawns[1].pos
pivot.world_pos=vec(origin.x+0.2,origin.y+0.1,origin.z+0.3)
driver_debug_bridge.native_visual_tick()
local pivot_slot=settings.presets[settings.preset].slots[2]
local pivot_target=native_display_position(body,pivot_slot)
local pivot_angle=math.rad(pivot_slot.yaw)
assert(math.abs(pivot:get_Position().x-(pivot_target.x+0.2*math.cos(pivot_angle)+0.3*math.sin(pivot_angle)))<0.001
    and math.abs(pivot:get_Position().z-(pivot_target.z-0.2*math.sin(pivot_angle)+0.3*math.cos(pivot_angle)))<0.001,
    'Facing-only correction mirrored the root-joint position offset')
local node={ToString=function() return 'Attack' end}
assert(action_hook({nil,pawns[1].am,0,node,0})=='skip'
    and action_hook({nil,human.am,0,node,0})==nil,'Primary-action lock affected player')
-- Full world orientation must work on either slope sign, every preset
-- heading and downward anchor Y, independently of the actor local rig.
pre_callbacks.UpdateBehavior()
do
    local bx,by,bz=body.get_AxisX,body.get_AxisY,body.get_AxisZ
    local player_joint=human.test_joint
    local player_local,player_world=player_joint.set_LocalRotation,player_joint.set_Rotation
    local player_writes=0
    player_joint.set_LocalRotation=function() player_writes=player_writes+1 end
    player_joint.set_Rotation=function() player_writes=player_writes+1 end
    local old_yaws={}
    for i=1,3 do old_yaws[i]=settings.presets[settings.preset].slots[i+1].yaw end
    local function rot(axis,angle)
        local s=math.sin(math.rad(angle)/2)
        return Quaternion.new(axis=='x' and s or 0,axis=='y' and s or 0,axis=='z' and s or 0,math.cos(math.rad(angle)/2))
    end
    local function axes(q)
        return vec(1-2*(q.y*q.y+q.z*q.z),2*(q.x*q.y+q.w*q.z),2*(q.x*q.z-q.w*q.y)),
            vec(2*(q.x*q.y-q.w*q.z),1-2*(q.x*q.x+q.z*q.z),2*(q.y*q.z+q.w*q.x)),
            vec(2*(q.x*q.z+q.w*q.y),2*(q.y*q.z-q.w*q.x),1-2*(q.x*q.x+q.y*q.y))
    end
    for _,pitch in ipairs({-24,24}) do for _,roll in ipairs({-17,17}) do
        local x,y,z=axes(rot('y',37)*rot('x',pitch)*rot('z',roll))
        body.get_AxisX=function() return x end;body.get_AxisZ=function() return z end
        for _,sign in ipairs({1,-1}) do
            body.get_AxisY=function() return vec(y.x*sign,y.y*sign,y.z*sign) end
            for _,yaw in ipairs({-180,-90,0,90,178}) do
                for i,ch in ipairs(pawns) do
                    ch.test_joint.rotation=Quaternion.new(1,0,0,0)
                    settings.presets[settings.preset].slots[i+1].yaw=yaw
                end
                driver_debug_bridge.native_visual_tick()
                local photo_before=gui['<IsDispPhotoModeAll>k__BackingField']
                gui['<IsDispPhotoModeAll>k__BackingField']=true;is_paused=true
                driver_debug_bridge.native_visual_tick()
                for i,ch in ipairs(pawns) do
                    assert_native_facing(ch,body,settings.presets[settings.preset].slots[i+1])
                    assert(ch.pos==pawn_before[i].pos and ch.test_controller.warps==pawn_before[i].warps,
                        'Pawn display rotation changed physics/root')
                end
                driver_debug_bridge.native_visual_restore()
                gui['<IsDispPhotoModeAll>k__BackingField']=photo_before;is_paused=false
                for _,ch in ipairs(pawns) do
                    assert(ch.test_joint.rotation.x==1 and ch.test_joint.rotation.w==0,
                        'Native local rotation not restored')
                end
            end
        end
    end end
    body.get_AxisX,body.get_AxisY,body.get_AxisZ=bx,by,bz
    for i,ch in ipairs(pawns) do
        ch.test_joint.rotation=Quaternion.new(0,0,0,1)
        settings.presets[settings.preset].slots[i+1].yaw=old_yaws[i]
    end
    assert(player_writes==0,'Pawn display wrote player rotation')
    player_joint.set_LocalRotation,player_joint.set_Rotation=player_local,player_world
end
print('PASS: pawn world facing/deck tilt across slope signs and inverted Y; player/root unchanged')

do
    local previous_list=gm.InteractSeatList
    local jack_seat=object('main_native_seat')
    jack_seat.TargetChara=pawns[1];jack_seat.State=3
    function jack_seat:get_type_definition() return {
        get_method=function() return {get_num_params=function() return 0 end} end} end
    jack_seat.CompMotJackFsm={call=function() return true end}
    local calls,logs=0,{}
    function jack_seat:call(method)
        if method=='get_IsSitState' then return true end
        calls=calls+1;error('Unexpected animation request')
    end
    gm.InteractSeatList={get_type_definition=previous_list.get_type_definition,
        call=function(_,method,index)
            if method=='get_Count' then return 4 end
            return index==0 and jack_seat or previous_list:call(method,index)
        end}
    local trace_dump=json.dump_file
    json.dump_file=function(path,value) logs[#logs+1]={path=path,data=value} end
    assert(not driver_debug_bridge.seat_motion_command('test'))
    assert(driver_debug_bridge.seat_motion_command('start'));driver_debug_bridge.seat_motion_tick()
    local first_path=driver_debug_bridge.seat_motion_read().path
    driver_debug_bridge.native_visual_tick()
    clock=clock+0.3;driver_debug_bridge.seat_motion_tick()
    assert(#logs>0 and calls==0,'Read-only recording invoked animation')
    assert(not driver_debug_bridge.seat_motion_command('test'))
    assert(hooks['continueInteract(app.Character)']({nil,mgr,pawns[1]})==nil)
    assert(hooks['execJack(app.MotionJackBase.JackParam, via.GameObject, via.motion.MotionJackFsm2)'](
        {nil,nil,{StateName='NativeLoop',JackFsmLayer=0,ResetStateToIdle=false},pawns[1]:get_GameObject(),{}})==nil)
    clock=clock+1;driver_debug_bridge.seat_motion_tick()
    local sample=logs[#logs].data.samples[#logs[#logs].data.samples]
    assert(sample.rig and sample.rig.root_joint and sample.rig.anchor,
        'Native rig frame missing: '..tostring(logs[#logs].data.events[#logs[#logs].data.events].detail))
    assert(sample.rig.phase=='before_display_position','Rig sampled after display write')
    assert(logs[#logs].data.continue_count==1,'Native continuation not recorded')
    assert(driver_debug_bridge.seat_motion_command('stop'));driver_debug_bridge.seat_motion_tick()
    assert(logs[#logs].data.reason=='stopped' and calls==0)
    assert(driver_debug_bridge.seat_motion_command('start'));driver_debug_bridge.seat_motion_tick()
    assert(first_path~=driver_debug_bridge.seat_motion_read().path,'LOG overwritten')
    driver_debug_bridge.seat_motion_close()
    assert(logs[#logs].data.reason=='scripts reset' and calls==0,'Reset invoked animation')
    json.dump_file=trace_dump;gm.InteractSeatList=previous_list
end
print('PASS: read-only main-Pawn rig trace, rejected animation commands and unique LOGs')
clock=clock+41;driver_debug_bridge.native_visual_tick()
assert(driver_debug_bridge.native_pose_node(pawns[1])==nil,'Diagnostic requested random sitting pose')
pre_callbacks.UpdateBehavior()
assert(pawns[1].test_joint:get_Position()==pawns[1].pos,'Skeleton restoration leaked')
print('PASS: seated-only pawn protection/action/interaction lock, boarding/destruction/exit exclusions and skeleton-only presets')
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
local drive_q={cart={ox=ox,cow=cow,body=body,anchor=body},ch=human}
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
assert(end_hook({nil,mgr,pawns[1]})==nil,'Manual pawn exit was blocked by seat lock')
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
-- release, relocates once, then submits the player request.
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
local teleport_warps=driver.test_controller.warps
local teleport_pos=driver.pos
assert(not pcall(driver_debug_bridge.native_driver_relocate,{body=body,ox=ox},driver)
    and driver.test_controller.warps==teleport_warps,'Bound driver relocation was accepted')
command('enter')
assert(exits==exits_before+1 and requests==requests_before and driver_debug_bridge.native_seat_busy(),
    'Occupied driver seat did not chain a one-shot NPC exit')
assert(data.mask==8 and left_data.mask==10 and driver.test_controller.warps==teleport_warps,
    'Driver flags modified or bound driver teleported')
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(exits==exits_before+1 and requests==requests_before,'NPC exit repeated while waiting')
npc_still_interacting=false;seat.SitChara=nil
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(requests==requests_before+1,'Player entry not submitted after NPC exit')
local relocation_cart=state.cart or {body=body,ox=ox}
local fx,fz=cart_forward(relocation_cart)
local relocation_origin=relocation_cart.body:get_Position()
assert(driver.test_controller.warps==teleport_warps+1 and driver.pos~=teleport_pos,
    'Unbound driver not physically teleported exactly once')
assert(math.abs(driver.pos.x-(relocation_origin.x-fx*50))<0.001
    and math.abs(driver.pos.z-(relocation_origin.z-fz*50))<0.001
    and driver.pos.y==teleport_pos.y,'Driver relocation target was not 50 behind cart at original height')
assert(not pcall(driver_debug_bridge.native_driver_relocate,relocation_cart,human),
    'Driver relocation accepted player')
assert(driver.test_fall.reset_calls==driver_falls+1 and driver.machine.enabled==driver_fsm,
    'Driver relocation missing fall reset or froze FSM')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(refs==0 and not driver_debug_bridge.native_seat_busy(),'Chained entry cleanup leaked')
assert(data.mask==8 and left_data.mask==10,'Chained entry failure leaked driver flags')
npc_still_interacting=true;seat.SitChara=driver;result.value=0
command('enter');command('exit')
assert(data.mask==8 and left_data.mask==10 and not driver_debug_bridge.native_seat_busy(),
    'Cancelled NPC exit wait leaked driver flags')
command('enter');clock=clock+16;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and left_data.mask==10 and not driver_debug_bridge.native_seat_busy(),
    'Timed-out NPC exit wait leaked driver flags')
seat.SitChara=nil
assert(driver.test_controller.warps==teleport_warps+1,'Cancelled/timed-out entry teleported driver')
driver.pos=vec(body.pos.x,body.pos.y,body.pos.z)
local pending_warps,pending_exits,pending_requests=driver.test_controller.warps,exits,requests
command('enter')
assert(exits==pending_exits+1 and requests==pending_requests and driver.test_controller.warps==pending_warps,
    'Boarding driver without SitChara was teleported before interaction release')
npc_still_interacting=false;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(driver.test_controller.warps==pending_warps+1 and requests==pending_requests+1,
    'Boarding driver was not relocated once after native release')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick();result.value=0
assert(refs==0,'Boarding-driver entry failure leaked native refs')
print('PASS: nearby idle/boarding/seated driver relocation with native-unbind and invalid-entry guards')
mgr.call=base_mgr_call;expected_exit_actor=human
assert(human.pos==position and human.test_controller.warps==warps and human.test_fall.reset_calls==falls
    and human.machine.enabled==fsm,'Native entry wrote forced player state')
-- Production E/X route: strict front distance, passenger exclusion and no
-- legacy acquisition. The first edge queues, the next tick submits natively.
local hotkey_position=human.pos
local hotkey_requests=requests
local function press_near(device)
    kb_down,gp_bits={},0;callbacks.UpdateHID()
    if device=='keyboard' then kb_down[keys.E]=true else gp_bits=pads.RLeft end
    callbacks.UpdateHID();callbacks.LateUpdateBehavior()
    kb_down,gp_bits={},0;callbacks.UpdateHID()
end
human.pos=vec(body.pos.x,body.pos.y,body.pos.z+front_offset.z+2)
press_near('keyboard')
assert(not driver_debug_bridge.native_seat_busy() and requests==hotkey_requests,'Distance boundary admitted E')
human.pos=vec(body.pos.x,body.pos.y,body.pos.z+front_offset.z)
passenger_test_state=true;press_near('keyboard')
assert(not driver_debug_bridge.native_seat_busy(),'Seated passenger admitted E')
passenger_test_state=false
_G.OJR_SeatBindings={{char=human}};press_near('gamepad')
assert(not driver_debug_bridge.native_seat_busy(),'OJR seated player admitted X')
_G.OJR_SeatBindings=nil
press_near('gamepad');assert(driver_debug_bridge.native_seat_busy(),'Near X did not queue native entry')
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(requests==hotkey_requests+1 and not state.active,'Near X used legacy route')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick();result.value=0
press_near('keyboard');clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(requests==hotkey_requests+2,'Near E did not submit native entry')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick();result.value=0
human.pos=hotkey_position
local previous_imgui=imgui
local pressed_button
imgui={tree_node=function(label) return label==TITLE or label=='General settings' end,
    tree_pop=function() end,text=function() end,slider_float=function(_,value) return false,value end,
    button=function(label) return label==pressed_button end}
pressed_button='Let me drive';callbacks.ui()
assert(driver_debug_bridge.native_seat_busy(),'Main Let me drive button not wired')
driver_debug_bridge.native_seat_close();imgui=previous_imgui
print('PASS: native main menu, E/X strict front-distance/passenger/OJR guards, boarding wait and camera delay/restore')
do
    local original_presets,original_preset=settings.presets,settings.preset
    local original_family,original_changed,original_drive=state.family,state.layout_changed,state.native_drive
    local cursors={}
    for _,family in ipairs(families) do cursors[family]=family_cursor[family] end
    local source=original_presets[1]
    local a,r,b,w,c=copy_layout(source,'A','Normal'),copy_layout(source,'R','Rainy'),
        copy_layout(source,'B','Normal'),copy_layout(source,'W','Wealthy'),copy_layout(source,'C','Normal')
    settings.presets={a,r,b,w,c};settings.preset=3
    family_cursor.Normal,family_cursor.Rainy,family_cursor.Wealthy=3,2,4
    state.family='Normal';state.native_drive={ready_at=clock+8};state.layout_changed=false
    local previous_ui=imgui
    imgui={tree_node=function(label) return label==TITLE or label=='Driving seat presets' end,
        tree_pop=function() end,combo=function(_,value) return false,value end,
        input_text=function(_,value) return false,value end,button=function(label) return label=='Delete current layout' end}
    callbacks.ui()
    imgui=previous_ui
    assert(#settings.presets==4 and settings.presets[settings.preset]==a and state.layout_changed,
        'Delete current layout button did not remove/select a same-family preset')
    assert(settings.presets[family_cursor.Rainy]==r and settings.presets[family_cursor.Wealthy]==w
        and state.native_drive.ready_at==clock+8,'Delete corrupted other cart cursors or restarted camera delay')
    settings.preset=4;family_cursor.Normal=4;delete_current_layout()
    assert(#settings.presets==3 and settings.presets[settings.preset]==a,'Deleting last-index preset broke selection')
    delete_current_layout()
    assert(#settings.presets==3 and settings.presets[settings.preset].family=='Normal'
        and settings.presets[settings.preset].name=='Normal - Default'
        and settings.presets[family_cursor.Rainy]==r and settings.presets[family_cursor.Wealthy]==w,
        'Deleting last cart-type preset failed to recreate only its default')
    choose_family('Rainy',false);assert(settings.presets[settings.preset]==r,'Reindexed rainproof selection failed')
    choose_family('Wealthy',false);assert(settings.presets[settings.preset]==w,'Reindexed luxury selection failed')
    choose_family('Normal',true);assert(settings.presets[settings.preset].family=='Normal','Cycling after delete crossed cart types')
    settings.presets={a};settings.preset=1
    family_cursor.Normal=1;family_cursor.Rainy=nil;family_cursor.Wealthy=nil
    delete_current_layout()
    assert(#settings.presets==1 and settings.preset==1 and settings.presets[1].family=='Normal',
        'Deleting sole global preset left an empty/invalid list')
    settings.presets,settings.preset=original_presets,original_preset
    for _,family in ipairs(families) do family_cursor[family]=cursors[family] end
    state.family,state.layout_changed,state.native_drive=original_family,original_changed,original_drive
end
print('PASS: delete-current UI, reindexing, same-cart selection/cycling, last-layout default and unchanged boarding delay')
driver_debug_bridge.native_visual_tick()
callbacks.reset()
assert(bus.owner==nil and not state.native_drive and refs==0,'Script reset leaked ownership/result refs')
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=previous_gm
sdk.get_managed_singleton,sdk.find_type_definition=previous_singleton,previous_type
json.dump_file=previous_dump
print('PASS: driver exit/entry chain, main Pawn Point 2, repeat missing-pawn boarding, seated skips, manual/distance exits and native driving')
end)()
