$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$out = Join-Path $PSScriptRoot "bin\Release"
$csc = "C:\Program Files\dotnet\sdk\9.0.313\Roslyn\bincore\csc.dll"
$netCoreRef = "C:\Program Files\dotnet\packs\Microsoft.NETCore.App.Ref\10.0.5\ref\net10.0"
$desktopRef = "C:\Program Files\dotnet\packs\Microsoft.WindowsDesktop.App.Ref\10.0.5\ref\net10.0"
$game = "D:\Vintagestory"

New-Item -ItemType Directory -Force -Path $out | Out-Null

$refs = @()
$refs += Get-ChildItem "$netCoreRef\*.dll" | ForEach-Object { "/r:$($_.FullName)" }
$refs += Get-ChildItem "$desktopRef\*.dll" | ForEach-Object { "/r:$($_.FullName)" }
$refs += "/r:$game\Lib\0Harmony.dll"
$refs += "/r:$game\VintagestoryAPI.dll"
$refs += "/r:$game\VintagestoryLib.dll"

dotnet $csc /noconfig /nostdlib+ /target:library /langversion:latest /nullable:enable /out:"$out\VintageShaderPolish.dll" @refs "$PSScriptRoot\*.cs"
