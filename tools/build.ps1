param([string]$GodotBinary = 'godot')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$expected = (Get-Content -LiteralPath (Join-Path $projectRoot '.engine-version')).Trim()
$actual = (& $GodotBinary --version | Out-String).Trim()
if (-not $actual.StartsWith("$expected.stable")) { throw "Expected Godot $expected stable; got $actual" }
$buildRoot = Join-Path $projectRoot '.local\build'
New-Item -ItemType Directory -Force -Path (Join-Path $buildRoot 'web'),(Join-Path $buildRoot 'windows') | Out-Null
& $GodotBinary --headless --editor --path $projectRoot --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
& $GodotBinary --headless --path $projectRoot --export-release 'Windows Desktop' (Join-Path $buildRoot 'windows\ShuDemo.exe')
if ($LASTEXITCODE -ne 0) { throw 'Windows export failed' }
& $GodotBinary --headless --path $projectRoot --export-release 'Web' (Join-Path $buildRoot 'web\index.html')
if ($LASTEXITCODE -ne 0) { throw 'Web export failed' }
foreach ($platform in 'windows','web') {
    $licenseDir = Join-Path (Join-Path $buildRoot $platform) 'licenses'
    New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\GODOT-LICENSE.txt'),(Join-Path $projectRoot 'assets\GODOT-NOTICES.txt'),(Join-Path $projectRoot 'assets\fonts\OFL.txt') -Destination $licenseDir
}
Write-Output "Built Windows and Web with $actual"
