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
assert(#state.seats==4 and not driver.machine.enabled and human.machine.enabled,'Player FSM was frozen')
assert(settings.presets[1].slots[1].x==0.3 and settings.presets[1].slots[1].z==-2,'Driver position was substituted for player position')
assert(pawns[1].am.CurrentActionList[0].Name=='LivSitChairCrosslegs','Journey pawn action was not inherited')
assert(settings.presets[1].slots[2].x==1 and settings.presets[1].slots[2].yaw==90,'Journey pawn position/direction not inherited')
assert(human.am.CurrentActionList[0].Name=='Wait','Native player action replaced on entry')
for _, pawn in ipairs(pawns) do assert(pawn.machine.enabled,'Pawn froze in the request frame') end
tick()
for _, pawn in ipairs(pawns) do assert(not pawn.machine.enabled,'Pawn did not freeze next behavior frame') end
assert(not human.warps,'Seat constraint unexpectedly warped player')
local before_render = human.pos
callbacks.frame(); assert(human.pos==before_render,'Render callback wrote player transform')
settings.presets[1].slots[2].randomIdle=true
state.seats[2].next_idle=clock-1
tick();assert(pawns[1].machine.enabled,'Idle animation was frozen in its request frame')
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
callbacks.ui()
human.pos=vec(0,0,0);command(acquire);assert(state.active)
reframework={is_drawing_ui=function() return true end}
mouse_bits=1;gp_bits=8;tick();assert(state.level==1,'REFramework menu click accelerated')
reframework=nil;mouse_bits=0;gp_bits=0;release()
command(acquire);assert(state.active)
for _,pawn in ipairs(pawns) do assert(pawn.machine.enabled) end
release();tick()
for _,pawn in ipairs(pawns) do assert(pawn.machine.enabled,'Released pending freeze survived') end
print('PASS: acquisition, ownership, four speeds, mouse/pad input, steering, pause, damage scope, restoration, destruction, failure rollback, standalone and old-build rejection')
