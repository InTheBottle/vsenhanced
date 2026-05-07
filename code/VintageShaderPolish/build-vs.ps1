$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$out = Join-Path $PSScriptRoot "bin\Release"
$packageRoot = Join-Path $root "_packaging\VintageShaderPolish"
$assetsRoot = Join-Path $packageRoot "assets\game"
$csc = "C:\Program Files\dotnet\sdk\9.0.313\Roslyn\bincore\csc.dll"
$netCoreRef = "C:\Program Files\dotnet\packs\Microsoft.NETCore.App.Ref\10.0.5\ref\net10.0"
$desktopRef = "C:\Program Files\dotnet\packs\Microsoft.WindowsDesktop.App.Ref\10.0.5\ref\net10.0"
$game = "D:\Vintagestory"

New-Item -ItemType Directory -Force -Path $out | Out-Null

$refs = @()
$refs += Get-ChildItem "$netCoreRef\*.dll" | ForEach-Object { "/r:$($_.FullName)" }
$refs += Get-ChildItem "$desktopRef\*.dll" | ForEach-Object { "/r:$($_.FullName)" }
$refs += "/r:$game\Lib\0Harmony.dll"
$refs += "/r:$game\Lib\OpenTK.Graphics.dll"
$refs += "/r:$game\Lib\OpenTK.Mathematics.dll"
$refs += "/r:$game\VintagestoryAPI.dll"
$refs += "/r:$game\VintagestoryLib.dll"

dotnet $csc /noconfig /nostdlib+ /target:library /langversion:latest /nullable:enable /out:"$out\VintageShaderPolish.dll" @refs "$PSScriptRoot\*.cs"

Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $assetsRoot "shaders"), (Join-Path $assetsRoot "shaderincludes")
New-Item -ItemType Directory -Force -Path (Join-Path $assetsRoot "shaders"), (Join-Path $assetsRoot "shaderincludes") | Out-Null
Copy-Item -Force "$out\VintageShaderPolish.dll" (Join-Path $packageRoot "VintageShaderPolish.dll")
Copy-Item -Force (Join-Path $root "shaders\*") (Join-Path $assetsRoot "shaders")
Copy-Item -Force (Join-Path $root "shaderincludes\*") (Join-Path $assetsRoot "shaderincludes")

$version = (Get-Content (Join-Path $packageRoot "modinfo.json") | ConvertFrom-Json).version
$zip = Join-Path $root "vintage-shader-polish-$version.zip"
Remove-Item -Force -ErrorAction SilentlyContinue $zip
Compress-Archive -Force -Path (Join-Path $packageRoot "*") -DestinationPath $zip
