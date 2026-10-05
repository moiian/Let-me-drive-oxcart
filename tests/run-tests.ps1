param([string]$LuaDll = 'C:\Program Files\Cheat Engine\lua53-64.dll')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$source = Join-Path $project 'reframework\autorun\Let me drive oxcart.lua'
$env:OXCART_TEST_LUA_DLL = $LuaDll
Get-Content -LiteralPath $source -Raw | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py')
if ($LASTEXITCODE -ne 0) { throw 'Syntax validation failed' }
$program = (Get-Content (Join-Path $PSScriptRoot 'runtime_mock.lua') -Raw) + "`n" +
    (Get-Content $source -Raw) + "`n" + (Get-Content (Join-Path $PSScriptRoot 'assertions.lua') -Raw) + "`n" +
    (Get-Content (Join-Path $PSScriptRoot 'driving_features_assertions.lua') -Raw) + "`n" +
    (Get-Content (Join-Path $PSScriptRoot 'native_seat_assertions.lua') -Raw)
$program | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py') --execute
if ($LASTEXITCODE -ne 0) { throw 'Runtime simulation failed' }
$migrationFixture = @'
local function fixture_layout(name)
    return {name=name,slots={{x=0,y=1,z=0,yaw=178},{x=1,y=1,z=-2,yaw=180},
        {x=-1,y=1,z=-2,yaw=180},{x=1,y=1,z=-3,yaw=180}}}
end
local legacy_layout=fixture_layout('Legacy')
local modern_layout=fixture_layout('Modern')
modern_layout.player_visual={enabled=false,offset={x=99,y=-99,z=3}}
modern_layout.camera={fov_enabled=false,fov=35,distance_enabled=true,distance=99}
_G.LMD_TEST_CONFIG={player_seat_rule=1,player_pose_lock_rule=1,cart_family_rule=1,preset=2,
    bindings={up={gamepad='LTrigTop'},down={gamepad='RTrigTop'}},
    debug_player_visual_seat=true,player_root_offset={x=0.4,y=0.3,z=-1},
    camera_fov_enabled=true,camera_fov=84,camera_distance_enabled=true,camera_distance=2.5,
    presets={legacy_layout,modern_layout}}
'@
$migrationChecks = @'
assert(settings.presets[1].player_visual.enabled and settings.presets[1].player_visual.offset.z==-1,
    'Loading an old config lost visual offsets')
assert(settings.preset==2 and not current_visual().enabled and current_visual().offset.x==10
    and current_visual().offset.y==-10 and current_visual().offset.z==3,
    'Layout-specific config did not override legacy globals or clamp values')
assert(settings.debug_player_pose_lock and settings.debug_player_position_sync and settings.debug_player_reset_fall
    and not settings.debug_player_freeze,'Release protection defaults incorrect')
assert(settings.presets[1].enabled and settings.presets[1].slots[1].randomIdle,'Default cycling/player idle migration failed')
assert(settings.presets[1].camera.fov_enabled and settings.presets[1].camera.fov==84
    and settings.presets[1].camera.distance==2.5,'Global camera settings not migrated')
assert(not settings.presets[2].camera.fov_enabled and settings.presets[2].camera.fov==35
    and settings.presets[2].camera.distance==10,'Per-layout camera precedence/clamp failed')
assert(settings.presets[1].camera~=settings.presets[2].camera,'Presets share camera settings')
local serialized
assert(settings.bindings.up.gamepad=='RTrigTop' and settings.bindings.down.gamepad=='LTrigTop',
    'Old default shoulder pair did not migrate')
json.dump_file=function(_,value) serialized=value end
save()
assert(serialized.presets[1].player_visual.offset.z==-1 and serialized.presets[2].player_visual.offset.z==3
    and serialized.player_root_offset==nil and serialized.debug_player_visual_seat==nil,
    'Save retained ambiguous global visual settings')
print('PASS: persisted legacy migration, per-layout precedence, widened clamps and new save schema')
assert(serialized.camera_fov==nil and serialized.camera_distance==nil
    and serialized.presets[1].camera.fov==84,'Save kept ambiguous global camera settings')
'@
$migrationProgram = $migrationFixture + "`n" +
    (Get-Content (Join-Path $PSScriptRoot 'runtime_mock.lua') -Raw) + "`n" +
    (Get-Content $source -Raw) + "`n" + $migrationChecks
$migrationProgram | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py') --execute
if ($LASTEXITCODE -ne 0) { throw 'Config migration simulation failed' }
