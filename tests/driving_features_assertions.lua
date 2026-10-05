;(function()
-- Cart-family filtering and measured defaults; preserve the existing baseline tests.
settings.debug_player_freeze=false
settings.presets={default_layout('Normal'),default_layout('Rainy'),default_layout('Wealthy'),default_layout('Normal')}
settings.presets[4].name='Normal alternate'
settings.preset=1;family_cursor={Normal=1,Rainy=2,Wealthy=3}
for _,layout in ipairs(settings.presets) do layout.player_visual.enabled=false end
human.pos=vec(0,0,0);body.name='gm80_042_00';command(acquire);tick()
assert(state.active and settings.preset==1 and state.family=='Normal',state.error)
local old_seat=state.seats[2]
local old_request=pawns[1].am.call
local exit_requests=0
pawns[1].am.call=function(self,method,priority,node,layer)
    if node=='Wait' then exit_requests=exit_requests+1 end
    return old_request(self,method,priority,node,layer)
end
input.sit=true;callbacks.LateUpdateBehavior()
assert(settings.preset==4,'Normal cycling selected a different cart type')
assert(state.seats[2]==old_seat and exit_requests==0,'Preset switch released pawn or issued competing Wait')
pawns[1].am.call=old_request
settings.presets[1].enabled=false
input.sit=true;callbacks.LateUpdateBehavior()
assert(settings.preset==4,'Disabled normal layout was included in cycling')
release();body.name='gm80_042_01';human.pos=vec(0,0,0);command(acquire);tick()
assert(state.active and settings.preset==2 and state.family=='Rainy' and human.pos.x==-0.051,
    'Rainproof takeover did not select measured default')
input.sit=true;callbacks.LateUpdateBehavior();assert(settings.preset==2,'Rainproof cycle crossed cart families')
release();body.name='gm80_052_00';human.pos=vec(0,0,0);command(acquire);tick()
assert(state.active and settings.preset==3 and state.family=='Wealthy','Luxury type was not detected')
release();body.name='gm80_042_00';human.pos=vec(0,0,0);command(acquire);tick()
assert(settings.preset==4,'Cart family forgot selected layout')
local layout=settings.presets[settings.preset]
layout.slots[1].anim='LivSitChairBook01';layout.slots[2].anim='SitOnChairCrossArmStart'
arrange();tick()
assert(human.am.CurrentActionList[0].Name=='LivSitChairBook01','Custom player action ignored')
assert(pawns[1].am.CurrentActionList[0].Name=='SitOnChairCrossArmStart','Custom pawn action ignored')
assert(external_request(human,'LivSitChairBook01')==nil and external_request(human,'DamageSmall')=='skip',
    'Custom player action escaped sitting protection')
local motion_calls={}
function human:get_Motion() return {getLayer=function(_,layer)
    assert(layer==0);return {call=function(_,method,bank,motion) motion_calls={method,bank,motion} end}
end} end
layout.slots[1].useDirectMotion=true;layout.slots[1].bankID=12;layout.slots[1].motionID=34
arrange();assert(motion_calls[2]==12 and motion_calls[3]==34,'Custom Bank/Motion IDs ignored')
layout.slots[1].useDirectMotion=false;arrange();tick()
-- Rebinding removes the previous ordinary bindings and supports mouse/gamepad/keyboard.
settings.bindings.up={keyboard='Alpha2',mouse='None',gamepad='LUp'}
settings.bindings.down={keyboard='Alpha1',mouse='R',gamepad='LDown'}
settings.bindings.sit={keyboard='Alpha4',mouse='None',gamepad='RLeft'}
settings.bindings.stand={keyboard='Alpha3',mouse='None',gamepad='Decide'}
kb_down={};gp_bits=0;mouse_bits=0;tick();state.level=1
kb_down[6]=true;tick();assert(state.level==1,'Rebinding retained old W binding')
kb_down={};mouse_bits=1;tick();assert(state.level==1,'Removed mouse-left still accelerated')
mouse_bits=0;tick();state.level=1
kb_down={};mouse_bits=0;tick();kb_down[10]=true;tick();assert(state.level==2,'Custom keyboard acceleration failed')
tick();assert(state.level==2,'Holding custom binding repeated action')
kb_down={};tick();gp_bits=64;tick();assert(state.level==3,'Custom gamepad acceleration failed')
gp_bits=0;tick();mouse_bits=2;tick();assert(state.level==3,'Removed mouse-right still decelerated')
mouse_bits=0;tick();gp_bits=1024;tick();assert(not state.active,'A did not release control')
gp_bits=0;tick()
local normal_button=imgui.button
imgui.button=function(label) return label=='Restore default driving keys' end
callbacks.ui();imgui.button=normal_button
assert(settings.bindings.up.mouse==nil and settings.bindings.stand.gamepad=='Decide'
    and settings.bindings.stand.keyboard=='Space','Restore defaults failed or retained mouse mapping')
assert(settings.bindings.up.gamepad=='RTrigTop' and settings.bindings.down.gamepad=='LTrigTop','Shoulder defaults reversed')
human.pos=vec(0,0,0);command(acquire);tick()
kb_down={};tick();kb_down[13]=true;tick()
assert(not state.active,'Default Space did not release control')
kb_down={};tick();command(acquire);tick()
local function mapping_click(label)
    local button=imgui.button
    imgui.button=function(text) return text==label end
    callbacks.ui();imgui.button=button
end
kb_down[6]=true
mapping_click('W##up_keyboard');tick()
assert(state.binding_capture and settings.bindings.up.keyboard=='W','Held opening key captured immediately')
kb_down={};tick();local speed=state.level
for _=1,10 do tick() end
assert(state.binding_capture and state.level==speed,'Idle capture ended or drove cart')
kb_down[12]=true;tick()
assert(not state.binding_capture and settings.bindings.up.keyboard=='Alpha4','Next keyboard key not captured')
tick();assert(state.level==speed,'Captured key immediately triggered acceleration')
kb_down={};tick();kb_down[12]=true;tick();assert(state.level==speed+1,'Captured binding did not work after release')
kb_down={};tick();gp_bits=16
mapping_click('LTrigTop##down_gamepad');tick()
assert(state.binding_capture,'Opening held gamepad button was captured')
gp_bits=0;tick();gp_bits=128;tick()
assert(not state.binding_capture and settings.bindings.down.gamepad=='LLeft','Next gamepad button not captured')
gp_bits=0;tick()
mapping_click('Alpha4##up_keyboard');tick()
mapping_click('Unbind##up_keyboard');tick()
assert(settings.bindings.up.keyboard=='None' and not state.binding_capture,'Explicit unbind failed')
mapping_click('E##sit_keyboard');tick()
mapping_click('Cancel mapping##sit_keyboard');tick()
assert(settings.bindings.sit.keyboard=='E' and not state.binding_capture,'Cancel mapping lost current binding')
release();mapping_click('Restore default driving keys');tick()
-- Draw suppression: no native text, GUIBase, visibility writes or cached UI.
local draw_element={}
local hud_go={call=function(_,method)
    assert(method=='get_Name','HUD attempted component lookup')
    return 'ui010201'
end}
function draw_element:call(method)
    assert(method=='get_GameObject','HUD attempted GUI field access')
    return hud_go
end
local other_element={call=function() return {call=function() return 'ui010202' end} end}
release()
assert(callbacks.gui_draw(draw_element)==true,'Inactive skill bar suppressed')
human.pos=vec(0,0,0);command(acquire);tick()
assert(callbacks.gui_draw(draw_element)==false,'Driving skill bar not hidden')
assert(state.hotbar_status=='Skill bar: hidden while driving')
assert(callbacks.gui_draw(other_element)==true,'Unrelated HUD hidden')
assert(callbacks.gui_draw(nil)==true,'Missing draw element not handled')
local failed_element={call=function() error('Unloaded component') end}
assert(callbacks.gui_draw(failed_element)==true,'Error did not allow normal drawing')
for _=1,4 do
    assert(callbacks.gui_draw(draw_element)==false)
    release()
    assert(callbacks.gui_draw(draw_element)==true,'Release did not restore drawing')
    human.pos=vec(0,0,0);command(acquire);tick()
end
callbacks.reset()
assert(callbacks.gui_draw(draw_element)==true,'Reset did not restore drawing')
human.pos=vec(0,0,0);command(acquire);tick()
status.broken=true;tick()
assert(not state.active and callbacks.gui_draw(draw_element)==true,'Cart destruction did not restore HUD')
status.broken=false
-- No enabled family layout is a recoverable configuration, not a control error.
settings.presets[2].enabled=false
select_family({body={get_GameObject=function() return {get_Name=function() return 'gm80_042_02' end} end}},false)
assert(settings.presets[settings.preset].family=='Rainy' and settings.presets[settings.preset].enabled,
    'Empty family did not get an enabled fallback')
print('PASS: cart families, animations, key capture and skill-bar draw suppression/restoration')
-- One-shot release bookmark and explicit recovery synchronize physics/fall state.
human.pos=vec(0,0,0);command(acquire);tick()
release('Cart destroyed')
assert(state.return_point and state.return_point.actor_address==address(human),'Release not recorded')
local bookmark=state.return_point
local expected=vec(human.pos.x,human.pos.y,human.pos.z)
human.pos=vec(50,-80,20)
local warps=human.test_controller.warps
return_to_release_position()
assert((human.pos-expected):length()<0.00001,'Recovery position differs')
assert(human.test_controller.warps==warps+1 and human.test_controller.position.y==expected.y,'Recovery did not synchronize physics')
assert(human.test_position_context.Position.y==expected.y and human['<FallInfo>k__BackingField']['<FallHeight>k__BackingField']==0,'Recovery did not synchronize context/fall')
release();assert(state.return_point==bookmark,'Inactive release overwrote bookmark')
state.active=true
assert(not pcall(return_to_release_position),'Recovery allowed active driving')
state.active=false
bookmark.actor_address=-1
assert(not pcall(return_to_release_position),'Recovery accepted different actor')
bookmark.actor_address=address(human)
state.return_pending=true;tick()
assert(not state.return_pending and human.pos.y==expected.y,'Recovery queue not executed')
callbacks.reset();assert(not state.return_point,'Reset retained stale recovery bookmark')
print('PASS: one-shot release bookmark, queued return, physics/fall sync and reset guards')
kb_down={};gp_bits=0;tick();human.pos=vec(2,0,1.5);body.pos=vec(0,0,0);ox.pos=vec(0,0,4)
kb_down[4]=true;tick();assert(not state.active,'Near-take accepted distance exactly 2')
kb_down={};tick();human.pos=vec(1.99,0,1.5);kb_down[4]=true;tick()
assert(state.active,'E near-take failed')
local entry_preset=settings.preset
tick();assert(settings.preset==entry_preset,'Held take key cycled on entry')
local driving_driver=state.driver
kb_down={};tick();kb_down[4]=true;tick()
assert(state.active and state.driver==driving_driver,'Active X/E repeated takeover or released driving')
release();kb_down={};gp_bits=0;tick();human.pos=vec(1,0,1.5);gp_bits=2;tick()
assert(state.active,'X near-take failed')
release();gp_bits=0;tick();settings.bindings.near_take.keyboard='Alpha2'
human.pos=vec(1,0,1.5);kb_down[4]=true;tick();assert(not state.active,'Old E binding still takes control')
kb_down={};tick();kb_down[10]=true;tick();assert(state.active,'Mapped near-take key failed')
release();kb_down={};gp_bits=0;tick()
print('PASS: mapped near-take E/X, strict distance threshold and shared Sit key')
ox.pos=vec(4,0,0)
assert(front_distance({body=body,ox=ox}, {get_Transform=function() return {get_Position=function() return vec(1.5,0,0) end} end})<0.001,
    'Front direction did not follow stationary ox/body line')
reframework=reframework or {}
local old_ui=reframework.is_drawing_ui
reframework.is_drawing_ui=function() return true end
settings.bindings.near_take.keyboard='E';human.pos=vec(1.5,0,0);kb_down={};tick();kb_down[4]=true;tick()
assert(state.active,'REFramework UI discarded near takeover')
release();reframework.is_drawing_ui=old_ui;kb_down={};tick()
-- Release-menu UI, family filtering, and player random sitting regression.
local recorded_text,recorded_nodes,layout_choices={}, {}, nil
local original_text,original_tree,original_combo=imgui.text,imgui.tree_node,imgui.combo
imgui.text=function(value) recorded_text[#recorded_text+1]=value end
imgui.tree_node=function(value) recorded_nodes[#recorded_nodes+1]=value;return true end
settings.presets={default_layout('Normal'),default_layout('Rainy'),default_layout('Normal')}
family_cursor={Normal=1,Rainy=2};settings.family_cursor=family_cursor;settings.preset=1
imgui.combo=function(label,index,choices)
    if label=='Cart type' then return true,2 end
    if label=='Active layout' then layout_choices=choices end
    return false,index
end
callbacks.ui()
assert(settings.preset==2 and #layout_choices==1 and layout_choices[1]==settings.presets[2].name,'Inactive family filter failed')
for _,node in ipairs(recorded_nodes) do assert(node~='DEBUG','DEBUG menu remains') end
for _,text in ipairs(recorded_text) do
    assert(not text:find('Shift + 1',1,true) and not text:find('Click a binding',1,true),'Tutorial text remains')
end
imgui.combo=original_combo
choose_family('Normal',false);human.pos=vec(0,0,0);ox.pos=vec(0,0,4);body.name='gm80_042_00'
command(acquire);tick()
imgui.combo=function(label,index,choices)
    if label=='Cart type' then return true,2 end
    if label=='Active layout' then layout_choices=choices end
    return false,index
end
callbacks.ui()
assert(settings.presets[settings.preset].family=='Normal' and #layout_choices==2,'Active family changed to incompatible cart')
imgui.combo=original_combo;imgui.text=original_text;imgui.tree_node=original_tree
local seated_player=state.seats[1]
assert(settings.presets[settings.preset].slots[1].randomIdle,'Player random sitting default OFF')
seated_player.next_idle=clock-1;tick()
assert(human.machine.enabled and human.am.CurrentActionList[0].Name==seated_player.pose_node,'Player random animation/FSM failed')
assert(external_request(human,seated_player.pose_node)==nil and external_request(human,'DamageSmall')=='skip','Player random pose lock stale')
settings.presets[settings.preset].slots[1].randomIdle=false
local fixed_pose=seated_player.pose_node;seated_player.next_idle=clock-1;tick()
assert(seated_player.pose_node==fixed_pose,'Disabled player random idles still ran')
local level=state.level
kb_down={[8]=true,[9]=true};gp_bits=0;tick()
assert(state.level==level,'Removed Shift+1 still accelerated')
kb_down={};tick();release()
print('PASS: compact menu, family-only preset selector, player random poses and removed modifier controls')
-- Native passenger seating blocks only conditional takeover; menu is explicit.
settings.bindings.near_take={keyboard='E',gamepad='RLeft'}
human.pos=vec(0,0,1.5);body.pos=vec(0,0,0);ox.pos=vec(0,0,4)
kb_down={};gp_bits=0;tick();passenger_controller.seated=true
kb_down[4]=true;tick();assert(not state.active,'Seated native passenger stolen from OJR')
kb_down={};tick();passenger_controller.seated=false
_G.OJR_SeatBindings={{char=human}}
kb_down[4]=true;tick();assert(not state.active,'Custom OJR passenger stolen')
_G.OJR_SeatBindings=nil;kb_down={};tick()
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=nil
kb_down[4]=true;tick();assert(not state.active and state.message:find('state unavailable',1,true),'Unknown seat state allowed takeover')
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=passenger_controller
kb_down={};tick();kb_down[3]=true;gp_bits=1;tick()
assert(not state.active,'Removed G/RT still takes control')
kb_down={};gp_bits=0;tick();passenger_controller.seated=true
state.toggle_pending=true;tick();assert(state.active,'Menu cannot explicitly take seated passenger')
kb_down[3]=true;gp_bits=1;tick();assert(state.active,'Removed G/RT still releases control')
release();passenger_controller.seated=false;kb_down={};gp_bits=0;tick()
print('PASS: native/OJR seating guards, unknown-state fallback, removed G/RT and explicit menu takeover')
-- Driver visual offset must never alter registration/root/physics/action/FSM.
-- Retain regression coverage for the temporarily disabled strategy.
driver_native_exit_testing=false
body.pos=vec(10,2,20);ox.pos=vec(14,2,20);driver.pos=vec(10,3,20)
driver.am.CurrentActionList[0].Name='SitOnChairActions'
driver_debug_bridge.freeze_enabled=true
local driver_action=driver.am.CurrentActionList[0].Name
local cart_fixture={body=body,ox=ox,driver=driver,status=status}
local before_warps,before_context,before_clear=driver.test_controller.warps,driver.test_position_context.writes,status.clear_calls or 0
local driver_root={local_position=vec(0,0.2,0),get_Valid=function() return true end,get_Parent=function() return nil end}
function driver_root:get_LocalPosition() return self.local_position end
function driver_root:set_LocalPosition(p) self.local_position=p end
function driver_root:get_Position() return vec(driver.pos.x+self.local_position.x,driver.pos.y+self.local_position.y,driver.pos.z+self.local_position.z) end
function driver_root:set_Position(p) self.local_position=p-driver.pos end
local driver_child={get_Valid=function() return true end,get_Parent=function() return driver_root end,
    set_Position=function() error('Child joint should not be offset independently') end}
function driver:get_Joints() return {get_elements=function() return {driver_root,driver_child} end} end
state.active=true;state.cart=cart_fixture
assert(prepare_driver_visual(cart_fixture,human))
apply_driver_visual()
assert(driver_root:get_Position().x==10 and driver_root:get_Position().z==20
    and math.abs(driver_root:get_Position().y-1002.2)<0.00001,'Rear visual target/animated pose incorrect')
apply_driver_visual()
assert(driver_root:get_Position().x==10,'Repeated visual offset accumulated')
assert(driver.pos.x==10 and driver.pos.y==3 and driver.pos.z==20
    and driver.test_controller.warps==before_warps and driver.test_position_context.writes==before_context
    and (status.clear_calls or 0)==before_clear and driver.am.CurrentActionList[0].Name==driver_action
    and not driver.machine.enabled,'Visual offset wrote native position or failed to freeze driver FSM')
pre_callbacks.UpdateBehavior()
assert(driver_root.local_position.x==0 and driver_root.local_position.y==0.2,'Offset not restored before behavior')
body.pos=vec(12,2,22);ox.pos=vec(12,2,26)
apply_driver_visual()
assert(driver_root:get_Position().x==12 and driver_root:get_Position().z==22,'Visual target did not follow cart rotation/movement')
release()
assert(not driver.machine.enabled and not state.visual_driver and state.driver_visual and driver_root:get_Position().z==22
    and driver.pos.x==10,'Release returned driver skeleton/root')
pre_callbacks.UpdateBehavior();callbacks.UpdateJointExpression()
assert(driver_root:get_Position().z==22,'Released driver lost visual offset next frame')
driver.pos=vec(11,3,21);callbacks.UpdateJointExpression()
assert(driver_root:get_Position().z==23,'Released driver animation/AI movement lost retained offset')
callbacks.reset()
assert(driver.machine.enabled and not state.driver_visual and driver_root.local_position.z==0 and not next(state.visual_drivers),'Reset failed to clear retained offsets/restore FSM')
driver.pos=vec(0,0,30);body.pos=vec(0,0,0);ox.pos=vec(0,0,4)
assert(not prepare_driver_visual(cart_fixture,human),'Distant driver selected')
cart_fixture.driver=nil;assert(not prepare_driver_visual(cart_fixture,human),'Missing driver not skipped')
cart_fixture.driver=human;assert(not prepare_driver_visual(cart_fixture,human),'Player mistaken for driver')
cart_fixture.driver=driver
-- Boarding cannot be distinguished by AI None alone: motion must be checked.
local stage_bank,stage_motion=0,3500
function driver:get_Motion() return {getLayer=function() return {
    get_MotionBankID=function() return stage_bank end,
    get_MotionID=function() return stage_motion end,
} end} end
driver.am.CurrentActionList[0].Name='NormalLocomotion'
assert(driver_ride_stage(cart_fixture,driver)==true,'Boarding motion mistaken for unseated')
stage_motion=3521;assert(driver_ride_stage(cart_fixture,driver)==true,'Driving motion not detected')
stage_motion=3503;assert(driver_ride_stage(cart_fixture,driver)==true,'Exit transition mistaken for unseated')
stage_bank,stage_motion=1,1020
assert(driver_ride_stage(cart_fixture,driver)==false,'Walking motion mistaken for seated')
driver.pos=vec(0,3,1);body.pos=vec(0,2,0);ox.pos=vec(0,2,4)
local root_before=driver_root.local_position
local warps_before=driver.test_controller.warps
assert(prepare_driver_visual(cart_fixture,human))
assert(driver.pos.x==0 and driver.pos.y==3 and driver.pos.z==-50
    and driver.test_controller.warps==warps_before+1
    and driver.test_position_context.Position.z==-1074
    and driver_root.local_position==root_before and not state.visual_driver,'Walking driver not physically relocated/synchronized')
release();assert(driver.pos.z==-50,'Release returned physical driver')
driver.get_Motion=nil;driver.am.CurrentActionList[0].Name='UnreadableAction'
assert(driver_ride_stage(cart_fixture,driver)==nil,'Unknown stage should remain unknown')
driver.pos=vec(0,0,1)
assert(prepare_driver_visual(cart_fixture,human) and state.visual_driver==driver,'Unknown stage did not fall back to visual offset')
callbacks.reset()
driver.am.CurrentActionList[0].Name='SitOnChairActions'
print('PASS: driver phase branching, boarding/driving visual offset, walking physical sync, no return on release, reset and unknown-stage fallback')
local pooled_driver=object('ch300680',vec(0,0,2))
local requested_ids={}
local pool_manager={getCharacter=function(_,id)
    requested_ids[id]=true
    if id==2619751808 then return pooled_driver end
end}
assert(find_nearby_driver(pool_manager,nil,body)==pooled_driver,'New driver ID pool fallback failed')
assert(requested_ids[2619751808],'New Character ID not queried')
pooled_driver.pos=vec(0,0,30)
assert(find_nearby_driver(pool_manager,nil,body)==nil,'Distant pooled driver accepted')
driver.pos=vec(0,0,1)
assert(find_nearby_driver(pool_manager,driver,body)==driver,'Registered nearby driver not preferred')
print('PASS: user-confirmed driver ID pool fallback and proximity scope')
-- Native distance never writes FOV or moves actor roots; baseline is restored.
do
local camera_manager={_DistanceOffset=0.7,get_type_definition=function() return {get_field=function(_,name) return name=='_DistanceOffset' end} end}
local original_singleton=sdk.get_managed_singleton
sdk.get_managed_singleton=function(name) if name=='app.CameraManager' then return camera_manager end return original_singleton(name) end
sdk.get_primary_camera=function() error('Distance must not access primary camera/FOV') end
local before_position=human.pos
state.active=true;current_camera().distance_enabled=true;current_camera().distance=3
update_camera_distance();assert(camera_manager._DistanceOffset==3 and human.pos==before_position,'Distance override/root scope wrong')
current_camera().distance_enabled=false;update_camera_distance()
assert(camera_manager._DistanceOffset==0.7,'Disabled distance not restored')
current_camera().distance_enabled=true;update_camera_distance();is_paused=true;update_camera_distance()
assert(camera_manager._DistanceOffset==0.7,'Paused distance not restored')
is_paused=false;update_camera_distance();state.active=false;update_camera_distance()
assert(camera_manager._DistanceOffset==0.7,'Release distance not restored')
state.active=true;update_camera_distance()
local previous_manager=camera_manager
camera_manager={_DistanceOffset=0.2,get_type_definition=previous_manager.get_type_definition}
update_camera_distance();assert(previous_manager._DistanceOffset==0.7 and camera_manager._DistanceOffset==0.2 and camera_override.suspended,
    'Manager replacement modified unrelated state')
camera_override.suspended=nil
camera_manager.get_type_definition=function() return {get_field=function() return nil end} end
update_camera_distance();assert(camera_manager._DistanceOffset==0.2,'Missing distance field still written')
state.active=false;current_camera().distance_enabled=false;sdk.get_managed_singleton=original_singleton
_G.AelinoreDriverDebugEnabled=true
driver.pos=vec(0,0,1);cart_fixture.driver=driver
begin_driver_debug(cart_fixture)
assert(driver_debug.lines[1]:find('before visual offset',1,true),'Missing pre-offset sample')
assert(prepare_driver_visual(cart_fixture,human))
assert(#driver_debug.lines==1,'Visual selection should not simulate root teleport')
poll_driver_debug();assert(#driver_debug.lines==2,'Follow-up driver sampling missing')
clock=clock+6;poll_driver_debug();assert(driver_debug.actor==nil,'Expired debug kept managed driver reference')
_G.AelinoreDriverDebugEnabled=nil;driver_debug.actor=nil
print('PASS: native camera distance/restore/paused/replacement/missing-field guards and opt-in driver snapshots')
-- Independent FOV and native distance overrides preserve separate baselines.
local fov_camera={fov=48,get_type_definition=function() return {get_method=function() return true end} end,
    call=function(self,name,value)
        if name=='get_FOV' then return self.fov end
        assert(name=='set_FOV','Unexpected camera API');self.fov=value
    end}
sdk.get_primary_camera=function() return fov_camera end
state.active=true;current_camera().fov_enabled=true;current_camera().fov=72
update_camera_fov();assert(fov_camera.fov==72,'Restored FOV option did not apply')
current_camera().fov_enabled=false;update_camera_fov();assert(fov_camera.fov==48,'FOV disable did not restore baseline')
current_camera().fov_enabled=true;update_camera_fov();is_paused=true;update_camera_fov()
assert(fov_camera.fov==48,'Paused FOV did not restore')
is_paused=false;update_camera_fov();release()
assert(fov_camera.fov==48 and not fov_override.camera,'Release FOV did not restore')
current_camera().fov_enabled=false
-- Missing skeleton fails closed; partial joint writes are restored.
driver.pos=vec(0,0,1);cart_fixture.driver=driver
state.active=true;state.cart=cart_fixture;state.player=human
assert(prepare_driver_visual(cart_fixture,human))
local original_joints=driver.get_Joints
driver.get_Joints=function() return nil end
callbacks.UpdateJointExpression()
assert(not state.visual_driver and not state.driver_visual and driver.pos.z==1,'Missing skeleton did not disable visual-only offset')
driver.get_Joints=original_joints
assert(prepare_driver_visual(cart_fixture,human))
local original_write=driver_root.set_Position
driver_root.set_Position=function(self,p) original_write(self,p);error('Injected joint write failure') end
callbacks.UpdateJointExpression()
assert(not state.visual_driver and not state.driver_visual and driver_root.local_position.z==0,'Failed write retained offset')
driver_root.set_Position=original_write
assert(prepare_driver_visual(cart_fixture,human));apply_driver_visual()
callbacks.reset()
assert(not state.visual_driver and not state.driver_visual and driver_root.local_position.z==0,'Reset retained driver offset')
print('PASS: independent FOV restore and driver skeleton unavailable/error/reset cleanup')
end
local diagnostic_reads=0
local nested_ai={get_type_definition=function() return {
    get_full_name=function() return 'app.OxcartAI' end,
    get_methods=function() return {{get_name=function() return 'ExitSeat' end,
        get_num_params=function() return 0 end,get_return_type=function() return {get_full_name=function() return 'System.Void' end} end}} end,
    get_fields=function() return {{get_name=function() return '_Seat' end}} end,
} end,call=function() error('Candidate exit method was invoked') end}
local diagnostic_status={get_type_definition=function() return {
    get_method=function(_,name) return {get_num_params=function() return name=='setDriver' and 1 or 0 end} end,
    get_methods=function() return {} end,get_full_name=function() return 'app.OxcartStatus' end,
} end,call=function(_,name)
    diagnostic_reads=diagnostic_reads+1
    if name=='get_oxcartAI' then return nested_ai end
    if name=='get_QuestForceSitDownDriver' then return true end
    if name=='getCurrentDriver' then return 123 end
    assert(name=='getDriver','Unexpected diagnostic call');return nil
end}
cart_fixture.status=diagnostic_status;_G.AelinoreDriverDebugEnabled=true
begin_driver_debug(cart_fixture)
assert(driver_debug.lines[1]:find('forceSit=true',1,true),'Force-seat flag not captured')
assert(table.concat(driver_debug.methods,'\n'):find('app.OxcartAI.ExitSeat',1,true),'Nested binding methods not collected')
assert(driver_debug_get(diagnostic_status,'setDriver')==nil,'Diagnostic invoked parameter-taking method')
clock=clock+6;poll_driver_debug()
assert(driver_debug.cart==nil and driver_debug.actor==nil,'Diagnostic kept binding objects after recording')
_G.AelinoreDriverDebugEnabled=nil
print('PASS: read-only force-seat/driver ID/nested binding metadata and expired-reference cleanup')
do
local writes,payload,log_name=0
local original_dump=json.dump_file
json.dump_file=function(path,data) writes=writes+1;log_name=path;payload=data end
state.active=false;driver.pos=vec(0,0,1)
local clear_calls=status.clear_calls or 0
local previous_action=driver.am.CurrentActionList[0].Name
assert(driver_debug_bridge.start(),'Native lifecycle start failed')
driver_debug_bridge.mark('Driver not seated')
clock=clock+6;poll_driver_debug()
assert(driver_debug.actor and driver_debug.lifecycle and writes==0,'Native trace stopped after five seconds or wrote every sample')
driver_debug_bridge.mark('Driver seated');driver_debug_bridge.mark('Cart driving')
assert(not state.active and (status.clear_calls or 0)==clear_calls and driver.pos.z==1
    and driver.am.CurrentActionList[0].Name==previous_action,'Native recorder changed driving state')
assert(driver_debug_bridge.stop() and writes==1 and log_name:match('%.log$'),'Stop did not write one LOG')
assert(payload.mode=='native driver lifecycle' and table.concat(payload.lines,'\n'):find('Cart driving',1,true)
    and payload.actor==nil and payload.cart==nil and not driver_debug.actor and not driver_debug.cart,
    'Native trace markers or scalar export/reference cleanup incorrect')
_G.AelinoreDriverDebugEnabled=true
begin_driver_debug(cart_fixture);clock=clock+6;poll_driver_debug()
assert(writes==2 and payload.reason=='5 seconds complete','Takeover trace not auto-saved')
_G.AelinoreDriverDebugEnabled=nil;json.dump_file=original_dump
print('PASS: read-only lifecycle trace, stage markers, long duration and one-shot automatic LOG export')
end
do
local original_index=settings.preset
local original_camera_settings=copy_camera(current_camera())
local original_get=sdk.get_managed_singleton
local manager={_DistanceOffset=0.6,get_type_definition=function() return {get_field=function() return true end} end}
local camera={fov=44,get_type_definition=function() return {get_method=function() return true end} end,
    call=function(self,name,value) if name=='get_FOV' then return self.fov end assert(name=='set_FOV');self.fov=value end}
sdk.get_managed_singleton=function(name) if name=='app.CameraManager' then return manager end return original_get(name) end
sdk.get_primary_camera=function() return camera end
local first=current_camera()
first.fov_enabled,first.fov,first.distance_enabled,first.distance=true,70,true,2
local duplicate=copy_layout(settings.presets[settings.preset],'Camera test','Normal')
assert(duplicate.camera~=first and duplicate.camera.fov==70 and duplicate.camera.distance==2,'Copied preset lost/shared camera settings')
duplicate.camera.fov,duplicate.camera.distance=85,4
settings.presets[#settings.presets+1]=duplicate
state.active=true;update_camera_fov();update_camera_distance()
assert(camera.fov==70 and manager._DistanceOffset==2,'Initial preset camera values not applied')
settings.preset=#settings.presets;update_camera_fov();update_camera_distance()
assert(camera.fov==85 and manager._DistanceOffset==4 and first.fov==70,'Switch did not apply independent preset')
duplicate.camera.fov_enabled,duplicate.camera.distance_enabled=false,false
update_camera_fov();update_camera_distance()
assert(camera.fov==44 and manager._DistanceOffset==0.6,'Disabled preset did not restore true original values')
duplicate.camera.fov_enabled,duplicate.camera.distance_enabled=true,true
update_camera_fov();update_camera_distance();release()
assert(camera.fov==44 and manager._DistanceOffset==0.6,'Release after cycling restored previous preset instead of baseline')
table.remove(settings.presets);settings.preset=original_index;settings.presets[original_index].camera=original_camera_settings
sdk.get_managed_singleton=original_get
local old_checkbox,old_slider=imgui.checkbox,imgui.slider_float
local labels={}
imgui.checkbox=function(name,value) labels[#labels+1]=name;return false,value end
imgui.slider_float=function(name,value) labels[#labels+1]=name;return false,value end
callbacks.ui();imgui.checkbox,imgui.slider_float=old_checkbox,old_slider
local order=table.concat(labels,'|')
assert(order:find('FOV (degrees)',1,true)<order:find('Camera offset',1,true)
    and order:find('Camera distance',1,true)<order:find('Camera offset',1,true),'Player camera controls not above Camera offset')
print('PASS: per-preset camera copy/cycling/disabled restore/release and Player driver UI placement')
end
do
local cart={driver=driver,status=status,body=body,ox=ox}
_G.AelinoreDriverDebugEnabled=true;begin_driver_debug(cart)
state.active=false
local name={ToString=function() return 'NativeDriverExitTest' end}
local primary=hooks['requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)']
assert(primary({nil,driver.am,1,name,0})==nil,'Read-only driver trace blocked native action')
assert(#driver_debug.events==1 and driver_debug.events[1]:find('NativeDriverExitTest',1,true)
    and driver_debug.events[1]:find('priority=1',1,true),'Driver request name/priority not captured')
primary({nil,human.am,1,name,0});assert(#driver_debug.events==1,'Trace included unrelated player request')
local original_call=status.call
local original_type=status.get_type_definition
status.get_type_definition=function() return {get_method=function(_,name)
    if name=='get_oxcartAI' then return {get_num_params=function() return 0 end} end
end} end
local ai={get_address=function() return 98765 end}
status.call=function(self,method) if method=='get_oxcartAI' then return ai end return original_call(self,method) end
assert(hooks.forceSitDown({nil,ai,0})==nil and hooks.InterractSeatForce({nil,ai,1})==nil,
    'Native seat event trace blocked execution')
assert(#driver_debug.events==3 and driver_debug.events[2]:find('forceSitDown',1,true)
    and driver_debug.events[3]:find('InterractSeatForce',1,true),'Native seat calls not captured')
status.call=original_call
status.get_type_definition=original_type
driver_debug.actor,driver_debug.cart=nil,nil;_G.AelinoreDriverDebugEnabled=nil
print('PASS: read-only selected-driver action requests and selected-cart seat event hooks')
end
do
local original_motion=driver.get_Motion
local original_dump=json.dump_file
local played,payload,writes=nil,nil,0
local layer={get_MotionBankID=function() return 0 end,get_MotionID=function() return played or 3521 end,
    call=function(_,signature,bank,id)
        assert(signature:find('changeMotion',1,true) and bank==0 and (id==3513 or id==3514));played=id
    end}
driver.get_Motion=function() return {getLayer=function() return layer end} end
json.dump_file=function(_,data) payload=data;writes=writes+1 end
state.active=false;driver.pos=vec(0,0,1)
local original_action=driver.am.CurrentActionList[0].Name
local cleared=status.clear_calls or 0
assert(driver_debug_bridge.test_exit(3513) and not played,'Exit animation was not queued')
is_paused=true;poll_driver_debug();assert(not played,'Exit animation played in paused GUI')
is_paused=false;poll_driver_debug()
assert(played==3513 and driver.pos.z==1 and driver.machine.enabled and (status.clear_calls or 0)==cleared
    and driver.am.CurrentActionList[0].Name==original_action,'Exit test changed registration/FSM/position/action node')
clock=clock+21;poll_driver_debug()
assert(payload.mode=='driver exit animation test 0/3513' and payload.reason=='20 second driver exit test complete'
    and writes==1 and not driver_debug.actor,'Exit test did not auto-export and stop')
assert(driver_debug_bridge.test_exit(3514));poll_driver_debug();assert(played==3514,'Second exit test ID not played')
clock=clock+21;poll_driver_debug()
state.active=true;assert(not driver_debug_bridge.test_exit(3513),'Exit test allowed manual-driver conflict');state.active=false
assert(not driver_debug_bridge.test_exit(3503),'Unapproved animation ID accepted')
driver.get_Motion=original_motion;json.dump_file=original_dump
print('PASS: queued 3513/3514 exit animation tests, pause/ownership guards, no position/FSM/registration changes and automatic LOG')
end
do
local old_tree,old_pop,old_button,old_slider=imgui.tree_node,imgui.tree_pop,imgui.button,imgui.slider_float
local old_begin,old_row,old_column,old_header,old_end,old_text=imgui.begin_table,imgui.table_next_row,imgui.table_next_column,imgui.table_header,imgui.end_table,imgui.text
local stack,headers={},{}
local row,column,rows,ended=0,0,{},false
local general_button,general_slider=false,false
imgui.tree_node=function(name) stack[#stack+1]=name;return true end
imgui.tree_pop=function() table.remove(stack) end
imgui.button=function(label)
    if label=='Take control' or label=='Release control' then general_button=stack[#stack]=='General settings' end
    return false
end
imgui.slider_float=function(label,value)
    if label=='Steering sensitivity (degrees/s)' then general_slider=stack[#stack]=='General settings' end
    return false,value
end
imgui.begin_table=function(name,count,flags) assert(name=='Driving keybinds' and count==3 and flags==1);return true end
imgui.table_next_row=function() row=row+1;column=0;rows[row]={} end
imgui.table_next_column=function() column=column+1;assert(column<=3,'Overflowing table column') end
imgui.table_header=function(name) headers[column]=name end
imgui.text=function(text)
    assert(not text:find('distance < 2',1,true),'Threshold text remains')
    if row>0 and column>0 and not ended then rows[row][column]=text end
end
imgui.end_table=function() ended=true end
callbacks.ui()
assert(general_button and general_slider and ended and #rows==6,'General settings/table structure incorrect')
assert(headers[1]=='Action' and headers[2]=='Gamepad' and headers[3]=='Keyboard' and headers[4]==nil,'Table headers misaligned')
assert(rows[2][1]=='Take control' and rows[5][4]==nil and rows[6][4]==nil,'Action/mouse columns misaligned')
imgui.tree_node,imgui.tree_pop,imgui.button,imgui.slider_float=old_tree,old_pop,old_button,old_slider
imgui.begin_table,imgui.table_next_row,imgui.table_next_column,imgui.table_header,imgui.end_table,imgui.text=old_begin,old_row,old_column,old_header,old_end,old_text
driver.pos=vec(0,0,1);body.pos=vec(0,0,0);ox.pos=vec(0,0,4)
driver.am.CurrentActionList[0].Name='SitOnChairActions';driver.machine.enabled=false
assert(prepare_driver_visual({driver=driver,body=body,ox=ox,status=status},human))
callbacks.reset();assert(not driver.machine.enabled,'Reset lost originally disabled driver FSM')
driver.machine.enabled=true;driver.am.CurrentActionList[0].Name='UnreadableAction'
assert(prepare_driver_visual({driver=driver,body=body,ox=ox,status=status},human))
assert(driver.machine.enabled,'Unknown driver stage froze FSM')
callbacks.reset()
print('PASS: four-column keybind table, General settings placement, default Space, phase-only FSM freeze and original-state restore')
end
do
local old_type,old_call=status.get_type_definition,status.call
local old_hook,old_ptr=sdk.hook,sdk.to_ptr
local old_thread=thread
local storage,combat_hooks={},{}
local function_version=1
local old_address=status.get_address
status.get_address=function() return 987 end
thread={get_hook_storage=function() return storage end}
sdk.to_ptr=function(value) return value end
sdk.hook=function(method,pre,post,ignore_jmp) assert(ignore_jmp==true);combat_hooks[method]={pre=pre,post=post} end
status.get_type_definition=function()
    return {get_method=function(_,name)
        if name=="isDriverBattleMode" or name=="isAnyoneBattleMode" then
            return {get_num_params=function() return 0 end,
                get_function=function() return function_version==0 and 0 or name..tostring(function_version) end,
                get_return_type=function() return {get_name=function() return "Boolean" end} end,
                name=name}
        end
    end}
end
local native_calls={}
status.call=function(self,name,...)
    if name=="isDriverBattleMode" or name=="isAnyoneBattleMode" then
        native_calls[name]=(native_calls[name] or 0)+1
        for method,hook in pairs(combat_hooks) do
            if method.name==name then local skipped=hook.pre({nil,self})==sdk.PreHookResult.SKIP_ORIGINAL;return hook.post(skipped and -999 or 0)==1 end
        end
        return false
    end
    return old_call(self,name,...)
end
driver_combat.hooks={};driver_combat.cleanup()
body.pos=vec(0,0,0);ox.pos=vec(0,0,4);driver.pos=vec(0,3,1)
driver.machine.enabled=true
local driver_human=driver["<Human>k__BackingField"]
local player_human=human["<Human>k__BackingField"]
driver_human.call=function(_,name) assert(name=="get_IsBattleMode()");return false end
player_human.call=function(_,name) assert(name=="get_IsBattleMode()");return true end
driver_debug_bridge.combat_read();driver_combat.poll()
local view=driver_debug_bridge.combat_read()
assert(view.driver_fsm==true and view.driver_battle==false and view.player_battle==true,'Battle/FSM live reads incorrect')
assert(driver_debug_bridge.combat_set("isDriverBattleMode",true))
assert(driver_debug_bridge.combat_set("isAnyoneBattleMode",true))
assert(not driver_debug_bridge.combat_set("OtherMethod",true),'Unknown battle override accepted')
driver_combat.poll();view=driver_debug_bridge.combat_read()
assert(view.isDriverBattleMode and view.isAnyoneBattleMode and not view.native.isDriverBattleMode,'Override/observed values not separated')
for method,hook in pairs(combat_hooks) do
    hook.pre({nil,human});assert(hook.post(0)==0,'Cart override leaked to unrelated object')
end
driver_debug_bridge.combat_set("isDriverBattleMode",false);driver_combat.poll()
assert(not driver_debug_bridge.combat_read().isDriverBattleMode,'Unchecking override did not restore natural result')
driver_debug_bridge.combat_set("freeze",true);driver_combat.poll()
assert(not driver.machine.enabled and driver_debug_bridge.combat_read().driver_fsm==false,'FSM not frozen/read back')
driver_debug_bridge.combat_set("freeze",false);driver_combat.poll()
assert(driver.machine.enabled,'FSM unfreeze failed')
driver_debug_bridge.teleport_driver()
is_paused=true;driver_combat.poll();assert(driver.pos.z==1,'Teleport ran while paused')
is_paused=false;local warp_count=driver.test_controller.warps
driver_combat.poll()
assert(driver.pos.z==-500 and driver.pos.y==3 and driver.test_controller.warps==warp_count+1
    and driver.test_position_context.Position.z==-1524,'500-unit teleport not physically synchronized')
driver.pos.z=-490;clock=clock+0.3;driver_combat.poll()
assert(driver.test_controller.warps==warp_count+1 and driver.pos.z==-490,'Teleport repeated/pinned driver')
driver_debug_bridge.combat_reset();driver_combat.poll()
assert(not next(driver_combat.flags) and not driver_debug_bridge.freeze_enabled and driver.machine.enabled,'Clear overrides/unfreeze failed')
driver_combat.cleanup();driver_debug_bridge.freeze_enabled=false
-- Early/unready entries retry without requiring script reload; changed entries reinstall.
driver_combat.entries,driver_combat.retry_at,driver_combat.hooks={},{},{}
function_version=0
driver_combat.install(status,'isAnyoneBattleMode')
assert(driver_combat.hooks.isAnyoneBattleMode~=true,'Zero function entry was hooked')
function_version=1;clock=clock+1.1;driver_combat.install(status,'isAnyoneBattleMode')
assert(driver_combat.hooks.isAnyoneBattleMode==true,'Unready hook did not retry')
function_version=2;driver_combat.install(status,'isAnyoneBattleMode')
assert(driver_combat.entries['isAnyoneBattleMode:isAnyoneBattleMode2'],'Changed entry not hooked')
driver.am.CurrentActionList[0].Name='SitOnChairActions'
driver.pos=vec(0,3,1);body.pos=vec(0,2,0);ox.pos=vec(0,2,4)
driver.machine.enabled=true
local cart={driver=driver,status=status,body=body,ox=ox}
local warps_before=driver.test_controller.warps
assert(prepare_driver_visual(cart,human))
state.active=true;state.cart=cart;apply_driver_visual()
assert(driver_root:get_Position().x==0 and driver_root:get_Position().z==0
    and math.abs(driver_root:get_Position().y-1002.2)<0.00001
    and driver.pos.z==1 and driver.test_controller.warps==warps_before and driver.machine.enabled,
    'Automatic takeover did not use 1000-unit visual-only offset with FSM untouched')
assert(status:call('isAnyoneBattleMode'),'Automatic battle stop requires debug panel')
assert(driver_combat.wait_active(ox) and ox.am.CurrentActionList[0].Name=='Wait','Immediate Wait not requested')
ox.am:call('',0,'Run',0);assert(ox.am.CurrentActionList[0].Name=='Wait','Battle-entry Run escaped one-second guard')
release();assert(status:call('isAnyoneBattleMode'),'Release removed automatic battle override')
ox.am:call('',0,'Run',0);assert(ox.am.CurrentActionList[0].Name=='Wait','Guard stopped on release')
local other_name=human.am.CurrentActionList[0].Name
human.am:call('',0,'Run',0);assert(human.am.CurrentActionList[0].Name=='Run','Guard leaked to player')
human.am.CurrentActionList[0].Name=other_name
clock=clock+1.1;driver_combat.update_waits()
ox.am:call('',0,'Run',0);assert(ox.am.CurrentActionList[0].Name=='Run','Wait guard did not expire')
driver.invalid=true;clock=clock+0.3;driver_combat.poll()
assert(not next(driver_combat.rules),'Unloaded driver retained automatic battle rule')
driver.invalid=nil
callbacks.reset();assert(not next(driver_combat.rules) and not next(driver_combat.waits),'Reset retained automatic rules/Wait guard')
driver_debug_bridge.freeze_enabled=true
status.get_type_definition,status.call=old_type,old_call
status.get_address=old_address
sdk.hook,sdk.to_ptr,thread=old_hook,old_ptr,old_thread
driver_human.call,player_human.call=nil,nil
print('PASS: scoped combat return overrides, native/effective readback, actual FSM freeze/unfreeze, queued 500-unit one-shot teleport and reset')
end
do
driver_combat.cleanup();restore_driver_visual();state.visual_drivers={}
state.active=false;driver.pos=vec(0,3,1);body.pos=vec(0,2,0);ox.pos=vec(0,2,4)
driver.machine.enabled=true
local gm=ox.EnemyCtrl.Ch2["<CachedOxcart>k__BackingField"]
local old_type,old_call=gm.get_type_definition,gm.call
local calls,writes=0,0
local old_dump=json.dump_file
json.dump_file=function(_,payload) writes=writes+1;assert(payload.mode=='native DrivingSeat.freeGetOff test');return true end
local seat={SitChara=driver,Status=2}
function seat:get_type_definition()
    return {get_method=function(_,name)
        if name=='end' or name=='freeGetOff' or name=='isSit' or name=='isSitting' or name=='get_IsInteract' then
            return {get_num_params=function() return 0 end,
                get_return_type=function() return {get_full_name=function() return (name=='end' or name=='freeGetOff') and 'System.Void' or 'System.Boolean' end} end}
        end
    end}
end
function seat:call(name)
    if name=='freeGetOff()' then calls=calls+1;self.SitChara=nil;self.Status=5;return end
    if name=='end()' then calls=calls+1;self.SitChara=nil;self.Status=0;return end
    if name=='isSit' or name=='isSitting' or name=='get_IsInteract' then return self.SitChara~=nil end
    error('Unexpected seat call '..name)
end
gm.get_type_definition=function() return {get_method=function(_,name)
    if name=='get_DrivingSeat' then return {get_num_params=function() return 0 end} end
end} end
gm.call=function(self,name,...) if name=='get_DrivingSeat' then return seat end;return old_call(self,name,...) end
local position=driver.pos
local warp_before,context_before=driver.test_controller.warps,driver.test_position_context.writes
local clear_before=status.clear_calls or 0
local action_before=driver.am.CurrentActionList[0].Name
assert(driver_debug_bridge.test_native_exit() and calls==0,'Native test not queued')
assert(not driver_debug_bridge.test_native_exit(),'Duplicate native test queued')
is_paused=true;poll_driver_debug();assert(calls==0,'Native test executed while paused')
is_paused=false;poll_driver_debug()
assert(calls==1 and driver.pos==position and driver.test_controller.warps==warp_before
    and driver.test_position_context.writes==context_before and (status.clear_calls or 0)==clear_before
    and driver.machine.enabled and driver.am.CurrentActionList[0].Name==action_before
    and not next(driver_combat.rules),'Native test injected extra mutations')
assert(table.concat(driver_debug.lines,'\n'):find('before freeGetOff',1,true)
    and table.concat(driver_debug.lines,'\n'):find('seat.matchesDriver=false',1,true),'Native binding snapshots absent')
clock=clock+21;poll_driver_debug()
assert(writes==1 and calls==1 and not driver_debug.driving_seat,'Native test repeated or retained seat/log not saved')
json.dump_file=old_dump
seat.SitChara=human
assert(driver_debug_bridge.test_native_exit());poll_driver_debug()
assert(calls==1 and driver_debug.result:find('not the selected driver',1,true),'Wrong occupant invoked freeGetOff')
seat.SitChara=driver
driver_combat.flags.isAnyoneBattleMode=true
assert(driver_debug_bridge.test_native_exit());poll_driver_debug()
assert(calls==1 and driver_debug.result:find('Existing battle',1,true),'Battle-overridden test executed')
driver_combat.cleanup()
driver.machine.enabled=false
assert(driver_debug_bridge.test_native_exit());poll_driver_debug()
assert(calls==1 and driver_debug.result:find('FSM is disabled',1,true),'Frozen driver test executed')
driver.machine.enabled=true
state.active=true;assert(not driver_debug_bridge.test_native_exit(),'Active driving accepted native test');state.active=false
seat.SitChara=driver;seat.Status=3
assert(driver_debug_bridge.finish_native_exit());poll_driver_debug()
assert(calls==1 and driver_debug.result:find('not FreeGetOff',1,true),'Seat end allowed before FreeGetOff')
seat.Status=5
local snapshots=0
json.dump_file=function(_,payload)
    snapshots=snapshots+1
    assert(payload.mode=='native DrivingSeat.end test')
    return true
end
assert(driver_debug_bridge.finish_native_exit())
is_paused=true;poll_driver_debug();assert(calls==1,'Seat end ran while paused')
is_paused=false;poll_driver_debug()
assert(calls==2 and seat.Status==0 and not seat.SitChara and snapshots==1
    and driver.pos==position and driver.test_controller.warps==warp_before
    and driver.test_position_context.writes==context_before and not next(driver_combat.rules)
    and not next(driver_combat.waits),'Seat end added mutations or missed immediate LOG')
poll_driver_debug();assert(calls==2,'Seat end repeated')
clock=clock+601;poll_driver_debug();assert(snapshots==2 and not driver_debug.driving_seat,'Seat end retained stale references')
json.dump_file=old_dump
do
local old_driver_type,old_driver_call=driver.get_type_definition,driver.call
local cleanup_calls,task_count,saved=0,2,0
local task={_State=1,TaskData={get_type_definition=function() return {get_full_name=function() return 'TestTaskData' end} end},
    get_type_definition=function() return {get_full_name=function() return 'TestTask' end} end}
local list={get_type_definition=function() return {get_method=function(_,name)
    if name=='get_Count' then return {get_num_params=function() return 0 end} end
end} end}
function list:call(name,index)
    if name=='get_Count' then return task_count end
    assert(name=='get_Item(System.Int32)' and index>=0 and index<task_count,'Unbounded task list access')
    return task
end
local agent={get_type_definition=function() return {get_method=function(_,name)
    if name=='cancelInteract' or name=='endGimmickAction' or name=='getCurrentTaskList' then
        return {get_num_params=function() return 0 end,get_return_type=function()
            return {get_full_name=function() return 'System.Void' end} end}
    end
end} end}
function agent:call(name)
    if name=='getCurrentTaskList' then return list end
    assert(name=='cancelInteract()' or name=='endGimmickAction()','Unexpected cleanup mutation')
    cleanup_calls=cleanup_calls+1;task_count=task_count-1
    seat.Status=0;seat.SitChara=nil
end
driver.get_type_definition=function() return {get_method=function(_,name)
    if name=='get_AISituationAgent' then return {get_num_params=function() return 0 end} end
end} end
driver.call=function(self,name,...) if name=='get_AISituationAgent' then return agent end;return old_driver_call(self,name,...) end
json.dump_file=function(_,payload) saved=saved+1;return true end
seat.Status=3;seat.SitChara=driver
assert(driver_debug_bridge.test_interaction_cleanup('cancelInteract'));poll_driver_debug()
assert(cleanup_calls==0,'Cleanup accepted a seated driver')
seat.Status=5
assert(driver_debug_bridge.test_interaction_cleanup('cancelInteract'))
assert(not driver_debug_bridge.test_interaction_cleanup('endGimmickAction'),'Duplicate cleanup queued')
is_paused=true;poll_driver_debug();assert(cleanup_calls==0,'Cleanup ran while paused')
is_paused=false;poll_driver_debug()
assert(cleanup_calls==1 and saved>=2 and driver_debug.mode=='native driver interaction cleanup','Cleanup or phase saves missing')
local path=driver_debug.log_path
assert(driver_debug_bridge.test_interaction_cleanup('endGimmickAction'));poll_driver_debug()
assert(cleanup_calls==2 and task_count==0 and driver_debug.log_path==path,'Second cleanup lost shared trace')
local events=table.concat(driver_debug.events,'\n')
assert(events:find('tasks.count=2',1,true) and events:find('tasks.count=0',1,true)
    and events:find('CALL cancelInteract: returned',1,true)
    and events:find('CALL endGimmickAction: returned',1,true),'Probe evidence missing')
local previous_saved=saved;clock=clock+11;poll_driver_debug()
assert(saved==previous_saved+1 and cleanup_calls==2,'Checkpoint repeated a mutation or did not save')
assert(driver.pos==position and driver.test_controller.warps==warp_before
    and driver.test_position_context.writes==context_before and driver.machine.enabled
    and not next(driver_combat.rules) and not next(driver_combat.waits),'Cleanup injected root/FSM/battle/Wait changes')
clock=clock+601;poll_driver_debug()
driver.get_type_definition,driver.call=old_driver_type,old_driver_call
json.dump_file=old_dump
print('PASS: isolated agent cleanup calls, staged task probes, shared LOG, checkpoint saves and no unrelated mutations')
end
do
seat.Status=3;seat.SitChara=driver
assert(driver_debug_bridge.test_driver_passenger());poll_driver_debug()
assert(not state.test_passenger_driver,'Passenger test accepted a still-seated driver')
seat.Status=5
local previous_position=driver.pos
assert(driver_debug_bridge.test_driver_passenger())
is_paused=true;poll_driver_debug();assert(not state.test_passenger_driver,'Passenger test ran while paused')
is_paused=false;poll_driver_debug()
assert(state.test_passenger_driver==driver and driver.pos==previous_position and driver.machine.enabled,
    'Arming passenger test moved/froze driver')
state.active=true;state.player=human;state.cart=cart_fixture
cart_fixture.anchor=body;cart_fixture.cow=ox:get_Transform()
state.seats={};settings.debug_player_position_sync=true;settings.debug_player_reset_fall=true
arrange()
local passenger
for _,record in ipairs(state.seats) do if record.driver_passenger then passenger=record end end
assert(passenger and passenger.actor==driver and passenger.pawn and passenger.custom_slot
    and passenger.pose_node=='SitOnChairActions' and driver.machine.enabled,'Driver did not reuse live pawn sitting')
local warp_count,fall_count=driver.test_controller.warps,driver.test_fall.reset_calls
constrain_seats(true)
assert(driver.test_controller.warps>warp_count and driver.test_fall.reset_calls>fall_count,
    'Driver passenger missed physics synchronization/fall reset')
arrange()
local count=0
for _,record in ipairs(state.seats) do if record.driver_passenger then count=count+1 end end
assert(count==1 and not next(driver_combat.rules) and not next(driver_combat.waits),
    'Preset duplicated driver or injected combat/Wait overrides')
release('passenger test complete')
assert(not state.test_passenger_driver and not state.test_passenger_cart and #state.seats==0
    and driver.machine.enabled,'Passenger release retained ownership or froze driver')
print('PASS: opt-in driver passenger, native seat/paused guards, pawn pose and physics/fall reuse, preset retention and release')
end
gm.get_type_definition,gm.call=old_type,old_call
print('PASS: queued native freeGetOff, exact occupant guard, isolated one-shot call, binding snapshots, 20-second LOG and no extra root/FSM/AI/animation changes')
end
driver_native_exit_testing=true
driver_combat.cleanup()
state.visual_drivers={}
driver.pos=body.pos
driver.am.CurrentActionList[0].Name='SitOnChairActions'
driver_debug_bridge.freeze_enabled=true
local root_before=driver.pos
local warps_before=driver.test_controller.warps
local context_before=driver.test_position_context.writes
assert(not prepare_driver_visual(cart_fixture,human),'Native exit testing allowed seated driver evacuation')
assert(driver.pos==root_before and driver.test_controller.warps==warps_before
    and driver.test_position_context.writes==context_before and driver.machine.enabled
    and not next(state.visual_drivers) and not next(driver_combat.rules)
    and not next(driver_combat.waits),'Native exit testing mutated driver/root/FSM/battle/ox Wait')
driver.am.CurrentActionList[0].Name='NormalLocomotion'
assert(not prepare_driver_visual(cart_fixture,human),'Native exit testing allowed unseated driver teleport')
assert(driver.pos==root_before and driver.test_controller.warps==warps_before
    and driver.test_position_context.writes==context_before and driver.machine.enabled
    and not next(state.visual_drivers) and not next(driver_combat.rules)
    and not next(driver_combat.waits),'Unseated driver isolation injected automatic changes')
print('PASS: production native-exit isolation skips all driver relocation, freezing, battle override and Wait')
do
local previous_dump=json.dump_file
local saves,paths,payloads=0,{},{}
json.dump_file=function(path,payload)
    saves=saves+1;paths[saves]=path;payloads[saves]=payload
end
driver_debug_bridge.road_control(true);driver_debug_bridge.road_poll()
assert(driver_debug_bridge.road_read().active and saves==1,'Road recording failed to start/save')
local original_human=human['<Human>k__BackingField']
local restorer={get_address=function() return 909090 end}
human['<Human>k__BackingField']={['<CoordRestorerOnOxcart>k__BackingField']=restorer}
driver_debug_bridge.road_native('onWarp',restorer)
driver_debug_bridge.road_mark()
local found
for _,event in ipairs(payloads[saves].events) do if event.name=='onWarp' then found=event end end
assert(found and found.detail.roles[1]=='player' and found.detail.actor==address(human)
    and found.detail.game_object==address(human:get_GameObject()) and found.detail.name,
    'Warp source identity/role missing')
human['<Human>k__BackingField']=original_human
local position_before=driver.pos
for i=1,132 do clock=clock+0.25;driver_debug_bridge.road_poll() end
assert(saves>=4 and #payloads[saves].prehistory<=120,'Road ring/checkpoint not bounded')
assert(payloads[saves].samples[1].player.position and payloads[saves].samples[1].cart_position,
    'Road state snapshots missing')
assert(payloads[saves].samples[1].player.identity.actor==address(human),'Snapshot actor identity missing')
local previous_saves=saves
driver_debug_bridge.road_mark()
assert(saves==previous_saves+1 and payloads[saves].events[#payloads[saves].events].name=='black_screen_manual_delayed',
    'Manual black-screen mark was not saved immediately')
driver_debug_bridge.road_damage({['<DamageGameObject>k__BackingField']=body:get_GameObject(),Damage=99999})
driver_debug_bridge.road_control(false);driver_debug_bridge.road_poll()
assert(not driver_debug_bridge.road_read().active and driver.pos==position_before,
    'Road recorder did not stop or mutated an actor')
for i=2,#paths do assert(paths[i]~=paths[i-1],'Road chunks overwrite prior evidence') end
assert(payloads[saves].events[1].name=='damage_before_reduction','Damage probe did not save')
json.dump_file=previous_dump
print('PASS: road recorder, bounded prehistory, 4 Hz snapshots, unique checkpoint chunks, immediate black-screen mark, damage and stop')
end
end)()
