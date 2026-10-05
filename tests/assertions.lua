-- Legacy relocation regressions run explicitly; production isolation is checked below.
driver_native_exit_testing=false
local function tick(dt)
    clock=clock+(dt or 1/60)
    callbacks.UpdateHID(); callbacks.LateUpdateBehavior(); callbacks.frame()
end
local suspends,resumes=0,0
assert(settings.presets[1].family=='Normal' and settings.presets[2].family=='Rainy' and settings.presets[3].family=='Wealthy',
    'Fresh defaults omit cart families')
assert(settings.presets[1].slots[1].x==0.029 and settings.presets[1].player_visual.offset.z==-4.044,
    'Normal screenshot default differs')
assert(settings.presets[2].slots[1].x==-0.051 and settings.presets[2].player_visual.offset.x==-2.102
    and settings.presets[2].player_visual.offset.y==-0.411,'Rainproof screenshot default differs')
-- Historical baseline regression fixture, independent of new measured defaults.
settings.presets={copy_layout(settings.presets[1],'Regression','Normal')};settings.preset=1
family_cursor={Normal=1}
settings.presets[1].pawns_customized=false
settings.presets[1].player_visual={enabled=false,offset={x=0,y=0,z=0}}
settings.presets[1].slots[1]={x=-0.071,y=0.920,z=0.274,yaw=178}
assert(settings.debug_player_freeze==false and settings.debug_player_pose_lock==true,'New defaults retain legacy FSM freeze')
-- Preserve existing legacy-FSM regression coverage; new pose-lock coverage
-- below uses the production default (FSM running).
settings.debug_player_freeze=true
bus.journey={suspend=function() suspends=suspends+1 end,resume=function() resumes=resumes+1 end,
    passenger_layout=function() return {
        {x=1,y=0.4,z=-3,lookX=1,lookZ=0,anim='LivSitChairCrosslegs',freezeFsm=true},
        {x=-1,y=0.4,z=-3,lookX=-1,lookZ=0,anim='LivSitChairLean',freezeFsm=true},
        {x=1,y=0.4,z=-4,lookX=0,lookZ=1,anim='SitOnChairCrossArmStart',freezeFsm=true},
    } end}
human.pos=vec(0.3,0.2,-2)
command(acquire)
assert(state.active and bus.owner==TITLE and suspends==1, state.error)
assert(#state.seats==4 and driver.machine.enabled and human.machine.enabled,'Driver frozen or player froze before action initialization')
assert(settings.presets[1].slots[1].x==-0.071 and settings.presets[1].slots[1].y==0.920
    and settings.presets[1].slots[1].z==0.274 and settings.presets[1].slots[1].yaw==178,'Fixed default driver seat differs from requested values')
assert(pawns[1].am.CurrentActionList[0].Name=='LivSitChairCrosslegs','Journey pawn action was not inherited')
assert(settings.presets[1].slots[2].x==1 and settings.presets[1].slots[2].yaw==90,'Journey pawn position/direction not inherited')
assert(human.am.CurrentActionList[0].Name=='SitOnChairActions','Player sitting animation was not requested')
for _, pawn in ipairs(pawns) do assert(pawn.machine.enabled,'Pawn froze in the request frame') end
tick()
assert(not human.machine.enabled,'Player did not freeze next behavior frame')
for _, pawn in ipairs(pawns) do assert(pawn.machine.enabled,'Pawn FSM stopped under new seat rule') end
assert(human.pos.x==-0.071 and human.pos.y==0.920 and human.pos.z==0.274,'Takeover kept player entry position instead of fixed seat')
assert(not human.warps,'Seat constraint unexpectedly warped player')
local before_render = human.pos
callbacks.frame(); assert(human.pos==before_render,'Render callback wrote player transform')
settings.presets[1].slots[2].randomIdle=true
state.seats[2].next_idle=clock-1
settings.presets[1].slots[1].randomIdle=true
tick();assert(pawns[1].machine.enabled,'Idle animation was frozen in its request frame')
assert(not human.machine.enabled and human.am.CurrentActionList[0].Name=='SitOnChairActions','Player ran a random idle')
tick();assert(pawns[1].machine.enabled,'Random idle stopped pawn FSM')
settings.presets[1].slots[2].randomIdle=false
assert(driver.pos.z==-50 and driver.machine.enabled,'Unseated driver not relocated with running FSM')
command(function() shift(1) end); assert(state.level==2 and ox.am.CurrentActionList[0].Name=='Walk')
command(function() shift(1);shift(1);shift(1) end); assert(state.level==4 and ox.am.CurrentActionList[0].Name=='Dash')
ox.am:call('',0,'Walk',0); assert(ox.am.CurrentActionList[0].Name=='Dash','External locomotion was not blocked')
command(function() shift(-1);shift(-1);shift(-1);shift(-1) end); assert(state.level==1)
mouse_bits=1; tick(); assert(state.level==1,'Removed mouse-left still accelerated')
tick();assert(state.level==1,'Held mouse affected speed')
mouse_bits=0;tick();mouse_bits=2;tick();assert(state.level==1,'Removed mouse-right affected speed')
mouse_bits=0; kb_down[2]=true
for i=1,10 do tick() end
assert(state.heading<20,'D steering sign incorrect')
kb_down[2]=false;stick_x=-1
for i=1,10 do tick() end
assert(state.heading>20,'Left-stick steering sign incorrect')
stick_x=0; for i=1,10 do tick() end
local target=state.heading;tick();assert(state.heading==target,'Neutral heading changed')
is_paused=true;mouse_bits=1;tick();assert(state.level==1,'Pause changed movement')
is_paused=false;mouse_bits=0;tick()
gp_bits=8;tick();assert(state.level==2,'RB mapping failed');gp_bits=0;tick()
local damage={Damage=100,['<DamageGameObject>k__BackingField']=human}
local damage_proc=hooks['damageProc(app.HitController.DamageInfo)']
local function intercepted(actor)
    return damage_proc({nil,nil,{Damage=100,['<DamageGameObject>k__BackingField']=actor}})
end
assert(intercepted(human)=='skip','Seat-bound player was not immune')
for _,pawn in ipairs(pawns) do assert(intercepted(pawn)=='skip','Seat-bound pawn was not immune') end
for _,actor in ipairs({ox,cow,body,driver,object('unrelated')}) do
    assert(intercepted(actor)==nil,'Non-seat actor received full immunity')
end
assert(damage_proc({nil,nil,{}})==nil,'Missing damage receiver was not ignored')
local seat_records=state.seats;state.seats={}
assert(intercepted(human)==nil,'Unbound player retained immunity while driving')
for _,pawn in ipairs(pawns) do assert(intercepted(pawn)==nil,'Unbound pawn retained immunity') end
state.seats=seat_records
local normal_pawn_get_object=pawns[1].get_GameObject
pawns[1].get_GameObject=function() error('Unloaded actor') end
assert(intercepted(pawns[2])=='skip','Unloaded seat actor interrupted damage hook')
pawns[1].get_GameObject=normal_pawn_get_object
hooks['updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)']({nil,nil,damage})
assert(damage.Damage==1,'Damage multiplier wrong')
damage={Damage=100,['<DamageGameObject>k__BackingField']=object('unrelated')}
hooks['updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)']({nil,nil,damage})
assert(damage.Damage==100,'Unrelated damage changed')
callbacks.reset();assert(not state.active and not bus.owner and resumes==1)
assert(intercepted(human)==nil,'Released player retained immunity')
for _,pawn in ipairs(pawns) do assert(intercepted(pawn)==nil,'Released pawn retained immunity') end
assert(human.machine.enabled and driver.machine.enabled and driver.pos.z==-50,'Release returned unseated driver or changed FSM')
for _,p in ipairs(pawns) do assert(p.machine.enabled) end
assert(ox.am.CurrentActionList[0].Name=='Wait')
command(acquire); assert(state.active)
status.broken=true;tick();assert(not state.active and resumes==2,'Destruction did not release')
status.broken=false
force_fail=true;command(acquire);assert(not state.active and not bus.owner and human.machine.enabled and driver.machine.enabled)
force_fail=false
driver.machine.enabled=false;command(acquire);assert(state.active);release();assert(driver.machine.enabled==false,'Original disabled FSM state lost')
driver.machine.enabled=true
command(acquire);human.pos=vec(100,0,0);tick();assert(not state.active,'Departure did not release')
human.pos=vec(0,0,0)
bus.journey=nil;command(acquire);assert(state.active,'Standalone acquisition failed');release()
_G.OJR_SeatBindings={};command(acquire);assert(not state.active,'Old unadapted Journey accepted');_G.OJR_SeatBindings=nil
imgui={tree_node=function() return true end,tree_pop=function() end,text=function() end,same_line=function() end,
    button=function() return false end,slider_float=function(_,v) return false,v end,
    combo=function(_,v) return false,v end,input_text=function(_,v) return false,v end,
    drag_int=function(_,v) return false,v end,
    drag_float=function(_,v) return false,v end}
imgui.begin_table=function() return true end
imgui.table_next_row=function() end
imgui.table_next_column=function() end
imgui.table_header=function() end
imgui.end_table=function() end
imgui.checkbox=function(_,v) return false,v end
callbacks.ui()
human.pos=vec(0,0,0);command(acquire);assert(state.active)
reframework={is_drawing_ui=function() return true end}
mouse_bits=1;gp_bits=8;tick();assert(state.level==1,'REFramework menu click accelerated')
reframework=nil;mouse_bits=0;gp_bits=0;release()
command(acquire);assert(state.active)
for _,pawn in ipairs(pawns) do assert(pawn.machine.enabled) end
release();tick()
for _,pawn in ipairs(pawns) do assert(pawn.machine.enabled,'Released pending freeze survived') end
assert(human.machine.enabled,'Released pending player freeze survived')
human.machine.enabled=false
command(acquire);assert(state.active and human.machine.enabled)
release();assert(not human.machine.enabled,'Original disabled player FSM state lost')
human.machine.enabled=true
command(acquire);tick();assert(not human.machine.enabled)
settings.debug_player_freeze=false;state.freeze_setting_changed=true;tick()
assert(human.machine.enabled,'Live player freeze OFF did not unfreeze')
for _,pawn in ipairs(pawns) do assert(pawn.machine.enabled,'Player freeze toggle affected pawn FSM') end
settings.debug_player_freeze=true;state.freeze_setting_changed=true;tick()
assert(human.machine.enabled,'Live player freeze ON ignored deferred boundary')
tick();assert(not human.machine.enabled,'Live player freeze ON failed')
is_paused=true;settings.debug_player_freeze=false;state.freeze_setting_changed=true;tick()
assert(human.machine.enabled,'Paused player freeze OFF did not apply')
is_paused=false;release()
settings.debug_player_freeze=false;command(acquire);tick();tick()
assert(human.machine.enabled,'Disabled player freeze was applied on takeover')
release();settings.debug_player_freeze=true
command(acquire);tick();assert(state.active)
local normal_get_object=body.get_GameObject
body.get_GameObject=function() error('Invoke threw an exception: unloaded body') end
is_paused=true;tick()
assert(not state.active and not bus.owner and not bus.heartbeat,'Unloaded body retained ownership')
assert(human.machine.enabled and driver.machine.enabled,'Unloaded body prevented FSM restoration')
for _,pawn in ipairs(pawns) do assert(pawn.machine.enabled,'Unloaded body prevented pawn restoration') end
body.get_GameObject=normal_get_object;is_paused=false
command(acquire);assert(state.active,'Reload acquisition still claims another owner');release()
settings.presets[1].slots[1].x=-0.5
human.pos=vec(0.7,0.2,-2)
command(acquire);tick()
assert(state.active and human.pos.x==-0.5 and settings.presets[1].slots[1].x==-0.5,'Reacquire overwrote edited fixed preset')
local second={name='Test layout',slots={},family='Normal',enabled=true,pawns_customized=true,player_visual=copy_player_visual(current_visual())}
for i,slot in ipairs(settings.presets[1].slots) do
    second.slots[i]={};for key,value in pairs(slot) do second.slots[i][key]=value end
end
second.slots[1].x=-0.6;settings.presets[2]=second
input.sit=true;callbacks.LateUpdateBehavior()
assert(settings.preset==2 and human.pos.x==-0.6,'Preset cycle overwrote driver seat with current offset')
release()
-- The experimental display seat must not move actor roots or pawn skeletons.
settings.preset=1
settings.presets[2]=nil
current_visual().enabled=true
settings.presets[1].slots[1]={x=-0.071,y=0.920,z=0.274,yaw=178}
local root={local_position=vec(0,0,0), writes=0}
function root:get_Valid() return true end
function root:get_Parent() return nil end
function root:get_LocalPosition() return self.local_position end
function root:set_LocalPosition(p) self.local_position=p end
function root:get_Position()
    return vec(human.pos.x+self.local_position.x,human.pos.y+self.local_position.y,human.pos.z+self.local_position.z)
end
function root:set_Position(p)
    self.local_position=p-human.pos; self.writes=self.writes+1
end
local child={get_Valid=function() return true end,get_Parent=function() return root end}
function human:get_Joints() return {get_elements=function() return {root,child} end} end
command(acquire);tick()
assert(human.pos.z==-0.856,'Experimental logic seat was not safe rear seat')
local pawn_position=pawns[1].pos
callbacks.UpdateJointExpression()
assert(math.abs(root:get_Position().z-0.274)<0.00001,'Player model did not reach display seat')
assert(human.pos.z==-0.856 and pawns[1].pos==pawn_position,'Display offset moved gameplay actor/pawn')
callbacks.UpdateJointExpression()
assert(math.abs(root:get_Position().z-0.274)<0.00001,'Repeated display callback accumulated offset')
is_paused=true;callbacks.UpdateJointExpression()
assert(math.abs(root:get_Position().z-0.274)<0.00001,'Paused display update accumulated offset')
is_paused=false
pre_callbacks.UpdateBehavior()
assert(root.local_position.z==0,'Display offset was not removed before gameplay')
root.local_position=vec(0,0.02,0)
callbacks.UpdateJointExpression()
assert(math.abs(root:get_Position().y-0.94)<0.00001,'Display offset erased animated joint pose')
settings.presets[1].slots[1].z=0.5
callbacks.UpdateJointExpression()
assert(math.abs(root:get_Position().z-0.5)<0.00001 and human.pos.z==-0.856,'Display slider moved logic seat')
current_visual().offset={x=0.4,y=0.3,z=-1}
pre_callbacks.UpdateBehavior();tick();callbacks.UpdateJointExpression()
assert(math.abs(human.pos.x-0.329)<0.00001 and math.abs(human.pos.y-1.220)<0.00001
    and math.abs(human.pos.z+1.856)<0.00001,'Root offset did not adjust only logic seat')
assert(math.abs(root:get_Position().z-0.5)<0.00001,'Root offset shifted visible driver seat')
assert(pawns[1].pos.x==pawn_position.x and pawns[1].pos.y==pawn_position.y
    and pawns[1].pos.z==pawn_position.z,'Player root sliders affected pawn position')
current_visual().offset={x=99,y=-99,z=99}
pre_callbacks.UpdateBehavior();tick()
assert(math.abs(human.pos.x-9.929)<0.00001 and math.abs(human.pos.y+9.080)<0.00001
    and math.abs(human.pos.z-9.144)<0.00001,'Root offsets exceeded widened bounds')
current_visual().offset={x=0.4,y=-0.3,z=1}
pre_callbacks.UpdateBehavior();tick();callbacks.UpdateJointExpression()
assert(math.abs(human.pos.y-0.620)<0.00001 and math.abs(human.pos.z-0.144)<0.00001,
    'Forward/downward root movement failed')
assert(math.abs(root:get_Position().z-0.5)<0.00001,'Forward/downward root movement shifted visible body')
assert(root_offset('bad',0,2)==0 and root_offset(0/0,0,2)==0
    and root_offset(math.huge,-2,2)==0,'Invalid persisted root offsets were accepted')
current_visual().offset={x=0,y=0,z=0}
-- Layout copies own their visual settings, and both UI/hotkey selection use them.
local original_visual = current_visual()
local normal_button = imgui.button
imgui.button=function(label) return label=='Add layout from current preset' end
callbacks.ui();imgui.button=normal_button
assert(settings.preset==2 and #settings.presets==2,'UI failed to duplicate layout')
assert(current_visual()~=original_visual and current_visual().offset~=original_visual.offset,
    'Duplicated layouts share visual settings')
current_visual().offset={x=0,y=-0.3,z=1}
pre_callbacks.UpdateBehavior();tick();callbacks.UpdateJointExpression()
assert(math.abs(human.pos.z-0.144)<0.00001,'New layout did not select its camera offset')
local normal_combo=imgui.combo
imgui.combo=function(label,v) if label=='Active layout' then return true,1 end return false,v end
callbacks.ui();imgui.combo=normal_combo
pre_callbacks.UpdateBehavior();tick()
assert(current_visual()==original_visual and human.pos.z==-0.856,'UI layout switch lost original offset')
settings.presets[2].player_visual.enabled=false
kb_down[4]=true;pre_callbacks.UpdateBehavior();tick();callbacks.UpdateJointExpression()
assert(settings.preset==2 and human.pos.z==0.5 and root.local_position.z==0,
    'Hotkey layout switch did not disable visual separation')
kb_down[4]=false;tick();kb_down[4]=true;tick();kb_down[4]=false;tick()
assert(settings.preset==1 and current_visual()==original_visual and human.pos.z==-0.856,
    'Hotkey did not restore visual settings')
settings.presets[2]=nil
local migrated=copy_player_visual(nil,{enabled=true,offset={x=0.4,y=0.3,z=-1}})
assert(migrated.enabled and migrated.offset.z==-1,'Legacy global settings migration failed')
local own=copy_player_visual({enabled=false,offset={y=-2,z=3}},migrated)
assert(not own.enabled and own.offset.y==-2 and own.offset.z==3,'Saved layout values were overridden by legacy settings')
release()
assert(root.local_position.z==0 and root.local_position.y==0.02,'Release did not restore unshifted animation pose')
assert(human.pos.x==-0.071 and human.pos.y==0.920 and human.pos.z==0.5,
    'Release moved visible body to rear logic seat instead of aligning camera root to body')
assert(math.abs(root:get_Position().z-0.5)<0.00001,'Visible player shifted on release')
assert(pawns[1].pos.x==pawn_position.x and pawns[1].pos.z==pawn_position.z,'Player release alignment moved pawn')
command(acquire);tick();callbacks.UpdateJointExpression()
arrange();tick()
assert(human.pos.z==-0.856,'Layout rebind performed release-to-display handoff')
callbacks.UpdateJointExpression()
current_visual().enabled=false
callbacks.UpdateJointExpression()
assert(root.local_position.z==0,'Disabling experiment retained model offset')
tick();assert(human.pos.z==0.5,'Disabled experiment did not restore normal seat positioning')
release()
human.get_Joints=function() error('Skeleton unavailable') end
current_visual().enabled=true
command(acquire);tick();callbacks.UpdateJointExpression()
assert(state.active and state.visual_status:find('Unavailable',1,true),'Skeleton failure broke driving or lacked diagnostic')
assert(state.player_visual==nil,'Failed skeleton update retained restoration records')
release();current_visual().enabled=false
-- Cleanup on title/menu unload must still succeed without a seat alignment.
current_visual().enabled=true
human.get_Joints=function() return {get_elements=function() return {root,child} end} end
command(acquire);tick();callbacks.UpdateJointExpression()
body.get_GameObject=function() error('Unloaded cart during visual handoff') end
is_paused=true;tick()
assert(not state.active and not bus.owner and state.player_visual==nil,'Unloaded cart prevented visual release cleanup')
assert(root.local_position.z==0 and human.machine.enabled,'Visual release retained offset or freeze after unload')
body.get_GameObject=normal_get_object;is_paused=false;current_visual().enabled=false
-- Synchronization is player-only, uses universal context coordinates, and
-- invokes the physical controller rather than Character:warp.
settings.debug_player_position_sync=true
human.pos=vec(0,0,0)
command(acquire);tick()
local context,controller=human.test_position_context,human.test_controller
assert(controller.warps>0 and controller.position.y==human.pos.y,'Physical player root was not synchronized')
assert(context.Position.x==human.pos.x+384 and context.Position.z==human.pos.z-1024,'Position context received scene coordinates')
for _,pawn in ipairs(pawns) do assert(pawn.test_controller.warps>0,'Seated pawn physics not synchronized') end
assert(not human.warps,'Sync invoked full Character warp')
local physical_calls,context_calls=controller.warps,context.writes
settings.debug_player_position_sync=false;tick()
assert(controller.warps==physical_calls and context.writes==context_calls,'Disabled sync still modified components')
settings.debug_player_position_sync=true
current_visual().enabled=true
tick();callbacks.UpdateJointExpression()
assert(human.pos.z==-0.856 and controller.position.z==-0.856 and context.Position.z==-1024.856,
    'Split visual mode synchronized physics to front display seat instead of safe rear root')
release()
assert(controller.position.z==settings.presets[settings.preset].slots[1].z,'Release did not align player physics with visible seat')
local ended_calls=controller.warps;tick()
assert(controller.warps==ended_calls,'Released controller continued syncing')
current_visual().enabled=false;human.pos=vec(0,0,0)
local original_controller=human['<AdjustTerrain>k__BackingField'].MainCharacterController
human['<AdjustTerrain>k__BackingField'].MainCharacterController=nil
command(acquire);tick()
assert(not state.active and not bus.owner and human.machine.enabled and driver.machine.enabled,
    'Unavailable physics controller left control/FSM locked')
human['<AdjustTerrain>k__BackingField'].MainCharacterController=original_controller
command(acquire);tick();release()
-- Fall resets are independent of position sync/FSM and stop on release.
settings.debug_player_freeze=false;settings.debug_player_reset_fall=true
human.pos=vec(0,0,0);command(acquire);tick()
local fall=human.test_fall
assert(fall.reset_calls>0 and fall['<FallHeight>k__BackingField']==0,'Fall accumulated height not reset')
assert(fall.BaseFallHeight.x==human.pos.x+384 and fall.BaseFallHeight.z==human.pos.z-1024,
    'Fall reference received scene coordinates instead of universal via.Position')
assert(human.machine.enabled,'Fall reset changed FSM setting')
for _,pawn in ipairs(pawns) do assert(pawn.test_fall.reset_calls>0,'Seated pawn fall reference not reset') end
local fall_calls=fall.reset_calls
settings.debug_player_reset_fall=false;fall['<FallHeight>k__BackingField']=9;tick()
assert(fall.reset_calls==fall_calls and fall['<FallHeight>k__BackingField']==9,'Fall reset OFF still applied')
settings.debug_player_reset_fall=true;settings.debug_player_position_sync=false;tick()
assert(fall.reset_calls>fall_calls,'Fall reset depended on position-sync toggle')
settings.debug_player_position_sync=true;release()
fall_calls=fall.reset_calls;tick()
assert(fall.reset_calls==fall_calls,'Released player still had fall reset')
current_visual().enabled=true;command(acquire);tick()
assert(fall.BaseFallHeight.z==-1024.856,'Split mode fall reference followed display seat instead of rear root')
release();assert(fall.BaseFallHeight.z==-1024.856,'Release continued resetting fall tracking')
current_visual().enabled=false;settings.debug_player_freeze=true
-- External primary requests are filtered without disabling player FSM.
settings.debug_player_freeze=false;settings.debug_player_pose_lock=true
human.pos=vec(0,0,0);command(acquire);tick()
local action_hook=hooks['requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)']
local function external_request(actor,node,layer)
    return action_hook({nil,actor.am,0,{ToString=function() return node end},layer or 0})
end
assert(human.machine.enabled and human.am.CurrentActionList[0].Name=='SitOnChairActions')
assert(external_request(human,'DamageSmall')=='skip','Damage replacement escaped pose lock')
assert(external_request(human,'FallLoop')=='skip','Falling replacement escaped pose lock')
assert(external_request(human,'NormalLocomotion')=='skip','Movement escaped pose lock')
assert(external_request(human,'SitOnChairActions')==nil,'Sitting request was blocked')
assert(external_request(human,'UpperBodyAction',1)==nil,'Secondary layer was blocked')
assert(external_request(pawns[1],'DamageSmall')=='skip','Seated pawn pose protection missing')
assert(state.player_blocked_actions==3 and state.player_last_blocked_action=='NormalLocomotion')
action(human,'SitOnChairActions');assert(state.player_blocked_actions==3,'Own sitting request intercepted')
settings.debug_player_pose_lock=false
assert(external_request(human,'FallLoop')==nil,'Disabled pose lock still active')
settings.debug_player_pose_lock=true;release()
assert(human.machine.enabled and human.am.CurrentActionList[0].Name=='Wait','Release failed to restore normal player action')
assert(external_request(human,'DamageSmall')==nil,'Released player remained action-locked')
-- All seated pawns adopt the player's synchronization/fall policy, while
-- retaining their independent preset and random idle actions.
human.pos=vec(0,0,0);pawns[3].machine.enabled=false
command(acquire);tick()
for _,pawn in ipairs(pawns) do
    assert(pawn.machine.enabled,'Seat-bound pawn FSM was not kept running')
    assert(pawn.test_controller.position.y==pawn.pos.y,'Pawn physics/root mismatch')
    assert(pawn.test_position_context.Position.z==pawn.pos.z-1024,'Pawn context coordinate mismatch')
    assert(pawn.test_fall.BaseFallHeight.z==pawn.pos.z-1024 and pawn.test_fall['<FallHeight>k__BackingField']==0,
        'Pawn fall reference/reset mismatch')
end
settings.presets[settings.preset].slots[2].randomIdle=true
local seated_pawn=state.seats[2]
seated_pawn.next_idle=clock-1
tick()
assert(pawns[1].am.CurrentActionList[0].Name==seated_pawn.pose_node,'Random sitting request blocked or expected pose stale')
assert(external_request(pawns[1],seated_pawn.pose_node)==nil,'Current random sitting node not allowed')
assert(external_request(pawns[1],'FallLoop')=='skip','Pawn fall replacement escaped lock')
local counts={}
for i,pawn in ipairs(pawns) do counts[i]={physics=pawn.test_controller.warps,fall=pawn.test_fall.reset_calls} end
settings.debug_player_position_sync=false;settings.debug_player_reset_fall=false;settings.debug_player_pose_lock=false
tick()
for i,pawn in ipairs(pawns) do
    assert(pawn.test_controller.warps==counts[i].physics and pawn.test_fall.reset_calls==counts[i].fall,'Shared toggle failed for pawn')
    assert(external_request(pawn,'NormalLocomotion')==nil,'Pose lock OFF still blocked pawn')
end
settings.debug_player_position_sync=true;settings.debug_player_reset_fall=true;settings.debug_player_pose_lock=true
release();tick()
for i,pawn in ipairs(pawns) do
    assert(pawn.test_controller.warps==counts[i].physics and pawn.test_fall.reset_calls==counts[i].fall,'Released pawn still synchronized/reset')
    assert(external_request(pawn,'NormalLocomotion')==nil,'Released pawn remained action locked')
end
assert(not pawns[3].machine.enabled,'Original disabled pawn FSM state was not restored')
pawns[3].machine.enabled=true
human.pos=vec(0,0,0);command(acquire);tick();status.broken=true;tick()
assert(not state.active and not bus.owner,'Destroyed cart retained passenger control')
for _,pawn in ipairs(pawns) do assert(pawn.machine.enabled and external_request(pawn,'DamageSmall')==nil,'Destroyed-cart pawn cleanup failed') end
status.broken=false
print('PASS: player/pawn position sync, running FSMs, sitting protection, random idles, fall reset, scope/toggles and release/destruction cleanup')
