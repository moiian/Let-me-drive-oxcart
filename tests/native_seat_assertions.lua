;(function()
local previous_gm=ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']
local previous_singleton,previous_type=sdk.get_managed_singleton,sdk.find_type_definition
local previous_dump=json.dump_file
local interacting,active=false,nil
local requests,exits,refs=0,0,0
local seat={}
local data={mask=8,get_field=function(self,key) return key=='CharacterType' and self.mask or 'driver_joint' end,
    set_field=function(self,key,value) assert(key=='CharacterType');self.mask=value end}
local io=object('native_io')
function io:call(method,point,ch)
    if method=='get_IsRegistered()' or method=='get_IsUpdatedAfterRegisterd()' then return true end
    if method=='getNumInteractPoint()' then return 3 end
    if method=='isInteractEnable(System.UInt32, app.Character)' then return point==1 and data.mask==9 end
    assert(method=='endInteractForSystem(System.UInt32, app.Character)' and point==1 and ch==human,method)
    exits=exits+1
end
local result={value=0,get_field=function(self) return self.value end,
    add_ref=function() refs=refs+1 end,release=function() refs=refs-1 end}
local mgr={call=function(_,method,a,point,ch)
    if method=='isInteracting(app.Character)' then return interacting end
    if method=='getActiveInteract(app.Character)' then return active end
    assert(method=='requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)'
        and a==io and point==1 and ch==human,method)
    requests=requests+1;return result
end}
local gm=object('native_cart')
gm.InteractiveObject=io
gm.NonDriverSeatNoList={call=function(_,method) return method=='get_Count()' and 1 or 1 end}
gm.InteractiveObjectDataList={get_element=function(_,i) return i==1 and data or
    {get_field=function(_,key) return key=='CharacterType' and 1 or 'other_joint' end} end}
function gm:get_type_definition() return {get_method=function() return {get_num_params=function() return 0 end} end} end
function gm:call(method,i)
    if method=='get_DrivingSeat' then return seat end
    if method=='getSeatNo(System.UInt32)' then return ({[0]=-1,[1]=0,[2]=1})[i] end
    if method=='getInteractChara(System.UInt32)' then return nil end
    error(method)
end
sdk.get_managed_singleton=function(name) return name=='app.InteractManager' and mgr or previous_singleton(name) end
sdk.find_type_definition=function(name)
    if name=='app.InteractManager.InteractRequestResultType' then
        return {get_field=function() return {get_data=function() return 1 end} end}
    end
    return previous_type(name)
end
json.dump_file=function() end
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=gm
state.active=false;is_paused=false
local position,warps,falls,fsm=human.pos,human.test_controller.warps,human.test_fall.reset_calls,human.machine.enabled
local function command(value)
    assert(driver_debug_bridge.native_seat_command(value));clock=clock+0.2;driver_debug_bridge.native_seat_tick()
end
command('scan')
assert(#driver_debug_bridge.native_seat_read().rows==3 and requests==0 and data.mask==8,driver_debug_bridge.native_seat_read().status)
seat.SitChara=driver;command('enter')
assert(requests==0 and not driver_debug_bridge.native_seat_busy(),'Occupied seat accepted')
seat.SitChara=nil;command('enter')
assert(requests==1 and data.mask==9 and refs==1,'Driver Player bit/request missing')
result.value=1;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Denied request leaked mask/lease')
result.value=0;command('enter')
interacting=true;active={Point={Object=io,PointNo=1}};seat.SitChara=human
clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(driver_debug_bridge.native_seat_read().status:find('CONFIRMED',1,true),'Native binding not confirmed')
assert(not pcall(acquire),'Manual acquisition overlaps native ownership')
active.Point.PointNo=2;command('exit');assert(exits==0,'Exited unrelated passenger interaction')
active.Point.PointNo=1;command('exit');assert(exits==1 and data.mask==9,'Mask restored before engine exit')
interacting=false;seat.SitChara=nil;clock=clock+0.2;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Exit cleanup failed')
command('enter');clock=clock+16;driver_debug_bridge.native_seat_tick()
assert(data.mask==8 and refs==0 and not driver_debug_bridge.native_seat_busy(),'Timeout cleanup failed')
assert(human.pos==position and human.test_controller.warps==warps and human.test_fall.reset_calls==falls
    and human.machine.enabled==fsm,'Native entry wrote forced player state')
ox.EnemyCtrl.Ch2['<CachedOxcart>k__BackingField']=previous_gm
sdk.get_managed_singleton,sdk.find_type_definition=previous_singleton,previous_type
json.dump_file=previous_dump
print('PASS: isolated native driver point, occupied/denied rejection, binding, owned exit, timeout, no forced player writes')
end)()
