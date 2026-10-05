local clock=100
os.clock=function() return clock end
local callbacks={}
local lookup_count,read_count,files=0,0,{}
local missing=false
local metadata_reads, metadata_error = 0, false
local npc={CharacterID=963132753,action='SitOnChairActions',bank=0,motion=2010}
function npc:get_Valid() return not missing end
function npc:get_GameObject() return {get_Name=function() return 'ch300298' end} end
function npc:get_ActionManager() return {CurrentActionList={[0]={Name=self.action}}} end
function npc:get_Motion() return {
getMotionCount=function() return 60 end,
call=function(_,method,bank,index,info)
    assert(method=='getMotionInfoByIndex(System.UInt32, System.UInt32, via.motion.MotionInfo)')
    assert(index>=0 and index<60)
    metadata_reads=metadata_reads+1
    if metadata_error then error('Unavailable motion metadata') end
    info.id=index==2 and 2010 or index==4 and 2020 or index==35 and 3521 or 9000+index
    info.name=index==2 and 'NpcSitLoop' or index==4 and 'NpcReadBookLoop' or index==35 and 'NpcDriveLoop' or 'Motion'..index
end,
getLayer=function(_,layer)
    if layer~=0 then return nil end
    return {get_MotionBankID=function() read_count=read_count+1;return npc.bank end,
        get_MotionID=function() return npc.motion end}
end} end
sdk={get_managed_singleton=function(name)
    assert(name=='app.NPCManager')
    return {getCharacter=function(_,id) lookup_count=lookup_count+1;if id==963132753 and not missing then return npc end end}
end,hook=function() error('Monitor installed hook') end,
create_instance=function(name,managed)
    assert(name=='via.motion.MotionInfo' and managed==true)
    return {get_MotionID=function(self) return self.id end,get_MotionName=function(self) return self.name end}
end}
json={load_file=function() return nil end,dump_file=function(_,value) files[#files+1]=value end}
re={on_application_entry=function(name,fn) callbacks[name]=fn end,on_draw_ui=function(fn) callbacks.ui=fn end,
    on_script_reset=function(fn) callbacks.reset=fn end}
local click,typed=nil,nil
imgui={tree_node=function() return true end,tree_pop=function() end,text=function() end,
    slider_float=function(_,value) return false,value end,
    input_text=function(_,value) if typed then local text=typed;typed=nil;return true,text end return false,value end,
    button=function(label) if click==label then click=nil;return true end return false end,
    checkbox=function(_,value) return false,value end}
