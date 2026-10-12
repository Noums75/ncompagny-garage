param(
    [string]$Lua = 'lua',
    [string]$LuaCompiler = 'luac',
    [string]$Node = 'node'
)

$ErrorActionPreference = 'Stop'
$resourceRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $resourceRoot
try {
    $luaFiles = @(
        Get-Item -LiteralPath 'fxmanifest.lua'
        Get-ChildItem -LiteralPath 'shared', 'client', 'server', 'tests' -Filter '*.lua' -File
    )
    foreach ($sourceFile in $luaFiles) {
        & $LuaCompiler -p $sourceFile.FullName
        if ($LASTEXITCODE -ne 0) { throw "Syntaxe Lua invalide : $($sourceFile.Name)" }
    }
    foreach ($sourceFile in (Get-ChildItem -LiteralPath 'web' -Filter '*.js' -File)) {
        & $Node --check $sourceFile.FullName
        if ($LASTEXITCODE -ne 0) { throw "Syntaxe JS invalide : $($sourceFile.Name)" }
    }
    foreach ($spec in (Get-ChildItem -LiteralPath 'tests' -Filter '*_spec.lua' -File | Sort-Object Name)) {
        & $Lua $spec.FullName
        if ($LASTEXITCODE -ne 0) { throw "Echec du test : $($spec.Name)" }
    }
    foreach ($spec in (Get-ChildItem -LiteralPath 'tests' -Filter '*_spec.js' -File | Sort-Object Name)) {
        & $Node $spec.FullName
        if ($LASTEXITCODE -ne 0) { throw "Echec du test : $($spec.Name)" }
    }
    Write-Output 'Toutes les verifications locales ont reussi.'
} finally {
    Pop-Location
}
