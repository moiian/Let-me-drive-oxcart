param([string]$LuaDll = 'C:\Program Files\Cheat Engine\lua53-64.dll')
$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$env:OXCART_TEST_LUA_DLL = $LuaDll
$taskDiagnostic = Get-Content -LiteralPath (Join-Path $taskProject 'reframework\autorun\Let me drive oxcart Position Diagnostics.lua') -Raw
$taskDiagnostic | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py')
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic syntax check failed' }
$taskProgram = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime_mock.lua') -Raw) + "`n" +
    (Get-Content -LiteralPath (Join-Path $taskProject 'reframework\autorun\Let me drive oxcart.lua') -Raw) + "`n" +
    (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'diagnostics_mock.lua') -Raw) + "`n" +
    "assert(load([====[`n$taskDiagnostic`n]====], 'position-diagnostics'))()`n" +
    (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'diagnostics_assertions.lua') -Raw)
$taskProgram | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py') --execute
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic simulation failed' }
