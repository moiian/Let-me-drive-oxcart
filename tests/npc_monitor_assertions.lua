callbacks.LateUpdateBehavior()
assert(snapshot.status:find('NPC found',1,true) and snapshot.object_name=='ch300298','NPC lookup failed')
assert(snapshot.actions[1].name=='SitOnChairActions' and snapshot.motions[1].id==2010,'Action/motion sample wrong')
assert(snapshot.motions[1].name=='NpcSitLoop','Actual motion name not resolved')
local initial_reads=read_count
for _=1,10 do clock=clock+0.01;callbacks.LateUpdateBehavior() end
assert(read_count==initial_reads,'Monitor exceeded 4 Hz')
npc.action='LivSitChairBook01';npc.motion=2020
clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(snapshot.actions[1].name=='LivSitChairBook01' and #history==2,'Action change missing')
assert(snapshot.motions[1].name=='NpcReadBookLoop','Changed clip name not resolved')
for i=1,20 do npc.motion=2020+i;clock=clock+0.25;callbacks.LateUpdateBehavior() end
assert(#history==12,'History is unbounded')
missing=true;clock=clock+1;callbacks.LateUpdateBehavior()
assert(#snapshot.actions==0 and snapshot.status:find('not loaded',1,true),'Unloaded NPC left stale animation')
missing=false;clock=clock+1;callbacks.LateUpdateBehavior()
assert(snapshot.status:find('NPC found',1,true),'NPC failed to reload')
typed='invalid';click='Apply NPC ID';callbacks.ui()
assert(target_id==963132753 and #files==0,'Invalid ID changed target or wrote config')
typed='123';click='Apply NPC ID';callbacks.ui();clock=clock+1;callbacks.LateUpdateBehavior()
assert(target_id==123 and #snapshot.actions==0,'New ID kept old NPC action')
assert(parse_id('0x39683651')~=nil and parse_id('-1')==nil and parse_id('1.5')==nil and parse_id('4294967296')==nil)
typed='963132753';click='Apply NPC ID';callbacks.ui();clock=clock+1;callbacks.LateUpdateBehavior()
-- Progressive scans remain bounded and ignore the invalid -1 motion sentinel.
clear_names();npc.motion=3521
local before_metadata=metadata_reads
clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(metadata_reads-before_metadata<=24 and snapshot.motions[1].name==nil,'Name scan exceeded budget')
clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(snapshot.motions[1].name=='NpcDriveLoop','Progressive scan did not finish')
before_metadata=metadata_reads
clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(metadata_reads==before_metadata,'Resolved name repeatedly scanned')
npc.motion=4294967295;clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(snapshot.motions[1].name==nil and snapshot.motions[1].name_status:find('No active',1,true),'Invalid motion shown as clip')
assert(metadata_reads==before_metadata,'Invalid motion caused metadata scan')
npc.motion=2010;click='Refresh motion names';callbacks.ui()
assert(next(motion_names)==nil,'Manual refresh kept stale names')
metadata_error=true;clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(snapshot.motions[1].name_status=='Metadata read unavailable','Metadata failure not reported')
metadata_error=false
-- Some builds expose layer reads on the getter object and bank metadata only
-- on Character.Motion. Emote Dogma uses the latter for its name enumeration.
local old_motion_getter=npc.get_Motion
npc['<Motion>k__BackingField']=old_motion_getter(npc)
npc.get_Motion=function(self)
    local value=old_motion_getter(self)
    value.getMotionCount=function() error('Getter has no metadata count') end
    local old_call=value.call
    value.call=function(self,method,...)
        if method=='getMotionCount(System.UInt32)' then error('Getter count unavailable') end
        return old_call(self,method,...)
    end
    return value
end
clear_names();clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(snapshot.motions[1].name=='NpcSitLoop' and motion_names[0].source=='backing','Backing motion metadata not selected')
local backing=npc['<Motion>k__BackingField']
backing.getMotionCount=nil
local backing_call=backing.call
backing.call=function(self,method,...)
    if method=='getMotionCount(System.UInt32)' then return 60 end
    return backing_call(self,method,...)
end
clear_names();clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(snapshot.motions[1].name=='NpcSitLoop','Explicit count fallback failed')
npc['<Motion>k__BackingField']=nil
clear_names();clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(snapshot.motions[1].metadata_error:find('Getter',1,true),'Count failure reason was swallowed')
npc.get_Motion=old_motion_getter
enabled=false;local paused_reads=read_count;clock=clock+1;callbacks.LateUpdateBehavior()
assert(read_count==paused_reads,'Disabled monitor kept sampling')
callbacks.reset();assert(actor==nil,'Reset retained engine object')
assert(next(motion_names)==nil,'Reset retained motion name cache')
print('PASS: NPC current motion names, bounded metadata scans, invalid IDs, refresh, 4 Hz and read-only behavior')
-- Distance sampling is independent of the NPC monitor toggle.
local function vector(x,y,z)
    return setmetatable({x=x,y=y,z=z},{__sub=function(a,b)
        local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z
        return {length=function() return math.sqrt(dx*dx+dy*dy+dz*dz) end}
    end})
end
Vector3f={new=vector}
local ppos,bpos=vector(1,0,1.5),vector(0,0,0)
local function positioned(name,pos)
    return {get_Valid=function() return true end,get_Name=function() return name end,
        get_Transform=function() return {get_Position=function() return pos() end,
            get_AxisZ=function() return vector(0,0,1) end} end}
end
local human=positioned('player',function() return ppos end)
local cart=positioned('gm80_042',function() return bpos end)
local old_singleton=sdk.get_managed_singleton
sdk.get_managed_singleton=function(name)
    if name=='app.CharacterManager' then return {['<ManualPlayer>k__BackingField']=human} end
    return old_singleton(name)
end
local scans=0
sdk.get_native_singleton=function() return {} end
sdk.find_type_definition=function() return {} end
sdk.call_native_func=function() return {call=function(_,_,name)
    scans=scans+1;if name=='gm80_042' then return cart end
end} end
enabled=false;distance_enabled=true;next_sample=0
callbacks.LateUpdateBehavior()
assert(distance_status:find('1.000',1,true) and distance_status:find('true',1,true),'Distance depends on NPC toggle')
local initial_scans=scans;ppos=vector(2,0,1.5);clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(distance_status:find('2.000',1,true) and distance_status:find('false',1,true),'Distance threshold incorrect')
assert(scans==initial_scans,'Cart discovery ran every sample')
distance_enabled=false;clock=clock+2;callbacks.LateUpdateBehavior()
assert(scans==initial_scans,'Disabled distance monitor still scanned')
_G.LMD_CartFrontProbe={read=function() return {distance=1.234,model='linked cart'} end}
distance_enabled=true;clock=clock+0.25;callbacks.LateUpdateBehavior()
assert(distance_status:find('1.234',1,true) and scans==initial_scans,'Debug distance differs from driving probe')
_G.LMD_CartFrontProbe=nil;distance_enabled=false
print('PASS: optional distance sampling, discovery throttling and threshold display')
do
local teleports,resets,native_tests,changes=0,0,0,{}
_G.LMD_DriverDebug={combat_read=function() return {freeze_enabled=false,driver_fsm=true,flags={}} end,
    combat_set=function(name,value) changes[name]=value end,
    teleport_driver=function() teleports=teleports+1 end,
    combat_reset=function() resets=resets+1 end,
    test_native_exit=function() native_tests=native_tests+1;return true,'Native test queued' end,
    combat_cleanup=function() resets=resets+1 end}
local original_checkbox=imgui.checkbox
imgui.checkbox=function(name,value)
    if name=='Freeze driver FSM' or name=='Force true: isDriverBattleMode' then return true,true end
    return false,value
end
click='Teleport driver 500 units behind cart (once)';callbacks.ui()
assert(teleports==1 and changes.freeze==true and changes.isDriverBattleMode==true,'Debug test buttons not connected')
click='Test native DrivingSeat.freeGetOff (once)';callbacks.ui();assert(native_tests==1,'Native exit button not connected')
click='Clear combat overrides / unfreeze driver';callbacks.ui();assert(resets==1,'Debug clear button not connected')
callbacks.reset();assert(resets==2,'Debug reset did not clean up overrides/FSM')
imgui.checkbox=original_checkbox;_G.LMD_DriverDebug=nil
print('PASS: debug combat/FSM controls, 500-unit teleport button and reset cleanup')
end
