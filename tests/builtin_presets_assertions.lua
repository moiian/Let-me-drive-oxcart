assert(#settings.presets==10 and settings.builtin_presets_rule==1)
local counts={}
for _,layout in ipairs(settings.presets) do
    assert(layout.builtin_id and layout.name:find(' - Default ',1,true))
    counts[layout.family]=(counts[layout.family] or 0)+1
end
assert(counts.Normal==4 and counts.Rainy==2 and counts.Wealthy==4)
assert(settings.presets[1].slots[1].x==-0.050999999046325684
    and settings.presets[1].camera.distance==3.9820001125335693,
    'Approved player/camera parameters lost')
assert(settings.presets[9].slots[2].y==3.0399999618530273,
    'Approved high pawn seat was normalized incorrectly')
local custom=copy_layout(settings.presets[1],next_layout_name('Normal'),'Normal')
assert(custom.name=='Normal - 1' and custom.builtin_id==nil)
settings.presets[#settings.presets+1]=custom
assert(next_layout_name('Normal')=='Normal - 2'
    and next_layout_name('Rainy')=='Rainproof - 1'
    and next_layout_name('Wealthy')=='Luxury - 1')
custom.name=settings.presets[1].name -- Name alone must never determine ownership.
custom.slots[1].x=7;custom.camera.fov=110
local original=clone_builtin(builtin_presets[1])
settings.presets[1].slots[1].x=8;settings.presets[1].camera.fov=90
settings.presets[1].name='Renamed built-in'
table.remove(settings.presets,2) -- Restore must also recreate deleted built-ins.
assert(driver_debug_bridge.restore_builtin_presets())
assert(settings.presets[1].slots[1].x==8,'Restore bypassed stand/delay')
clock=clock+0.31;driver_debug_bridge.switch_preset_tick()
assert(#settings.presets==11 and settings.presets[1].name==original.name
    and settings.presets[1].slots[1].x==original.slots[1].x
    and settings.presets[1].camera.fov==original.camera.fov)
assert(custom.slots[1].x==7 and custom.camera.fov==110
    and custom.name==original.name and custom.builtin_id==nil,
    'Restore changed a user-added preset with a built-in name')
local ids={}
for _,layout in ipairs(settings.presets) do
    if layout.builtin_id then assert(not ids[layout.builtin_id]);ids[layout.builtin_id]=true end
end
for _,layout in ipairs(builtin_presets) do assert(ids[layout.builtin_id]) end
local first=settings.presets[1]
first.slots[1].x=9
assert(builtin_presets[1].slots[1].x==original.slots[1].x,'Mutable preset changed factory template')
assert(driver_debug_bridge.restore_builtin_presets())
driver_debug_bridge.stand_hotkey()
clock=clock+1;driver_debug_bridge.switch_preset_tick()
assert(settings.presets[1]==first,'Stand did not cancel pending default restore')
local captured
json.dump_file=function(_,value) captured=value end
save()
assert(captured.builtin_presets_rule==1 and captured.presets[1].builtin_id,
    'Built-in identity not persisted')
print('PASS: ten approved built-ins, per-cart naming, isolated reset, deleted built-in restore and Stand cancellation')
