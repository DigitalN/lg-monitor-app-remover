<#
.SYNOPSIS
    Detects and removes the auto-installed "LG Monitor App" adware and stops it
    silently reinstalling. Portable across machines (auto-discovers driver packages).

.DESCRIPTION
    Background: LG monitors (UltraGear and others) silently install the Microsoft
    Store app "LGElectronics.LGMonitorApp" via Windows Update / device metadata when
    the display is connected. Recent builds pop McAfee trial ads and the app declares
    "uses all system resources". This script:
      1. Reports any LG monitor app / driver hooks / running LG processes it finds.
      2. Removes the LGMonitorApp Store app (current user, all users, and provisioned).
      3. Deletes the LG "software component" + "extension" driver packages that
         re-trigger the install (found dynamically, not hardcoded).
      4. Sets policy PreventDeviceMetadataFromNetwork=1 so Windows won't auto-fetch
         companion apps for new hardware. (Skip with -SkipMetadataPolicy.)
      5. Re-verifies and prints a summary.

    The script self-elevates (UAC prompt). It does NOT touch the display driver, so
    the monitor keeps working normally.

.PARAMETER ScanOnly
    Report what's present and exit. Makes no changes. (No admin needed for a basic scan,
    but the script still elevates to read all-users packages / driver store fully.)

.PARAMETER SkipMetadataPolicy
    Remove the app + driver hooks but do NOT set the metadata-download policy
    (keeps Windows' auto-download of device companion apps/icons enabled).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Remove-LGMonitorAdware.ps1 -ScanOnly
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Remove-LGMonitorAdware.ps1
#>
[CmdletBinding()]
param(
    [switch]$ScanOnly,
    [switch]$SkipMetadataPolicy
)

$ErrorActionPreference = 'Continue'

function Write-Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Good($t)    { Write-Host "  [OK]  $t" -ForegroundColor Green }
function Write-Warn2($t)   { Write-Host "  [!]   $t" -ForegroundColor Yellow }
function Write-Info($t)    { Write-Host "  [i]   $t" -ForegroundColor Gray }

# ---- Self-elevate ----
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting administrator rights (approve the UAC prompt)..." -ForegroundColor Yellow
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$PSCommandPath`"")
    if ($ScanOnly)            { $argList += '-ScanOnly' }
    if ($SkipMetadataPolicy)  { $argList += '-SkipMetadataPolicy' }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -ErrorAction Stop
    } catch {
        Write-Host "Elevation was declined. Re-run and approve the UAC prompt to make changes." -ForegroundColor Red
    }
    return
}

Write-Host "LG Monitor App adware removal  --  $([Environment]::MachineName)" -ForegroundColor White
if ($ScanOnly) { Write-Host "MODE: SCAN ONLY (no changes will be made)" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 1. DETECT
# ---------------------------------------------------------------------------
Write-Section "Scan"

$app = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'LGElectronics|LGMonitor' }
if ($app) { $app | ForEach-Object { Write-Warn2 ("Store app present: {0}" -f $_.PackageFullName) } }
else      { Write-Good "No LG Monitor Store app installed." }

$prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'LGElectronics|LGMonitor' }
if ($prov) { $prov | ForEach-Object { Write-Warn2 ("Provisioned (new-user) package: {0}" -f $_.PackageName) } }

# Find LG driver packages dynamically by parsing pnputil /enum-drivers
$enum = & pnputil.exe /enum-drivers 2>$null | Out-String
$blocks = ($enum -split "\r?\n\r?\n")
$lgDrivers = @()
foreach ($b in $blocks) {
    if ($b -notmatch 'lgmonitor') { continue }   # skips header + unrelated packages
    $pub = $null; $orig = $null
    if ($b -match 'Published Name:\s*(?<pub>\S+)')  { $pub  = $Matches['pub'] }
    if ($b -match 'Original Name:\s*(?<orig>\S+)')  { $orig = $Matches['orig'] }
    if ($pub -and $orig -match 'lgmonitor') {
        $lgDrivers += [pscustomobject]@{ Published = $pub; Original = $orig }
    }
}
if ($lgDrivers) { $lgDrivers | ForEach-Object { Write-Warn2 ("LG driver hook: {0}  ({1})" -f $_.Published, $_.Original) } }
else            { Write-Good "No LG monitor-app driver packages in the driver store." }

$proc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Company -match 'LG Electronics' }
if ($proc) { $proc | ForEach-Object { Write-Warn2 ("Running LG process: {0} (PID {1})" -f $_.ProcessName, $_.Id) } }
else       { Write-Good "No running LG-signed processes." }

if ($ScanOnly) {
    Write-Host "`nScan complete (no changes made). Re-run without -ScanOnly to clean." -ForegroundColor Cyan
    if ($Host.Name -eq 'ConsoleHost') { Read-Host "`nPress Enter to close" }
    return
}

# ---------------------------------------------------------------------------
# 2. REMOVE APP
# ---------------------------------------------------------------------------
Write-Section "Remove app"
if ($app) {
    foreach ($p in $app) {
        try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; Write-Good ("Removed {0}" -f $p.Name) }
        catch {
            # Fall back to per-user removal if -AllUsers not permitted
            try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; Write-Good ("Removed (current user) {0}" -f $p.Name) }
            catch { Write-Warn2 ("Could not remove {0}: {1}" -f $p.Name, $_.Exception.Message) }
        }
    }
} else { Write-Info "Nothing to remove." }

if ($prov) {
    foreach ($pp in $prov) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null; Write-Good ("Deprovisioned {0}" -f $pp.PackageName) }
        catch { Write-Warn2 ("Could not deprovision {0}: {1}" -f $pp.PackageName, $_.Exception.Message) }
    }
}

# ---------------------------------------------------------------------------
# 3. DELETE DRIVER HOOKS
# ---------------------------------------------------------------------------
Write-Section "Delete driver hooks"
if ($lgDrivers) {
    foreach ($d in $lgDrivers) {
        $out = & pnputil.exe /delete-driver $d.Published /uninstall /force 2>&1 | Out-String
        if ($out -match 'deleted successfully') { Write-Good ("Deleted {0} ({1})" -f $d.Published, $d.Original) }
        else { Write-Warn2 ("{0}: {1}" -f $d.Published, ($out.Trim())) }
    }
} else { Write-Info "No LG driver hooks to delete." }

# ---------------------------------------------------------------------------
# 4. BLOCK RE-DOWNLOAD (metadata policy)
# ---------------------------------------------------------------------------
Write-Section "Reinstall block (device-metadata policy)"
if ($SkipMetadataPolicy) {
    Write-Info "Skipped per -SkipMetadataPolicy (Windows may re-offer companion apps for new hardware)."
} else {
    try {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name 'PreventDeviceMetadataFromNetwork' -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Good "PreventDeviceMetadataFromNetwork = 1  (Windows won't auto-download device apps)."
        Write-Info  "Trade-off: no auto-fetched companion apps/fancy icons for new hardware. To undo: set this value to 0 or delete it."
    } catch { Write-Warn2 ("Could not set policy: {0}" -f $_.Exception.Message) }
}

# ---------------------------------------------------------------------------
# 5. VERIFY
# ---------------------------------------------------------------------------
Write-Section "Verify"
$appLeft = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LGElectronics|LGMonitor' }
if ($appLeft) { Write-Warn2 "Store app STILL present." } else { Write-Good "Store app: gone." }
$enum2 = & pnputil.exe /enum-drivers 2>$null | Out-String
if ($enum2 -match 'lgmonitor') { Write-Warn2 "LG driver package STILL present." } else { Write-Good "Driver hooks: gone." }
if (-not $SkipMetadataPolicy) {
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'
    if ((Test-Path $k) -and (Get-ItemProperty $k).PreventDeviceMetadataFromNetwork -eq 1) { Write-Good "Reinstall-block policy: active." }
}
Write-Host "`nDone. A reboot clears any inert 'LG Monitor Support Application' phantom entries. Your monitor is unaffected." -ForegroundColor Cyan

if ($Host.Name -eq 'ConsoleHost') { Read-Host "`nPress Enter to close" }
