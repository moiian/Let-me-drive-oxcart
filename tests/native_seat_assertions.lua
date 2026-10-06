;(function()
local previous_gm=ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']
local previous_singleton,previous_type=sdk.get_managed_singleton,sdk.find_type_definition
local previous_dump=json.dump_file
local function assert_native_facing(ch,anchor,slot,actor_rotation)
    local expected=actor_rotation or Quaternion.new(0,0,0,1)
    local q=ch.test_joint.rotation
    assert(q.x==expected.x and q.y==expected.y and q.z==expected.z and q.w==expected.w,
        'Position-only diagnostic changed native rotation')
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
for _,layout in ipairs(settings.presets) do assert(not layout.native_default,'Read-only Default survived migration') end
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
local original_visual_ready=state.native_drive.visual_ready_at
driver_debug_bridge.native_boarding_pause(2)
assert(state.native_drive.ready_at==original_ready+2 and state.native_entry_ready_at==original_ready+2,
    'Pause did not preserve eight seconds of game-time boarding')
assert(state.native_drive.visual_ready_at==original_visual_ready+2,'Pause advanced player preset countdown')
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
drive({up=true})
assert(state.native_drive.drive.level==1 and ox.am.CurrentActionList[0].Name=='Wait',
    'Boarding wait ended before eight seconds')
assert(camera.fov==60 and camera_manager._DistanceOffset==1,
    'Player presets applied at five seconds instead of eight')
local movement_ready=state.native_drive.ready_at
clock=clock+1;driver_debug_bridge.native_boarding_pause(1)
assert(state.native_drive.ready_at==movement_ready+1 and state.native_drive.visual_ready_at==original_visual_ready+3,
    'Pause did not preserve both eight-second delays')
clock=clock+3
callbacks.PrepareRendering()
assert(camera.fov==80 and camera_manager._DistanceOffset==3 and camera_transform.pos.x==7
    and camera_transform.pos.y==8 and camera_transform.pos.z==9,'Delayed FOV/distance overrides missing or camera position changed')
callbacks.PrepareRendering()
assert(camera_transform.pos.x==7,'Rendering changed camera position')
assert(hooks['freeGetOff']==nil,'Unsafe early-departure hook was retained')
assert(native_camera_ready(),'Player presets disabled while still in driver seat')
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
assert(settings.preset==preset_before and state.preset_switch,'Preset switched without stand/wait phase')
clock=clock+0.29;drive({})
assert(settings.preset==preset_before,'Preset switched before 0.3 seconds')
clock=clock+0.02;drive({})
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
local real_pawn_exit=driver_debug_bridge.native_pawns_exit
local pawn_exit_calls=0
driver_debug_bridge.native_pawns_exit=function()
    pawn_exit_calls=pawn_exit_calls+1;return real_pawn_exit()
end
driver_debug_bridge.native_pawns_exit()
assert(native_camera_ready(),'Pawn stand button disabled player presets')
pawn_exit_calls=0
drive({stand=true})
assert(exits==0 and not state.native_drive and driver_debug_bridge.native_seat_busy(),
    'Stand did not stop script driving or inserted a native player exit')
assert(pawn_exit_calls==1,'Stand mapping did not release pawn anchors')
assert(not native_camera_ready() and camera.fov==60 and camera_manager._DistanceOffset==1,
    'Stand hotkey did not revoke and restore player presets')
callbacks.PrepareRendering()
assert(camera.fov==60 and camera_manager._DistanceOffset==1,'Player presets reapplied after Stand hotkey')
local stopped_preset=settings.preset
local stopped_count=#settings.presets
delete_current_layout()
assert(#settings.presets==stopped_count,'Deleting active preset bypassed Stand switch lock')
drive({sit=true})
assert(settings.preset==stopped_preset and not driver_debug_bridge.switch_preset(nil,true),
    'Preset switching allowed after Stand stopped driving')
assert(not pcall(acquire),'Manual acquisition overlaps native ownership')
active.Point.PointNo=2;command('exit');assert(exits==0,'Exited unrelated passenger interaction')
active.Point.PointNo=1;command('exit');assert(exits==1 and data.mask==9 and left_data.mask==10,'Mask restored before engine exit')
assert(pawn_exit_calls==1,'Pawn anchors released at exit start rather than full native departure')
interacting=false;seat.SitChara=nil;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(pawn_exit_calls==2,'Full player departure did not release pawn anchors')
driver_debug_bridge.native_pawns_exit=real_pawn_exit
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
driver_debug_bridge.native_pawns_command=real_pawn_command
do
    local native_requests,native_exits=0,0
    local bound={}
    function mgr:call(method,ch)
        if method=='isInteracting(app.Character)' then return bound[ch]==true end
        if method=='getActiveInteract(app.Character)' then return bound[ch] and {Point={Object=io,PointNo=2}} or nil end
        native_requests=native_requests+1;error('Hybrid pawn path must not request native interaction')
    end
    function io:call(method,point,ch)
        assert(method=='endInteractForSystem(System.UInt32, app.Character)')
        native_exits=native_exits+1
    end
    local cart={ox=ox,cow=cow,body=body,anchor=body,status=status}
    local player_pos,player_warps=human.pos,human.test_controller.warps
    local original_look=body.get_AxisY
    body.get_AxisY=function() return vec(0,0.8,0.6) end
    local before={}
    local joint_writes=0
    for i,ch in ipairs(pawns) do
        before[i]={fsm=ch.machine.enabled,warp=ch.test_controller.warps,
            joint_set=ch.test_joint.set_Position,rot_set=ch.test_joint.set_Rotation}
        ch.test_joint.set_Position=function() joint_writes=joint_writes+1 end
        ch.test_joint.set_Rotation=function() joint_writes=joint_writes+1 end
    end
    assert(driver_debug_bridge.native_pawns_command(true,cart))
    driver_debug_bridge.native_pawns_tick()
    assert(#state.seats==3 and native_requests==0,'Hybrid pawn acquisition missing or requested native seats')
    for i,ch in ipairs(pawns) do
        local slot=settings.presets[settings.preset].slots[i+1]
        local expected=offset_position(body,slot)
        assert(ch.pos.x==expected.x and ch.pos.y==expected.y and ch.pos.z==expected.z,
            'Pawn root did not use cart anchored position')
        assert(ch.look_up.y==0.8 and ch.look_up.z==0.6,'Pawn real rotation lost deck tilt')
        local a=math.rad(slot.yaw)
        assert(math.abs(ch.look_target.x-(ch.pos.x+math.sin(a)))<0.00001,
            'Pawn real facing lost preset yaw')
        assert(ch.test_controller.warps>before[i].warp and ch.test_fall.reset_calls>0,
            'Pawn physics/fall state was not synchronized')
        assert(driver_debug_bridge.native_pawn_context(ch) and driver_debug_bridge.native_pose_node(ch),
            'Pawn protection/action lock scope unavailable')
    end
    assert(human.pos==player_pos and human.test_controller.warps==player_warps and joint_writes==0,
        'Hybrid pawn path moved player or pawn skeleton')
    local original_index=settings.preset
    local source=settings.presets[original_index]
    local copy=copy_layout(source,'Switch sequence test',source.family)
    copy.slots[2].x=source.slots[2].x+1
    settings.presets[#settings.presets+1]=copy
    local new_index=#settings.presets
    assert(driver_debug_bridge.switch_preset(new_index))
    assert(#state.seats==0 and settings.preset==original_index,
        'Preset switch did not stand pawns before applying layout')
    assert(not driver_debug_bridge.switch_preset(new_index),'Overlapping switch accepted')
    is_paused=true;clock=clock+2;driver_debug_bridge.switch_preset_tick();is_paused=false
    clock=clock+0.29;driver_debug_bridge.switch_preset_tick()
    assert(settings.preset==original_index,'Paused switch timer advanced or switched too early')
    clock=clock+0.02;driver_debug_bridge.switch_preset_tick()
    assert(settings.preset==new_index and #state.seats==0,'Delayed layout was not committed before reseating')
    driver_debug_bridge.native_pawns_tick()
    assert(#state.seats==3 and pawns[1].pos.x==offset_position(body,copy.slots[2]).x,
        'Pawns did not reseat on switched layout')
    assert(driver_debug_bridge.switch_preset(original_index))
    driver_debug_bridge.stand_hotkey()
    clock=clock+1;driver_debug_bridge.switch_preset_tick()
    assert(settings.preset==new_index and not state.preset_switch and #state.seats==0,
        'Stand did not cancel pending preset switch/reseating')
    settings.preset=original_index;family_cursor[source.family]=original_index
    table.remove(settings.presets)
    driver_debug_bridge.native_pawns_command(true,cart);driver_debug_bridge.native_pawns_tick()
    local damage_hook=hooks['damageProc(app.HitController.DamageInfo)']
    assert(damage_hook({nil,nil,{['<DamageGameObject>k__BackingField']=pawns[1]}})=='skip')
    assert(damage_hook({nil,nil,{['<DamageGameObject>k__BackingField']=human}})==nil)
    local update_hook=hooks['updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)']
    local old_drive=state.native_drive
    state.native_drive={cart=cart}
    local guard,other_cart=object('guard'),object('gm80_042_other')
    for _,receiver in ipairs({body,ox,cow}) do
        for _,amount in ipairs({0.01,10,999,1999,1000000,0,-10}) do
            local info={['<DamageGameObject>k__BackingField']=receiver,Damage=amount}
            assert(update_hook({nil,nil,info})==nil,'Cart protection skipped native transaction')
            assert(info.Damage==(amount>0 and 0 or amount),'Cart damage was not zeroed or healing changed')
        end
    end
    for _,receiver in ipairs({human,driver,guard,other_cart}) do
        local info={['<DamageGameObject>k__BackingField']=receiver,Damage=1000}
        assert(update_hook({nil,nil,info})==nil and info.Damage==1000,
            'Cart protection affected player, driver, guard or unrelated cart')
        assert(damage_hook({nil,nil,info})==nil,'NPC/player damage transaction blocked')
    end
    local pawn_damage={['<DamageGameObject>k__BackingField']=pawns[1],Damage=1000}
    assert(update_hook({nil,nil,pawn_damage})=='skip' and pawn_damage.Damage==0,
        'Managed pawn protection regressed')
    state.native_drive=nil
    local inactive_damage={['<DamageGameObject>k__BackingField']=body,Damage=1000}
    assert(update_hook({nil,nil,inactive_damage})==nil and inactive_damage.Damage==1000,
        'Cart protection persisted after driving ended')
    assert(update_hook({nil,nil,{Damage=1000}})==nil,'Missing receiver crashed damage hook')
    state.native_drive=old_drive
    print('PASS: driven cart/ox positive damage zeroed, native callbacks preserved, NPC/player/unrelated cart excluded')
    assert(not driver_debug_bridge.seat_motion_command('test'))
    assert(driver_debug_bridge.seat_motion_command('start'));driver_debug_bridge.seat_motion_tick()
    clock=clock+41;driver_debug_bridge.native_pawns_tick()
    driver_debug_bridge.seat_motion_tick()
    assert(driver_debug_bridge.seat_motion_command('stop'));driver_debug_bridge.seat_motion_tick()
    assert(driver_debug_bridge.native_pose_node(pawns[1])~=nil and native_requests==0,
        'Random sitting pose route missing or reintroduced native interaction')
    local random_before=math.random
    local expected_nodes={"SitOnChairActions","LivSitChairCrosslegs","LivSitChairLean",
        "SitOnChairCrossArmStart","LivSitPose","LivSitChairBook01","LivSitChairLoseieus"}
    for i,node in ipairs(expected_nodes) do
        math.random=function(n) if n then assert(n==7);return i else return 0.5 end end
        clock=clock+41;driver_debug_bridge.native_pawns_tick()
        assert(driver_debug_bridge.native_pose_node(pawns[1])==node,'Random sitting list differs from requested names')
    end
    math.random=random_before
    driver_debug_bridge.native_visual_tick()
    assert(joint_writes==0,'Display layer still writes pawn skeletons')
    driver_debug_bridge.native_pawns_exit()
    for i,ch in ipairs(pawns) do
        assert(ch.machine.enabled==before[i].fsm,'Release lost original pawn FSM state')
        ch.test_joint.set_Position=before[i].joint_set;ch.test_joint.set_Rotation=before[i].rot_set
    end
    assert(not driver_debug_bridge.native_pawn_context(pawns[1]),'Release retained pawn protection')
    -- A bound native passenger must be unbound BEFORE any root movement.
    bound[pawns[1]]=true
    local root=pawns[1].pos
    assert(driver_debug_bridge.native_pawns_command(true,cart));driver_debug_bridge.native_pawns_tick()
    assert(pawns[1].pos==root and native_exits==1 and #state.seats==2,
        'Bound passenger was moved before native exit')
    bound[pawns[1]]=nil
    driver_debug_bridge.native_pawns_tick()
    assert(#state.seats==3 and native_requests==0,'Retry did not anchor missing pawn')
    local root_before_exit=pawns[1].pos
    human.pos=vec(body.pos.x+5,body.pos.y,body.pos.z);driver_debug_bridge.native_pawns_tick()
    assert(#state.seats==3,'Pawn anchors released at exactly five units')
    root_before_exit=pawns[1].pos
    human.pos=vec(body.pos.x+5.01,body.pos.y,body.pos.z);driver_debug_bridge.native_pawns_tick()
    assert(#state.seats==0 and pawns[1].pos==root_before_exit,'Distance exit teleported pawn or kept lock')
    human.pos=player_pos;body.get_AxisY=original_look
    driver_debug_bridge.native_pawns_close()
end
io.call,mgr.call,gm.call=old_io_call,old_mgr_call,old_gm_call
print('PASS: pawn real-root/cart tilt/yaw, sync/fall, random pose, protection, native-exit guard, retries and distance release')

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
human.pos=vec(body.pos.x,body.pos.y,body.pos.z+front_offset.z+4)
press_near('keyboard')
assert(not driver_debug_bridge.native_seat_busy() and requests==hotkey_requests,'Distance boundary admitted E')
human.pos=vec(body.pos.x,body.pos.y,body.pos.z+front_offset.z+3.9)
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
    assert(#settings.presets==5 and state.preset_switch,'Delete bypassed stand/wait sequence')
    local ready_at=state.native_drive.ready_at
    clock=clock+0.31;driver_debug_bridge.switch_preset_tick()
    assert(#settings.presets==4 and settings.presets[settings.preset]==a and state.layout_changed,
        'Delete current layout button did not remove/select a same-family preset')
    assert(settings.presets[family_cursor.Rainy]==r and settings.presets[family_cursor.Wealthy]==w
        and state.native_drive.ready_at==ready_at,'Delete corrupted other cart cursors or restarted camera delay')
    settings.preset=4;family_cursor.Normal=4;delete_current_layout(true)
    assert(#settings.presets==3 and settings.presets[settings.preset]==a,'Deleting last-index preset broke selection')
    delete_current_layout(true)
    assert(#settings.presets==3 and settings.presets[settings.preset].family=='Normal'
        and settings.presets[settings.preset].name=='Normal - Default'
        and settings.presets[family_cursor.Rainy]==r and settings.presets[family_cursor.Wealthy]==w,
        'Deleting last cart-type preset failed to recreate only its default')
    choose_family('Rainy',false);assert(settings.presets[settings.preset]==r,'Reindexed rainproof selection failed')
    choose_family('Wealthy',false);assert(settings.presets[settings.preset]==w,'Reindexed luxury selection failed')
    choose_family('Normal',true);assert(settings.presets[settings.preset].family=='Normal','Cycling after delete crossed cart types')
    settings.presets={a};settings.preset=1
    family_cursor.Normal=1;family_cursor.Rainy=nil;family_cursor.Wealthy=nil
    delete_current_layout(true)
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
do
    local old_ui=imgui
    local labels={}
    local layout=settings.presets[settings.preset]
    local player_direct,pawn_direct=layout.slots[1].useDirectMotion,layout.slots[2].useDirectMotion
    layout.slots[1].useDirectMotion=true;layout.slots[2].useDirectMotion=true
    local function note(label,value) labels[label]=true;return false,value end
    imgui={tree_node=function(label)
        return label==TITLE or label=='Driving seat presets' or label=='Player driver'
            or label=='Pawn 1' or label=='Pawn 2' or label=='Pawn 3'
        end,tree_pop=function() end,text=function() end,button=function() return false end,
        combo=note,input_text=note,checkbox=note,drag_float=note,drag_int=note,slider_float=note}
    callbacks.ui()
    for _,name in ipairs({'Use Bank/Motion IDs##1','bankID##1','motionID##1',
        'Action name##1','Random sitting idles##1'}) do
        assert(not labels[name],'Native player animation controls remain visible')
    end
    assert(labels['Override FOV'] and labels['Camera distance'] and labels['x##1'],
        'Player position/camera controls were removed with animation controls')
    assert(labels['Use Bank/Motion IDs##2'] and labels['bankID##2']
        and labels['Action name##3'] and labels['Random sitting idles##2'],
        'Pawn animation controls were removed')
    layout.slots[1].useDirectMotion,layout.slots[2].useDirectMotion=player_direct,pawn_direct
    imgui=old_ui
end
print('PASS: player animation controls absent; player camera/position and pawn animation controls preserved')
sdk.get_managed_singleton,sdk.find_type_definition=previous_singleton,previous_type
json.dump_file=previous_dump
print('PASS: native player driver entry/exit, hybrid pawn anchors, manual/distance release and native driving')
end)()
