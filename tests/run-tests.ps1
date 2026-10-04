param([string]$LuaDll = 'C:\Program Files\Cheat Engine\lua53-64.dll')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$source = Join-Path $project 'reframework\autorun\Let me drive oxcart.lua'
$env:OXCART_TEST_LUA_DLL = $LuaDll
Get-Content -LiteralPath $source -Raw | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py')
if ($LASTEXITCODE -ne 0) { throw 'Syntax validation failed' }
$program = (Get-Content (Join-Path $PSScriptRoot 'runtime_mock.lua') -Raw) + "`n" +
    (Get-Content $source -Raw) + "`n" + (Get-Content (Join-Path $PSScriptRoot 'assertions.lua') -Raw)
$program | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py') --execute
if ($LASTEXITCODE -ne 0) { throw 'Runtime simulation failed' }
