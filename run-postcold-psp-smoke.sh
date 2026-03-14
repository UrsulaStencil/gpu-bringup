#!/usr/bin/env bash
set -euo pipefail

SUDO_PASSWORD="${SUDO_PASSWORD:-}"
SMOKE_DEADLINE_SEC="${SMOKE_DEADLINE_SEC:-180}"
LOG_DIR="${LOG_DIR:-/home/orange/gpu-bringup/logs}"
MODPROBE_ARGS="${MODPROBE_ARGS:-fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1}"
MODPROBE_TIMEOUT_SEC="${MODPROBE_TIMEOUT_SEC:-45}"
RMMOD_TIMEOUT_SEC="${RMMOD_TIMEOUT_SEC:-15}"
STORM_SAMPLE_SEC="${STORM_SAMPLE_SEC:-2}"
MMHUB_FAULT_GUARD_THRESHOLD="${MMHUB_FAULT_GUARD_THRESHOLD:-64}"
IH_OVERFLOW_GUARD_THRESHOLD="${IH_OVERFLOW_GUARD_THRESHOLD:-12}"
PRE_MODPROBE_RESET="${PRE_MODPROBE_RESET:-none}"
PRE_MODPROBE_RESET_BRIDGE="${PRE_MODPROBE_RESET_BRIDGE:-02:00.0}"
SKIP_SBR_ON_FRESH_BOOT="${SKIP_SBR_ON_FRESH_BOOT:-1}"
FRESH_BOOT_SBR_GUARD_SEC="${FRESH_BOOT_SBR_GUARD_SEC:-180}"
FORCE_PRE_MODPROBE_RESET="${FORCE_PRE_MODPROBE_RESET:-0}"

if [[ "${SMOKE_DEADLINE_ACTIVE:-0}" != "1" ]] &&
   command -v timeout >/dev/null 2>&1 &&
   [[ "${SMOKE_DEADLINE_SEC:-0}" =~ ^[0-9]+$ ]] &&
   (( SMOKE_DEADLINE_SEC > 0 )); then
	export SMOKE_DEADLINE_ACTIVE=1
	exec timeout --foreground "${SMOKE_DEADLINE_SEC}s" bash "$0" "$@"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
MODULE_PATH="/lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko"
BOOT_AGE_SEC="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"
MODPROBE_UNIT="codex-amdgpu-modprobe-${STAMP}.service"
RMMOD_UNIT="codex-amdgpu-rmmod-${STAMP}.service"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/postcold-psp-smoke-$STAMP.log"
LIVE_DMESG_FILE="$LOG_DIR/postcold-psp-dmesg-$STAMP.log"
GUARD_DMESG_FILE="$LOG_DIR/postcold-psp-guard-$STAMP.log"
PHASE_ANALYZER="${PHASE_ANALYZER:-/home/orange/gpu-bringup/analyze-psp-phases.sh}"

capture_phase_summary() {
	echo "[smoke] capture full dmesg snapshot: $LIVE_DMESG_FILE"
	if command -v timeout >/dev/null 2>&1; then
		timeout 10s dmesg -T > "$LIVE_DMESG_FILE" || true
	else
		dmesg -T > "$LIVE_DMESG_FILE" || true
	fi
	echo

	echo "[smoke] dmesg snapshot extract"
	rg -i "amdgpu|psp|mmhub|UTCL2|LOAD_TOC|SETUP_TMR|LOAD_ASD|LOAD_TA|ring create|ring init" "$LIVE_DMESG_FILE" | tail -n 400 || true
	echo

	if [[ -x "$PHASE_ANALYZER" ]]; then
		echo "[smoke] phase analysis"
		"$PHASE_ANALYZER" "$LIVE_DMESG_FILE" || true
	fi
}

sudo_cmd() {
	if [[ -n "$SUDO_PASSWORD" ]]; then
		printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@"
	else
		sudo "$@"
	fi
}

sudo_bash() {
	if [[ -n "$SUDO_PASSWORD" ]]; then
		printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' bash -lc "$1"
	else
		sudo bash -lc "$1"
	fi
}

run_secondary_bus_reset() {
	local bridge="$1"
	local orig new

	orig="$(sudo_cmd setpci -s "$bridge" BRIDGE_CONTROL)"
	orig="${orig//[[:space:]]/}"
	if [[ -z "$orig" ]]; then
		echo "[smoke] secondary bus reset: failed to read BRIDGE_CONTROL for $bridge"
		return 1
	fi

	new="$(printf '%04x' $((0x$orig | 0x0040)))"
	echo "[smoke] secondary bus reset: bridge=$bridge orig=$orig assert=$new"
	sudo_cmd setpci -s "$bridge" BRIDGE_CONTROL="$new"
	sleep 0.2
	sudo_cmd setpci -s "$bridge" BRIDGE_CONTROL="$orig"
	sleep 0.5
	sudo_bash "echo 1 > /sys/bus/pci/rescan"
	sleep 1
}

run_modprobe_with_timeout() {
	local timeout_sec="$1"
	shift
	local cmd=("$@")
	local active sub result status

	if ! sudo_cmd systemd-run \
		--unit="$MODPROBE_UNIT" \
		--quiet \
		--collect \
		--service-type=exec \
		--property=TimeoutStopSec=5s \
		--property=KillMode=mixed \
		--property=SendSIGKILL=yes \
		"${cmd[@]}"; then
		echo "[smoke] failed to start transient modprobe unit: $MODPROBE_UNIT"
		return 1
	fi

	echo "[smoke] modprobe unit: $MODPROBE_UNIT (timeout ${timeout_sec}s)"
	for ((i = 0; i < timeout_sec; i++)); do
		active="$(systemctl show "$MODPROBE_UNIT" -p ActiveState --value 2>/dev/null || true)"
		sub="$(systemctl show "$MODPROBE_UNIT" -p SubState --value 2>/dev/null || true)"
		result="$(systemctl show "$MODPROBE_UNIT" -p Result --value 2>/dev/null || true)"
		status="$(systemctl show "$MODPROBE_UNIT" -p ExecMainStatus --value 2>/dev/null || true)"
		if [[ "$active" != "active" && "$active" != "activating" ]]; then
			echo "[smoke] modprobe unit completed: active=${active:-unknown} sub=${sub:-unknown} result=${result:-unknown} status=${status:-unknown}"
			return 0
		fi
		sleep 1
	done

	echo "[smoke] modprobe exceeded ${timeout_sec}s; stopping transient unit"
	sudo_cmd systemctl stop "$MODPROBE_UNIT" >/dev/null 2>&1 || true
	sleep 6
	active="$(systemctl show "$MODPROBE_UNIT" -p ActiveState --value 2>/dev/null || true)"
		sub="$(systemctl show "$MODPROBE_UNIT" -p SubState --value 2>/dev/null || true)"
		result="$(systemctl show "$MODPROBE_UNIT" -p Result --value 2>/dev/null || true)"
		status="$(systemctl show "$MODPROBE_UNIT" -p ExecMainStatus --value 2>/dev/null || true)"
	if [[ "$active" == "active" || "$active" == "activating" ]]; then
		echo "[smoke] modprobe unit $MODPROBE_UNIT is still active after stop: sub=${sub:-unknown} result=${result:-unknown} status=${status:-unknown}"
		return 124
	fi

	echo "[smoke] modprobe unit stopped after timeout: active=${active:-unknown} sub=${sub:-unknown} result=${result:-unknown} status=${status:-unknown}"
	return 124
}

run_rmmod_with_timeout() {
	local timeout_sec="$1"
	local active sub result status

	if ! sudo_cmd systemd-run \
		--unit="$RMMOD_UNIT" \
		--quiet \
		--collect \
		--service-type=exec \
		--property=TimeoutStopSec=5s \
		--property=KillMode=mixed \
		--property=SendSIGKILL=yes \
		rmmod amdgpu; then
		echo "[smoke] failed to start transient rmmod unit: $RMMOD_UNIT"
		return 1
	fi

	echo "[smoke] rmmod unit: $RMMOD_UNIT (timeout ${timeout_sec}s)"
	for ((i = 0; i < timeout_sec; i++)); do
		active="$(systemctl show "$RMMOD_UNIT" -p ActiveState --value 2>/dev/null || true)"
		sub="$(systemctl show "$RMMOD_UNIT" -p SubState --value 2>/dev/null || true)"
		result="$(systemctl show "$RMMOD_UNIT" -p Result --value 2>/dev/null || true)"
		status="$(systemctl show "$RMMOD_UNIT" -p ExecMainStatus --value 2>/dev/null || true)"
		if [[ "$active" != "active" && "$active" != "activating" ]]; then
			echo "[smoke] rmmod unit completed: active=${active:-unknown} sub=${sub:-unknown} result=${result:-unknown} status=${status:-unknown}"
			return 0
		fi
		sleep 1
	done

	echo "[smoke] rmmod exceeded ${timeout_sec}s; stopping transient unit"
	sudo_cmd systemctl stop "$RMMOD_UNIT" >/dev/null 2>&1 || true
	sleep 6
	active="$(systemctl show "$RMMOD_UNIT" -p ActiveState --value 2>/dev/null || true)"
	sub="$(systemctl show "$RMMOD_UNIT" -p SubState --value 2>/dev/null || true)"
	result="$(systemctl show "$RMMOD_UNIT" -p Result --value 2>/dev/null || true)"
	status="$(systemctl show "$RMMOD_UNIT" -p ExecMainStatus --value 2>/dev/null || true)"
	if [[ "$active" == "active" || "$active" == "activating" ]]; then
		echo "[smoke] rmmod unit $RMMOD_UNIT is still active after stop: sub=${sub:-unknown} result=${result:-unknown} status=${status:-unknown}"
		return 124
	fi

	echo "[smoke] rmmod unit stopped after timeout: active=${active:-unknown} sub=${sub:-unknown} result=${result:-unknown} status=${status:-unknown}"
	return 124
}

log_lingering_tasks() {
	echo "[smoke] lingering modprobe/amdgpu tasks"
	ps -C modprobe -o pid=,stat=,comm=,args= 2>/dev/null || true
	ps -C amdgpu-reset-de -o pid=,stat=,comm=,args= 2>/dev/null || true
}

count_d_state_tasks() {
	local count=0
	local stat

	while read -r stat; do
		[[ "$stat" == D* ]] && ((count += 1))
	done < <(ps -C modprobe -o stat= 2>/dev/null || true)

	while read -r stat; do
		[[ "$stat" == D* ]] && ((count += 1))
	done < <(ps -C amdgpu-reset-de -o stat= 2>/dev/null || true)

	printf '%s\n' "$count"
}

loop_guard_triggered() {
	local mmhub_faults=0
	local ih_overflows=0
	local dstate_tasks=0

	sleep "$STORM_SAMPLE_SEC"
	if command -v timeout >/dev/null 2>&1; then
		timeout 10s dmesg -T > "$GUARD_DMESG_FILE" || true
	else
		dmesg -T > "$GUARD_DMESG_FILE" || true
	fi

	mmhub_faults="$(grep -Ec '\\[mmhub\\] page fault' "$GUARD_DMESG_FILE" || true)"
	ih_overflows="$(grep -Ec 'IH ring buffer overflow' "$GUARD_DMESG_FILE" || true)"
	dstate_tasks="$(count_d_state_tasks)"

	echo "[smoke] loop guard: mmhub_faults=$mmhub_faults ih_overflows=$ih_overflows dstate_tasks=$dstate_tasks sample_sec=${STORM_SAMPLE_SEC}s"

	if (( dstate_tasks > 0 )) ||
	   (( mmhub_faults >= MMHUB_FAULT_GUARD_THRESHOLD )) ||
	   (( ih_overflows >= IH_OVERFLOW_GUARD_THRESHOLD )); then
		echo "[smoke] loop guard: triggered, skipping deeper checks to avoid runaway fault/worker loops"
		return 0
	fi

	return 1
}

should_skip_bridge_sbr() {
	[[ "$PRE_MODPROBE_RESET" == "bridge_sbr" ]] || return 1
	[[ "$SKIP_SBR_ON_FRESH_BOOT" == "1" ]] || return 1
	[[ "$FORCE_PRE_MODPROBE_RESET" != "1" ]] || return 1
	[[ "${BOOT_AGE_SEC:-0}" =~ ^[0-9]+$ ]] || return 1
	(( BOOT_AGE_SEC <= FRESH_BOOT_SBR_GUARD_SEC )) || return 1
	return 0
}

{
	echo "[smoke] date=$(date -Is)"
	echo "[smoke] uname -r: $(uname -r)"
	echo "[smoke] boot_id: ${BOOT_ID:-unknown}"
	echo "[smoke] boot age sec: ${BOOT_AGE_SEC:-unknown}"
	echo "[smoke] modprobe args: $MODPROBE_ARGS"
	echo "[smoke] pre-modprobe reset: $PRE_MODPROBE_RESET"
	if [[ -r "$MODULE_PATH" ]]; then
		echo "[smoke] amdgpu.ko sha256: $(sha256sum "$MODULE_PATH" | awk '{print $1}')"
	fi
	echo

	echo "[smoke] lspci -nn -s 03:00.0"
	lspci -nn -s 03:00.0 || true
	echo

	echo "[smoke] unload amdgpu"
	run_rmmod_with_timeout "$RMMOD_TIMEOUT_SEC" || true
	echo

	if should_skip_bridge_sbr; then
		echo "[smoke] pre-modprobe reset: skipping bridge_sbr on fresh boot (age=${BOOT_AGE_SEC}s <= guard=${FRESH_BOOT_SBR_GUARD_SEC}s)"
		echo "[smoke] pre-modprobe reset: set FORCE_PRE_MODPROBE_RESET=1 to override"
		echo
	elif [[ "$PRE_MODPROBE_RESET" == "bridge_sbr" ]]; then
		echo "[smoke] pre-modprobe reset: secondary bus reset on $PRE_MODPROBE_RESET_BRIDGE"
		run_secondary_bus_reset "$PRE_MODPROBE_RESET_BRIDGE" || true
		echo
	fi

	echo "[smoke] clear dmesg"
	sudo_cmd dmesg -C || true
	echo

	echo "[smoke] modprobe amdgpu $MODPROBE_ARGS"
	echo "[smoke] modprobe timeout: ${MODPROBE_TIMEOUT_SEC}s"
	read -r -a modprobe_extra <<<"$MODPROBE_ARGS"
	modprobe_rc=0
	run_modprobe_with_timeout "$MODPROBE_TIMEOUT_SEC" modprobe amdgpu "${modprobe_extra[@]}" || modprobe_rc=$?
	sleep 2
	echo

	log_lingering_tasks
	echo

	if (( modprobe_rc != 0 )); then
		echo "[smoke] modprobe did not complete cleanly; skipping /dev/dri and vulkaninfo checks"
		echo
		capture_phase_summary
		echo "[smoke] unload amdgpu after timeout/failure"
		run_rmmod_with_timeout "$RMMOD_TIMEOUT_SEC" || true
		exit 0
	fi

	if loop_guard_triggered; then
		echo
		capture_phase_summary
		echo "[smoke] unload amdgpu after loop-guard trigger"
		run_rmmod_with_timeout "$RMMOD_TIMEOUT_SEC" || true
		exit 0
	fi

	capture_phase_summary

	echo "[smoke] lsmod | grep amdgpu"
	lsmod | grep amdgpu || true
	echo

	echo "[smoke] /dev/dri"
	ls -l /dev/dri || true
	echo

	echo "[smoke] vulkaninfo --summary"
	if command -v timeout >/dev/null 2>&1; then
		timeout 20s vulkaninfo --summary || true
	else
		vulkaninfo --summary || true
	fi
	echo

	echo "[smoke] unload amdgpu after capture"
	run_rmmod_with_timeout "$RMMOD_TIMEOUT_SEC" || true
	echo
} | tee "$LOG_FILE"

echo
echo "LOG_FILE=$LOG_FILE"
echo "LIVE_DMESG_FILE=$LIVE_DMESG_FILE"
