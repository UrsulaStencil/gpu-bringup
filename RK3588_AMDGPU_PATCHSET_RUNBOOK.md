# RK3588 + AMDGPU (vendor 6.1) Runbook

This runbook applies the prepared patchset for Armbian `rk35xx-vendor-6.1` and validates bring-up on RX 6400 (`1002:743f`).

## Patchset location

- Source patch bundle:
  - `/home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1`
- Copied into build tree:
  - `/home/orange/gpu-bringup/armbian-build/userpatches/kernel/rk35xx-vendor-6.1`
  - `/home/orange/gpu-bringup/armbian-build/userpatches/config/kernel/linux-rk35xx-vendor.config`

Files:

- `0000-enable-amdgpu.config`
- `0001-arm64-mm-handle-alignment-faults-for-pcie-mmio.patch`
- `0002-arm64-mm-force-device-mappings-for-pcie-mmio.patch`
- `0003-drm-force-writecombined-mappings-for-dma.patch`
- `0004-drm-amdgpu-disable-interrupt-state-test.patch`
- `0005-drm-amdgpu-honor-reset-method-and-allow-soc21-pci-reset.patch`
- `0006-drm-amdgpu-allow-pci-reset-method-param.patch`
- `0007-drm-amdgpu-skip-kcq-setup-when-num-kcq-zero.patch`
- `0008-drm-amdgpu-gfx10-skip-kgq-when-num-kcq-zero.patch`
- `0009-drm-amdgpu-gmc10-avoid-shutdown-tlb-flush-wedges.patch`
- `0010-drm-amdgpu-fence-avoid-irq-put-warn-on-unwind.patch`
- `0011-drm-amdgpu-gfx10-log-ring-timeout-register-state.patch`
- `0012-drm-amdgpu-gfx10-force-mmio-wptr-on-arm64.patch`
- `0013-drm-amdgpu-gfx10-log-cp-control-state-on-timeout.patch`
- `0014-drm-amdgpu-gfx10-program-rb-wptr-poll-ctrl-on-resume.patch`
- `0015-drm-amdgpu-gfx10-set-rb-exe-in-cp-rb-cntl.patch`
- `0016-drm-amdgpu-gfx10-log-rb-address-registers-on-timeout.patch`
- `0017-drm-amdgpu-gfx10-skip-cp-clear-state-bootstrap-on-arm64.patch`
- `0018-drm-amdgpu-gfx10-retry-cp-unhalt-via-rlc-if-halt-bits-stick.patch`
- `0019-drm-amdgpu-gfx10-arm64-nop-rptr-ring-pretest.patch`
- `0020-drm-ttm-arm64-coherent-cached-and-always-vmap.patch`
- `0021-drm-amdgpu-psp-v11-arm64-extend-waits-and-log-timeouts.patch`
- `0022-drm-amdgpu-ucode-allow-fw-load-type-3-rlc-backdoor.patch`
- `0023-drm-amdgpu-arm64-skip-init-reset-for-rlc-backdoor.patch`
- `0024-drm-amdgpu-ucode-skip-fw-buf-bo-for-rlc-backdoor.patch`
- `0025-drm-amdgpu-gfx10-log-rlc-autoload-timeout-registers.patch`
- `0026-drm-amdgpu-gfx10-log-rlc-autoload-toc-entries.patch`
- `0027-drm-amdgpu-gfx10-log-raw-psp-toc-entry-for-rlc-autoload.patch`
- `0028-drm-amdgpu-psp-log-toc-population-after-microcode-init.patch`

Archived/experimental (not part of active baseline): `0029`, `0030`.

## One-command helper

Use:

```bash
cd /home/orange/gpu-bringup
./run-rk3588-amdgpu-bringup.sh prepare
KERNEL_BTF=no ./run-rk3588-amdgpu-bringup.sh build
./run-rk3588-amdgpu-bringup.sh install
reboot
./run-rk3588-amdgpu-bringup.sh smoke
```

## Manual commands

### 1) Prepare `userpatches`

```bash
mkdir -p /home/orange/gpu-bringup/armbian-build/userpatches/kernel/rk35xx-vendor-6.1
cp -f \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0001-arm64-mm-handle-alignment-faults-for-pcie-mmio.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0002-arm64-mm-force-device-mappings-for-pcie-mmio.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0003-drm-force-writecombined-mappings-for-dma.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0004-drm-amdgpu-disable-interrupt-state-test.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0005-drm-amdgpu-honor-reset-method-and-allow-soc21-pci-reset.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0006-drm-amdgpu-allow-pci-reset-method-param.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0007-drm-amdgpu-skip-kcq-setup-when-num-kcq-zero.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0008-drm-amdgpu-gfx10-skip-kgq-when-num-kcq-zero.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0009-drm-amdgpu-gmc10-avoid-shutdown-tlb-flush-wedges.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0010-drm-amdgpu-fence-avoid-irq-put-warn-on-unwind.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0011-drm-amdgpu-gfx10-log-ring-timeout-register-state.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0012-drm-amdgpu-gfx10-force-mmio-wptr-on-arm64.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0013-drm-amdgpu-gfx10-log-cp-control-state-on-timeout.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0014-drm-amdgpu-gfx10-program-rb-wptr-poll-ctrl-on-resume.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0015-drm-amdgpu-gfx10-set-rb-exe-in-cp-rb-cntl.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0016-drm-amdgpu-gfx10-log-rb-address-registers-on-timeout.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0017-drm-amdgpu-gfx10-skip-cp-clear-state-bootstrap-on-arm64.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0018-drm-amdgpu-gfx10-retry-cp-unhalt-via-rlc-if-halt-bits-stick.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0019-drm-amdgpu-gfx10-arm64-nop-rptr-ring-pretest.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0020-drm-ttm-arm64-coherent-cached-and-always-vmap.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0021-drm-amdgpu-psp-v11-arm64-extend-waits-and-log-timeouts.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0022-drm-amdgpu-ucode-allow-fw-load-type-3-rlc-backdoor.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0023-drm-amdgpu-arm64-skip-init-reset-for-rlc-backdoor.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0024-drm-amdgpu-ucode-skip-fw-buf-bo-for-rlc-backdoor.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0025-drm-amdgpu-gfx10-log-rlc-autoload-timeout-registers.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0026-drm-amdgpu-gfx10-log-rlc-autoload-toc-entries.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0027-drm-amdgpu-gfx10-log-raw-psp-toc-entry-for-rlc-autoload.patch \
  /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0028-drm-amdgpu-psp-log-toc-population-after-microcode-init.patch \
  /home/orange/gpu-bringup/armbian-build/userpatches/kernel/rk35xx-vendor-6.1/

mkdir -p /home/orange/gpu-bringup/armbian-build/userpatches/config/kernel
cp -f \
  /home/orange/gpu-bringup/armbian-build/config/kernel/linux-rk35xx-vendor.config \
  /home/orange/gpu-bringup/armbian-build/userpatches/config/kernel/linux-rk35xx-vendor.config
{
  echo
  echo "# --- RK3588 AMDGPU bring-up overrides ---"
  grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' \
    /home/orange/gpu-bringup/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1/0000-enable-amdgpu.config
} >> /home/orange/gpu-bringup/armbian-build/userpatches/config/kernel/linux-rk35xx-vendor.config
```

### 2) Build kernel artifact

```bash
cd /home/orange/gpu-bringup/armbian-build
KERNEL_BTF=no ./compile.sh kernel BOARD=orangepi5-plus BRANCH=vendor RELEASE=trixie BUILD_DESKTOP=no KERNEL_CONFIGURE=no
```

### 3) Install generated packages

Prefer the exact hashed artifacts (not `output/debs`), then install with `dpkg -i`:

```bash
sudo dpkg -i \
  /home/orange/gpu-bringup/armbian-build/output/packages-hashed/global/linux-image-vendor-rk35xx_*_arm64.deb \
  /home/orange/gpu-bringup/armbian-build/output/packages-hashed/global/linux-dtb-vendor-rk35xx_*_arm64.deb \
  /home/orange/gpu-bringup/armbian-build/output/packages-hashed/global/linux-headers-vendor-rk35xx_*_arm64.deb
```

If no headers package was built, install only image + dtb.
`output/debs` can be re-versioned (`26.02.0-trunk`) and may not reflect the exact module payload you expect while iterating with same kernel release string.

### 4) Install boot safety guard (prevents no-boot on missing custom DTB)

`linux-dtb-vendor-rk35xx` removes `/boot/dtb*` during `preinst`, so out-of-tree custom DTBs are deleted unless reinstalled.

Install guard scripts:

```bash
cd /home/orange/gpu-bringup
sudo install -m 755 armbian-fdt-sanity.sh /usr/local/sbin/armbian-fdt-sanity.sh
sudo install -m 755 zz-armbian-fdt-sanity.postinst /etc/kernel/postinst.d/zz-armbian-fdt-sanity
sudo /usr/local/sbin/armbian-fdt-sanity.sh
```

Behavior:

- If `fdtfile=` in `/boot/armbianEnv.txt` points to a missing file, it auto-falls back to `rockchip/rk3588-orangepi-5-plus.dtb`.
- A timestamped backup of `armbianEnv.txt` is written before modification.

### 5) Add temporary boot debug flags (recommended first boot)

Append to kernel cmdline:

- `drm.debug=0x1ff`
- `log_buf_len=4M`
- `amdgpu.aspm=0`
- `amdgpu.runpm=0`

For RK3588 + RX6400 DC/DM crashes, force render-first mode:

- `amdgpu.dc=0`
- `amdgpu.num_kcq=0` (degraded mode: skip KCQ path while validating GFX init)
- optional debug toggle: `amdgpu.async_gfx_ring=0` (can shift failure into KIQ write-reg stalls on this platform)
  - for `modprobe` CLI use `async_gfx_ring=0` (without `amdgpu.` prefix)

Keep bring-up safe by default while iterating:

- `modprobe.blacklist=amdgpu`
- Load manually for smoke: `sudo modprobe amdgpu`

### 6) Reboot

```bash
sudo reboot
```

## Smoke tests and pass criteria

### Gate 1: kernel + module

```bash
uname -r
sudo modprobe amdgpu
cat /sys/module/amdgpu/parameters/dc
lsmod | grep -i amdgpu
lspci -nnk -s 03:00.0
```

Pass:

- module loads
- `Kernel driver in use: amdgpu`

### Gate 2: firmware + init path

```bash
dmesg -T | grep -i amdgpu | tail -n 300
```

Pass:

- `beige_goby_*` firmware load visible
- no immediate `ring timeout` / fatal init failure

### Gate 3: userspace nodes

```bash
ls -l /dev/dri
for d in /sys/class/drm/card*; do echo "$d -> $(readlink -f "$d/device/driver" 2>/dev/null)"; done
```

Pass:

- AMD render node visible (`renderD*`)

### Gate 4: Vulkan

```bash
vulkaninfo --summary
```

Pass:

- AMD GPU appears as physical Vulkan device (not only `llvmpipe`)

## Failure signatures to triage first

- `failed to load firmware amdgpu/beige_goby_*`
- `alignment fault` / `Unhandled fault`
- `ring gfx timeout` / `VM fault`
- `Problem resizing BAR0` followed by hard init failure
- `Display Core failed to initialize ...` + NULL pointer dereference (DC/DM path)
- `ring kiq_2.1.0 test failed (-110)` + `hw_init of IP block <gfx_v10_0> failed -110`
- `failed to write reg <...> wait reg <...>` loops (KIQ register write path stuck)
- repeated `WARNING ... amdgpu_irq_put` during failed init teardown
- `modprobe amdgpu` stuck in `D` state with stack in `amdgpu_virt_kiq_reg_write_reg_wait` -> `gmc_v10_0_flush_gpu_tlb`
- boot with red LED/no console after update when `fdtfile` points to missing custom DTB

## Notes

- This patchset targets render-first bring-up.
- Display output via GPU ports may still require extra ARM64/DCN work and is intentionally out of first-pass scope.
