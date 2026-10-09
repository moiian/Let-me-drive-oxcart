assert(not height.enabled and not height.recording,'Height probe must default OFF')
local function point(x,y,z)
    return setmetatable({x=x,y=y,z=z},{__sub=function(a,b) return point(a.x-b.x,a.y-b.y,a.z-b.z) end,
        __index={length=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end}})
end
local function actor_at(id,y)
    local actor={id=id,pos=point(0,y,1),bone_offset=0.4}
    function actor:get_Valid() return not self.invalid end
    function actor:get_address() return self.id end
    function actor:get_Transform() return self end
    function actor:get_Position() return self.pos end
    function actor:get_GameObject() return self end
    function actor:get_Name() return 'pawn'..self.id end
    local joint={get_Valid=function() return true end,get_Parent=function() return nil end,
        get_Name=function() return 'root' end,get_Position=function() return point(0,actor.pos.y+actor.bone_offset,1) end}
    function actor:get_Joints() return {get_elements=function() return {joint} end} end
    -- Deliberately no setters, requestAction, physics, or FSM methods.
    return actor
end
local first,second=actor_at(1,2),actor_at(2,3)
local wrapper1,wrapper2={get_CachedCharacter=function() return first end},{get_CachedCharacter=function() return second end}
local pm={get_MainPawn=function() return wrapper1 end,get_PartyPawnList=function() return {
    _items={[0]=wrapper1,[1]=wrapper2},get_Count=function() return 2 end} end}
local cart=actor_at(9,0);cart.pos=point(0,0,0)
cart.get_AxisY=function() return point(0,0.6,0.8) end
local old_singleton=sdk.get_managed_singleton
sdk.get_managed_singleton=function(name)
    if name=='app.PawnManager' then return pm end
    if name=='app.CharacterManager' then return {['<ManualPlayer>k__BackingField']=first} end
    return old_singleton(name)
end
sdk.get_native_singleton=function() return {} end
sdk.find_type_definition=function() return {} end
local no_cart=false
sdk.call_native_func=function() return {call=function(_,_,name) if name=='gm80_042' and not no_cart then return cart end end} end
height.enabled=true
height_sample('LateUpdateBehavior')
assert(#height.rows==2 and math.abs(height.rows[1].relative_height-2)<1e-8,'Roster dedup/tilted projection wrong')
first.pos=point(0,2.5,1);clock=clock+0.02
height_sample('LateUpdateBehavior')
assert(math.abs(height.rows[1].delta_y-0.5)<1e-8 and math.abs(height.rows[1].delta_relative-0.3)<1e-8,'Height delta wrong')
assert(math.abs(height.rows[1].range_y-0.5)<1e-8 and height.rows[1].range_bone_offset<1e-8,'Root/bone jitter not distinguished')
first.bone_offset=1.4
callbacks.PrepareRendering()
assert(math.abs(height.rows[1].range_bone_offset-1)<1e-8,'Bone-only change not captured')
height_record(true)
height_sample('PrepareRendering')
height.marks[#height.marks+1]={t=0,label='test'}
height_record(false)
local log=files[#files]
assert(log.version==1 and #log.samples==1 and #log.marks==1 and log.samples[1].phase=='PrepareRendering','Recording/save failed')
no_cart=true;clock=clock+3
height_sample('LateUpdateBehavior')
assert(height.rows[1].relative_height==nil and height.rows[1].range_relative==nil,'Missing cart left stale projection/range')
second.invalid=true;clock=clock+1.1;height_sample('LateUpdateBehavior')
assert(#height.rows==1,'Unloaded actor retained')
height.enabled=false
local previous_rows=height.rows
height_sample('PrepareRendering')
assert(height.rows==previous_rows,'OFF continued sampling')
callbacks.reset()
assert(not height.enabled and not height.recording,'Reset failed to close probe')
print('PASS: read-only height monitor, pawn order/dedup, tilted cart projection, actor/bone jitter, rolling range, logging, unavailable actors/cart and reset')
