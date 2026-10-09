assert(not animation_test.lock and not animation_test.hook,'Animation lock must default OFF')
assert(not animation_test.include_player and not animation_test.freeze,'Player/FSM tests must default OFF')
animation_test_set_player(true)
assert(#seat_animation_nodes==7,'Expected seven seated idle buttons')
local hook,hook_count=nil,0
local function character(id)
    local ch={id=id,following=true,requests={},node='Wait'}
    function ch:get_Valid() return not self.invalid end
    function ch:get_address() return self.id end
    function ch:get_Name() return 'ch'..self.id end
    function ch:get_GameObject() return self end
    function ch:call(method) assert(method=='getComponent(System.Type)');return self end
    local manager={get_GameObject=function() return ch end,CurrentActionList={[0]={Name='Wait'}}}
    function manager:requestActionCore(priority,node,layer)
        if ch.fail then error('Request failed') end
        local result=hook and hook({nil,self,priority,{ToString=function() return node end},layer})
        if result=='skip' or ch.native_reject then return end
        ch.node=node;self.CurrentActionList[0].Name=node
        ch.requests[#ch.requests+1]={priority=priority,node=node,layer=layer}
    end
    ch['<ActionManager>k__BackingField']=manager
    function ch:get_ActionManager() return manager end
    -- No Transform/physics methods; FSM supplied only in the explicit test below.
    return ch
end
local human=character(1)
local pawns={character(2),character(3),character(4)}
local guest,outsider=character(5),character(6);outsider.following=false
local wrappers={}
for i,ch in ipairs(pawns) do wrappers[i]={get_CachedCharacter=function() return ch end} end
local singleton=sdk.get_managed_singleton
sdk.get_managed_singleton=function(name)
    if name=='app.CharacterManager' then return {['<ManualPlayer>k__BackingField']=human} end
    if name=='app.PawnManager' then return {get_MainPawn=function() return wrappers[1] end,
        get_PartyPawnList=function() return {get_Count=function() return #wrappers end,get_Item=function(_,i) return wrappers[i+1] end} end} end
    if name=='app.NPCManager' then return {NPCHolderDic={{CharaID=5},{CharaID=5},{CharaID=6}},
        getCharacter=function(_,id) return id==5 and guest or outsider end} end
    return singleton(name)
end
sdk.find_type_definition=function(name)
    if name=='app.NPCUtil' then return {get_method=function(_,signature)
        assert(signature=='isAccompanyPLParty(app.Character)');return {call=function(_,receiver,ch) assert(receiver==nil);return ch.following end} end} end
    assert(name=='app.ActionManager')
    return {get_method=function(_,signature)
        assert(signature=='requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)');return {} end}
end
sdk.hook=function(_,fn) hook=fn;hook_count=hook_count+1 end
sdk.to_managed_object=function(x) return x end
sdk.to_int64=function(x) return x end
sdk.typeof=function(x) return x end
sdk.PreHookResult={SKIP_ORIGINAL='skip'}
local actors=animation_test_roster()
assert(#actors==5 and actors[1].actor==human and actors[5].actor==guest,'Player/pawn/guest order/filter/dedup wrong')
animation_test.pending=seat_animation_nodes[1];animation_test_tick()
for _,entry in ipairs(actors) do
    local request=entry.actor.requests[1]
    assert(request.priority==1 and request.node=='SitOnChairActions' and request.layer==0,'Random-idle request path wrong')
end
assert(#outsider.requests==0,'Unrelated NPC received animation')
pawns[1]:get_ActionManager():requestActionCore(0,'Run',0)
assert(pawns[1].node=='Run','OFF blocked an action')
animation_test_set_lock(true)
assert(animation_test.lock and hook_count==1)
pawns[1]:get_ActionManager():requestActionCore(0,'Attack',0)
assert(pawns[1].node=='Run' and animation_test.blocked==1,'ON did not block competing base action')
pawns[1]:get_ActionManager():requestActionCore(0,'Upper',1)
assert(pawns[1].node=='Upper','Upper layer was blocked')
human:get_ActionManager():requestActionCore(0,'Walk',0)
assert(human.node=='Walk','Debug lock affected player')
outsider:get_ActionManager():requestActionCore(0,'Attack',0)
assert(outsider.node=='Attack','Debug lock affected unrelated NPC')
for _,node in ipairs(seat_animation_nodes) do
    animation_test_play(node)
    for _,entry in ipairs(actors) do
        assert(entry.actor.node==node,'Switch was blocked by previous allowed pose')
        assert(animation_test.records[entry.key].node==node)
        assert(not animation_test.issuing[entry.key],'Internal bypass leaked')
    end
end
for _,entry in ipairs(actors) do for _,request in ipairs(entry.actor.requests) do
    if request.priority==1 then assert(request.node~='Wait','Random animation switching inserted preset Wait') end
end end
local previous=animation_test.records['2']
pawns[1].fail=true;animation_test_play('LivSitPose');pawns[1].fail=false
assert(not animation_test.issuing['2'] and animation_test.records['2']==previous,'Failed action did not restore lock/bypass')
human.native_reject=true;local before=human.node;animation_test_play('LivSitChairLean')
assert(human.node==before and animation_test.rows[1].actual==before,'Native reject falsely changed playback status')
guest.following=false;clock=clock+2;animation_test_tick()
assert(not animation_test.records['5'],'Departed NPC retained lock')
animation_test_set_lock(false)
pawns[1]:get_ActionManager():requestActionCore(0,'Attack',0)
assert(pawns[1].node=='Attack','OFF did not release pose guard')
animation_test_set_lock(true);assert(hook_count==1,'Toggling installed duplicate hooks')
click='Save animation test report';callbacks.ui()
assert(files[#files].events and files[#files].rows,'Test report missing diagnostics')
animation_test.pending='LivSitPose';click='Release debug animation locks';callbacks.ui()
assert(not animation_test.lock and next(animation_test.records)==nil and not animation_test.pending,'Release did not cancel pending/locks')
animation_test_play('LivSitPose');animation_test_set_lock(true);callbacks.reset()
assert(not animation_test.lock and next(animation_test.records)==nil and next(animation_test.issuing)==nil,'Reset retained test locks')
print('PASS: standalone seven animations, player/pawn/escort targeting, priority-1 transitions, NPC-only optional lock, bypass, errors, native rejection, departure, release/report/reset')

-- Explicit FSM tests operate on the same machine objects other mods would use.
human.native_reject=false;guest.following=true
for _,entry in ipairs(actors) do
    local machine={enabled=entry.actor~=pawns[2],writes=0,enables=0}
    function machine:call(method,value)
        if method=='get_Enabled()' then return self.enabled end
        assert(method=='set_Enabled(System.Boolean)');self.enabled=value;self.writes=self.writes+1
        if value then self.enables=self.enables+1 end
    end
    entry.actor.machine=machine
    entry.actor['<Human>k__BackingField']={Fsm=machine}
end
-- Exercise the ActionManager FSM fallback on one pawn.
pawns[3]['<Human>k__BackingField']=nil;pawns[3]:get_ActionManager().Fsm=pawns[3].machine
animation_test_set_player(false)
animation_test_set_freeze(true);animation_test_tick()
assert(human.machine.enabled and not pawns[1].machine.enabled and not guest.machine.enabled,'Default freeze affected player or missed NPCs')
assert(not pawns[3].machine.enabled,'ActionManager FSM fallback missing')
local human_requests=#human.requests
animation_test_play('LivSitPose')
assert(#human.requests==human_requests,'Player excluded option still requested player animation')
assert(not pawns[1].machine.enabled and pawns[1].machine.enables==0,'Animation request temporarily enabled frozen FSM')
clock=clock+0.2;animation_test_tick();assert(not pawns[1].machine.enabled,'FSM thawed during animation')
clock=clock+0.11;animation_test_tick();assert(not pawns[1].machine.enabled and pawns[1].machine.enables==0,'Delayed thaw remains')
animation_test_set_player(true);animation_test_tick();assert(not human.machine.enabled,'Player included option did not freeze FSM')
animation_test_play('LivSitChairLean');assert(not human.machine.enabled and human.machine.enables==0,'Included player thawed for animation')
animation_test_set_player(false);assert(human.machine.enabled and not animation_test.frozen['1'],'Player exclusion did not restore original FSM')
guest.following=false;clock=clock+2;animation_test_tick()
assert(guest.machine.enabled and not animation_test.frozen['5'],'Departure did not restore guest FSM')
animation_test_set_freeze(false)
assert(pawns[1].machine.enabled and not pawns[2].machine.enabled and pawns[3].machine.enabled,'OFF did not restore exact original states')
animation_test_set_freeze(true);animation_test_tick()
assert(not pawns[1].machine.enabled,'Refreeze failed')
click='Release debug animation locks';callbacks.ui()
assert(not animation_test.freeze and pawns[1].machine.enabled,'Release button did not restore FSM')
animation_test_set_freeze(true);animation_test_tick();callbacks.reset()
assert(not animation_test.freeze and pawns[1].machine.enabled and next(animation_test.frozen)==nil,'Reset leaked FSM freeze')
print('PASS: player inclusion/exclusion, real Human/ActionManager FSM remains frozen during requests, exact state restore, departure, release and reset')
