#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/armbian-build}"
PATCH_SRC="${PATCH_SRC:-$SCRIPT_DIR/armbian-userpatches/kernel/archive/rk35xx-vendor-6.1}"
PATCH_DST="$BUILD_DIR/userpatches/kernel/rk35xx-vendor-6.1"
KERNEL_CONFIG_BASE="$BUILD_DIR/config/kernel/linux-rk35xx-vendor.config"
KERNEL_CONFIG_DST="$BUILD_DIR/userpatches/config/kernel/linux-rk35xx-vendor.config"

BOARD="${BOARD:-orangepi5-plus}"
BRANCH="${BRANCH:-vendor}"
RELEASE="${RELEASE:-trixie}"

usage() {
	cat <<'EOF'
Usage:
  ./run-rk3588-amdgpu-bringup.sh prepare
  ./run-rk3588-amdgpu-bringup.sh build
  ./run-rk3588-amdgpu-bringup.sh install
  ./run-rk3588-amdgpu-bringup.sh smoke
  ./run-rk3588-amdgpu-bringup.sh all

Environment overrides:
  BUILD_DIR=/path/to/armbian-build
  PATCH_SRC=/path/to/rk35xx-vendor-6.1-patches
  BOARD=orangepi5-plus
  BRANCH=vendor
  RELEASE=trixie
  SMOKE_MODPROBE_ARGS="mes=0 num_kcq=0 msi=1"
EOF
}

require_file() {
	local f="$1"
	if [[ ! -f "$f" ]]; then
		echo "Missing required file: $f" >&2
		exit 1
	fi
}

sudo_cmd() {
	if sudo -n true >/dev/null 2>&1; then
		sudo "$@"
		return
	fi

	if [[ -n "${SUDO_PASSWORD:-}" ]]; then
		printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@"
		return
	fi

	sudo "$@"
}

sudo_bash() {
	if sudo -n true >/dev/null 2>&1; then
		sudo bash -lc "$1"
		return
	fi

	if [[ -n "${SUDO_PASSWORD:-}" ]]; then
		printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' bash -lc "$1"
		return
	fi

	sudo bash -lc "$1"
}

run_modprobe_with_timeout() {
	local timeout_sec="$1"
	shift
	local cmd=("$@")
	local cmd_str pid

	printf -v cmd_str '%q ' "${cmd[@]}"
	pid="$(sudo_bash "$cmd_str >/dev/null 2>&1 & echo \$!")"
	pid="${pid//[[:space:]]/}"

	if [[ -z "$pid" ]]; then
		echo "[smoke] failed to start modprobe background wrapper"
		return 1
	fi

	echo "[smoke] modprobe pid: $pid (timeout ${timeout_sec}s)"
	for ((i = 0; i < timeout_sec; i++)); do
		if ! sudo_cmd kill -0 "$pid" >/dev/null 2>&1; then
			echo "[smoke] modprobe exited within timeout"
			return 0
		fi
		sleep 1
	done

	echo "[smoke] modprobe exceeded ${timeout_sec}s; sending TERM/KILL"
	sudo_cmd kill -TERM "$pid" >/dev/null 2>&1 || true
	sleep 2
	if sudo_cmd kill -0 "$pid" >/dev/null 2>&1; then
		sudo_cmd kill -KILL "$pid" >/dev/null 2>&1 || true
		sleep 1
	fi
	if sudo_cmd kill -0 "$pid" >/dev/null 2>&1; then
		echo "[smoke] modprobe pid $pid is still alive after KILL"
		return 124
	fi

	echo "[smoke] modprobe killed after timeout"
	return 124
}

prepare_patches() {
	echo "[prepare] syncing patches into Armbian userpatches..."
	require_file "$PATCH_SRC/0000-enable-amdgpu.config"
	require_file "$PATCH_SRC/0001-arm64-mm-handle-alignment-faults-for-pcie-mmio.patch"
	require_file "$PATCH_SRC/0002-arm64-mm-force-device-mappings-for-pcie-mmio.patch"
	require_file "$PATCH_SRC/0003-drm-force-writecombined-mappings-for-dma.patch"
	require_file "$PATCH_SRC/0004-drm-amdgpu-disable-interrupt-state-test.patch"
	require_file "$PATCH_SRC/0005-drm-amdgpu-honor-reset-method-and-allow-soc21-pci-reset.patch"
	require_file "$PATCH_SRC/0006-drm-amdgpu-allow-pci-reset-method-param.patch"
	require_file "$PATCH_SRC/0007-drm-amdgpu-skip-kcq-setup-when-num-kcq-zero.patch"
	require_file "$PATCH_SRC/0008-drm-amdgpu-gfx10-skip-kgq-when-num-kcq-zero.patch"
	require_file "$PATCH_SRC/0009-drm-amdgpu-gmc10-avoid-shutdown-tlb-flush-wedges.patch"
	require_file "$PATCH_SRC/0010-drm-amdgpu-fence-avoid-irq-put-warn-on-unwind.patch"
	require_file "$PATCH_SRC/0011-drm-amdgpu-gfx10-log-ring-timeout-register-state.patch"
	require_file "$PATCH_SRC/0012-drm-amdgpu-gfx10-force-mmio-wptr-on-arm64.patch"
	require_file "$PATCH_SRC/0013-drm-amdgpu-gfx10-log-cp-control-state-on-timeout.patch"
	require_file "$PATCH_SRC/0014-drm-amdgpu-gfx10-program-rb-wptr-poll-ctrl-on-resume.patch"
	require_file "$PATCH_SRC/0015-drm-amdgpu-gfx10-set-rb-exe-in-cp-rb-cntl.patch"
	require_file "$PATCH_SRC/0016-drm-amdgpu-gfx10-log-rb-address-registers-on-timeout.patch"
	require_file "$PATCH_SRC/0017-drm-amdgpu-gfx10-skip-cp-clear-state-bootstrap-on-arm64.patch"
	require_file "$PATCH_SRC/0018-drm-amdgpu-gfx10-retry-cp-unhalt-via-rlc-if-halt-bits-stick.patch"
	require_file "$PATCH_SRC/0019-drm-amdgpu-gfx10-arm64-nop-rptr-ring-pretest.patch"
	require_file "$PATCH_SRC/0020-drm-ttm-arm64-coherent-cached-and-always-vmap.patch"
	require_file "$PATCH_SRC/0021-drm-amdgpu-psp-v11-arm64-extend-waits-and-log-timeouts.patch"
	require_file "$PATCH_SRC/0022-drm-amdgpu-ucode-allow-fw-load-type-3-rlc-backdoor.patch"
	require_file "$PATCH_SRC/0023-drm-amdgpu-arm64-skip-init-reset-for-rlc-backdoor.patch"
	require_file "$PATCH_SRC/0024-drm-amdgpu-ucode-skip-fw-buf-bo-for-rlc-backdoor.patch"
	require_file "$PATCH_SRC/0025-drm-amdgpu-gfx10-log-rlc-autoload-timeout-registers.patch"
	require_file "$PATCH_SRC/0026-drm-amdgpu-gfx10-log-rlc-autoload-toc-entries.patch"
	require_file "$PATCH_SRC/0027-drm-amdgpu-gfx10-log-raw-psp-toc-entry-for-rlc-autoload.patch"
	require_file "$PATCH_SRC/0028-drm-amdgpu-psp-log-toc-population-after-microcode-init.patch"
	require_file "$KERNEL_CONFIG_BASE"

	mkdir -p "$PATCH_DST"
	mkdir -p "$(dirname "$KERNEL_CONFIG_DST")"
	rm -f "$PATCH_DST"/*.patch
	cp -f \
		"$PATCH_SRC/0001-arm64-mm-handle-alignment-faults-for-pcie-mmio.patch" \
		"$PATCH_SRC/0002-arm64-mm-force-device-mappings-for-pcie-mmio.patch" \
		"$PATCH_SRC/0003-drm-force-writecombined-mappings-for-dma.patch" \
		"$PATCH_SRC/0004-drm-amdgpu-disable-interrupt-state-test.patch" \
		"$PATCH_SRC/0005-drm-amdgpu-honor-reset-method-and-allow-soc21-pci-reset.patch" \
		"$PATCH_SRC/0006-drm-amdgpu-allow-pci-reset-method-param.patch" \
		"$PATCH_SRC/0007-drm-amdgpu-skip-kcq-setup-when-num-kcq-zero.patch" \
		"$PATCH_SRC/0008-drm-amdgpu-gfx10-skip-kgq-when-num-kcq-zero.patch" \
		"$PATCH_SRC/0009-drm-amdgpu-gmc10-avoid-shutdown-tlb-flush-wedges.patch" \
		"$PATCH_SRC/0010-drm-amdgpu-fence-avoid-irq-put-warn-on-unwind.patch" \
		"$PATCH_SRC/0011-drm-amdgpu-gfx10-log-ring-timeout-register-state.patch" \
		"$PATCH_SRC/0012-drm-amdgpu-gfx10-force-mmio-wptr-on-arm64.patch" \
		"$PATCH_SRC/0013-drm-amdgpu-gfx10-log-cp-control-state-on-timeout.patch" \
		"$PATCH_SRC/0014-drm-amdgpu-gfx10-program-rb-wptr-poll-ctrl-on-resume.patch" \
		"$PATCH_SRC/0015-drm-amdgpu-gfx10-set-rb-exe-in-cp-rb-cntl.patch" \
		"$PATCH_SRC/0016-drm-amdgpu-gfx10-log-rb-address-registers-on-timeout.patch" \
		"$PATCH_SRC/0017-drm-amdgpu-gfx10-skip-cp-clear-state-bootstrap-on-arm64.patch" \
		"$PATCH_SRC/0018-drm-amdgpu-gfx10-retry-cp-unhalt-via-rlc-if-halt-bits-stick.patch" \
		"$PATCH_SRC/0019-drm-amdgpu-gfx10-arm64-nop-rptr-ring-pretest.patch" \
		"$PATCH_SRC/0020-drm-ttm-arm64-coherent-cached-and-always-vmap.patch" \
		"$PATCH_SRC/0021-drm-amdgpu-psp-v11-arm64-extend-waits-and-log-timeouts.patch" \
		"$PATCH_SRC/0022-drm-amdgpu-ucode-allow-fw-load-type-3-rlc-backdoor.patch" \
		"$PATCH_SRC/0023-drm-amdgpu-arm64-skip-init-reset-for-rlc-backdoor.patch" \
		"$PATCH_SRC/0024-drm-amdgpu-ucode-skip-fw-buf-bo-for-rlc-backdoor.patch" \
		"$PATCH_SRC/0025-drm-amdgpu-gfx10-log-rlc-autoload-timeout-registers.patch" \
		"$PATCH_SRC/0026-drm-amdgpu-gfx10-log-rlc-autoload-toc-entries.patch" \
		"$PATCH_SRC/0027-drm-amdgpu-gfx10-log-raw-psp-toc-entry-for-rlc-autoload.patch" \
		"$PATCH_SRC/0028-drm-amdgpu-psp-log-toc-population-after-microcode-init.patch" \
		"$PATCH_DST/"

	cp -f "$KERNEL_CONFIG_BASE" "$KERNEL_CONFIG_DST"
	{
		echo
		echo "# --- RK3588 AMDGPU bring-up overrides ---"
		grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' "$PATCH_SRC/0000-enable-amdgpu.config"
	} >> "$KERNEL_CONFIG_DST"

	echo "[prepare] done: $PATCH_DST"
	echo "[prepare] done: $KERNEL_CONFIG_DST"
}

build_kernel() {
	echo "[build] building Armbian kernel artifact..."
	cd "$BUILD_DIR"
	./compile.sh kernel \
		BOARD="$BOARD" \
		BRANCH="$BRANCH" \
		RELEASE="$RELEASE" \
		BUILD_DESKTOP=no \
		KERNEL_CONFIGURE=no
}

install_kernel_debs() {
	echo "[install] installing generated kernel packages..."
	local deb_dir="$BUILD_DIR/output/debs"
	local hashed_dir="$BUILD_DIR/output/packages-hashed/global"
	local latest_image=""
	local artifact_tag=""
	local from_dir=""
	local base=""
	local prefix=""

	latest_image="$(ls -1t "$hashed_dir"/linux-image-"$BRANCH"-rk35xx_*_arm64.deb 2>/dev/null | head -n 1 || true)"
	if [[ -n "$latest_image" ]]; then
		from_dir="$hashed_dir"
		base="$(basename "$latest_image")"
		prefix="linux-image-$BRANCH-rk35xx_"
		artifact_tag="${base#$prefix}"
		artifact_tag="${artifact_tag%_arm64.deb}"
	else
		latest_image="$(ls -1t "$deb_dir"/linux-image-"$BRANCH"-rk35xx_*.deb 2>/dev/null | head -n 1 || true)"
		if [[ -z "$latest_image" ]]; then
			echo "No kernel image packages found in $hashed_dir or $deb_dir" >&2
			exit 1
		fi
		from_dir="$deb_dir"
		artifact_tag="${latest_image##*__}"
		artifact_tag="${artifact_tag%.deb}"
	fi

	shopt -s nullglob
	local dtb_pkgs=()
	local header_pkgs=()
	if [[ "$from_dir" == "$hashed_dir" ]]; then
		dtb_pkgs=("$from_dir"/linux-dtb-"$BRANCH"-rk35xx_"$artifact_tag"_arm64.deb)
		header_pkgs=("$from_dir"/linux-headers-"$BRANCH"-rk35xx_"$artifact_tag"_arm64.deb)
	else
		dtb_pkgs=("$from_dir"/linux-dtb-"$BRANCH"-rk35xx_*__"$artifact_tag".deb)
		header_pkgs=("$from_dir"/linux-headers-"$BRANCH"-rk35xx_*__"$artifact_tag".deb)
	fi
	shopt -u nullglob

	if [[ ${#dtb_pkgs[@]} -eq 0 ]]; then
		echo "No matching DTB package found for artifact tag '$artifact_tag' in $from_dir" >&2
		exit 1
	fi

	local install_pkgs=("$latest_image" "${dtb_pkgs[@]}")
	if [[ ${#header_pkgs[@]} -gt 0 ]]; then
		install_pkgs+=("${header_pkgs[@]}")
	fi

	echo "[install] selected artifact tag: $artifact_tag"
	echo "[install] selected source: $from_dir"
	printf '[install] package: %s\n' "${install_pkgs[@]}"
	sudo_cmd dpkg -i "${install_pkgs[@]}"

	echo "[install] done. Reboot required."
}

smoke_tests() {
	local smoke_modprobe_args="${SMOKE_MODPROBE_ARGS:-}"
	local smoke_modprobe_timeout_sec="${SMOKE_MODPROBE_TIMEOUT_SEC:-45}"
	local modprobe_extra=()
	local stamp live_dmesg_file boot_id module_path
	if [[ -n "$smoke_modprobe_args" ]]; then
		# Intentional split for module arguments provided by caller.
		read -r -a modprobe_extra <<<"$smoke_modprobe_args"
	fi
	stamp="$(date +%Y%m%d-%H%M%S)"
	live_dmesg_file="/home/orange/gpu-bringup/logs/smoke-live-dmesg-$stamp.log"
	boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
	module_path="/lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko"

	echo "[smoke] date=$(date -Is)"
	echo "[smoke] uname -r"
	uname -r
	echo "[smoke] boot_id: ${boot_id:-unknown}"
	if [[ -r "$module_path" ]]; then
		echo "[smoke] amdgpu.ko sha256: $(sha256sum "$module_path" | awk '{print $1}')"
	fi
	echo
	echo "[smoke] lspci -nnk -s 03:00.0"
	lspci -nnk -s 03:00.0 || true
	echo
	echo "[smoke] clear dmesg"
	sudo_cmd dmesg -C || true
	echo
	echo "[smoke] modprobe amdgpu ${smoke_modprobe_args}"
	echo "[smoke] modprobe timeout: ${smoke_modprobe_timeout_sec}s"
	run_modprobe_with_timeout "$smoke_modprobe_timeout_sec" modprobe amdgpu "${modprobe_extra[@]}" || true
	sleep 2
	echo
	echo "[smoke] capture full dmesg snapshot: $live_dmesg_file"
	dmesg -T > "$live_dmesg_file" || true
	if [[ -r /sys/module/amdgpu/parameters/dc ]]; then
		echo "[smoke] amdgpu dc parameter: $(cat /sys/module/amdgpu/parameters/dc)"
	fi
	echo
	echo "[smoke] lsmod | grep amdgpu"
	lsmod | grep -i amdgpu || true
	echo
	echo "[smoke] /dev/dri"
	ls -l /dev/dri || true
	echo
	echo "[smoke] vulkaninfo --summary"
	timeout 60s vulkaninfo --summary || true
	echo
	echo "[smoke] unload amdgpu after capture"
	sudo_cmd modprobe -r amdgpu || true
	echo
	echo "[smoke] dmesg snapshot extract"
	rg -i "amdgpu|psp|mmhub|UTCL2|LOAD_TOC|SETUP_TMR|LOAD_ASD|LOAD_TA|ring create|ring init" "$live_dmesg_file" | tail -n 400 || true
	echo
	echo "[smoke] live dmesg file: $live_dmesg_file"
}

main() {
	local cmd="${1:-}"
	case "$cmd" in
		prepare)
			prepare_patches
			;;
		build)
			prepare_patches
			build_kernel
			;;
		install)
			install_kernel_debs
			;;
		smoke)
			smoke_tests
			;;
		all)
			prepare_patches
			build_kernel
			install_kernel_debs
			;;
		*)
			usage
			exit 1
			;;
	esac
}

main "$@"
