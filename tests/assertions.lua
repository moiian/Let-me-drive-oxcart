local function tick(dt)
    clock=clock+(dt or 1/60)
    callbacks.UpdateHID(); callbacks.LateUpdateBehavior(); callbacks.frame()
end
local suspends,resumes=0,0
bus.journey={suspend=function() suspends=suspends+1 end,resume=function() resumes=resumes+1 end,
    passenger_layout=function() return {
        {x=1,y=0.4,z=-3,lookX=1,lookZ=0,anim='LivSitChairCrosslegs',freezeFsm=true},
        {x=-1,y=0.4,z=-3,lookX=-1,lookZ=0,anim='LivSitChairLean',freezeFsm=true},
        {x=1,y=0.4,z=-4,lookX=0,lookZ=1,anim='SitOnChairCrossArmStart',freezeFsm=true},
    } end}
human.pos=vec(0.3,0.2,-2)
command(acquire)
assert(state.active and bus.owner==TITLE and suspends==1, state.error)
assert(#state.seats==4 and not driver.machine.enabled and human.machine.enabled,'Player FSM froze before its action could initialize')
assert(settings.presets[1].slots[1].x==-0.071 and settings.presets[1].slots[1].y==0.920
    and settings.presets[1].slots[1].z==0.274 and settings.presets[1].slots[1].yaw==178,'Fixed default driver seat differs from requested values')
assert(pawns[1].am.CurrentActionList[0].Name=='LivSitChairCrosslegs','Journey pawn action was not inherited')
assert(settings.presets[1].slots[2].x==1 and settings.presets[1].slots[2].yaw==90,'Journey pawn position/direction not inherited')
assert(human.am.CurrentActionList[0].Name=='SitOnChairActions','Player sitting animation was not requested')
for _, pawn in ipairs(pawns) do assert(pawn.machine.enabled,'Pawn froze in the request frame') end
tick()
assert(not human.machine.enabled,'Player did not freeze next behavior frame')
for _, pawn in ipairs(pawns) do assert(not pawn.machine.enabled,'Pawn did not freeze next behavior frame') end
assert(human.pos.x==-0.071 and human.pos.y==0.920 and human.pos.z==0.274,'Takeover kept player entry position instead of fixed seat')
assert(not human.warps,'Seat constraint unexpectedly warped player')
local before_render = human.pos
callbacks.frame(); assert(human.pos==before_render,'Render callback wrote player transform')
settings.presets[1].slots[2].randomIdle=true
state.seats[2].next_idle=clock-1
settings.presets[1].slots[1].randomIdle=true
tick();assert(pawns[1].machine.enabled,'Idle animation was frozen in its request frame')
assert(not human.machine.enabled and human.am.CurrentActionList[0].Name=='SitOnChairActions','Player ran a random idle')
tick();assert(not pawns[1].machine.enabled,'Idle animation did not refreeze next frame')
settings.presets[1].slots[2].randomIdle=false
assert(driver.pos.x==3.5)
command(function() shift(1) end); assert(state.level==2 and ox.am.CurrentActionList[0].Name=='Walk')
command(function() shift(1);shift(1);shift(1) end); assert(state.level==4 and ox.am.CurrentActionList[0].Name=='Dash')
ox.am:call('',0,'Walk',0); assert(ox.am.CurrentActionList[0].Name=='Dash','External locomotion was not blocked')
command(function() shift(-1);shift(-1);shift(-1);shift(-1) end); assert(state.level==1)
mouse_bits=1; tick(); assert(state.level==2,'Mouse left did not accelerate')
tick();assert(state.level==2,'Held mouse repeated')
mouse_bits=0;tick();mouse_bits=2;tick();assert(state.level==1,'Mouse right did not decelerate')
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
hooks['updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)']({nil,nil,damage})
assert(damage.Damage==1,'Damage multiplier wrong')
damage={Damage=100,['<DamageGameObject>k__BackingField']=object('unrelated')}
hooks['updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)']({nil,nil,damage})
assert(damage.Damage==100,'Unrelated damage changed')
callbacks.reset();assert(not state.active and not bus.owner and resumes==1)
assert(human.machine.enabled and driver.machine.enabled and driver.pos.x==0)
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
imgui={tree_node=function() return true end,tree_pop=function() end,text=function() end,
    button=function() return false end,slider_float=function(_,v) return false,v end,
    combo=function(_,v) return false,v end,input_text=function(_,v) return false,v end,
    drag_float=function(_,v) return false,v end}
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
for _,pawn in ipairs(pawns) do assert(not pawn.machine.enabled,'Player toggle unfroze a pawn') end
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
local second={name='Test layout',slots={},pawns_customized=true}
for i,slot in ipairs(settings.presets[1].slots) do
    second.slots[i]={};for key,value in pairs(slot) do second.slots[i][key]=value end
end
second.slots[1].x=-0.6;settings.presets[2]=second
input.sit=true;callbacks.LateUpdateBehavior()
assert(settings.preset==2 and human.pos.x==-0.6,'Preset cycle overwrote driver seat with current offset')
release()
print('PASS: acquisition, ownership, four speeds, mouse/pad input, steering, pause, damage scope, restoration, destruction, failure rollback, standalone and old-build rejection')
