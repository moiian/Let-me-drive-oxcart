local clock = 100
os.clock = function() return clock end
local callbacks, hooks = {}, {}
local kb_down, gp_bits, stick_x, mouse_bits = {}, 0, 0, 0
local is_paused, missing, force_fail = false, false, false
local function vec(x,y,z)
    local v = {x=x,y=y,z=z}
    return setmetatable(v, {__sub=function(a,b) return vec(a.x-b.x,a.y-b.y,a.z-b.z) end,
        __index={length=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end}})
end
Vector3f = {new=vec}
local counter = 0
local function object(name, p)
    counter = counter + 1
    local obj = {name=name,id=counter,pos=p or vec(0,0,0)}
    function obj:get_address() return self.id end
    function obj:get_Valid() return not self.invalid end
    function obj:get_Name() return self.name end
    function obj:get_Position() return self.pos end
    function obj:set_Position(p) self.pos=p end
    function obj:get_Transform() return self end
    function obj:get_GameObject() return self.go or self end
    function obj:get_AxisX() return vec(1,0,0) end
    function obj:get_AxisY() return vec(0,1,0) end
    function obj:get_AxisZ() return vec(0,0,1) end
    function obj:lookAt() self.looked=true end
    function obj:get_Child() return nil end
    function obj:get_CharaID() return self.id end
    function obj:get_ActionManager() return self.am end
    function obj:call(method,p)
        assert(method=='warp(via.vec3, app.CharacterWarpOption)', method)
        self.pos, self.physics_pos, self.warps = p, p, (self.warps or 0)+1
    end
    obj.machine = {enabled=true, call=function(self, method, value)
        if method=='get_Enabled()' then return self.enabled end
        self.enabled=value
    end}
    obj.am = {Fsm=obj.machine, CurrentActionList={[0]={Name='Wait'}}}
    function obj.am:get_GameObject() return obj end
    function obj.am:call(method, priority, node, layer)
        if force_fail and priority==1 then error('Injected seat failure') end
        local str = {ToString=function() return node end}
        local hook = hooks['requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)']
        if hook and hook({nil,self,priority,str,layer})=='skip' then return end
        self.CurrentActionList[0].Name=node
    end
    obj['<ActionManager>k__BackingField']=obj.am
    obj['<Human>k__BackingField']={Fsm=obj.machine}
    return obj
end
local human, ox, cow, body, driver = object('player'),object('ox'),object('cow'),object('gm80_042'),object('driver')
local pawns = {object('pawn1'),object('pawn2'),object('pawn3')}
local heading=20
cow['<PosRotContext>k__BackingField']={call=function() return heading end}
function cow:call(method,value) self[method]=value end
ox.EnemyCtrl={Ch2={['<CachedConnectParts>k__BackingField']={CowChara=cow}}}
function ox:call() return self end
local status={broken=false,call=function(self,m)
    if m=='getCurrentDriver' then return driver.id end
    if m=='isBroken_OxCart()' then return self.broken end
    return false
end}
local cm={['<ManualPlayer>k__BackingField']=human}
local nm={OxcartManager={_RaidAttack_CachedGameObject=ox,getStatus=function() return status end},getCharacter=function() return driver end}
local gui={call=function(_,m) if m=='isPausedGUI()' then return is_paused end return false end}
local function pawn_wrap(actor) return {get_CachedCharacter=function() return actor end} end
local members={_items={[0]=pawn_wrap(pawns[2]),[1]=pawn_wrap(pawns[3])},get_Count=function() return 2 end}
local pm={get_MainPawn=function() return pawn_wrap(pawns[1]) end,get_PartyPawnList=function() return members end}
local keyboard_names={A=1,D=2,G=3,E=4,F=5,W=6,S=7,LShift=8,Alpha1=9,Alpha2=10,Alpha3=11,Alpha4=12}
local gamepad_names={RTrigBottom=1,RLeft=2,Cancel=4,RTrigTop=8,LTrigTop=16,LTrigBottom=32,LUp=64,LLeft=128,LRight=256,LDown=512}
local function definition(name)
    return {get_fields=function()
        local values = name=='via.hid.KeyboardKey' and keyboard_names or name=='via.hid.GamePadButton' and gamepad_names or name=='via.hid.MouseButton' and {L=1,R=2} or {}
        local fields={}
        for key,value in pairs(values) do fields[#fields+1]={is_static=function() return true end,get_name=function() return key end,get_data=function() return value end} end
        return fields
    end,get_method=function(_,sig) return sig end}
end
local kb={call=function(_,_,key) return kb_down[key] or false end}
local gp={call=function(_,m) if m=='get_AxisL()' then return {x=stick_x} end return gp_bits end}
local mouse={call=function(_,_,flag) return flag and (mouse_bits & flag)==flag or false end}
local scene={call=function(_,_,name) if name=='gm80_042' then return body end end}
sdk={find_type_definition=definition,typeof=function(x) return x end,get_native_singleton=function(x) return x end,
    get_managed_singleton=function(name)
        if name=='app.CharacterManager' then return cm elseif name=='app.NPCManager' then return missing and nil or nm
        elseif name=='app.GuiManager' then return gui elseif name=='app.PawnManager' then return pm end
    end,
    call_native_func=function(name,_,method)
        if name=='via.hid.Keyboard' then return kb elseif name=='via.hid.Gamepad' then return gp
        elseif name=='via.hid.Mouse' then return mouse elseif name=='via.SceneManager' then return scene end
    end,
    hook=function(method,pre) hooks[method]=pre end,to_managed_object=function(x) return x end,to_int64=function(x) return x end,
    PreHookResult={SKIP_ORIGINAL='skip'}}
json={load_file=function() return nil end,dump_file=function() end}
log={error=function() end,warn=function() end}
re={on_application_entry=function(name,fn) callbacks[name]=fn end,on_frame=function(fn) callbacks.frame=fn end,
    on_draw_ui=function(fn) callbacks.ui=fn end,on_script_reset=function(fn) callbacks.reset=fn end,on_config_save=function() end}
imgui={}
