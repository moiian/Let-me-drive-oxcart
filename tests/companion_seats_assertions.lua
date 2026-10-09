;(function()
local singleton_before,type_before=sdk.get_managed_singleton,sdk.find_type_definition
local get_character_before=nm.getCharacter
local guests,holders={},{ }
for i=1,11 do
    local ch=object('guest'..i);add_position_components(ch)
    ch.following=i<=10
    guests[i]=ch;holders[i]={CharaID=ch.id}
end
holders[12]={CharaID=guests[1].id} -- Duplicate holder must not create another seat.
nm.NPCHolderDic=holders
nm.getCharacter=function(_,id)
    for _,ch in ipairs(guests) do if ch.id==id then return ch end end
    return get_character_before(nm,id)
end
sdk.find_type_definition=function(name)
    if name=='app.NPCUtil' then
        return {get_method=function(_,signature)
            assert(signature=='isAccompanyPLParty(app.Character)')
            return {call=function(_,instance,ch)
                assert(instance==nil)
                if ch.read_failed then error('Membership temporarily unreadable') end
                return ch.following==true
            end}
        end}
    end
    return type_before(name)
end
local interacting={}
sdk.get_managed_singleton=function(name)
    if name=='app.InteractManager' then return {call=function(_,method,ch)
        assert(method=='isInteracting(app.Character)');return interacting[ch]==true
    end} end
    return singleton_before(name)
end
local c={ox=ox,body=body,anchor=body,cow=cow,status=status}
human.pos=vec(body.pos.x,body.pos.y,body.pos.z)
state.active=false;is_paused=false;escort_roster.next_scan=0
local list=companions()
assert(#list==9 and list[1]==pawns[1] and list[2]==pawns[2] and list[3]==pawns[3])
assert(list[4]~=guests[11],'Non-following NPC entered roster')
local first_guest=list[4]
assert(driver_debug_bridge.pawn_anchor_command(c))
driver_debug_bridge.pawn_anchor_tick()
assert(#state.seats==9,'Nine companions did not acquire seats')
for i,r in ipairs(state.seats) do
    assert(r.slot==i+1 and r.actor==list[i],'Initial seat assignment was not sequential')
    assert(r.actor.test_controller.warps>0 and r.actor.test_fall.reset_calls>0,'Guest physics/fall sync missing')
    assert(r.actor.test_fall.reset_calls==1,'Initial sit reset fall more than once')
end
local original_slots={}
for _,r in ipairs(state.seats) do original_slots[r.actor]=r.slot end
local action_hook=hooks['requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)']
local run={ToString=function() return 'Run' end}
assert(action_hook({nil,first_guest.am,0,run,0})~='skip','Retired guest action guard still active')
assert(settings.freeze_companion_fsm and first_guest.machine.enabled,'Initial pose did not initialize with FSM enabled')
local initial_resets=first_guest.test_fall.reset_calls
state.behavior_frame=state.behavior_frame+1;driver_debug_bridge.freeze_pose_tick()
assert(not first_guest.machine.enabled,'Guest FSM did not freeze after initialization')
driver_debug_bridge.native_pawns_tick();driver_debug_bridge.pawn_anchor_pose()
assert(first_guest.test_fall.reset_calls==initial_resets,'Routine follow still resets fall')
local guest_record
for _,r in ipairs(state.seats) do if r.actor==first_guest then guest_record=r end end
local request_before=first_guest.am.call
first_guest.am.call=function(self,...)
    assert(first_guest.machine.enabled and first_guest.test_fall.reset_calls==initial_resets+1,'Random request missed same-frame fall reset before animation')
    return request_before(self,...)
end
animate(guest_record,{anim='LivSitPose'},true)
first_guest.am.call=request_before
assert(first_guest.test_fall.reset_calls==initial_resets+1,'Random pose did not reset fall once')
assert(first_guest.machine.enabled,'Random pose request did not thaw FSM')
driver_debug_bridge.native_pawns_tick();assert(first_guest.machine.enabled,'FSM froze in request callback')
state.behavior_frame=state.behavior_frame+1;driver_debug_bridge.freeze_pose_tick()
assert(not first_guest.machine.enabled,'FSM did not refreeze on next callback without advancing time')
local motion_before=first_guest.get_Motion
first_guest.get_Motion=function() return {getLayer=function() return {call=function()
    assert(first_guest.machine.enabled,'Direct motion requested while FSM frozen')
end} end} end
animate(guest_record,{useDirectMotion=true},true)
assert(first_guest.machine.enabled and guest_record.freeze_frame,'Direct motion missed next-frame freeze')
state.behavior_frame=state.behavior_frame+1;driver_debug_bridge.freeze_pose_tick()
assert(not first_guest.machine.enabled)
first_guest.get_Motion=motion_before
animate(guest_record,{anim='LivSitPose'},true)
settings.freeze_companion_fsm=false;driver_debug_bridge.native_pawns_tick();assert(first_guest.machine.enabled,'Global OFF did not restore FSM')
state.behavior_frame=state.behavior_frame+1;driver_debug_bridge.freeze_pose_tick()
assert(first_guest.machine.enabled,'Global OFF retained pending freeze')
settings.freeze_companion_fsm=true;driver_debug_bridge.native_pawns_tick()
local hit=hooks['damageProc(app.HitController.DamageInfo)']
assert(hit({nil,nil,{['<DamageGameObject>k__BackingField']=first_guest}})=='skip','Guest protection missing')
assert(hit({nil,nil,{['<DamageGameObject>k__BackingField']=guests[11]}})~='skip','Unbound NPC protected')

first_guest.following=false;clock=clock+1.1
driver_debug_bridge.pawn_anchor_tick()
assert(#state.seats==9,'Vacant seat was not filled by next following NPC')
assert(not driver_debug_bridge.pawn_anchor_context(first_guest),'Departed guest stayed bound')
for _,r in ipairs(state.seats) do
    if original_slots[r.actor] then assert(r.slot==original_slots[r.actor],'Remaining occupant changed slot') end
end
assert(first_guest.machine.enabled and first_guest.am.CurrentActionList[0].Name=='Wait','Guest release did not restore control')
assert(hit({nil,nil,{['<DamageGameObject>k__BackingField']=first_guest}})~='skip','Released guest retained protection')
local retained=state.seats[4].actor
retained.read_failed=true;clock=clock+1.1;driver_debug_bridge.pawn_anchor_tick()
assert(driver_debug_bridge.pawn_anchor_context(retained),'Failed query was interpreted as departure')
retained.read_failed=false
nm.NPCHolderDic=nil;clock=clock+1.1;driver_debug_bridge.pawn_anchor_tick()
assert(#state.seats==9,'Unreadable NPC roster released valid occupants')
nm.NPCHolderDic=holders
local before_interact=retained.am.CurrentActionList[0].Name
interacting[retained]=true;driver_debug_bridge.pawn_anchor_tick()
assert(not driver_debug_bridge.pawn_anchor_context(retained),'Quest interaction did not release guest root ownership')
assert(retained.am.CurrentActionList[0].Name==before_interact,'Guest release overwrote active quest interaction')
interacting[retained]=nil
local released_record=state.seats[1]
animate(released_record,{anim='LivSitPose'},true)
driver_debug_bridge.pawn_anchor_exit()
state.behavior_frame=state.behavior_frame+1;driver_debug_bridge.freeze_pose_tick()
assert(released_record.actor.machine.enabled,'Released actor was refrozen by pending frame work')
assert(#state.seats==0 and not driver_debug_bridge.pawn_anchor_context(retained))
clock=clock+2;driver_debug_bridge.pawn_anchor_tick()
assert(#state.seats==0,'Stand automatically reseated companions')

-- No three-pawn cap: ordinary roster enumeration accepts an extra member.
local count_before=members.get_Count
local extra=object('extra_roster_member');add_position_components(extra)
members._items[2]=pawn_wrap(extra);members.get_Count=function() return 3 end
escort_roster.next_scan=0;list=companions()
assert(list[4]==extra and list[5]~=extra and #list==9,'Guest allocation assumed exactly three pawns')
members._items[2]=nil;members.get_Count=count_before

for _,layout in ipairs(settings.presets) do
    assert(#layout.slots==10,'Preset did not expand to driver plus nine companions')
end
for _,factory in ipairs(builtin_presets) do
    local copy=clone_builtin(factory)
    for i=1,4 do for key,value in pairs(factory.slots[i]) do
        assert(copy.slots[i][key]==value,'Approved existing seat changed during expansion')
    end end
    for i=5,10 do
        for j=2,i-1 do
            local a,b=copy.slots[i],copy.slots[j]
            assert((a.x-b.x)^2+(a.z-b.z)^2>=0.65^2,'Additional factory seats overlap existing seats')
        end
    end
    copy.slots[10].x=3.21
    local duplicate=copy_layout(copy,'Copy',copy.family)
    assert(duplicate.slots[10].x==3.21 and duplicate.slots[10]~=copy.slots[10],'New seats were lost or shared on copy')
end
nm.NPCHolderDic=nil;nm.getCharacter=get_character_before
sdk.get_managed_singleton,sdk.find_type_definition=singleton_before,type_before
print('PASS: nine-seat roster, stable slots, physics/protection, FSM init/thaw/freeze/OFF/restore, retired guard, release and presets')
end)()
