param([string]$LuaDll = 'C:\Program Files\Cheat Engine\lua53-64.dll')
$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$env:OXCART_TEST_LUA_DLL = $LuaDll
$taskSource = Get-Content -LiteralPath (Join-Path $taskProject 'reframework\autorun\aelinore debug tool.lua') -Raw
$taskSource | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py')
if ($LASTEXITCODE -ne 0) { throw 'NPC monitor syntax validation failed' }
$taskProgram = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'npc_monitor_mock.lua') -Raw) + "`n" +
    $taskSource + "`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'npc_monitor_assertions.lua') -Raw)
$taskProgram | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py') --execute
if ($LASTEXITCODE -ne 0) { throw 'NPC monitor simulation failed' }
$heightProgram = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'npc_monitor_mock.lua') -Raw) + "`n" +
    $taskSource + "`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'height_monitor_assertions.lua') -Raw)
$heightProgram | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py') --execute
if ($LASTEXITCODE -ne 0) { throw 'Pawn height monitor simulation failed' }
