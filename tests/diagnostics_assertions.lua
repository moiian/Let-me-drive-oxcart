assert(hooks['restoreCoord(app.Gm80_042)']==nil,'Recorder installed a native hook')
assert(rawget(_G,'LMD_PositionObserver')==nil,'Recorder installed a pose observer')
-- Isolate recorder writes from the controller's optional skeleton-display writes.
for _, layout in ipairs(settings.presets) do layout.player_visual.enabled=false end
command(acquire)
callbacks.LateUpdateBehavior()
ui_click('Start recording');callbacks.frame()
local before=write_count
callbacks.UpdateJointExpression()
assert(write_count==before,'Recorder mutated an actor')
for _=1,30 do clock=clock+0.1;callbacks.UpdateJointExpression();callbacks.frame() end
assert(#recorded_files==0,'Recorder exported while running')
human.test_joint.pos=vec(0,12,0)
local test_stuck=human['<LandingProcessor>k__BackingField'].FallingStuckStopper
test_stuck.TimerStuck=3.25;test_stuck['<IsStopperActive>k__BackingField']=true
clock=clock+0.6;callbacks.UpdateJointExpression()
ui_click('Mark event')
command(release)
assert(_G.LMD_PositionProbe.read().cart==nil,'Inactive bridge rediscovered cart')
clock=clock+0.6;callbacks.UpdateJointExpression()
export_failure=true
ui_click('Stop and export');callbacks.frame()
assert(#recorded_files==0,'Failed export discarded error')
export_failure=false;ui_click('Retry export');callbacks.frame()
assert(#recorded_files==1,'Retry did not preserve data')
local d=recorded_files[1].data
assert(d.meta.schema==2 and d.meta.rate_hz==2 and not d.meta.native_hooks)
assert(#d.samples>=6 and #d.samples<=9,'2 Hz cap failed')
assert(#d.samples[1].actors==1,'Default player-only mode failed')
assert(#d.samples[1].actors[1].joints==1,'Direct joint getter failed')
assert(d.samples[1].actors[1].root.universal.x-d.samples[1].actors[1].root.scene.x==1000)
assert(#d.samples[1].slots==4,'Preset slots missing')
assert(d.samples[1].position_sync==true and d.samples[1].position_sync_status,'Player sync status missing')
assert(d.samples[1].reset_fall==true and d.samples[1].fall_reset_status,'Fall reset state missing from trace')
assert(d.samples[1].pose_lock==true and d.samples[1].freeze_player==false,'Pose lock/FSM defaults missing from trace')
assert(d.samples[1].actors[1].base_fall_position_raw,'Fall base via.Position not captured')
assert(d.samples[1].cart.body.scene,'Cart body Transform was treated as a GameObject')
local contact_sample=d.samples[1].actors[1]
assert(contact_sample.landing_available and contact_sample.stuck_available and contact_sample.safety_available)
assert(contact_sample.contacts.ground==true and contact_sample.contacts.wall==false,'Contact false/nil values lost')
assert(contact_sample.contacts.ground_count==1 and contact_sample.contacts.wall_count==0,'Contact counts lost')
assert(contact_sample.contacts.floor.name=='gm80_042_00','Floor identity missing')
assert(contact_sample.last_terrain_ground.normal.y==1 and contact_sample.safe_position_raw,'Ground/safe position missing')
assert(d.samples[#d.samples].active==false,'Post-release data missing')
local saw_height,saw_stuck=false,false
for _,s in ipairs(d.samples) do
    if s.actors[1].joints[1].local_position.y==12 then saw_height=true end
    if s.actors[1].stuck.TimerStuck==3.25 and s.actors[1].stuck['<IsStopperActive>k__BackingField']==true then saw_stuck=true end
end
assert(saw_height,'Skeleton height data missing')
assert(saw_stuck,'Stuck activation/timer transition missing')
local first=recorded_files[1].path
ui_click('Start recording');callbacks.frame()
local original=human.get_Joints
human.test_joint.get_Parent=function() return {get_Valid=function() return false end} end
human.get_Joints=function() return {} end
callbacks.UpdateJointExpression()
human.get_Joints=original
human['<LandingProcessor>k__BackingField']=nil
clock=clock+2.1;callbacks.UpdateJointExpression()
callbacks.reset()
assert(#recorded_files==2 and recorded_files[2].path~=first,'Reset export or unique filenames failed')
assert(#recorded_files[2].data.samples[2].actors[1].joints==1,'Empty skeleton cache did not retry')
assert(not recorded_files[2].data.meta.errors.joints,'Recovered skeleton still marked unavailable')
assert(recorded_files[2].data.samples[2].actors[1].landing_available==false,'Missing landing component not distinguished')
print('Lightweight diagnostics simulation passed: no hooks/writes, 2 Hz, bones, release, retry, reset')
