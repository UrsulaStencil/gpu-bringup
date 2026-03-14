# Session State: RK3588 + RX 6400 AMDGPU Bring-up

Last updated: 2026-03-14T15:37:00+01:00

## Goal

Enable AMDGPU on Orange Pi 5 Plus (RK3588) with RX 6400 (`1002:743f`) on Armbian vendor kernel (`rk35xx`, 6.1), with reproducible patches and a controlled smoke-test flow.

## Latest checkpoint

- Fresh reboot validation of the minimal PMFW revert:
  - classification:
    - PROTECTED_FRESH
  - logs:
    - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-153451.log`
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-153451.log`
  - boot id:
    - `52e121c3-b4be-4f41-bb1e-996c7249d5bb`
  - module hash:
    - `08efc87519f2614e748f177d3bb3c060818f2f7571e3b81ed9be948245d27290`
  - exact source change validated there:
    - reverted only the local PMFW/SMU special-casing in `psp_hw_start()`
    - preserved local iteration36 changes for:
      - fixed/natural TMR placement
      - ASD shared-buffer init
      - optional RAP skip on MP0 `11.0.13`
      - diagnostic logging
  - current source snapshot for the validated `amdgpu_psp.c` state:
    - `/home/orange/gpu-bringup/state-snapshots/amdgpu-psp-current-diff-20260314-153451.patch`
  - broader prior context snapshot:
    - `/home/orange/gpu-bringup/state-snapshots/amdgpu-worktree-diff-20260314-iteration36.patch`
  - analyzer result:
    - `13/21` phases green
    - green:
      - `vbios`
      - `post-1`
      - `vram`
      - `reserve_tmr`
      - `mem_training`
      - `fw_buf`
      - `ring_init`
      - `ring_prewait`
      - `boot_kdb`
      - `boot_spl`
      - `boot_sysdrv`
      - `ID_LOAD_TOC`
      - `SMC_prep`
  - first hard blocker:
    - `smu_load`
    - exact lines:
      - `arm64 bring-up: load_ip_fw prep ucode=SMC id=0x31 mc=0x8000578000 size=0x3b200 type=0x12`
      - `psp submit-post: cmd=LOAD_IP_FW(0x6) ... resp{status=0xa5a5a5a5 ...}`
      - `arm64 bring-up: PSP cmd wait expired for LOAD_IP_FW with no response`
      - `[drm:psp_load_smu_fw [amdgpu]] *ERROR* PSP load smu failed!`
  - interpretation:
    - the one-change revert restored the intended fresh `smu_load` frontier
    - this matches the older depth reference `113549`
    - it did not regress earlier validated phases below the protected floor
  - previous on-disk module backup:
    - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.bak-20260314-152903`
    - previous hash:
      - `86b03d3b9735631345a41be0244b03e9af8d1c2a0080abff5487ad505d5791bd`

- Current protected baseline run is now:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-123919.log`
  - matching smoke log:
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-123919.log`
  - boot id:
    - `a773619f-2a35-48c1-b781-427b5c5d8786`
  - module hash used there:
    - `905b768b546de99670d2af8aebf35c49eca5ed97971c3eed51a350b191d028ab`
  - analyzer result:
    - `13/21` phases green
    - green:
      - `vbios`
      - `post-1`
      - `vram`
      - `reserve_tmr`
      - `mem_training`
      - `fw_buf`
      - `ring_init`
      - `ring_prewait`
      - `boot_kdb`
      - `boot_spl`
      - `boot_sysdrv`
      - `ID_LOAD_TOC`
      - `SETUP_TMR`
    - red:
      - `discovery`
      - `post-2`
      - `boot_sos`
      - `LOAD_ASD`
      - `LOAD_TA`
      - `SMC_prep`
      - `SMU_ok`
      - `gfx_ring`
  - first hard blocker:
    - `tmr_load`
    - exact line:
      - `[drm:psp_hw_start [amdgpu]] *ERROR* PSP load tmr failed!`
  - important result:
    - this is the best explicitly validated early-to-mid phase chain so far
    - `GPU posting now...` ends with `C2PMSG_81=0x00000000`
    - `ID_LOAD_TOC` completes with response `status=0x0`
    - `SETUP_TMR` is reached, but PSP never writes back a response payload
    - failure shape:
      - MP0/MMHUB faults on `0x0000000100000000`
      - repeated IH overflow
      - `PSP cmd wait expired for SETUP_TMR with no response`
      - final failure at `PSP load tmr failed`
- Important comparison inside the same target path (`fw_load_type=1`):
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-113549.log`
  - matching smoke log:
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-113549.log`
  - module hash used there:
    - `3d78d1a378b29a33a738c0efdc6700e98857a36d373a7fe8acc87a1c8d1229f1`
  - important result:
    - same `fw_load_type=1` path reached deeper and first blocked at `LOAD_IP_FW`
    - failure shape:
      - MP0/MMHUB faults on `0x0000000100000000`
      - repeated IH overflow
      - `PSP cmd wait expired for LOAD_IP_FW with no response`
  - interpretation:
    - `113549` remains the depth reference for the target path
    - `123919` remains the protected baseline because its earlier chain is more explicitly validated
    - current work target is to recover `LOAD_IP_FW` depth without regressing the protected `123919` phases
- New same-boot directional result after the current sequence rollback:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-125222.log`
  - matching smoke log:
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-125222.log`
  - module hash used there:
    - `3403cd47f47000673579612b4ce19dca4e1c1a97dca26db827da6abdea975845`
  - interpretation:
    - same-boot only, therefore not a new protected baseline
    - the narrow PMFW/SMU sequencing change worked directionally:
      - `SETUP_TMR` is no longer the first blocker
      - early `SMC` `LOAD_IP_FW` is visible again
      - first blocker returns to `smu_load`
    - this matches the older deeper `113549` shape and is the strongest indication so far that the later `tmr_load` regression came from the early PMFW skip path
- Same-boot direct-path comparison now exists, but is not the primary truth source:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-113841.log`
  - matching smoke log:
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-113841.log`
  - command used:
    - `fw_load_type=0 async_gfx_ring=0 num_kcq=0 mes=0 msi=1`
  - interpretation:
    - useful only as a contaminated same-boot comparison after the trusted `113549` run
    - ends in early SMU failure:
      - `SMU: I'm not done with your previous command`
      - `SMC engine is not correctly up!`
      - probe fails `-62`
- New instrumentation-only module is now installed on disk:
  - current on-disk module hash:
    - `5316a10e3fd06e8c69f26c397b19b42e1250f1fb1a5de1ce848e28112a709891`
  - backup:
    - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.bak-20260314-114132`
  - change scope:
    - `drivers/gpu/drm/amd/amdgpu/amdgpu_psp.c`
    - added `rl load prep ... preview=...` logging in `psp_rl_load()`
    - added `load_ip_fw prep ucode=... mc=... size=... type=...` logging for non-PSP firmware loads
  - intent:
    - narrow the current blocker to exact RL/`LOAD_IP_FW` inputs on the next fresh run
    - avoid blind addressing changes before the failing payload is explicitly visible
- Method correction now implemented in the smoke script:
  - `/home/orange/gpu-bringup/run-postcold-psp-smoke.sh`
  - a fresh-boot guard now skips `PRE_MODPROBE_RESET=bridge_sbr` by default when boot age is small
  - this prevents destroying a just-achieved cold-boot state with an unnecessary hot-reset
  - override remains possible with:
    - `FORCE_PRE_MODPROBE_RESET=1`
  - `modprobe amdgpu` now runs in its own transient systemd unit instead of the interactive login session
  - rationale:
    - reduce shutdown delays caused by `session-3.scope` waiting on a hung `modprobe`
    - keep future stuck AMDGPU probes out of the user's login scope
- New reboot helper:
  - `/home/orange/gpu-bringup/gpu-safe-reboot.sh`
  - stops transient `codex-amdgpu-modprobe-*.service` units, tries `rmmod amdgpu`, then requests reboot from its own transient unit
- Current strongest interpretation:
  - the highest-value reference is now the fresh no-SBR PSP path in `113549`
  - the current blocker is no longer "dead all-ones PSP after post"
  - it is now specifically the RL/`LOAD_IP_FW` transition after a successful `LOAD_TOC` + TMR setup
  - same-boot direct-path results are still useful, but should not override the fresh `113549` reference

- Latest trusted fresh-boot smoke on the current branch:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-102801.log`
  - module hash used there: `a7574452fc4fe124d43b5623911836169fce18535e7842065ae41360e472df76`
  - outcome:
    - `GPU posting now...`
    - second post retry also ran
    - `reserve_tmr` restored
    - memory-training init restored
    - PSP bootloader still dead with all-ones mailboxes
    - `PSP load kdb failed`
- Same-boot A/B on `fw_load_type=3`:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-102946.log`
  - same dead-PSP result as `fw_load_type=1`
- Explicit `reset_method=5` retest on the now-improved hot-reset path:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-103255.log`
  - hangs in early `PCI reset`
  - captured stack from stuck `modprobe`:
    - `pci_dev_lock -> pci_reset_function -> amdgpu_device_pci_reset -> nv_asic_reset`
- New current on-disk module hash:
  - `e10811cb3be12c3185f860471f06902203068f16423e0f22b927375adb5ead5c`
- New current kernel diff snapshot:
  - `/home/orange/gpu-bringup/state-snapshots/amdgpu-worktree-diff-20260314-iteration33.patch`
- New patch intent now on disk, not yet runtime-validated:
  - `drivers/gpu/drm/amd/amdgpu/psp_v11_0.c`
  - reject `0xffffffff` as false-success for relevant MP0 mailbox waits
  - skip memory training when PSP mailboxes are already all-ones before bootloader load
- This should remove the current false-success contamination from memory training and mode1-reset completion on the next reboot.
- Same-boot bring-up is materially repaired in two areas:
  - discovery fallback now survives `invalid ip discovery binary signature from vram`
  - VBIOS fallback now survives `Invalid PCI ROM header signature: expecting 0xaa55, got 0xffff`
- Exact matching MSI VBIOS identified and installed:
  - BIOS name from earlier good runs: `113-V508AERO-0OC`
  - matching ROM: TechPowerUp entry `263728`
  - installed file: `/lib/firmware/amdgpu/vbios-1002-743f-1462-5082.rom`
  - ROM MD5: `84593509c4656e0febdf10a1aa57ac2c`
- Verified same-boot milestone:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-042059.log`
  - sequence reached:
    - static Beige Goby discovery fallback
    - firmware-file VBIOS fallback
    - skip of broken init reset for `fw_load_type=1`
    - BAR reassignment
    - VRAM/GTT bring-up
  - first new hard blocker:
    - kernel BUG in `drivers/gpu/drm/amd/amdgpu/gmc_v10_0.c:603`
- Root cause of the new BUG is now constrained:
  - after skipping the broken reset path, `CONFIG_MEMSIZE` becomes invalid
  - symptoms:
    - bogus `VRAM: 4294967295M`
    - bogus `AGP: 17587891077120M`
    - later crash in VM PDE construction
  - known-good earlier runs consistently used `mc_vram=0xff000000` (`4080M`)
- Reset matrix is now narrowed down:
  - auto `MODE1 reset` fails in same-boot bring-up
  - explicit `PCI reset` (`reset_method=5`) also fails immediately with `-25`
  - log: `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-042023.log`
- New on-disk module already includes the next fix:
  - `gmc_v10_0_mc_init()` now falls back to `0xff0` MiB for this exact board/GPU tuple (`1002:743f`, `1462:5082`) when `CONFIG_MEMSIZE` is `0`/`0xffffffff`
  - current on-disk module hash: `e3fff7acdd0a856edc17f5673bc4c47cb42f76b07a1a6defa0ec8ad13b96d0f6`
- Current RAM state is no longer trustworthy for more reload tests:
  - `amdgpu-reset-de` remains alive after the BUG
  - further same-boot reloads from this session should be treated as contaminated
- Historical deepest clean PSP milestones still remain valid:
  - `/home/orange/gpu-bringup/logs/manual-live-dmesg-20260314-022230.log`
  - `ID_LOAD_TOC -> SETUP_TMR -> LOAD_ASD -> LOAD_TA(HDCP) -> LOAD_TA(DTM)`
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-032604.log`
  - trusted cold path reached `LOAD_IP_FW`

## Historical checkpoint before the latest iteration

- Earlier deepest clean bring-up milestone:
  - `ID_LOAD_TOC -> SETUP_TMR -> LOAD_ASD`
  - verified in `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-015811.log`
- This older milestone is retained only for chronology; the newer top-of-file checkpoint is authoritative.

## User intent captured

- No manual ad-hoc patching.
- Deep research + practical execution in one pass.
- Build and install to be executed in-session; user will do final smoke after reboot.

## High-level outcome in this session

- Patch stack prepared and validated.
- Armbian build script corrected for current patching mechanism.
- Patched kernel built successfully.
- Kernel packages installed successfully.
- System is now at reboot-required state before final smoke test.

## Key decisions and corrections made

1. Initial Armbian run required `KERNEL_BTF=no` due RAM check failure (`5735/6451 MiB`).
2. First long build attempt showed a tooling mismatch:
   - User patches were copied to `userpatches/kernel/archive/rk35xx-vendor-6.1`.
   - Current Armbian patching expects `userpatches/kernel/rk35xx-vendor-6.1`.
   - Result: build proceeded without AMDGPU patches.
3. Helper script was fixed:
   - Patch destination changed to `userpatches/kernel/rk35xx-vendor-6.1`.
   - Config fragment handling added: create `userpatches/config/kernel/linux-rk35xx-vendor.config` from base config + AMDGPU overrides.
4. Rebuild confirmed correct behavior:
   - `Applying 5 patches ... 5 applied; 0 with problems`
   - Includes `0001/0002/0003` AMDGPU ARM64/MMIO/DMA patches.

## Artifacts in workspace

Patch source bundle:

- `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0000-enable-amdgpu.config`
- `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0001-arm64-mm-handle-alignment-faults-for-pcie-mmio.patch`
- `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0002-arm64-mm-force-device-mappings-for-pcie-mmio.patch`
- `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0003-drm-force-writecombined-mappings-for-dma.patch`

Patched-in build tree destinations:

- `/home/orange/gpu-bringup/armbian-build/userpatches/kernel/rk35xx-vendor-6.1/`
- `/home/orange/gpu-bringup/armbian-build/userpatches/config/kernel/linux-rk35xx-vendor.config`

Automation + runbook:

- `/home/orange/gpu-bringup/run-rk3588-amdgpu-bringup.sh`
- `/home/orange/gpu-bringup/RK3588_AMDGPU_PATCHSET_RUNBOOK.md`

Session memory mirror:

- `/home/orange/.codex/memories/RK3588_AMDGPU_SESSION_STATE.md`

## Build and install results

Build command used:

```bash
cd /home/orange/gpu-bringup
KERNEL_BTF=no ./run-rk3588-amdgpu-bringup.sh build
```

Build status:

- Success (`Runtime 46:26 min`)
- Log: `/home/orange/gpu-bringup/armbian-build/output/logs/log-kernel-4c4b8f02-ad2c-4eff-8ab9-ab99fb260074.log.ans`
- Generated package set version:
  - `6.1.115-Se408-Dedd0-Pf8ee-C5458-H62d0-HK01ba-Vc222-Bdc65-R448a`
  - Re-versioned to `26.02.0-trunk`

Install command used:

```bash
cd /home/orange/gpu-bringup
./run-rk3588-amdgpu-bringup.sh install
```

Install status:

- Success
- Installed package versions now:
  - `linux-image-vendor-rk35xx 26.02.0-trunk`
  - `linux-dtb-vendor-rk35xx 26.02.0-trunk`
  - `linux-headers-vendor-rk35xx 26.02.0-trunk`
- Installer output ended with: `[install] done. Reboot required.`

## Pre-reboot verification snapshot

PCI visibility:

- `lspci -nnk` still sees RX6400 (`1002:743f`) and `Kernel modules: amdgpu`.

Kernel config on disk:

- `/boot/config-$(uname -r)` now shows:
  - `CONFIG_DRM_AMDGPU=m`
  - `CONFIG_DRM_AMD_DC=y`

Runtime loading attempt before reboot:

- `sudo modprobe amdgpu` => `Exec format error`
- `dmesg` shows: `drm_buddy: disagrees about version of symbol module_layout`
- Interpretation: expected module ABI mismatch with currently running pre-update kernel image/session; reboot required to align running kernel + modules.

Graphics userspace currently:

- `vulkaninfo --summary` still reports `llvmpipe` (pre-reboot state).

## Current machine state (now)

- Running kernel (not rebooted yet): `Linux orangepi5-plus 6.1.115-vendor-rk35xx #1 SMP Tue Nov 25 13:05:16 UTC 2025`
- New kernel packages are installed and ready for next boot.
- Reboot is the next required step before meaningful AMDGPU smoke.

## What to do immediately after reboot

Run:

```bash
cd /home/orange/gpu-bringup
./run-rk3588-amdgpu-bringup.sh smoke
```

Or manually:

```bash
uname -a
lspci -nnk -s 03:00.0
lsmod | grep -i amdgpu || true
vulkaninfo --summary
dmesg -T | grep -i amdgpu | tail -n 200
```

## Success criteria after reboot

- `lspci -nnk -s 03:00.0` shows `Kernel driver in use: amdgpu`
- `lsmod | grep amdgpu` non-empty
- `vulkaninfo --summary` reports AMD GPU (not only `llvmpipe`)
- `dmesg -T | grep -i amdgpu` without fatal VM/ring/MMIO faults

## Scope boundary

- This pass is for render/compute bring-up first.
- Direct display output over GPU ports may still need extra ARM64/DCN-specific work in a follow-up.

## Post-reboot smoke results (executed)

Timestamp: 2026-03-11T08:37+01:00

System now running new kernel build:

- `uname -a` => `Linux orangepi5-plus 6.1.115-vendor-rk35xx #1 SMP Mon Feb 23 06:39:00 CET 2026`

Smoke command executed:

```bash
cd /home/orange/gpu-bringup
./run-rk3588-amdgpu-bringup.sh smoke
```

Observed:

- `lspci -nnk -s 03:00.0`: **Kernel driver in use: amdgpu** (PASS gate 1a)
- `lsmod | grep amdgpu`: module loaded (PASS gate 1b)
- `/dev/dri`: `card0`, `card1`, `renderD128`, `renderD129`
- `vulkaninfo --summary`: still only `llvmpipe` (FAIL gate 4)

Critical dmesg findings:

- `[drm] Display Core failed to initialize with v3.2.207!`
- `Unable to handle kernel NULL pointer dereference at virtual address 0000000000000008`
- `Internal error: Oops: 0000000096000044 [#1] SMP`
- Crash path:
  - `drm_atomic_private_obj_fini`
  - `amdgpu_dm_fini`
  - `amdgpu_dm_init.isra.0`
  - `dm_hw_init`
  - `amdgpu_device_init`

Interpretation:

- PCI binding + base amdgpu load are now achieved.
- Bring-up currently fails in AMD Display Core init path (DC/DM), causing kernel Oops.
- This explains missing AMD Vulkan device despite driver bind.

## Mitigation applied after smoke failure

Goal: force render-first mode and bypass DC/DM init crash path.

Changes made:

- `/boot/armbianEnv.txt`:
  - `extraargs=cma=256M amdgpu.dc=0 amdgpu.runpm=0`
  - backup: `/boot/armbianEnv.txt.bak-2026-03-11-dc0`
- Added module options:
  - `/etc/modprobe.d/amdgpu-rk3588.conf`
  - contents: `options amdgpu dc=0 runpm=0 aspm=0`
- Updated smoke helper to avoid hangs and show active DC parameter:
  - `/home/orange/gpu-bringup/run-rk3588-amdgpu-bringup.sh`
  - `modprobe` now wrapped with timeout and reports `/sys/module/amdgpu/parameters/dc`

Status:

- Changes are staged on disk and require reboot to take effect for early module init.

Next required action:

```bash
sudo reboot
```

After reboot:

```bash
cd /home/orange/gpu-bringup
./run-rk3588-amdgpu-bringup.sh smoke
```

## Post-failure forensic and recovery status (new)

### What actually happened

- Reboot chronology from persistent journal:
  - Boot `-2` (started `2026-03-11 00:46:37`): normal bring-up environment with `cma=256M`.
  - Boot `-1` (started `2026-03-11 08:36:27`): `amdgpu` autoloaded and hit the known DC/DM crash (`Display Core failed ...` + NULL deref).
  - Boot `0` (started `2026-03-11 08:49:36`): recovery boot with `modprobe.blacklist=amdgpu`, stable.
- Current runtime confirms:
  - kernel: `6.1.115-vendor-rk35xx #1 SMP Mon Feb 23 06:39:00 CET 2026`
  - cmdline includes `modprobe.blacklist=amdgpu`
  - RX6400 visible on PCIe, but no active `amdgpu` bind by default.

### Root cause analysis: expected vs procedural gap

- Expected for this platform:
  - `amdgpu` DC/DM path can crash on RK3588 + RX6400 (confirmed by Oops in `amdgpu_dm_*` path).
- Procedural gap (preventable):
  - `linux-dtb-vendor-rk35xx` package `preinst` executes:
    - `rm -rf /boot/dtb`
    - `rm -rf /boot/dtb-6.1.115-vendor-rk35xx`
  - Any custom DTB in `/boot/dtb/...` is therefore removed on update.
  - If `fdtfile=` still points to removed custom DTB (e.g. `...-rx6400test.dtb`), reboot can fail very early (red LED/no normal boot).

### Additional controlled smoke tests after recovery

- Manual load test at `2026-03-11 09:44` with module options `dc=0 runpm=0 aspm=0`:
  - DC/DM NULL-deref did **not** recur.
  - Init still failed later with:
    - `ring kiq_2.1.0 test failed (-110)`
    - `hw_init of IP block <gfx_v10_0> failed -110`
    - `amdgpu: probe ... failed with error -110`
- Variant test at `2026-03-11 09:50` with `msi=0` in addition:
  - Same failure signature (`kiq ... -110`), no improvement.

Interpretation:

- We moved from a DC crash to a later GFX/KIQ init failure.
- Remaining blocker is no longer the original DC/DM null pointer path.

### Safety hardening now installed

- New guard scripts added:
  - `/home/orange/gpu-bringup/armbian-fdt-sanity.sh`
  - `/home/orange/gpu-bringup/zz-armbian-fdt-sanity.postinst`
- Installed system-wide:
  - `/usr/local/sbin/armbian-fdt-sanity.sh`
  - `/etc/kernel/postinst.d/zz-armbian-fdt-sanity`
- Guard behavior:
  - checks if `fdtfile=` target exists under `/boot/dtb`
  - auto-falls back to `rockchip/rk3588-orangepi-5-plus.dtb` if missing
  - writes timestamped backup of `/boot/armbianEnv.txt`

### Current safe operating state

- `/boot/armbianEnv.txt` currently uses stock DTB and keeps `modprobe.blacklist=amdgpu`.
- `/etc/modprobe.d/amdgpu-rk3588.conf` remains in place with:
  - `options amdgpu dc=0 runpm=0 aspm=0`
- This keeps boot stable while allowing explicit/manual bring-up experiments.

## Iteration 2 (reset-method control) status

### New patchset additions

- Added `0005-drm-amdgpu-honor-reset-method-and-allow-soc21-pci-reset.patch`:
  - removes forced `amdgpu_reset_method = AMD_RESET_METHOD_NONE` override during init-reset.
  - allows `AMD_RESET_METHOD_PCI` in `soc21_asic_reset_method()`.
- Added `0006-drm-amdgpu-allow-pci-reset-method-param.patch`:
  - extends reset-method parameter validation from `-1..4` to `-1..AMD_RESET_METHOD_PCI`.
  - updates module parameter docs to include `5 = pci`.
- Build helper updated to include both patches in `prepare` copy list:
  - `/home/orange/gpu-bringup/run-rk3588-amdgpu-bringup.sh`
- Runbook updated accordingly:
  - `/home/orange/gpu-bringup/RK3588_AMDGPU_PATCHSET_RUNBOOK.md`

### Build/install history for this iteration

- Intermediate build with `0005` only:
  - fingerprint: `6.1.115-Se408-Dedd0-Pc861-C5458-H62d0-HK01ba-Vc222-Bdc65-R448a`
- Final build with `0005+0006`:
  - fingerprint: `6.1.115-Se408-Dedd0-P5108-C5458-H62d0-HK01ba-Vc222-Bdc65-R448a`
  - log: `/home/orange/gpu-bringup/armbian-build/output/logs/log-kernel-a81c1ced-890e-4d8c-9dec-f2b07fc54a26.log.ans`
- Final `P5108` image/dtb/headers debs were reinstalled successfully.

### Runtime test result after `0006`

Validation:

- `modinfo amdgpu` now reports:
  - `reset_method ... 5 = pci`

Manual test:

- command: `modprobe amdgpu reset_method=5` (controlled capture script)
- dmesg progression:
  - normal init up to IP block enumeration
  - then: `amdgpu ...: PCI reset`
  - no subsequent progress/failure line emitted
- process state:
  - `/sbin/modprobe amdgpu reset_method=5` entered uninterruptible `D` state
  - cannot be killed with `SIGKILL`
- side effects:
  - `lspci -nnk -s 03:00.0` shows `Kernel driver in use: amdgpu`
  - no AMD render node appears (`/sys/class/drm/card1` remains `RKNPU`)
  - `vulkaninfo --summary` still shows only `llvmpipe`

Interpretation:

- PCI-reset path is now genuinely reached (unlike before), but it currently deadlocks on this platform.
- This is progress in control/observability, but not a usable init path yet.

### Operational note

- A smoke helper regression was fixed:
  - `timeout 25s sudo_cmd modprobe amdgpu` was invalid (function call under `timeout`).
  - now uses direct `sudo_cmd modprobe amdgpu`.
- Because of the current `D`-state modprobe thread, a reboot is recommended before further GPU tests.

## Iteration 3 (2026-03-13) status

### Baseline after reboot

- Running kernel: `6.1.115-vendor-rk35xx` (`#1 SMP Mon Feb 23 06:39:00 CET 2026`).
- Cmdline still contains `modprobe.blacklist=amdgpu`.
- RX6400 still visible on PCIe (`1002:743f`).
- Default manual load initially failed early on MES firmware:
  - `Direct firmware load for amdgpu/gc_10_3_5_mes.bin failed`
  - `early_init of IP block <mes_v10_1> failed -19`

### Build + install corrections applied

- `0007-drm-amdgpu-skip-kcq-setup-when-num-kcq-zero.patch` was built in artifact `P4c59`.
- Critical packaging finding:
  - `output/packages-hashed/global/*P4c59*_arm64.deb` contained patched `amdgpu.ko`.
  - `output/debs/*P4c59*.deb` (re-versioned `26.02.0-trunk`) did not reflect the same payload during this cycle.
- Installer workflow was corrected:
  - prefer `output/packages-hashed/global`
  - install exact artifacts via `dpkg -i` (not generic wildcard `apt install`).
- `run-rk3588-amdgpu-bringup.sh` updated accordingly.

### Verified installed payload

- Installed package versions now:
  - `linux-image-vendor-rk35xx 6.1.115-Se408-Dedd0-P4c59-C5458-H62d0-HK01ba-Vc222-Bdc65-R448a`
  - `linux-dtb-vendor-rk35xx 6.1.115-Se408-Dedd0-P4c59-C5458-H62d0-HK01ba-Vc222-Bdc65-R448a`
  - `linux-headers-vendor-rk35xx 6.1.115-Se408-Dedd0-P4c59-C5458-H62d0-HK01ba-Vc222-Bdc65-R448a`
- Installed module hash:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
  - `sha256=39bb8a21cd311bdbe173e99338bfb717a6e7f95990fd8427b95e1ac9a2a6f44a`
- Module string evidence of `0007`:
  - `no kernel compute queues configured; skipping KCQ setup`

### Runtime validation results

1. Test with:
   - `modprobe amdgpu dc=0 runpm=0 aspm=0 mes=0 num_kcq=0 msi=1`
   - Result:
     - `dmesg` now shows `no kernel compute queues configured; skipping KCQ setup` (patch effective)
     - still fails with `ring kiq_2.1.0 test failed (-110)` and `hw_init of IP block <gfx_v10_0> failed -110`
2. Test with additional:
   - `async_gfx_ring=0`
   - Result:
     - no immediate `probe ... failed` line in first phase
     - repeated `failed to write reg ... wait reg ...` loops on KIQ write path
     - temporary `Kernel driver in use: amdgpu` observed in `lspci`, but no AMD DRM render node and Vulkan remained `llvmpipe`

### Safety state at end of this iteration

- `amdgpu` module was unloaded again to leave system in stable state.
- `lspci -nnk -s 03:00.0` back to `Kernel modules: amdgpu` (no active bind).
- Reboot safety guard and DTB fallback protections remain installed.

### Current blocker (narrowed)

- KCQ path is now correctly bypassed with `num_kcq=0`.
- Remaining blocker is deeper KIQ register-write / ring-test behavior (`-110` / failed write-reg loop), not DC/DM and not MES path.

## Iteration 4 (2026-03-13, post-panic recovery) status

### What was found immediately after reboot

- User reported panic/hard hang symptoms on previous run.
- Persistent journal had only two boots available; crash boot window was very short and did not retain useful amdgpu panic text.
- Critical filesystem finding:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko` was `0` bytes.
  - backup from before replacement remained intact:
    - `amdgpu.ko.bak-pre-0008` (`sha256=39bb8a21...`).

Interpretation:

- The empty module file is a procedural artifact (interrupted module replacement), not the root cause of the amdgpu runtime failures.
- It would have broken subsequent modprobe attempts unless corrected.

### Recovery actions executed

- Preserved forensic copy of the empty module:
  - `amdgpu.ko.broken-20260313-164056`
- Restored an intact module first, then reran smoke with controlled args:
  - `mes=0 num_kcq=0 msi=1`
- Confirmed `0008` behavior in runtime logs:
  - `no kernel compute queues configured; skipping KCQ setup`
  - `num_kcq=0; skipping KGQ setup`
- Failure still occurs later:
  - `ring gfx_0.0.0 test failed (-110)`
  - `hw_init of IP block <gfx_v10_0> failed -110`
  - repeated teardown warnings from `amdgpu_irq_put`
  - repeated `failed to write reg ... wait reg ...` from KIQ path
- Stuck task evidence captured:
  - `modprobe` in `D` state stack:
    - `amdgpu_virt_kiq_reg_write_reg_wait`
    - `gmc_v10_0_flush_gpu_tlb`
    - `amdgpu_device_fini_hw` teardown path

### New patch added

- Added `0009-drm-amdgpu-gmc10-avoid-shutdown-tlb-flush-wedges.patch`:
  - in `gmc_v10_0_flush_gpu_tlb()`:
    - skip GPU TLB flush during `adev->shutdown` with one-time info log.
  - in `gmc_v10_0_hw_fini()`:
    - call `amdgpu_irq_put()` only when the IRQ source is enabled.

Rationale:

- Prevent teardown wedge in failed-init path.
- Remove noisy/unsafe WARN-on-`irq_put` behavior when source was never enabled.

### Tooling updates made in this iteration

- `run-rk3588-amdgpu-bringup.sh`:
  - includes `0009` in `prepare_patches()` require/copy list.
  - usage smoke example now defaults to:
    - `SMOKE_MODPROBE_ARGS="mes=0 num_kcq=0 msi=1"`
    - (no longer defaulting `async_gfx_ring=0`).
- `RK3588_AMDGPU_PATCHSET_RUNBOOK.md` updated with `0009` and new failure signatures.

### Current installed on-disk module (next boot payload)

- Built module hash with `0009`:
  - `sha256=7dfe79adf57a5597ed79025c264976b018aa0d85c0fd94c52e9950effaef9bee`
- Installed to:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
- Signature strings present in installed module:
  - `shutdown in progress; skipping GPU TLB flush`
  - `no kernel compute queues configured; skipping KCQ setup`
  - `num_kcq=0; skipping KGQ setup`

### Operational state at handoff

- Current runtime still carries a wedged `modprobe amdgpu` task from the last smoke (pre-`0009` module instance loaded in memory).
- System remains controllable, but this `D`-state task cannot be cleanly removed.
- A reboot is required to:
  - clear the wedged task,
  - load the newly installed `0009` module image,
  - perform a clean smoke verification.

### Next commands after reboot

```bash
uname -a
cat /proc/cmdline
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange SMOKE_MODPROBE_ARGS='mes=0 num_kcq=0 msi=1' ./run-rk3588-amdgpu-bringup.sh smoke
```

Expected validation delta for `0009`:

- no long `D`-state hang in teardown path after failed init,
- no `WARN ... amdgpu_irq_put` flood,
- if init still fails, it should return failure promptly with cleaner unwind.

### Validation result for `0009` (same boot, no reboot required)

Fresh smoke run executed after unloading previous module instance:

```bash
SUDO_PASSWORD=orange SMOKE_MODPROBE_ARGS='mes=0 num_kcq=0 msi=1' ./run-rk3588-amdgpu-bringup.sh smoke
```

Observed:

- Probe still fails at same functional point:
  - `ring gfx_0.0.0 test failed (-110)`
  - `hw_init of IP block <gfx_v10_0> failed -110`
  - `probe ... failed with error -110`
- `0009` behavior is active:
  - `[drm] shutdown in progress; skipping GPU TLB flush` logged during unwind.
- Important improvement:
  - no repeated `failed to write reg ... wait reg ...` loop after this run.
  - no persistent `D`-state `modprobe` remained.
  - module could be unloaded cleanly after smoke (`modprobe -r amdgpu` succeeded).

Remaining issue:

- `amdgpu_irq_put` WARN traces still appear from `amdgpu_fence_driver_hw_fini` path (not from `gmc_v10_0_hw_fini` anymore).
- Vulkan remains `llvmpipe`; no successful AMD render path yet.

Current system safety state:

- `modprobe.blacklist=amdgpu` still active on cmdline.
- `amdgpu` currently unloaded; system left in stable state.

## Iteration 5 (2026-03-13, fence unwind cleanup) status

### New patch added

- Added `0010-drm-amdgpu-fence-avoid-irq-put-warn-on-unwind.patch`:
  - file: `drivers/gpu/drm/amd/amdgpu/amdgpu_fence.c`
  - change: guard `amdgpu_irq_put()` in `amdgpu_fence_driver_hw_fini()` with `amdgpu_irq_enabled()`.

### Integration updates

- `run-rk3588-amdgpu-bringup.sh` updated to require/copy `0010` in `prepare_patches()`.
- Runbook patch list/manual copy list updated to include `0010`.
- `prepare` executed; patch chain now in build tree is `0001..0010`.

### Built and installed module payload

- New installed module hash (`0009+0010`):
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
  - `sha256=1cc716026651880fd36b382af4a29dadc7124be33f25d41c219db4cd27f0b5e7`
- Previous module backup:
  - `amdgpu.ko.pre-0010` (`sha256=7dfe79ad...`)

### Smoke validation with `0009+0010`

Command:

```bash
SUDO_PASSWORD=orange SMOKE_MODPROBE_ARGS='mes=0 num_kcq=0 msi=1' ./run-rk3588-amdgpu-bringup.sh smoke
```

Key runtime result (`16:56:46`):

- still fails at core bring-up point:
  - `ring gfx_0.0.0 test failed (-110)`
  - `hw_init of IP block <gfx_v10_0> failed -110`
  - `probe ... failed with error -110`
- KCQ/KGQ skips still active:
  - `no kernel compute queues configured; skipping KCQ setup`
  - `num_kcq=0; skipping KGQ setup`
- teardown is now cleaner:
  - `shutdown in progress; skipping GPU TLB flush` present
  - no repeated `failed to write reg ... wait reg ...` loops for this run
  - no `amdgpu_irq_put` WARN flood for this run
- module unload succeeded after smoke (`modprobe -r amdgpu`).

### Current blocker after Iteration 5

- Functional blocker remains unchanged:
  - GFX ring bring-up (`gfx_v10_0` ring test `-110`) on RK3588 path.
- Stability/regression status improved:
  - failure path now unwinds quickly and no longer wedges in long write-reg loops.

## Iteration 6 (2026-03-13, diagnostic matrix + module refresh) status

### Matrix run executed

- Script:
  - `/home/orange/gpu-bringup/run-amdgpu-modprobe-matrix.sh`
- Log:
  - `/home/orange/gpu-bringup/logs/modprobe-matrix-20260313-170202.log`
- Case summary:
  - baseline `mes=0 num_kcq=0 msi=1`: init reaches `gfx_v10_0` and fails at `ring gfx_0.0.0 ... -110`; unwind clean.
  - `async_gfx_ring=0`: explicit gfxhub UTCL2 page faults (`address 0x0`, CPG client) before same `-110`.
  - `msi=0`: still same `-110` failure.
  - `reset_method=5`: `modprobe` timeout/hang; leaves stuck task.
  - `aspm=0`: run did not progress usefully after reset-wedged case.

### Runtime state after matrix

- Persistent stuck task from reset case:
  - `modprobe amdgpu mes=0 num_kcq=0 msi=1 reset_method=5` in `D` state (`PID 6330`).
  - kernel thread `[amdgpu-reset-de]` present.
- Module currently loaded and in use; unload not possible in this state.
- Current cmdline keeps safety blacklist:
  - `modprobe.blacklist=amdgpu`

### Patchset/module payload state now

- `0011` diagnostics patch is present in patch source bundle and runbook/script integration.
- Source tree already contains diagnostic logging in `gfx_v10_0_ring_test_ring()`.
- Rebuilt `amdgpu.ko` with root permissions (worktree owned by root).
- Installed refreshed module to:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
- New installed hash:
  - `sha256=4ae5529094a8d636bbfdd242cced50d9d512428c64c036129fc2c7115f1e5aa3`
- Backup created:
  - `amdgpu.ko.bak-20260313-171054`
- Verified strings in installed module:
  - `gfx ring test timeout: ring=%s idx=%d scratch=0x%08x expected=0xDEADBEEF`
  - `gfx ring status: GRBM_STATUS=0x%08x GRBM_STATUS2=0x%08x`
  - `shutdown in progress; skipping GPU TLB flush`

### Required next action (clean state)

- Reboot is required now to clear the wedged `D`-state task and load the refreshed module cleanly.
- After reboot, run exactly:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange SMOKE_MODPROBE_ARGS='mes=0 num_kcq=0 msi=1' ./run-rk3588-amdgpu-bringup.sh smoke
```

### What to capture from next smoke

- `gfx ring test timeout` diagnostic lines with:
  - scratch value,
  - `rptr/wptr/sw_wptr`,
  - `GRBM_STATUS/GRBM_STATUS2`.
- These registers are the decision point for the next functional patch (MMIO posting vs. ring progress vs. power-gate path).

## Iteration 7-13 (2026-03-13, deep CP/GFX fault narrowing) status

### Clean smoke after reboot (baseline with refreshed diagnostics)

- Command run after reboot:
  - `SUDO_PASSWORD=orange SMOKE_MODPROBE_ARGS='mes=0 num_kcq=0 msi=1' ./run-rk3588-amdgpu-bringup.sh smoke`
- Key timeout payload captured:
  - `scratch=0xcafedead`, `rptr=0x0`, `wptr=0x500`, `sw_wptr=0x500`
  - `GRBM_STATUS=0x00003028`, `GRBM_STATUS2=0x00000008`
- Decoding:
  - only command-fifo-availability / clean bits were set
  - no meaningful CP forward progress on default path

### Additional patch iterations introduced

- `0012-drm-amdgpu-gfx10-force-mmio-wptr-on-arm64.patch`
  - force `ring->use_doorbell=false` for gfx ring on arm64.
- `0013-drm-amdgpu-gfx10-log-cp-control-state-on-timeout.patch`
  - add `CP_ME_CNTL`, `CP_STAT`, `CP_RB0_*` timeout diagnostics.
- `0014-drm-amdgpu-gfx10-program-rb-wptr-poll-ctrl-on-resume.patch`
  - program `CP_RB_WPTR_POLL_CNTL` defaults in resume path.
- `0015-drm-amdgpu-gfx10-set-rb-exe-in-cp-rb-cntl.patch`
  - set `RB_EXE` bits when programming `CP_RB{0,1}_CNTL`.
- `0016-drm-amdgpu-gfx10-log-rb-address-registers-on-timeout.patch`
  - add RB base/rptr/poll addr register logs + software ring GPU addrs.
- `0017-drm-amdgpu-gfx10-skip-cp-clear-state-bootstrap-on-arm64.patch`
  - skip heavy clear-state bootstrap stream for arm64 isolation.
- `0018-drm-amdgpu-gfx10-retry-cp-unhalt-via-rlc-if-halt-bits-stick.patch`
  - retry CP unhalt write through RLC path if halt bits stay latched.
- `0019-drm-amdgpu-gfx10-arm64-nop-rptr-ring-pretest.patch`
  - run NOP+rptr pretest before scratch-based ring test on arm64.

### Critical bifurcation identified

1. Default path (`mes=0 num_kcq=0 msi=1`):
- timeout remains with inert register signature:
  - `CP_ME_CNTL=0x00000000`, `CP_STAT=0x00000000`, `CP_RB0_CNTL=0x00a00000`
  - `CP_RB0_RPTR=0`, `CP_RB0_WPTR=0x500`, `CP_RB_WPTR_POLL_CNTL=0x00400000`
  - RB address register reads looked effectively uninitialized in timeout path:
    - `BASE=0xfedcbaef`, `RPTR_ADDR=0x0`, `WPTR_POLL_ADDR=0x0`

2. `async_gfx_ring=0` path:
- CP/RB programming becomes coherent and reproducible:
  - `CP_RB0_BASE=0x00004420` (matches `ring->gpu_addr=0x442000 >> 8`)
  - `RPTR_ADDR=0x00400040`, `WPTR_POLL_ADDR=0x00400060`
  - `CP_RB_WPTR_POLL_CNTL=0x00900100`
- but failures shift to GPU VM faults at address `0x0`:
  - `GCVM_L2_PROTECTION_FAULT_STATUS` seen as `0x00000D3B` / `0x00000D3A`
  - faulty UTCL2 client reported as `CPG (0x6)` (plus secondary CB/DB report)
- CP state in this branch at timeout:
  - `CP_ME_CNTL=0x15000000`
  - `CP_STAT=0x80008000`
  - `CP_RB0_CNTL=0x1000080a`
- `0017` reduced queued command depth (`wptr` shifted from `0x500` to `0x100`) but did not eliminate VM fault / timeout.
- `0019` NOP pretest still times out (`start_rptr=0x0`, `cur_rptr=0x0`) in this faulting branch.

### Current on-disk runtime payload

- Installed module:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
  - `sha256=c007b1d8c46e857e70ac040c35209c4b3b755e2c088dffc3ebb77478843f9a38`
- Backup chain now includes:
  - `...-pre0012`, `...-pre0013`, `...-pre0014`, `...-pre0015`, `...-pre0016`, `...-pre0017`, `...-pre0018`, `...-pre0019`

### Operational state at handoff

- No wedged `D`-state `modprobe` tasks at current handoff.
- `amdgpu` module unloaded cleanly after latest iteration.
- Boot safety remains unchanged:
  - cmdline keeps `modprobe.blacklist=amdgpu`.

### Updated blocker statement

- Primary blocker is now narrowed from generic ring timeout to a specific split:
  - default path: inert CP/RB state at timeout,
  - `async_gfx_ring=0` path: CP/RB path alive but immediate GCVM UTCL2 faults on address `0x0` (CPG client), with no rptr advancement.
- This indicates the next patch direction should target VM/context initialization for early CPG accesses (not DC/DM, not KCQ/KGQ, and no longer teardown stability).

## Iteration 14 (2026-03-13 evening, reset-hang containment + patch cleanup)

### New matrix outcome (important behavior shift)

- `run-amdgpu-modprobe-matrix.sh` was executed with:
  - baseline: `mes=0 num_kcq=0 msi=1`
  - `async0`: `mes=0 num_kcq=0 async_gfx_ring=0 msi=1`
  - `msi0`: `mes=0 num_kcq=0 msi=0`
  - `reset_pci`: `mes=0 num_kcq=0 msi=1 reset_method=5`
  - `aspm_off`: `mes=0 num_kcq=0 msi=1 aspm=0`
- Full matrix log:
  - `/home/orange/gpu-bringup/logs/modprobe-matrix-20260313-184251.log`
- For baseline/async0/msi0, failures shifted earlier than ring-test:
  - `psp is not working correctly before mode1 reset!`
  - `GPU mode1 reset failed`
  - `asic reset on init failed`
  - probe failure `-22`
- `reset_method=5` reproduced a hard hang pattern:
  - `modprobe_exit=124`
  - `amdgpu: PCI reset` was the last meaningful log line before stall.

### Live runtime state after matrix

- Stuck uninterruptible tasks now present:
  - `modprobe amdgpu ... reset_method=5` in `D` state (`PID 27089`).
  - follow-up recovery attempt (`echo 1 > .../0000:03:00.0/remove`) also stuck (`PID 27250` in `D`).
- `amdgpu` module remains loaded (`refcount 1`), unload fails with `Module amdgpu is in use`.
- PCI topology still shows GPU/audio functions (`03:00.0` + `03:00.1`) visible.

### Source cleanup performed (to de-risk next boot test)

- `gfx_v10_0.c` was cleaned back from experimental arm64 runtime changes to a safer baseline:
  - removed arm64 forced `ring->use_doorbell = false`
  - removed CP unhalt/pipe-reset recovery experiments
  - removed extra arm64 CP microcode reset/flush experiments
  - removed arm64 clear-state-skip experiment
  - removed RB_EXE / RB_WPTR_POLL_CNTL forcing experiments
  - removed ad-hoc `wmb()` insertions in gfx/compute set_wptr paths
- Kept:
  - KGQ skip behavior when `num_kcq=0`
  - extended timeout diagnostics in `gfx_v10_0_ring_test_ring()` (including CP/RB/FW/ICACHE registers)

### Safety hardening in tooling

- `run-amdgpu-modprobe-matrix.sh` was changed to skip dangerous cases by default:
  - `reset_pci` and `aspm_off` now only run with:
    - `INCLUDE_DANGEROUS_CASES=1`

### Module build/install state

- Rebuilt `amdgpu.ko` as root from cleaned `gfx_v10_0.c`.
- Installed to:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
- Current installed hash:
  - `sha256=d11083c6d4b78dcb4831429b20e4fac4013b39a4530e257de058e4b6a06926f9`
- Backup created:
  - `amdgpu.ko.bak-20260313-184739`

### Required next action

- Reboot is required before any further smoke:
  - clear `D`-state stuck tasks (`27089`, `27250`)
  - load the newly installed cleaned module from disk
- After reboot, run only safe smoke first:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange SMOKE_MODPROBE_ARGS='mes=0 num_kcq=0 msi=1 fw_load_type=0' ./run-rk3588-amdgpu-bringup.sh smoke
```

## Iteration 15 (2026-03-13 night, TTM mapping patch integration)

### What was changed (live source + persistent patchset)

- Applied the Raspberry Pi arm-SoC TTM mapping fix pattern (`70fe325`-style) into live vendor-6.1 sources:
  - `drivers/gpu/drm/ttm/ttm_bo_util.c`
    - removed single-page `kmap` shortcut in `ttm_bo_kmap_ttm()`
    - always uses `vmap(..., ttm_io_prot(...))`
  - `drivers/gpu/drm/ttm/ttm_module.c`
    - for `ttm_cached` on `CONFIG_ARM64`, return `pgprot_dmacoherent(tmp)`
- Persisted this into userpatches as:
  - `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0020-drm-ttm-arm64-coherent-cached-and-always-vmap.patch`
- Updated orchestration/docs so future rebuilds keep it:
  - `/home/orange/gpu-bringup/run-rk3588-amdgpu-bringup.sh` (require/copy `0020`)
  - `/home/orange/gpu-bringup/RK3588_AMDGPU_PATCHSET_RUNBOOK.md` (patch list + manual cp command)

### Build/install performed

- Rebuilt modules in live tree:
  - `make -C ... M=drivers/gpu/drm/ttm modules`
  - `make -C ... M=drivers/gpu/drm/amd/amdgpu modules`
- Backups created before install:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/ttm/ttm.ko.bak-20260313-191820`
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.bak-20260313-191820`
- Installed hashes:
  - `ttm.ko` -> `sha256=ccc6e337f96cec72b5b053f4e25e626560550cf36292e35fc2a03c9f5b9e50af`
  - `amdgpu.ko` -> `sha256=d11083c6d4b78dcb4831429b20e4fac4013b39a4530e257de058e4b6a06926f9`

### Smoke run and outcome

- Command:
  - `cd /home/orange/gpu-bringup && SUDO_PASSWORD=orange SMOKE_MODPROBE_ARGS='mes=0 num_kcq=0 msi=1 fw_load_type=0' ./run-rk3588-amdgpu-bringup.sh smoke`
- Log:
  - `/home/orange/gpu-bringup/logs/smoke-20260313-191841.log`
- Result:
  - No host hang / no `D`-state lockup in this run.
  - `amdgpu` module loads and then probe fails; Vulkan stays `llvmpipe`.
  - Failure remains `ring gfx_0.0.0 test failed (-110)` / `hw_init ... gfx_v10_0 failed -110`.

### Latest register signature (newest attempt at 19:19:05)

- `CP_ME_CNTL=0x00000000`
- `CP_STAT=0x00000000` (earlier same-boot attempt at 19:13:25 showed `0x84028000`)
- `CP_RB0_CNTL=0x00a00000`
- `CP_RB0_BASE=0xfedcbaef`
- `CP_RB0_RPTR=0x0`, `CP_RB0_WPTR=0x0`, `CP_RB_WPTR_POLL_CNTL=0x00400000`
- `RPTR_ADDR=0x0`, `WPTR_POLL_ADDR=0x0`
- firmware/icache regs remain `0xffffffff`, `RLCS_BOOTLOAD_STATUS=0x00000000`

### Runtime state at handoff

- Cmdline still contains:
  - `modprobe.blacklist=amdgpu`
- GPU remains visible on PCIe:
  - `0000:03:00.0` Navi24 (`1002:743f`)
- `amdgpu` currently loaded (refcount `0`) and can be unloaded/reloaded for next tests.

## Iteration 16 (2026-03-13 late night, PSP reset path focus + `0021`)

### New parameter-matrix evidence

- Ran additional matrices:
  - `/home/orange/gpu-bringup/logs/modprobe-matrix-20260313-194806.log`
  - `/home/orange/gpu-bringup/logs/modprobe-matrix-20260313-194849.log`
- `fw_load_type=1` with baseline/async/msi variations still fails early with:
  - `psp is not working correctly before mode1 reset!`
  - `GPU mode1 reset failed`
  - probe error `-22`.
- `reset_method=5` + `fw_load_type=1` changed behavior to hard stall:
  - `modprobe_exit=124`
  - last meaningful line: `amdgpu: PCI reset`.
  - module stays bound (`Kernel driver in use: amdgpu`) and unload fails.

### Deadlock forensics captured

- SysRq blocked-task dump confirms `modprobe` stuck in:
  - `pci_dev_lock -> pci_reset_function -> amdgpu_device_pci_reset -> nv_asic_reset`
- Captured call trace lines from:
  - `dmesg -T` after `echo w > /proc/sysrq-trigger`
- Current stuck task snapshot:
  - `modprobe` in `D` state while loading `amdgpu ... reset_method=5 fw_load_type=1`.

### Patch implemented to target PSP timeout class

- Live source updated:
  - `drivers/gpu/drm/amd/amdgpu/psp_v11_0.c`
- Added helper:
  - `psp_v11_0_wait_for_ext(...)`
  - extends waits to up to `2,000,000us` on `arm64` + `MP0 IP 11.0.13` (beige_goby).
  - logs timeout diagnostics (`reg`, current value, expected/mask, timeout).
- Wired helper into:
  - `psp_v11_0_ring_stop()`
  - `psp_v11_0_ring_create()` (sOS ready + response waits)
  - `psp_v11_0_mode1_reset()`

### Persistent patchset integration

- New persisted patch:
  - `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0021-drm-amdgpu-psp-v11-arm64-extend-waits-and-log-timeouts.patch`
- Orchestration updated to include `0021`:
  - `/home/orange/gpu-bringup/run-rk3588-amdgpu-bringup.sh`
  - `/home/orange/gpu-bringup/RK3588_AMDGPU_PATCHSET_RUNBOOK.md`
- Synced into build tree:
  - `cd /home/orange/gpu-bringup && ./run-rk3588-amdgpu-bringup.sh prepare`

### Module rebuild/install status

- Rebuilt `amdgpu.ko` from live vendor-6.1 tree with PSP patch.
- Installed over runtime module path (with timestamped backup) and ran `depmod`.
- New installed hash:
  - `sha256=4e5109c9729f3044a6c40e7cd170f15ba0ed49b7981500c1f3a6f30ca6b4f19d`
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`

### Current required next action

- Reboot required now to:
  - clear existing `D`-state `modprobe`/PCI-reset deadlock from `reset_method=5`.
  - load the freshly installed `amdgpu.ko` (`sha256=4e5109...`).
- First post-reboot smoke should avoid `reset_method=5` and start with:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange SMOKE_MODPROBE_ARGS='mes=0 num_kcq=0 msi=1 fw_load_type=1' ./run-rk3588-amdgpu-bringup.sh smoke
```

## Iteration 17 (2026-03-13 night, full Coreforge screen + selective backport)

### What was screened (requested full pass)

- Pulled and parsed full Coreforge compare used by Jeff Geerling article:
  - `https://github.com/raspberrypi/linux/compare/rpi-6.6.y...Coreforge:linux:rpi-6.6.y-gpu.patch`
- Identified AMD-relevant patch subjects in that stack:
  - `[PATCH 01/16] memory access fixes/workarounds for the pi5`
  - `[PATCH 09/16] another memcpy, tripped by vaapi`
  - `[PATCH 12/16] gfx10 successful init`
  - `[PATCH 13/16] amdkfd alignment for arm64`
  - `[PATCH 15/16] rx7000`
  - `[PATCH 16/16] sdma_6 mqd struct fix`
- Strategy used: do **selective** RK3588 backport of ARM64/MMIO-safe hunks, not blind 1:1 port.

### Backported into live vendor-6.1 tree

- `drivers/gpu/drm/amd/amdgpu/amdgpu_device.c`
  - WB clear switched to `memset_io`
- `drivers/gpu/drm/amd/amdgpu/amdgpu_gfx.c`
  - KIQ HPD clear switched to `memset_io`
- `drivers/gpu/drm/amd/amdgpu/amdgpu_sa.c`
  - SA BO zeroing switched to `memset_io`
- `drivers/gpu/drm/amd/amdgpu/amdgpu_ttm.c`
  - ARM64 path uses `ttm_uncached` instead of `ttm_cached` for non-USWC GTT TT
- `drivers/gpu/drm/amd/amdgpu/amdgpu_ucode.c`
  - firmware/JT copies switched to `memcpy_toio`
  - SR-IOV fw buffer clear switched to `memset_io`
- `drivers/gpu/drm/amd/amdgpu/amdgpu_psp.c`
  - PSP command/fw buffer/frame paths switched to `memset_io` + `memcpy_toio`/`memcpy_fromio`
- `drivers/gpu/drm/amd/amdgpu/amdgpu_vcn.c`
  - VCN message pointers made `volatile`
  - decode buffer clear switched to `memset_io`
- `drivers/gpu/drm/amd/amdgpu/amdgpu_cs.c`
  - IB parse copy switched to `memcpy_fromio`
- `drivers/gpu/drm/amd/amdgpu/gfx_v10_0.c`
  - MMIO-safe MQD/RLC copy/clear backports (`memset_io`, `memcpy_toio`, `memcpy_fromio`, `volatile`)

Note:
- These Coreforge-derived changes are currently applied in the live source/module state.
- A clean persistent patch artifact for this bundle is intentionally pending, because direct export from the dirty tree overlapped with existing `0001..0021` patches and must be split before enabling in automated patch copy flow.

### Additional runtime adjustments during this iteration

- `psp_v11_0.c`: arm64 slow wait raised from `2,000,000us` to `10,000,000us` for mode1 path diagnostics.
- Removed several earlier experimental runtime hacks from `gfx_v10_0.c` to return closer to baseline:
  - removed forced `ring->use_doorbell=false`
  - removed arm64 early-return skip in `gfx_v10_0_cp_gfx_start()`
  - removed forced `RB_EXE` bits and explicit `CP_RB_WPTR_POLL_CNTL` programming in gfx resume

### Observed behavior after backport

- Immediately after backport (smoke logs around `20:33-20:35`):
  - still reached `SMU is initialized successfully!`
  - still failed with `ring gfx_0.0.0 test failed (-110)`
  - `async_gfx_ring=0` branch still showed early GCVM UTCL2 faults (`0xD3B`) then `-110`
- After many rapid reloads:
  - PSP path often regressed to warm-reset `-22` (`GPU mode1 reset failed`) and stayed there without cold reboot.
  - even with 10s PSP wait, timeout persists at `reg=0x16080 val=0x00070000`.
- DIRECT path (`fw_load_type=0`) remains runnable (due existing arm64 skip-reset behavior), still ends in `-110`:
  - with `num_kcq=0`: `ring gfx_0.0.0 test failed (-110)`
  - `CP_PFP/HYP_ME` readback registers still `0xffffffff` in diagnostics

### Important clarification discovered

- Correct module parameter is `async_gfx_ring=...`.
- `amdgpu_async_gfx_ring=...` is invalid and logged as unknown parameter.

### Current runtime payload

- Installed module:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
  - latest installed hash: `sha256=19093d88f06fb3b8ff40077e3fb7a9bef39bfa43c8cc5678e723be81201e6dde`

### Required next action (strict)

- A full cold reboot/power cycle is required before trusting PSP-path comparisons again.
- Reason: warm reload loops now frequently trap into persistent mode1-reset `-22` state.
- First post-cold-boot retest should be:

```bash
sudo modprobe -r amdgpu || true
sudo dmesg -C
sudo modprobe amdgpu fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1
dmesg -T | grep -i amdgpu | tail -n 200
```

- Convenience runner added for this exact retest:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange ./run-postcold-psp-smoke.sh
```

- Latest runner output (still warm-reset limited):
  - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260313-211929.log`
  - Result: still `MODE1 reset -> psp wait timeout (reg 0x16080 val 0x00070000) -> -22`.

## Iteration 18 (2026-03-13 late night, fw_load_type=3 / RLC-backdoor experiment)

### What was added

- Experimental load-type mapping in live source:
  - `drivers/gpu/drm/amd/amdgpu/amdgpu_ucode.c`
  - default load-type selection now maps `fw_load_type=3` to `AMDGPU_FW_LOAD_RLC_BACKDOOR_AUTO` (instead of falling through to PSP).
- Persisted as new userpatch:
  - `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0022-drm-amdgpu-ucode-allow-fw-load-type-3-rlc-backdoor.patch`
- During first fw3 smoke this exposed a kernel oops in mode1 reset path (see below). To contain that:
  - `drivers/gpu/drm/amd/amdgpu/amdgpu_device.c` arm64 reset guard extended to also skip init reset for `AMDGPU_FW_LOAD_RLC_BACKDOOR_AUTO`.
- Persisted as:
  - `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0023-drm-amdgpu-arm64-skip-init-reset-for-rlc-backdoor.patch`
- Orchestration updated to include `0022` + `0023`:
  - `/home/orange/gpu-bringup/run-rk3588-amdgpu-bringup.sh`
  - `/home/orange/gpu-bringup/RK3588_AMDGPU_PATCHSET_RUNBOOK.md`

### Smoke result for fw3 (before reset-guard containment)

- Command run:
  - `modprobe amdgpu mes=0 num_kcq=0 msi=1 fw_load_type=3`
- Log:
  - `/home/orange/gpu-bringup/logs/smoke-20260313-214102-fw3.log`
- New failure signature:
  - `Unable to handle kernel NULL pointer dereference at virtual address 000000000000065c`
  - `pc : smu_mode1_reset_is_support+0x8/0x50 [amdgpu]`
  - call path includes `amdgpu_device_mode1_reset` during init reset.

Interpretation:
- The fw3 mapping itself is accepted, but init still entered the mode1 reset path where this branch is not safe on current arm64 bring-up state.
- This is why `0023` was added immediately after to skip that reset for fw3 mode.

### Rebuild/install status after containment patch

- Rebuilt `amdgpu.ko` with `0022+0023`.
- Installed module hash:
  - `sha256=149a28fba30fe2790e01b8db9fc6905c4a2fd1b46470ff81519726ad1ae4589a`
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
- Backups created:
  - `.../amdgpu.ko.bak-20260313-214333`
  - previous backup `.../amdgpu.ko.bak-20260313-214040`

### Current runtime caveat

- The current boot has `amdgpu` still loaded in-use after the fw3 oops and cannot be cleanly unloaded:
  - `modprobe -r amdgpu` => `FATAL: Module amdgpu is in use.`
- Therefore the newly installed module payload (`149a28...`) is on disk but not active in-memory yet.

### Required next step

- Reboot once to clear the post-oops module state.
- First post-reboot validation should be:

```bash
cd /home/orange/gpu-bringup
echo orange | sudo -S dmesg -C
echo orange | sudo -S modprobe amdgpu mes=0 num_kcq=0 msi=1 fw_load_type=3
dmesg -T | grep -i amdgpu | tail -n 260
```

- If fw3 still regresses, immediately compare with direct baseline:

```bash
echo orange | sudo -S modprobe -r amdgpu || true
echo orange | sudo -S dmesg -C
echo orange | sudo -S modprobe amdgpu mes=0 num_kcq=0 msi=1 fw_load_type=0
dmesg -T | grep -i amdgpu | tail -n 260
```

## Iteration 19 (2026-03-13 night, stabilize after fw3 crash path)

### What was clarified

- PCIe root port link is correctly Gen3 x4 on this board:
  - `0000:00:00.0 LnkCap: Speed 8GT/s, Width x4`
  - `0000:00:00.0 LnkSta: Speed 8GT/s, Width x4`
- Earlier `BAR ... failed to assign` messages are transient during reallocation; BAR0/BAR2 end up assigned again in the same probe sequence.

### What was changed now

- Rolled back the two risky fw3/PSP containment experiments in live source:
  - `drivers/gpu/drm/amd/amdgpu/amdgpu_discovery.c`
    - removed PSP IP-block inclusion for `AMDGPU_FW_LOAD_RLC_BACKDOOR_AUTO`.
  - `drivers/gpu/drm/amd/amdgpu/amdgpu_psp.c`
    - removed arm64 early-return skip in `psp_hw_init()` for fw3.
- Kept diagnostic logging (`0025..0028`) but removed `0029/0030` from active automation:
  - `/home/orange/gpu-bringup/run-rk3588-amdgpu-bringup.sh`
  - `/home/orange/gpu-bringup/RK3588_AMDGPU_PATCHSET_RUNBOOK.md`
  - Runbook marks `0029/0030` as archived/experimental only.

### Rebuild/install status

- Rebuilt module from current source:
  - `make -j$(nproc) M=drivers/gpu/drm/amd/amdgpu modules`
- Installed module:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
  - new hash: `8c366c69f706a55b4366bf95f6090ec75d469261b074f95bcf040c20f8ac6c42`
  - backup hash: `251355b74bf94a2373788618d93bef731255c15d7f6c8fd56442b73ee381d459`
    - backup file: `.../amdgpu.ko.bak-20260313-224136`

### Runtime caveat

- Existing in-memory `amdgpu` instance is still from pre-rebuild session and remains stuck in-use after prior fw3 crash path.
- Module unload attempts remain blocked, so the newly installed payload is on disk but not active in RAM yet.

### Required next test step

- Reboot once, then run baseline smoke on fw1/fw0 (not fw3) first:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange MODPROBE_ARGS='fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1' ./run-postcold-psp-smoke.sh
```

- Compare with fw0 immediately after:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange MODPROBE_ARGS='fw_load_type=0 async_gfx_ring=0 num_kcq=0 mes=0 msi=1' ./run-postcold-psp-smoke.sh
```

## Iteration 20 (2026-03-13 late night, fw0 direct-path narrowing after reboot)

### Baseline re-check after reboot

- Boot cmdline still intentionally blacklists automatic load:
  - `modprobe.blacklist=amdgpu`
- Root link remains confirmed Gen3 x4.

### Reliable fw0 result before the latest unvalidated test

- Manual/reliable `fw_load_type=0` smoke continued to show the same narrow failure:
  - probe reaches VRAM/GART init cleanly
  - `gfx_v10_0` fails with `ring gfx_0.0.0 test failed (-110)`
  - CP/RLC readback registers remain `0xffffffff`
- Representative diagnostics:
  - `failed to halt cp gfx`
  - `gfx cp ucode load readback abnormal: ... direct pfp_ucode=0xffffffff ...`
  - `gfx ring state: rptr=0x0 wptr=0x500 sw_wptr=0x500`
  - `gfx cp fw regs: PFP_UCODE_ADDR=0xffffffff ... RLCS_BOOTLOAD_STATUS=0x00000000`

### What was changed in live source during this narrowing

- `drivers/gpu/drm/amd/amdgpu/gfx_v10_0.c`
  - kept earlier ring-timeout diagnostics
  - added `gfx_v10_0_cp_gfx_prepare_for_load()` helper
  - helper now:
    - checks PCI command register / bus-master bit before CP load
    - halts CP
    - if CP is still busy, performs local `gfx_v10_0_soft_reset()`
    - logs post-reset `CP_STAT` / `GRBM_STATUS` / `GRBM_STATUS2`
- A short-lived experiment that added post-IC-base invalidate/prime waits to the PFP/CE/ME direct loaders was removed again because it produced no improvement.

### Important new positive finding

- The local GFX soft reset is useful and changed the state in a real way.
- Before soft reset:
  - `CP_STAT=0x84008000`
  - `GRBM_STATUS=0xa0003028`
  - `GRBM_STATUS2=0x70000008`
- After soft reset:
  - `CP_STAT=0x00000000`
  - `GRBM_STATUS=0x00003028`
  - `GRBM_STATUS2=0x00000008`
- Interpretation:
  - one real gap is now closed: the CP no longer starts the direct-load path from a permanently dirty/busy state.
  - however, even from this cleaner state, the direct CP microcode/icache register readback still collapses to `0xffffffff`.

### Follow-up experiment and outcome

- Switched direct `mec/pfp/ce/me` BO copies in `gfx_v10_0.c` from `memcpy()` to `memcpy_toio()` and added `wmb()` before unmap.
- Result:
  - no observable improvement in the reliable `fw0` smoke signature
  - `0xffffffff` CP readback remained unchanged
- Interpretation:
  - pure copy semantic mismatch is now less likely to be the primary remaining blocker.

### Reliable module state from this phase

- Hash that was reliably smoke-tested with the local soft-reset helper:
  - `709accae37ecf6e166bd1804b7435e6e40c238c6af504f9daf4db467b12a8670`

## Iteration 21 (2026-03-13 very late, unvalidated GPA-override reapply attempt)

### What was added

- `drivers/gpu/drm/amd/amdgpu/gfx_v10_0.c`
  - `gfx_v10_0_cp_gfx_prepare_for_load()` was extended to:
    - re-apply `gfx_v10_0_disable_gpa_mode()` before CP halt
    - re-apply it again after the local soft reset
    - log `CPC_PSP_DEBUG` / `CPG_PSP_DEBUG` readback

Reason:
- the direct fw0 path already enables GPA override in `gfx_v10_0_hw_init()`;
- hypothesis was that the later local `GRBM_SOFT_RESET` may clear those bits and break subsequent CP direct-load addressing.

### Why this is NOT yet a trusted result

- The module carrying the GPA re-apply/readback change was installed on disk:
  - current on-disk hash: `dafc0c5ea2f594081b72f2f617174e2cefa5797ba0bbcdf73467b0845fae173c`
- But the follow-up load was not a normal `modprobe` smoke. A direct `insmod` attempt was used while recovering module-index state, and that crashed earlier in the display path:
  - `Unable to handle kernel NULL pointer dereference at virtual address 0000000000000008`
  - `pc : drm_atomic_private_obj_fini+0x20/0x64`
  - `lr : amdgpu_dm_fini+0x48/0x13c [amdgpu]`
  - call trace includes:
    - `amdgpu_dm_init.isra.0+0x3dc/0x16a0 [amdgpu]`
    - `dm_hw_init+0x20/0x50 [amdgpu]`
    - `amdgpu_device_init+0x1798/0x1bf8 [amdgpu]`
    - `amdgpu_pci_probe+0x174/0x32c [amdgpu]`
- This oops happened before the useful fw0 CP diagnostics were reached again.

### Current caveat at save time

- `amdgpu` is again resident/in-use after the failed `insmod` path and cannot be cleanly unloaded in this boot.
- Therefore:
  - the current on-disk module (`dafc0c...`) is present but unvalidated
  - the last trusted behavioral finding remains Iteration 20:
    - local GFX soft reset helps clean CP state
    - direct CP microcode/icache register programming still does not stick

### Strict next step after reboot

- Reboot to clear the post-oops loaded module state.
- Do NOT use direct `insmod` for the next comparison unless module-indexing is broken again.
- First trusted comparison after reboot should be:

```bash
echo orange | sudo -S /sbin/modprobe -r amdgpu || true
echo orange | sudo -S dmesg -C
echo orange | sudo -S /sbin/modprobe amdgpu fw_load_type=0 async_gfx_ring=0 num_kcq=0 mes=0 msi=1
echo orange | sudo -S dmesg -T | grep -i amdgpu | tail -n 260
```

- If the GPA-readback build crashes or misbehaves again, revert only the GPA re-apply/readback addition and keep the previously useful local soft-reset helper as the trusted narrowing baseline.

## Iteration 22 (2026-03-14 early morning, PSP warm-vs-cold split clarified)

### Installed module state

- Current installed module hash:
  - `b5cb339b856bc25f3842d5d5b8978e4d67eef1b86b1d07447f47599019227fb4`
- Source tree carrying this module:
  - `/home/orange/gpu-bringup/armbian-build/cache/sources/linux-kernel-worktree/6.1__rk35xx__arm64`

### What was added in this iteration

- `drivers/gpu/drm/amd/amdgpu/amdgpu_psp.c`
  - added `psp ta shared alloc:` logging
  - added `psp ta load prep:` logging
  - these are meant to expose ASD/TA shared-buffer MC/PA addresses on the next successful cold-path run
- `drivers/gpu/drm/amd/amdgpu/psp_v11_0.c`
  - added `psp ring prewait:` logging before the `sOS ready for ring creation` wait
  - added `psp ring prewait timeout regs:` dump on timeout
- `run-postcold-psp-smoke.sh`
  - no longer truncates to `grep ... | tail`
  - now stores a full `dmesg -T` snapshot in a paired file:
    - `postcold-psp-dmesg-<timestamp>.log`
- `run-rk3588-amdgpu-bringup.sh smoke`
  - same full-`dmesg` snapshot behavior

### High-confidence runtime split

- Warm reboot path is currently reproducible and stops before the first PSP command submit:
  - after `psp ring init: type=2 ring_mc=0x8000105000 ring_size=0x1000`
  - immediate MP0/MMHUB faults begin at:
    - `in page starting at address 0x0000000200000000`
  - ring create then waits forever for `sOS ready`
- New warm-path register evidence:
  - before wait:
    - `psp ring prewait: C2P64=0x00030000 C2P65=0x00000000 C2P66=0x00000000 C2P81=0x44af199d`
  - on timeout:
    - `psp ring prewait timeout regs: C2P64=0x00030000 C2P65=0x00000000 C2P66=0x00000000 C2P69=0x00105000 C2P70=0x00000080 C2P71=0x00001000 C2P81=0x44af199d`
  - then:
    - `Failed to wait for sOS ready for ring creation`
    - `PSP create ring failed!`
- Verified warm-path snapshot log:
  - `/home/orange/gpu-bringup/logs/smoke-live-dmesg-20260314-004112.log`

### Relation to the earlier deeper fw3 findings

- This warm-reboot failure does NOT invalidate the earlier deeper cold-path results.
- The deeper path remains the last trusted cold-state finding:
  - `LOAD_TOC` produced a valid response despite PSP fence timeout
  - `SETUP_TMR` also produced `status=0`
  - the next hard blocker was `LOAD_ASD`, with no PSP response write
- Therefore the current priority is:
  - use the new TA/ASD logging on the next cold boot
  - capture the exact ASD shared-buffer addresses when the system reaches that deeper path again

### Coreforge comparison outcome

- The Coreforge/RPi5 line of investigation was useful, but most of the obvious ARM-side `amdgpu` fixes were already present locally:
  - `memset_io`
  - `memcpy_fromio`
  - `ttm_uncached` on ARM64 GTT
- So Coreforge was directionally helpful, but not the missing one-line fix for the current PSP issue.

### Exact next step after the next cold boot

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange MODPROBE_ARGS='fw_load_type=3 num_kcq=0 mes=0 msi=1' ./run-postcold-psp-smoke.sh
```

Then inspect:

- newest `postcold-psp-smoke-*.log`
- matching `postcold-psp-dmesg-*.log`

and specifically grep for:

```bash
rg -n "psp ta shared alloc|psp ta load prep|LOAD_TOC|SETUP_TMR|LOAD_ASD|submit-pre|submit-post|ignoring PSP fence timeout" /home/orange/gpu-bringup/logs/postcold-psp-dmesg-*.log
```

## Iteration 23 (2026-03-14 night, reserve/training geometry pinned down)

### Installed module state

- Newly installed `amdgpu.ko` hash:
  - `694baba46b86e66e7308b02d104e2f09a2f77709f0d358fa39b15bc5fc5c697e`
- Previous installed hash kept as backup baseline:
  - `b5cb339b856bc25f3842d5d5b8978e4d67eef1b86b1d07447f47599019227fb4`

### What was added

- `drivers/gpu/drm/amd/amdgpu/amdgpu_ttm.c`
  - logs `reserve_tmr` geometry:
    - BIOS reserved FB size
    - effective reserve size
    - `mc_vram` / `real_vram` / `visible_vram`
    - `vram_start` / `vram_end`
    - `vram_base_offset`
  - logs memory-training reserve offsets:
    - `p2c`
    - `c2p`
    - `fw_reserved_offset`
- `drivers/gpu/drm/amd/amdgpu/amdgpu_psp.c`
  - logs memory-training decision:
    - runtime DB present or not
    - boot config bitmask
    - enable state
- `drivers/gpu/drm/amd/amdgpu/psp_v11_0.c`
  - logs when v11 memory training actually begins and which ops resolve

### New verified values

- Warm verifier log:
  - `/home/orange/gpu-bringup/logs/warm-verify-dmesg-20260314-012014.log`
- Reserve/memory-training geometry on this card:
  - `bios_reserved=0x300000`
  - `reserve_size=0x300000`
  - `mc_vram=0xff000000`
  - `real_vram=0xff000000`
  - `visible_vram=0x10000000`
  - `fw_reserved_offset=0xfed00000`
  - `c2p=0xfec00000`
  - `p2c=0xfeff8000`
- This means the reserved VRAM area is now concretely pinned to the last few MiB below the 4080 MiB top-of-VRAM boundary.

### Diagnostic experiments done

- `vramlimit=3584` and `vramlimit=4064` were tested as geometry probes.
- Both fail much earlier in `gmc_v10_0` / TTM reserve path with:
  - `alloc c2p_bo failed(-22)`
- Conclusion:
  - `vramlimit` is too invasive as a quick probe here.
  - It does confirm that the memory-training reserve area is highly sensitive and part of the problem surface.

### Current warm-state behavior with the new module

- Important change:
  - the current warm verifier no longer stops before first submit
  - it now reaches:
    - `ID_LOAD_TOC`
    - then `SETUP_TMR`
- After `SETUP_TMR` submit it falls into endless MP0/MMHUB faults at:
  - `0x0000000200000000`
- In this warm run there is no `SETUP_TMR` response writeback and no clean timeout unwind; the user-space `modprobe` remained stuck after the submit.
- Residual process seen:
  - `modprobe amdgpu fw_load_type=3 num_kcq=0 mes=0 msi=1`
  - PID `4098`
  - could not be cleanly killed from user space during this session

### Interpretation

- This is progress in diagnostics:
  - we now know the exact firmware-reserved and memory-training offsets
  - warm path is currently deeper than the older `ring create prewait` stall
- But it is not a functional success yet:
  - current blocker is still in the PSP/TMR area
  - now with concrete evidence that reserved VRAM / training layout is involved

### Exact next step

- Reboot to clear the stuck in-kernel `modprobe` state, then run a fresh cold-state smoke with the new module:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange MODPROBE_ARGS='fw_load_type=3 num_kcq=0 mes=0 msi=1' ./run-postcold-psp-smoke.sh
```

- Then inspect first:
  - newest `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-*.log`
  - `/home/orange/gpu-bringup/logs/warm-verify-dmesg-20260314-012014.log`

## Iteration 24 (2026-03-14 late night, TMR fixed, ASD fix staged, cold validation pending)

### Module hashes and what each one changed

- `3f24c1eb679507a16a6239499f368ea725460a1071465c696d96594a42696cd7`
  - introduced fixed/natural TMR placement below the reserved training window
- `1004ca940b60e56688082c196e2f07e89dd94b33604d7b3587f632d2e33e799c`
  - added missing ASD shared-buffer allocation in `psp_asd_initialize()`
- `a0259ff7e37481c40ea7cd00bdc50a826773116af500ca206ab8f24d312c07c5`
  - latest installed module
  - changed ARM64 init-reset skip logic so explicit `reset_method=` is honored for experiments

### What was definitively solved

- Fixed TMR placement was the real breakthrough.
- In `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-015811.log` the fw3 cold-path reached:
  - `ID_LOAD_TOC` with valid response
  - fixed TMR placement at:
    - `offset=0xfdc00000`
    - `mc=0x80fdc00000`
    - `pa_mod_size=0x0`
  - `SETUP_TMR` with `resp{status=0x0 ...}`
  - then `LOAD_ASD`
- This is further than the earlier states that stopped at `SETUP_TMR` or even before ring creation.

### What the new blocker revealed

- The first clean `LOAD_ASD` attempt still carried:
  - `shared_mc=0x0`
  - `shared_pa=0x0`
  - `shared_len=0x0`
- Therefore the next concrete bug was not "mystical PSP behavior" but a missing ASD TA shared buffer on this path.
- That was fixed in source by adding:
  - `psp_ta_init_shared_buf(psp, &psp->asd_context.mem_context);`

### Why the later results looked worse

- After the ASD-buffer fix and later reset-override patch were installed, the remaining tests in this boot were all warm/reload-style validations.
- Those are currently polluted by stale ASIC/PSP state because:
  - fw3 bring-up intentionally skips the usual init reset in the auto path
  - sysfs reset was not usable on this platform
  - manual bridge reset and forced `reset_method=5` both produced non-comparable early failures
- Concretely:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-020248.log`
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-020354.log`
  - both fail very early with `get invalid ip discovery binary signature from vram`
- Those are not evidence that the TMR/ASD work regressed on cold boot.

### Current best interpretation

- Highest-confidence solved items:
  - `LOAD_TOC`
  - `SETUP_TMR`
- Highest-confidence current blocker:
  - validating the ASD shared-buffer fix on a true cold path
- Current progress estimate:
  - diagnosis about `98%`
  - functional bring-up about `82-85%`

### New helper/logging hardening

- `run-postcold-psp-smoke.sh`
  - now logs `boot_id`
  - now logs installed `amdgpu.ko` SHA256
  - now attempts `modprobe -r amdgpu` after capture
- `run-rk3588-amdgpu-bringup.sh smoke`
  - same additions
- Focused source snapshot:
  - `/home/orange/gpu-bringup/state-snapshots/amdgpu-worktree-diff-20260314-iteration24.patch`
  - SHA256:
    - `cd581ceab560b72d8bf40c27cdefe84897e22feecb09d52a3e4887f6ad726bb8`

### Exact next trusted step

- Reboot to get a truly fresh cold state with the current installed module `1bbe9bf3...`.
- Then run exactly:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange MODPROBE_ARGS='fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1' MODPROBE_TIMEOUT_SEC=45 ./run-postcold-psp-smoke.sh
```

- First files to inspect after that run:
  - newest `/home/orange/gpu-bringup/logs/postcold-psp-smoke-*.log`
  - matching `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-*.log`
- Why this changed:
  - `fw_load_type=3` now looks like a beige_goby-specific dead-end because its CPU-side RLC TOC parse reads non-plaintext SOS data
  - the optional `RAP` TA is now skipped on `arm64` + `MP0 11.0.13`

## Iteration 31 update (2026-03-14 pre-dawn, autonomous same-boot reset path)

### Fresh verified findings

- On the still-running boot `9ecc216c-0cfd-41ae-ad9c-7e06afbc7df9`, a plain smoke with on-disk module `0628c42239b8bc7b9cf37ef73db8ac398d831df5e4ba764b9ee4fb611aeefd5e` still failed in the known early PSP path:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-045039.log`
  - `PSP load kdb failed`
  - internal `psp_v11_0_mode1_reset()` still saw `C2PMSG_64 = 0x00030000`
- Therefore the lingering same-boot blocker is still a stale `DESTROY_RINGS` / PSP-not-ready state when no deeper device reset is performed.

### New autonomy breakthrough

- A targeted Secondary Bus Reset on the downstream GPU bridge works on this hardware:
  - bridge: `0000:02:00.0`
  - downstream device remains visible after rescan:
    - `0000:03:00.0` VGA
    - `0000:03:00.1` HDMI audio
- This gives a realistic replacement for the user-dependent manual cold-start loop.

### What the first SBR-driven smoke changed

- First smoke after asserting SBR on `02:00.0`:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-045401.log`
- Failure moved away from the earlier PSP/KDB loop into a later GMC/VM bring-up crash:
  - `kernel BUG at drivers/gpu/drm/amd/amdgpu/gmc_v10_0.c:603`
  - stack: `gmc_v10_0_get_vm_pde -> amdgpu_gmc_get_pde_for_bo -> gfxhub_v2_1_gart_enable`
- The immediately preceding memory geometry was wrong:
  - `VRAM: 4080M 0x0000FFFFFF000000 - 0x00010000FDFFFFFF`
  - this is invalid compared to all previously good cold-path logs, which consistently showed:
    - `vram_start=0x8000000000`
    - `fb_offset=0x0`
- Interpretation:
  - SBR really does change device state in a useful way
  - but because the init reset is intentionally skipped on this path, `GCMC_VM_FB_LOCATION_BASE` / `FB_OFFSET` can come back bogus after SBR
  - the crash is then caused by an underflow in `amdgpu_gmc_vram_mc2pa()`, not by the earlier PSP address/PSP reset bugs

### New fixes now on disk

- `drivers/gpu/drm/amd/amdgpu/gmc_v10_0.c`
  - added a new exact-tuple helper for the MSI RX 6400 (`1002:743f`, `1462:5082`)
  - added static FB layout fallback for the hot-reset path:
    - `base = 0x8000000000`
    - `fb_offset = 0x0`
  - keeps existing static `CONFIG_MEMSIZE` fallback at `0xff0` MiB
- `/home/orange/gpu-bringup/run-postcold-psp-smoke.sh`
  - new optional pre-step:
    - `PRE_MODPROBE_RESET=bridge_sbr`
  - default bridge:
    - `PRE_MODPROBE_RESET_BRIDGE=02:00.0`
  - behavior:
    - unload `amdgpu`
    - assert/clear `BRIDGE_CONTROL` secondary-bus-reset bit
    - rescan PCI bus
    - then clear `dmesg` and run the normal smoke path

### Build/install state

- Rebuilt `amdgpu.ko` from the updated live source tree.
- Installed on disk at:
  - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
- Current on-disk hash:
  - `680988ad42780b4d123f31a156a01f0faca4e9a1a1a8a9ee56093d5c438e2c6d`

### Runtime caveat

- The current in-RAM state is dirty again after the `gmc_v10_0.c:603` BUG:
  - `amdgpu` remains loaded
  - `amdgpu-reset-de` is still present
- So the newly installed `680988...` module is on disk but not yet meaningfully testable in this exact RAM session.

### Best next step

- Preferred next autonomous smoke after a fresh OS boot:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange PRE_MODPROBE_RESET=bridge_sbr PRE_MODPROBE_RESET_BRIDGE=02:00.0 MODPROBE_ARGS='fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1' MODPROBE_TIMEOUT_SEC=60 ./run-postcold-psp-smoke.sh
```

## Iteration 36 update (2026-03-14 afternoon, SMU/TMR boundary isolated and smoke set extended)

### Historical clarification

- The remembered `SMU is initialized successfully!` runs were real, but they belonged to the older direct path:
  - date:
    - `2026-03-13`
  - path:
    - `fw_load_type=0`
  - later blocker there:
    - `ring gfx_0.0.0 test failed (-110)`
- That milestone is **not** yet a trusted result of the current preferred PSP path:
  - `fw_load_type=1`

### New runs on boot `2fab404c-77de-44af-8ce2-c72798e9bd24`

- Fresh trusted PSP reference:
  - smoke:
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-134619.log`
  - dmesg:
    - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-134619.log`
  - module hash:
    - `ae855baebded3bfff3525128c6e7642f58506fcb878426ca30d95bbd4ed06f6a`
  - result:
    - PMFW forced-early branch
    - `13/21` green
    - first blocker:
      - `smu_load`

- Same-boot directional proof after adding the explicit SMU readiness precheck:
  - smoke:
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-135942.log`
  - dmesg:
    - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-135942.log`
  - module hash:
    - `be675166dc7aa9c586ba22f01f5eae388ff1ef95fc04a429bcc80bdc0d7f4a6d`
  - key new facts:
    - `PMFW alive but SMU precheck failed ret=-62; keep early psp_load_smu_fw`
    - `LOAD_IP_FW(SMC)` returned `resp{status=0x0 ...}`
    - first blocker moved later to:
      - `tmr_load`
      - `SETUP_TMR` no response
  - interpretation:
    - useful directional progress
    - not fresh truth

- Same-boot boundary-smoke validation after another reload:
  - smoke:
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-140252.log`
  - dmesg:
    - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-140252.log`
  - module hash:
    - `be675166dc7aa9c586ba22f01f5eae388ff1ef95fc04a429bcc80bdc0d7f4a6d`
  - result:
    - degraded to `ring_create`
  - interpretation:
    - repeated same-boot probing on this boot is now dirty
    - do not treat this as a real regression of the fresh baseline

### New smoke/process changes

- `AGENTS.md` updated:
  - every newly working frontier must get its own dedicated boundary smoke
- New boundary smoke:
  - `/home/orange/gpu-bringup/run-psp-smu-tmr-smoke.sh`
  - reports:
    - PMFW branch
    - SMU precheck
    - `SMC_prep`
    - `LOAD_IP_FW`
    - `SETUP_TMR`
    - `FIRST_BLOCKER`

### New narrow hypothesis and staged patch

- Failing frontier targeted:
  - `tmr_load`
- Hypothesis:
  - after successful early `psp_load_smu_fw()` on exact `arm64 + MP0 11.0.13 + fw_load_type=1`, SMU/PMFW may still be busy and poison the immediate next `SETUP_TMR`
- Evidence:
  - `135942` shows:
    - precheck `ret=-62`
    - then successful `LOAD_IP_FW(SMC)`
    - then immediate `SETUP_TMR` no-response timeout
- New staged code:
  - `drivers/gpu/drm/amd/amdgpu/amdgpu_psp.c`
  - helper:
    - `psp_arm64_post_smu_reload_settle()`
  - behavior:
    - only on exact `arm64 + MP0 11.0.13 + fw_load_type=PSP`
    - bounded short settle after successful early `psp_load_smu_fw()`
    - one post-reload readiness check before `psp_tmr_load()`
- Current on-disk module hash:
  - `86b03d3b9735631345a41be0244b03e9af8d1c2a0080abff5487ad505d5791bd`

### Current trustworthy state

- Fresh protected references remain:
  - `123919`
    - first blocker `tmr_load`
  - `134619`
    - first blocker `smu_load`
- Same-boot directional evidence:
  - `135942`
    - `LOAD_IP_FW(SMC)` can succeed on the newer path
    - blocker then becomes `tmr_load`
- Current boot after repeated same-boot tests:
  - no longer suitable for more trusted runtime conclusions

### Next exact trusted step

- Reboot normally
- Then run:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange SMOKE_DEADLINE_SEC=120 MODPROBE_TIMEOUT_SEC=30 RMMOD_TIMEOUT_SEC=10 STORM_SAMPLE_SEC=2 MMHUB_FAULT_GUARD_THRESHOLD=32 IH_OVERFLOW_GUARD_THRESHOLD=6 PRE_MODPROBE_RESET=none MODPROBE_ARGS='fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1' ./run-psp-smu-tmr-smoke.sh
```

## Iteration 35 update (2026-03-14 afternoon, PMFW/SMU fork isolated)

- Protected fresh baselines are unchanged:
  - `123919` on `boot_id=a773619f-2a35-48c1-b781-427b5c5d8786`
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-123919.log`
    - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-123919.log`
    - module hash:
      - `905b768b546de99670d2af8aebf35c49eca5ed97971c3eed51a350b191d028ab`
    - best protected phase depth:
      - `13/21` green
      - first blocker `tmr_load`
  - deeper fresh reference:
    - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-113549.log`
    - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-113549.log`
    - first blocker `smu_load`

- Important methodology fact:
  - no true reboot happened during the latest work
  - live boot remained:
    - `boot_id=a773619f-2a35-48c1-b781-427b5c5d8786`
  - all new runs below are same-boot directional only

- Current clean on-disk module hash:
  - `ae855baebded3bfff3525128c6e7642f58506fcb878426ca30d95bbd4ed06f6a`

- Same-boot run on the restored clean path:
  - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-130623.log`
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-130623.log`
  - result:
    - `9/21` phases green
    - first blocker remains `smu_load`
  - newly proven:
    - after failed `LOAD_IP_FW`, PMFW is still alive
    - evidence:
      - `mp1_fw_flags=0x00000001`
      - `alive=1`
      - `centralized=1`
      - `mp1_state=0`
    - this narrows the problem to PSP->SMU handoff/response, not "PMFW dead"

- Disproven same-boot hypotheses:
  1. extra HDP flush for `firmware.fw_buf`
     - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-130119.log`
     - no improvement
  2. staging SMC payload into `fw_pri` before `LOAD_IP_FW`
     - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-130319.log`
     - command address changed, outcome stayed the same

- Temporary probe that was reverted immediately:
  - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-131259.log`
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-131259.log`
  - hypothesis:
    - send `PrepareMp1ForUnload` right before `LOAD_IP_FW`
  - result:
    - `SMU: I'm not done with your previous command`
    - `[PrepareMp1] Failed!`
    - `ret=-62`
    - still no PSP response for `LOAD_IP_FW`
  - conclusion:
    - do not keep this behavior change
    - reverted immediately

- Current structural insight:
  - the unresolved fork is now explicit:
    - one path forces early `psp_load_smu_fw()` and first blocks at `smu_load`
    - the alternative path skips early SMU reload and first blocks at `tmr_load`
  - next work must reconcile this fork against the protected fresh baselines instead of opening unrelated hypotheses

## Iteration 34 update (2026-03-14 late morning, reset/GTT counterchecks closed)

- Clean boot used for controlled same-boot A/B:
  - `boot_id=6510ad6e-d1c6-4c4e-a956-3176d0ce29aa`

### A/B 1: explicit init `MODE1` reset

- Command path:
  - `reset_method=2 fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1`
- Logs:
  - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-114608.log`
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-114608.log`
- Result:
  - early failure again in init reset
  - `SMU: I'm not done with your previous command`
  - `psp mode 1 reset failed`
  - `asic reset on init failed`
- Conclusion:
  - the current `skip asic reset on init` quirk is still required on this path
  - this is no longer just a guess; the fresh controlled A/B reproduced the failure

### A/B 2: revert firmware buffer from VRAM back to GTT

- Temporary test module hash:
  - `f3cdff5b5612999182ec6453136ddb943922004902093bede0dbf2b14262e2f0`
- Logs:
  - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-114935.log`
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-114935.log`
- Proven:
  - firmware buffer really switched to GTT:
    - `firmware.fw_buf domain=gtt load_type=1 mc=0x846000 psp_addr=0x846000`
  - the result is strictly worse than the current VRAM-backed reference:
    - failure already in PSP ring creation
    - `C2P64=0x00070000`
    - `Failed to wait for sOS ready for ring creation`
    - `PSP create ring failed`
  - it does **not** reach `ID_LOAD_TOC`
  - it does **not** reach the later `SMC LOAD_IP_FW` blocker
- Conclusion:
  - VRAM-backed `firmware.fw_buf` is required for the better RK3588 path
  - the earlier suspicion that this might be a misapplied upstream generalization is now tested and rejected for our exact setup

### Current best-known primary path

- Best trusted reference remains the fresh no-SBR PSP path:
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-113549.log`
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-114257.log`
- On that better path:
  - `ID_LOAD_TOC` succeeds
  - the first hard blocker is the early PMFW/SMU reload inside `psp_hw_start()`
  - exact failing stage:
    - `psp_load_smu_fw()`
    - `LOAD_IP_FW`
    - instrumented as:
      - `load_ip_fw prep ucode=SMC id=0x31 mc=0x8000578000 size=0x3b200 type=0x12`
  - failure shape:
    - no PSP response
    - `PSP cmd wait expired for LOAD_IP_FW with no response`
    - followed by MMHUB/MP0 faults on `0x0000000100000000`

### Current on-disk restored module

- Restored better-path module hash:
  - `023abf0b2bdbcc7ae5066a55b3feb8298a3f907e279403d702c1c9301d8074f6`

### Next exact focus

- Do **not** revisit:
  - init `MODE1` reset
  - GTT firmware BO
- Continue only on:
  - PMFW/SMU reload sequencing and liveness on `MP0 11.0.13`
  - why `psp_hw_start()` early `psp_load_smu_fw()` now stalls before `TMR load`, while older historical runs still reached `SMU is initialized successfully!`

### Current estimate

- diagnostics about `99%`
- functional bring-up about `93-94%`

## Iteration 32 update (2026-03-14 morning, FB fallback validated + next null-callback fix)

### What was newly proven

- Fresh boot:
  - `boot_id=4a56af61-4fcb-47f3-a6a0-92e8bc830f51`
- First trusted run with:
  - `PRE_MODPROBE_RESET=bridge_sbr`
  - `fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1`
- Logs:
  - `/home/orange/gpu-bringup/logs/postcold-psp-smoke-20260314-095135.log`
  - `/home/orange/gpu-bringup/logs/postcold-psp-dmesg-20260314-095135.log`
- Result:
  - the new static FB fallback definitely worked
  - log shows:
    - `arm64 bring-up: using static FB layout fallback base=0xffffff000000 fb_offset=0xffffffff000000`
    - followed by restored sane geometry:
      - `VRAM: 4080M 0x0000008000000000 - 0x00000080FEFFFFFF`
- Therefore the prior `0xFFFFFF...` VRAM-base bug is solved.

### New blocker isolated

- The next crash is later and cleaner:
  - `Unable to handle kernel NULL pointer dereference at virtual address 0x0`
  - `lr : gmc_v10_0_hw_init+0xb8/0x194`
- Disassembly/source correlation shows the null indirect call is:
  - `adev->hdp.funcs->init_registers(adev);`
  - within `gmc_v10_0_gart_enable()`
- Root cause:
  - on this path `HDP_HWIP=5.2.1` maps to `hdp_v5_2_funcs`
  - `hdp_v5_2_funcs` provides `flush_hdp` but not `init_registers`
  - previous crash hid this bug; the new FB fallback exposed it

### New fix now on disk

- `drivers/gpu/drm/amd/amdgpu/gmc_v10_0.c`
  - `gmc_v10_0_gart_enable()` now guards optional HDP callbacks:
    - `init_registers`
    - `flush_hdp`
  - on this exact arm64 beige_goby path it logs when `init_registers` is absent and skips it
- Rebuilt and installed module hash:
  - `c159865505e0046c6d488d7c53195c62a675e95f0be163f9888169600fa80e57`

### Runtime caveat

- The currently loaded in-RAM module is still the pre-`c159...` image from the crashy run.
- `amdgpu-reset-de` remains alive, so this boot is again not trustworthy for validating the new on-disk module.

### Next trusted step

- Reboot once, then run:

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange PRE_MODPROBE_RESET=bridge_sbr PRE_MODPROBE_RESET_BRIDGE=02:00.0 MODPROBE_ARGS='fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1' MODPROBE_TIMEOUT_SEC=60 ./run-postcold-psp-smoke.sh
```
