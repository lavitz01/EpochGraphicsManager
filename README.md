# Project Epoch Graphics Manager

Windows 11 PowerShell tool (CLI + dark GUI) to detect, back up, configure, and optionally install graphics enhancements for **Project Epoch** on the **World of Warcraft 3.3.5a build 12340** client.

**Default mode is dry-run.** Nothing is written until you pass `-Apply` (CLI) or check **Apply changes** (GUI).

DLL-based stages (**Lumenveil**, **DXVK**, **ReShade**) stay locked until you explicitly approve them after reading current Project Epoch rules.

## Safety rules enforced by this manager

- Never overwrites Epoch `PATCH-D` / `PATCH-M` (protected).
- Never deletes original client files; never renames MPQs automatically; never replaces `Wow.exe`.
- Never modifies launcher-managed core archives as part of HD install.
- Never auto-runs downloaded setup executables (`ReShade` setup, arbitrary scripts).
- `Lumenveil-Setup.cmd` runs only with explicit `-RunLumenveilSetup` (CLI) — the GUI copies files and tells you to run setup yourself.
- Downloads only from verified official URLs listed in `Config/sources.json` (with SHA-256 where published).
- EpochAuthenticHD has **no GitHub release assets** and **no published checksum** — you must stage its Google Drive pack manually.

## Upstream sources inspected

| Project | Source of truth used |
|---|---|
| [EpochAuthenticHD](https://github.com/thierbig/EpochAuthenticHD) | README (2026-11-08 letter remap D→E, E→F, F→G, M→N; Google Drive pack; Data MPQs + optional Icons) |
| [Lumenveil](https://github.com/lumenveil/Lumenveil) | README + `docs/INSTALL.md` + `docs/RESHADE.md` + release **v0.1.1** + SHA256 |
| [DXVK](https://github.com/doitsujin/dxvk) | Releases **v2.7.1** (EpochAuthenticHD) and **v3.1.1** (Lumenveil ReShade doc); `x32\d3d9.dll` only |
| [ReShade](https://reshade.me/) | Official site (noted 6.8.0); setup is manual |
| Project Epoch | [Rules](https://project-epoch.org/rules.html); FAQ notes HD mods interact poorly with custom Epoch content |

### Compatibility warning

Project Epoch rules prohibit cheats, hacks, bots, and unauthorized third-party software that automates play or provides unfair advantages. Community reports indicate client modifications (extra MPQs / injectors) may conflict with launcher integrity checks or ToS enforcement. **Confirm current staff guidance before enabling HD packs or DLL tools.** This manager does not bypass anti-cheat or integrity systems.

## Requirements

- Windows 11
- [PowerShell 7+](https://aka.ms/powershell) (`pwsh`)
- Project Epoch client with `Wow.exe` + `Data\` (often under `...\Ascension Launcher\resources\epoch_live`)

## Quick start (GUI)

```bat
Start-Gui.cmd
```

Or:

```powershell
pwsh -File .\Install.ps1 -Action Gui
```

Recommended order:

1. **Detect Game** (or **Browse Client…**)
2. **Backup Client** (enable **Apply changes**)
3. **Configure RTX 4090** or **Configure GTX 1080** (Apply)
4. Optionally stage/install HD → Lumenveil → DXVK → ReShade (separate stages; DLL approval required)
5. **Verify Installation**
6. Keep **Restore Original Client** available if anything misbehaves

## CLI reference

All mutating commands are dry-run unless `-Apply` is passed.

```powershell
# Detect
pwsh -File .\Install.ps1 -Action Detect
pwsh -File .\Install.ps1 -Action Detect -ClientPath 'D:\Games\epoch_live'

# Backup / verify / restore
pwsh -File .\Backup.ps1 -ClientPath 'D:\Games\epoch_live' -Apply
pwsh -File .\Verify.ps1 -ClientPath 'D:\Games\epoch_live'
pwsh -File .\Restore.ps1 -ClientPath 'D:\Games\epoch_live' -BackupPath 'C:\Users\You\EpochGraphicsBackups\epoch-client-backup-YYYYMMDD-HHMMSS' -Apply

# Hardware profiles
pwsh -File .\Configure-RTX4090.ps1 -ClientPath 'D:\Games\epoch_live' -Apply
pwsh -File .\Configure-GTX1080.ps1 -ClientPath 'D:\Games\epoch_live' -Apply

# HD (manual staging first)
# 1) Download Google Drive pack from EpochAuthenticHD README
# 2) Extract MPQs into .\Staging\EpochAuthenticHD\
pwsh -File .\Install.ps1 -Action InstallHd -ClientPath 'D:\Games\epoch_live' -Apply

# Optional DLL stages (explicit approval)
pwsh -File .\Install.ps1 -Action InstallLumenveil -ClientPath 'D:\Games\epoch_live' -ApproveDllMods -Apply
pwsh -File .\Install.ps1 -Action InstallDxvk -ClientPath 'D:\Games\epoch_live' -DxvkVersion 2.7.1 -ApproveDllMods -Apply
pwsh -File .\Install.ps1 -Action InstallReshade -ClientPath 'D:\Games\epoch_live' -ApproveDllMods -Apply
```

## Hardware profiles

### RTX4090 (Computer 1)

- 3840×2160 @ 144 Hz
- Maximum texture filtering / high environment / water / shadows / atmosphere
- Full Lumenveil-compatible ReShade preset (`Assets/presets/ReShade-RTX4090.ini` = upstream Lumenveil preset)
- `farclip` capped at **1000** (below AuthenticHD’s 1600 macro) for 32-bit memory safety

### GTX1080 (Computer 2)

- 2560×1440 @ 60 Hz
- Maximum *compatible* quality with moderated shadows / atmosphere / particles
- Lightweight ReShade preset (`ReShade-GTX1080.ini`: SMAA + FakeHDR only)
- `farclip` **777**

Profiles write/merge `WTF\Config.wtf`, write `dxvk.conf` lines documented by Lumenveil, and copy the matching ReShade preset. They do **not** install DLLs by themselves.

## HD graphics staging (EpochAuthenticHD)

1. Open the Drive link documented in the [EpochAuthenticHD README](https://github.com/thierbig/EpochAuthenticHD) (also opened by the manager).
2. Extract into `Staging\EpochAuthenticHD\` so `.MPQ` files are discoverable (and optional `Icons`).
3. Run **Install HD Graphics** / `-Action InstallHd`.
4. Expected custom letters per current README: `PATCH-4/5/E/F/G/N/R/W/X` — **not** D or M.

## Lumenveil / DXVK / ReShade

| Stage | What the manager does | What you must do |
|---|---|---|
| Lumenveil 0.1.1 | Downloads zip, verifies SHA-256 `56bc42d5…`, copies files | Approve DLL; run `Lumenveil-Setup.cmd` once |
| DXVK 2.7.1 (default) or 3.1.1 | Downloads release tarball, verifies SHA-256, copies `x32\d3d9.dll` | Approve DLL |
| ReShade | Opens reshade.me, writes install guide + preset | Approve DLL; run official setup yourself (Vulkan if DXVK present, else D3D9); enable SweetFX + iMMERSE |

## Transfer configuration to Computer 2 (GTX 1080)

1. Copy this entire `EpochGraphicsManager` folder to the second PC (USB/network).
2. Install PowerShell 7 if needed.
3. On PC2: Detect/Browse the local Epoch client → **Backup** with Apply.
4. Run **Configure GTX 1080** with Apply (not RTX 4090).
5. Re-do optional installs on PC2 (do not copy `d3d9.dll` / `version.dll` blindly between machines without re-verification). You *may* reuse:
   - `Staging\EpochAuthenticHD\` MPQs
   - `Downloads\` verified archives
   - `Assets\presets\` and `Config\profiles\GTX1080.json`
6. Verify on PC2, then test in-game. Prefer launching in a way that does not let the launcher silently repair away custom Data files if you chose to use HD MPQs.

State for each machine lives in `State\install-state.json` — safe to delete and regenerate per PC.

## Layout

```
EpochGraphicsManager/
  Install.ps1, Backup.ps1, Verify.ps1, Restore.ps1
  Configure-RTX4090.ps1, Configure-GTX1080.ps1, Start-Gui.cmd
  Gui/Launch-Gui.ps1
  Modules/*.psm1
  Config/sources.json
  Config/profiles/*.json
  Assets/presets/*.ini
  Staging/   # manual HD drop zone
  Downloads/ # verified archives
  State/     # install-state + pre-write copies
  Logs/
```

## Logging & rollback

- Logs: `Logs\*.log`
- Full client backups: `%USERPROFILE%\EpochGraphicsBackups\epoch-client-backup-*`
- Pre-write copies: `State\prewrite\*`
- Restore uses the recorded backup (GUI) or `-BackupPath` (CLI). A pre-restore snapshot is taken first.

## Disclaimer

This project is an independent fan utility. It is not affiliated with Blizzard Entertainment or Project Epoch. Use graphics modifications at your own risk and only in accordance with the rules of the service you play on.
