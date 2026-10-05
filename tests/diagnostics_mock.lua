-- Extend the controller fixture without allowing the recorder to mutate actors.
local post_hooks, recorded_files = {}, {}
local export_failure=false
local hook_storage = {}
thread={get_hook_storage=function() return hook_storage end}
sdk.hook=function(method,pre,post) hooks[method]=pre;post_hooks[method]=post end
local write_count=0
local function extend(actor)
    local original_position_set=actor.set_Position
    actor.set_Position=function(self,p) write_count=write_count+1;original_position_set(self,p) end
    actor.get_UniversalPosition=function(self) return vec(self.pos.x+1000,self.pos.y+2000,self.pos.z+3000) end
    actor.get_LocalPosition=function(self) return self.pos end
    actor.get_Parent=function() return nil end
    actor.get_IsGround=function() return true end
    actor.get_LastGroundPosition=actor.get_UniversalPosition
    local original_call=actor.call
    actor.call=function(self,method,...)
        local name=method:match('^([%w_]+)%(')
        if name and self[name] then return self[name](self,...) end
        if method:find('warp',1,true) then return original_call(self,method,...) end
        if method=='getComponent(System.Type)' and self==ox then return original_call(self,method,...) end
        return nil
    end
    local joint={pos=vec(0,0,0)}
    joint.get_Valid=function() return true end
    joint.get_Parent=function() return nil end
    joint.get_Name=function() return 'Root' end
    joint.get_LocalPosition=function(self) return self.pos end
    joint.get_Position=function(self) return vec(actor.pos.x+self.pos.x,actor.pos.y+self.pos.y,actor.pos.z+self.pos.z) end
    joint.set_LocalPosition=function(self,p) write_count=write_count+1;self.pos=p end
    joint.set_Position=function(self,p) write_count=write_count+1;self.pos=p-actor.pos end
    joint.call=function(self,method) local name=method:match('^([%w_]+)%(');return self[name] and self[name](self) end
    actor.test_joint=joint
    actor.get_Joints=function() return {get_elements=function() return {joint} end} end
    local context=object('context')
    context.Position=actor:get_UniversalPosition()
    context.call=function(self,method,value)
        if method=='get_Pos()' then return self.Position end
        if method=='setPos(via.Position)' then self.Position=value;return end
    end
    actor['<PosRotContext>k__BackingField']=context
    local restorer=object('restorer')
    restorer.Context={HasInfo=true,IsInside=true,LocalPos=vec(0,0,-1)}
    restorer.IsRestoring=false;restorer.CountSinceTeleported=100
    restorer.call=function(_,method)
        if method=='get_PrevPosition()' then return actor:get_UniversalPosition() end
        if method=='get_IsTeleported()' then return false end
    end
    actor['<Human>k__BackingField']['<CoordRestorerOnOxcart>k__BackingField']=restorer
    actor.test_restorer=restorer
    local stuck={['<IsStopperActive>k__BackingField']=false,TimerStuck=0,
        FrameDetectStuck=2,DistanceStopperActive=0.5,BasePosition=actor:get_UniversalPosition()}
    actor['<LandingProcessor>k__BackingField']={FallingStuckStopper=stuck,
        ['<IsKeepGround>k__BackingField']=true,['<IsPrevKeepGround>k__BackingField']=true,
        ['<IsObjectGround>k__BackingField']=true,['<LastGroundPosition>k__BackingField']=actor:get_UniversalPosition(),
        LastTerrainGroundInfo={['<IsValid>k__BackingField']=true,Position=actor:get_UniversalPosition(),
            Normal=vec(0,1,0),GameObject=body}}
    local fall=actor['<FallInfo>k__BackingField'] or {}
    fall['<FallHeight>k__BackingField']=0;fall['<FallHeightOnLanding>k__BackingField']=0
    fall.BaseFallHeight=actor:get_UniversalPosition()
    actor['<FallInfo>k__BackingField']=fall
    actor['<FallPreventerPosRecorder>k__BackingField']={IsUnsafe=false,['<Pos>k__BackingField']=actor:get_UniversalPosition()}
    local terrain=actor['<AdjustTerrain>k__BackingField']
    if terrain then
        local cc=terrain.MainCharacterController
        local original_cc=cc.call
        cc.call=function(self,method,...)
            local vals={['get_Ground()']=true,['get_Wall()']=false,['get_Ceiling()']=false,['get_Jump()']=false,
                ['get_NumGroundContactPoints()']=1,['get_NumWallContactPoints()']=0,['get_NumCeilingContactPoints()']=0,
                ['get_Height()']=1.8,['get_Radius()']=0.3,['get_FloorGameObject()']=body,['get_LocalOffsetPosition()']=vec(0,0,0)}
            if vals[method]~=nil then return vals[method] end
            return original_cc(self,method,...)
        end
    end
end
for _,actor in ipairs({human,ox,body,driver}) do extend(actor) end
for _,actor in ipairs(pawns) do extend(actor) end
sdk.get_primary_camera=function() return human end
local function assert_plain(value,seen)
    local kind=type(value)
    assert(kind=='table' or kind=='string' or kind=='number' or kind=='boolean' or kind=='nil','Managed/function value leaked into JSON')
    if kind=='number' then assert(value==value and math.abs(value)~=math.huge,'Non-finite JSON number') end
    if kind=='table' then
        seen=seen or {};assert(not seen[value],'Cycle in JSON');seen[value]=true
        for key,item in pairs(value) do assert_plain(key,seen);assert_plain(item,seen) end
        seen[value]=nil
    end
end
json.dump_file=function(path,data)
    if path:find('LMD_PositionTrace_',1,true) then
        if export_failure then error('Injected export failure') end
        assert_plain(data);recorded_files[#recorded_files+1]={path=path,data=data}
    end
    return true
end
-- Preserve all callbacks when both scripts register for the same engine phase.
local function combine(store,key,fn)
    local previous=store[key]
    store[key]=function(...) if previous then previous(...) end;return fn(...) end
end
re.on_application_entry=function(name,fn) combine(callbacks,name,fn) end
re.on_pre_application_entry=function(name,fn) combine(pre_callbacks,name,fn) end
re.on_frame=function(fn) combine(callbacks,'frame',fn) end
re.on_script_reset=function(fn) combine(callbacks,'reset',fn) end
re.on_draw_ui=function(fn) combine(callbacks,'ui',fn) end
local click
imgui={tree_node=function() return true end,tree_pop=function() end,text=function() end,same_line=function() end,
    button=function(label) if label==click then click=nil;return true end return false end,
    slider_float=function(_,v) return false,v end,checkbox=function(_,v) return false,v end,
    combo=function(_,v) return false,v end,input_text=function(_,v) return false,v end,
    drag_float=function(_,v) return false,v end}
local function ui_click(label) click=label;callbacks.ui();assert(click==nil,'Missing diagnostic button: '..label) end
