# LG Monitor App Remover

A single, self-elevating PowerShell script that removes the silently‑installed **"LG Monitor App"**
(`LGElectronics.LGMonitorApp`) from Windows 10/11 and stops it from reinstalling.

Scan first, clean when you're ready. Safe to re-run. No dependencies — just Windows PowerShell.

---

## The problem

When an LG monitor is connected, Windows auto‑installs the Microsoft Store app
**`LGElectronics.LGMonitorApp`** through the device‑metadata / Windows Update mechanism —
**no prompt, no consent.** Recent builds pop up **McAfee trial ads**, and the app declares that it
"uses all system resources." Because it arrives via a *driver software‑component hook* rather than a
normal install, most people never remember installing it and can't fully remove it from the Store.

It isn't covert malware — it's LG's official monitor‑control app — but it's unwanted, auto‑installed
adware. **Removing it does not affect your display**; the monitor keeps working through the normal
GPU/monitor driver.

> This got wide press coverage in July 2026 (Tom's Hardware, TechSpot, Windows Latest, Gizmodo, and
> others). The same silent‑install mechanism has been used by other vendors too (e.g. Alienware).

---

## What the script does

| Step | Action |
|------|--------|
| **1. Scan** | Reports the LG Store app, provisioned package, LG driver hooks, and any running LG process. |
| **2. Remove app** | Removes `LGElectronics.LGMonitorApp` for all users **and** deprovisions it so new accounts don't get re‑seeded. |
| **3. Delete driver hooks** | Finds and deletes the LG *software‑component* + *extension* driver packages (`oemNN.inf`) that re‑trigger the install. Discovered **dynamically** — the numbers differ on every PC. |
| **4. Block reinstall** | Sets policy `PreventDeviceMetadataFromNetwork = 1` so Windows won't auto‑download companion apps for hardware. |
| **5. Verify** | Re‑checks everything and prints a clean / not‑clean summary. |

It's belt‑and‑suspenders: it removes the app, deletes the hooks that reinstall it, **and** sets the
policy that would otherwise re‑fetch it.

---

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in) — Windows PowerShell or PowerShell 7 both work
- Administrator rights (the script **self‑elevates** with a UAC prompt)

---

## Usage

1. Download `Remove-LGMonitorAdware.ps1`.
2. Open **PowerShell** (a normal, non‑admin window is fine — the script elevates itself).
3. **Check first (makes no changes):**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Remove-LGMonitorAdware.ps1 -ScanOnly
   ```
4. **Clean it up:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Remove-LGMonitorAdware.ps1
   ```
5. Approve the **UAC prompt** when it appears. A reboot afterward clears any inert leftover device
   entries (optional, not urgent).

> Prefer clicking? Right‑click the `.ps1` → **Run with PowerShell**. The `-ExecutionPolicy Bypass`
> in the commands above avoids execution‑policy blocks without changing any system setting.

### Options

| Flag | Effect |
|------|--------|
| `-ScanOnly` | Report what's present and exit. Makes **no** changes. |
| `-SkipMetadataPolicy` | Remove the app + driver hooks, but **don't** set the metadata‑download policy (keeps Windows' auto‑download of device companion apps enabled). |

---

## The one trade‑off

The reinstall block (`PreventDeviceMetadataFromNetwork = 1`) is machine‑wide: Windows will **no longer
auto‑download companion apps or fancy names/icons for any new hardware** you plug in. That is exactly
what stops the LG (and Alienware, etc.) silent installs. You can still install any companion app
manually if you ever want one. Use `-SkipMetadataPolicy` to skip this and rely on the driver‑hook
deletion alone.

---

## How to undo

- **Re‑enable device app downloads** (run in an elevated PowerShell):
  ```powershell
  Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' -Name PreventDeviceMetadataFromNetwork
  ```
- **Get the LG app back:** install "LG Monitor App" from the Microsoft Store manually.

---

## Manual method (no script)

Run these in an **elevated** PowerShell:

```powershell
# 1. Remove the app (all users) + deprovision
Get-AppxPackage -AllUsers *LGMonitor* | Remove-AppxPackage -AllUsers
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -match LGMonitor | Remove-AppxProvisionedPackage -Online

# 2. Find + delete the LG driver hooks (note the oemNN.inf names shown)
pnputil /enum-drivers | Select-String -Context 0,4 lgmonitor
pnputil /delete-driver oemXX.inf /uninstall /force   # repeat for each match

# 3. Block reinstall
New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' -Force | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' `
  -Name PreventDeviceMetadataFromNetwork -Value 1 -PropertyType DWord -Force
```

GUI alternative for the block: `gpedit.msc` → Computer Configuration → Administrative Templates →
System → Device Installation → **Prevent device metadata retrieval from the Internet** → Enabled.

---

## Notes / troubleshooting

- **"Is my PC even affected?"** Run with `-ScanOnly`. No LG app + no LG driver hooks = nothing to do.
- **Phantom entries after cleanup:** you may see inert `LG Monitor Support Application` devices with
  status *Unknown* until you reboot. They have no backing driver and do nothing — a reboot clears them.
- **Windows Home** lacks `gpedit.msc`, but the registry/script method works everywhere.
- **Safe to re‑run.** Every step is idempotent — on an already‑clean PC it just reports "gone / nothing to do."
- **Not just LG.** The metadata policy blocks any vendor using the same mechanism; the app/driver
  removal is LG‑specific.

---

## Disclaimer

Provided **as‑is, without warranty of any kind**. It modifies system state (removes an app, deletes
driver packages, sets a policy). Review the script before running it and use it at your own risk. See
[LICENSE](LICENSE).

---

## License

[MIT](LICENSE)
