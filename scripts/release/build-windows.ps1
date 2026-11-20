# Unsigned Windows x64 release, with the same Resources tree as build.sh.
# Run npm ci and npm run build:office-editor in office/ first.
# RELEASE_OUT, CARGO_TARGET_DIR, BROKER_TARGET_DIR, NSH_TARGET_DIR,
# BUWIZ_BOT_BIN, BUWIZ_BROKER_BIN, NSH_BIN, NSH_HOST_BIN,
# NODE_MODULES, OFFICE_DIST, OFFICE_FONTS and MATERIAL_SYMBOLS_TTF
# override the corresponding build.sh inputs. ISCC selects Inno Setup 6.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

function Setting([string]$Name, [string]$Default) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function FullPath([string]$Path) {
    if (![IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $Root $Path }
    return [IO.Path]::GetFullPath($Path)
}

function Require([string]$Path, [string]$Hint) {
    if (!(Test-Path -LiteralPath $Path)) { throw "Missing ${Path}: $Hint" }
}

function Native([string]$Program, [string[]]$Arguments) {
    Write-Host "> $Program $($Arguments -join ' ')"
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

function CargoVersion([string]$Workspace, [string]$Package) {
    $json = & cargo metadata --locked --no-deps --format-version 1 --manifest-path (Join-Path $Workspace 'Cargo.toml')
    if ($LASTEXITCODE -ne 0) { throw "cargo metadata failed for $Workspace" }
    $packages = @(($json | ConvertFrom-Json).packages | Where-Object { $_.name -eq $Package })
    if ($packages.Count -ne 1) { throw "Expected one $Package package in $Workspace" }
    return $packages[0].version
}

function CargoRelease([string]$Workspace, [string]$Target, [string[]]$BuildArgs) {
    Push-Location $Workspace
    $previous = $env:CARGO_TARGET_DIR
    try {
        $env:CARGO_TARGET_DIR = $Target
        Native 'cargo' (@('build', '--release', '--locked', '--target', 'x86_64-pc-windows-msvc') + $BuildArgs)
    } finally {
        $env:CARGO_TARGET_DIR = $previous
        Pop-Location
    }
}

function CheckVersion([string]$Binary, [string]$Expected) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Binary
    $start.Arguments = '--version'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['BUWIZ_BACKEND'] = 'http://127.0.0.1:1'
    $start.EnvironmentVariables['BUWIZ_DATA_DIR'] = Join-Path $Out 'version-check/data'
    $start.EnvironmentVariables['BUWIZ_BACKGROUND'] = '1'
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (!$process.Start()) { throw "Could not start $Binary --version" }
        if (!$process.WaitForExit(30000)) {
            $process.Kill()
            throw "$Binary --version timed out"
        }
        $actual = $process.StandardOutput.ReadToEnd().Trim()
        $errorText = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0 -or $actual -cne $Expected) {
            throw "$Binary --version: expected '$Expected', got '$actual' ($errorText)"
        }
        Write-Host $actual
    } finally { $process.Dispose() }
}

if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Build on Windows x64' }
$rust = & rustc -vV
if ($LASTEXITCODE -ne 0 -or !($rust -contains 'host: x86_64-pc-windows-msvc')) {
    throw 'The x86_64-pc-windows-msvc Rust toolchain is required'
}
$env:RUSTC_WRAPPER = ''
$Out = FullPath (Setting 'RELEASE_OUT' (Join-Path $Root 'dist'))
$AppTarget = FullPath (Setting 'CARGO_TARGET_DIR' (Join-Path $Root 'app/target'))
$BrokerTarget = FullPath (Setting 'BROKER_TARGET_DIR' (Join-Path $Root 'broker/target'))
$NshTarget = FullPath (Setting 'NSH_TARGET_DIR' (Setting 'CARGO_TARGET_DIR' (Join-Path $Root 'nsh/target')))
$Office = Join-Path $Root 'office'
$Modules = FullPath (Setting 'NODE_MODULES' (Join-Path $Office 'node_modules'))
$Fonts = FullPath (Setting 'OFFICE_FONTS' (Join-Path $Modules '@betteroffice/fonts'))
$Editor = FullPath (Setting 'OFFICE_DIST' (Join-Path $Office 'editor/dist'))
$Assets = Join-Path $Root 'broker/buwiz-broker/assets'
Require (Join-Path $Modules '@betteroffice') 'run npm ci in office/'
Require (Join-Path $Fonts 'assets/Carlito-Regular.ttf') 'run npm ci in office/'
Require (Join-Path $Fonts 'LICENSES') 'office font licenses are required'
Require (Join-Path $Fonts 'LICENSE') 'office font license is required'
Require (Join-Path $Editor 'editor.js') 'run npm run build:office-editor in office/'

$Iscc = Setting 'ISCC' ''
if (!$Iscc) {
    $found = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($found) { $Iscc = $found.Source }
    else { $Iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe' }
}
Require $Iscc 'install Inno Setup 6 (choco install innosetup -y), or set ISCC'

$Version = CargoVersion (Join-Path $Root 'app') 'buwiz-bot'
$BrokerVersion = CargoVersion (Join-Path $Root 'broker') 'buwiz-broker'
if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $BrokerVersion -ne $Version) {
    throw "App ($Version) and broker ($BrokerVersion) must share a MAJOR.MINOR.PATCH version"
}

$SymbolsUrl = 'https://fonts.gstatic.com/s/materialsymbolsoutlined/v382/kJF1BvYX7BgnkSrUwT8OhrdQw4oELdPIeeII9v6oDMzByHX9rA6RzaxHMPdY43zj-jCxv3fzvRNU22ZXGJpEpjC_1v-p_4MrImHCIJIZrDCvHOem.ttf'
$SymbolsHash = '69b4db8f8971c5206adb2d3891787c33eee828271fa56209e05ee0e3202729dd'
$SymbolsOverride = Setting 'MATERIAL_SYMBOLS_TTF' ''
$Symbols = FullPath (Setting 'MATERIAL_SYMBOLS_TTF' (Join-Path $env:LOCALAPPDATA 'Buwiz Bot/Cache/fonts/MaterialSymbolsOutlined-v382.ttf'))
if (!(Test-Path -LiteralPath $Symbols) -and !$SymbolsOverride) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Symbols) | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $SymbolsUrl -OutFile "$Symbols.part"
        if ((Get-FileHash "$Symbols.part" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $SymbolsHash) {
            throw 'Material Symbols Outlined sha256 mismatch'
        }
        Move-Item -Force -LiteralPath "$Symbols.part" -Destination $Symbols
    } finally {
        if (Test-Path -LiteralPath "$Symbols.part") { Remove-Item -LiteralPath "$Symbols.part" -Force }
    }
}
Require $Symbols "download $SymbolsUrl, or set MATERIAL_SYMBOLS_TTF"
if ((Get-FileHash $Symbols -Algorithm SHA256).Hash.ToLowerInvariant() -ne $SymbolsHash) {
    throw "Material Symbols Outlined sha256 mismatch: $Symbols"
}
Write-Host "Material Symbols Outlined sha256 verified: $SymbolsHash"

$AppBin = Setting 'BUWIZ_BOT_BIN' ''
if (!$AppBin) {
    CargoRelease (Join-Path $Root 'app') $AppTarget @('--bin', 'buwiz-bot', '--no-default-features')
    $AppBin = Join-Path $AppTarget 'x86_64-pc-windows-msvc/release/buwiz-bot.exe'
}
$AppBin = FullPath $AppBin
Require $AppBin 'app release build is required'
$strings = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($AppBin))
foreach ($setting in @('gpui-agent: serving', 'BUWIZ_HUB_POSTED_ALLOW', 'GPUI_AGENT_ACTOR', 'BUWIZ_HUB_FULL_TEXT')) {
    if ($strings.Contains($setting)) { throw "$AppBin contains '$setting': build with --no-default-features" }
}
$strings = $null
$BrokerBin = Setting 'BUWIZ_BROKER_BIN' ''
if (!$BrokerBin) {
    CargoRelease (Join-Path $Root 'broker') $BrokerTarget @('-p', 'buwiz-broker')
    $BrokerBin = Join-Path $BrokerTarget 'x86_64-pc-windows-msvc/release/buwiz-broker.exe'
}
$NshBin = Setting 'NSH_BIN' ''
$HostBin = Setting 'NSH_HOST_BIN' ''
if ([bool]$NshBin -ne [bool]$HostBin) { throw 'Set both NSH_BIN and NSH_HOST_BIN, or neither' }
if (!$NshBin) {
    CargoRelease (Join-Path $Root 'nsh') $NshTarget @('-p', 'nsh-cli', '-p', 'nsh-windows-host')
    $NshBin = Join-Path $NshTarget 'x86_64-pc-windows-msvc/release/nsh.exe'
    $HostBin = Join-Path $NshTarget 'x86_64-pc-windows-msvc/release/nsh-windows-host.exe'
}
$BrokerBin = FullPath $BrokerBin
$NshBin = FullPath $NshBin
$HostBin = FullPath $HostBin
foreach ($binary in @($BrokerBin, $NshBin, $HostBin)) { Require $binary 'release binary is required' }

$Stage = Join-Path $Out 'stage'
if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
$Resources = Join-Path $Stage 'Resources'
$Broker = Join-Path $Resources 'broker'
foreach ($dir in @('bin', 'Resources/fonts/office/LICENSES', 'Resources/broker/bin',
    'Resources/broker/server/office/editor/dist', 'Resources/broker/node_modules')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage $dir) | Out-Null
}
Copy-Item -LiteralPath $AppBin -Destination (Join-Path $Stage 'bin/buwiz-bot.exe')
Copy-Item -LiteralPath $Symbols -Destination (Join-Path $Resources 'fonts/MaterialSymbolsOutlined.ttf')
Copy-Item -LiteralPath (Join-Path $Root 'app/fonts/MaterialSymbolsOutlined-LICENSE') -Destination (Join-Path $Resources 'fonts')
Copy-Item -Path (Join-Path $Fonts 'assets/*.ttf') -Destination (Join-Path $Resources 'fonts/office')
Copy-Item -Path (Join-Path $Fonts 'LICENSES/*') -Destination (Join-Path $Resources 'fonts/office/LICENSES') -Recurse
Copy-Item -LiteralPath (Join-Path $Fonts 'LICENSE') -Destination (Join-Path $Resources 'fonts/office')
Copy-Item -LiteralPath $BrokerBin -Destination (Join-Path $Broker 'buwiz-broker.exe')
Copy-Item -LiteralPath $NshBin -Destination (Join-Path $Broker 'bin/nsh.exe')
Copy-Item -LiteralPath $HostBin -Destination (Join-Path $Broker 'bin/nsh-windows-host.exe')
Copy-Item -LiteralPath (Join-Path $Office 'viewer.html') -Destination (Join-Path $Broker 'server/office/viewer.html')
Copy-Item -LiteralPath (Join-Path $Office 'editor/editor.html') -Destination (Join-Path $Broker 'server/office/editor/editor.html')
Copy-Item -LiteralPath (Join-Path $Office 'seeds') -Destination (Join-Path $Broker 'server/office/seeds') -Recurse
Copy-Item -Path (Join-Path $Editor '*') -Destination (Join-Path $Broker 'server/office/editor/dist') -Recurse
Copy-Item -LiteralPath (Join-Path $Assets 'plugins') -Destination (Join-Path $Broker 'server/plugins') -Recurse
Copy-Item -LiteralPath (Join-Path $Assets 'trust.json') -Destination (Join-Path $Broker 'server/trust.json')
Copy-Item -LiteralPath (Join-Path $Modules '@betteroffice') -Destination (Join-Path $Broker 'node_modules/@betteroffice') -Recurse
Get-ChildItem -LiteralPath $Stage -Recurse -Force -Filter '.DS_Store' | Remove-Item -Force

CheckVersion (Join-Path $Stage 'bin/buwiz-bot.exe') "buwiz-bot $Version"
CheckVersion (Join-Path $Broker 'buwiz-broker.exe') "buwiz-broker $Version"
Native $Iscc @("/DAppVersion=$Version", "/DStageDir=$Stage", "/O$Out", (Join-Path $PSScriptRoot 'buwiz-bot.iss'))
$Setup = Join-Path $Out "Buwiz-Bot-$Version-windows-x64-setup.exe"
Require $Setup 'Inno Setup did not create the installer'
$Hash = (Get-FileHash -LiteralPath $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
$Sum = "$Hash  $([IO.Path]::GetFileName($Setup))"
[IO.File]::WriteAllText("$Setup.sha256", "$Sum`n", [Text.Encoding]::ASCII)
Write-Host $Sum
Write-Host "Built unsigned $Setup ($((Get-Item -LiteralPath $Setup).Length) bytes)"
