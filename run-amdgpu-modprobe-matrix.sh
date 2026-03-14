#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/home/orange/gpu-bringup/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/modprobe-matrix-$(date +%Y%m%d-%H%M%S).log"

SUDO_PASSWORD="${SUDO_PASSWORD:-}"
INCLUDE_DANGEROUS_CASES="${INCLUDE_DANGEROUS_CASES:-0}"
EXTRA_MODPROBE_ARGS="${EXTRA_MODPROBE_ARGS:-}"

sudo_cmd() {
	if sudo -n true >/dev/null 2>&1; then
		sudo "$@"
		return
	fi
	if [[ -n "$SUDO_PASSWORD" ]]; then
		printf '%s\n' "$SUDO_PASSWORD" | sudo -S "$@"
		return
	fi
	sudo "$@"
}

run_case() {
	local name="$1"
	local args="$2"
	if [[ -n "$EXTRA_MODPROBE_ARGS" ]]; then
		args="$args $EXTRA_MODPROBE_ARGS"
	fi
	local marker="AMDGPU_TEST_${name}_$(date +%s)"

	{
		echo
		echo "===== CASE $name ====="
		echo "ARGS: $args"
		echo "MARKER: $marker"
		echo "TIME: $(date -Iseconds)"
	} | tee -a "$LOG_FILE"

	# Ensure clean state between runs.
	if ! timeout 20s bash -lc "printf '%s\n' '$SUDO_PASSWORD' | sudo -S modprobe -r amdgpu" >/dev/null 2>&1; then
		true
	fi
	sleep 1

	sudo_cmd sh -c "echo '$marker' > /dev/kmsg"

	if timeout 25s bash -lc "printf '%s\n' '$SUDO_PASSWORD' | sudo -S modprobe amdgpu $args"; then
		echo "modprobe_exit=0" | tee -a "$LOG_FILE"
	else
		echo "modprobe_exit=$?" | tee -a "$LOG_FILE"
	fi

	sleep 2

	{
		echo "--- lspci -nnk -s 03:00.0"
		lspci -nnk -s 03:00.0 || true
		echo "--- lsmod (amdgpu/drm)"
		lsmod | rg '^amdgpu|^drm' || true
		echo "--- key dmesg since marker"
		dmesg -T | awk -v m="$marker" '
			$0 ~ m {p=1}
			p
		' | rg -n 'AMDGPU_TEST_|amdgpu|ring gfx_0.0.0|hw_init of IP block <gfx_v10_0>|failed to write reg|shutdown in progress|probe of 0000:03:00.0 failed|amdgpu_irq_put|KCQ|KGQ|SMU is initialized successfully|BAR 0|Not enough PCI address space' || true
	} | tee -a "$LOG_FILE"

	if ! timeout 20s bash -lc "printf '%s\n' '$SUDO_PASSWORD' | sudo -S modprobe -r amdgpu" >/dev/null 2>&1; then
		true
	fi
	sleep 1
}

if [[ -z "$SUDO_PASSWORD" ]]; then
	echo "SUDO_PASSWORD is required for unattended matrix run." >&2
	exit 1
fi

run_case baseline "mes=0 num_kcq=0 msi=1"
run_case async0 "mes=0 num_kcq=0 async_gfx_ring=0 msi=1"
run_case msi0 "mes=0 num_kcq=0 msi=0"

if [[ "$INCLUDE_DANGEROUS_CASES" == "1" ]]; then
	run_case reset_pci "mes=0 num_kcq=0 msi=1 reset_method=5"
	run_case aspm_off "mes=0 num_kcq=0 msi=1 aspm=0"
else
	echo
	echo "Skipping dangerous cases (reset_pci, aspm_off). Set INCLUDE_DANGEROUS_CASES=1 to run them." | tee -a "$LOG_FILE"
fi

echo
echo "Matrix complete. Log: $LOG_FILE"
