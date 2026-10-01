# LG Monitor App Remover

A PowerShell script that removes the **LG Monitor App** Windows silently installs when you plug in an
LG monitor, and stops it coming back. Works on Windows 10 and 11. Makes no network connections.

## Why

Plugging in an LG monitor can make Windows install `LGElectronics.LGMonitorApp` from the Microsoft Store
with no prompt. It runs at startup and has shown McAfee ads. Removing it doesn't affect your monitor,
which keeps working through the normal display driver.

## Usage

1. [Download the script](https://raw.githubusercontent.com/DigitalN/lg-monitor-app-remover/main/Remove-LGMonitorAdware.ps1)
   (right-click, **Save link as**), or from PowerShell:
   ```powershell
   irm https://raw.githubusercontent.com/DigitalN/lg-monitor-app-remover/main/Remove-LGMonitorAdware.ps1 -OutFile .\Remove-LGMonitorAdware.ps1
   ```
2. Open PowerShell in the folder where you saved it and scan first (changes nothing):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Remove-LGMonitorAdware.ps1 -ScanOnly
   ```
3. Clean up:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Remove-LGMonitorAdware.ps1
   ```
4. Approve the UAC prompt. Rebooting afterwards clears leftover device entries (optional).

Always save the file and run it with `-File`. Piping it into `iex` won't work.

| Option | Effect |
|---|---|
| `-ScanOnly` | Report what's installed. Changes nothing. |
| `-SkipMetadataPolicy` | Don't turn on the reinstall block (step 4 below). |

## What it does

1. Scans for LG Store apps, LG driver packages and running LG processes.
2. Removes **every** LG Store app (`LGElectronics.*` or `*LGMonitor*`) for all users and new accounts.
   This is deliberately broad.
3. Deletes the LG driver packages that trigger the install. They're found automatically, since the
   `oemNN.inf` names differ on every PC.
4. Turns on the Windows policy that stops any device auto-installing its companion app
   (`PreventDeviceMetadataFromNetwork = 1`).
5. Checks everything again and prints a summary.

It always runs elevated in Windows PowerShell 5.1, relaunching itself if needed, and is safe to re-run.
Each run saves a log next to the script (`LGMonitorRemover_<scan|clean>_<date>_<time>.log`). Logs stay
on your PC.

## Trade-off and undo

Step 4 applies to all hardware: Windows won't auto-download companion apps or custom icons for any new
device. You can still install those apps yourself. To undo it, run this in an admin PowerShell:

```powershell
Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' -Name PreventDeviceMetadataFromNetwork
```

## Troubleshooting

- **Driver still listed after "deleted successfully".** If the LG driver came through Windows Update,
  Windows can silently undo the deletion. It's harmless: the driver only reacts to LG monitor hardware,
  and with the app removed and the policy on, it can't reinstall anything. Leave it, and don't take
  ownership of the DriverStore folder to delete it by hand. If Windows Update keeps offering it, hide it
  with Microsoft's "Show or hide updates" tool (wushowhide).
- **"LG Monitor Support Application" devices showing Unknown** after cleanup are inert and disappear
  after a reboot.

## Manual method

In an admin PowerShell:

```powershell
# Remove LG Store apps
Get-AppxPackage -AllUsers | Where-Object Name -match 'LGElectronics|LGMonitor' | Remove-AppxPackage -AllUsers
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -match 'LGElectronics|LGMonitor' | Remove-AppxProvisionedPackage -Online

# List LG driver packages, then delete each Published Name (oemNN.inf).
# Don't add /uninstall: pnputil ignores /force when both are given.
pnputil /enum-drivers | Select-String -Context 1,4 lgmonitor
pnputil /delete-driver oemNN.inf /force

# Block reinstalls
New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' -Force | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' `
  -Name PreventDeviceMetadataFromNetwork -Value 1 -PropertyType DWord -Force
```

On Windows Pro you can set the block in `gpedit.msc` instead: Computer Configuration > Administrative
Templates > System > Device Installation > **Prevent automatic download of applications associated with
device metadata** (called "Prevent device metadata retrieval from the Internet" on older Windows) >
Enabled.

## Credits

Forked from [samuelcon41/lg-monitor-app-remover](https://github.com/samuelcon41/lg-monitor-app-remover)
by Sam, who wrote the original script, documentation and driver troubleshooting research. This fork
adds a `/force` retry for stuck drivers, always runs in Windows PowerShell 5.1, shows a clear message
when piped into `iex`, and writes log files.

## License

[MIT](LICENSE). Provided as-is with no warranty. Review the script before running it.
