#!/usr/bin/env bash
set -euo pipefail

SUDO_PASSWORD="${SUDO_PASSWORD:-}"
REBOOT_UNIT="codex-safe-reboot-$(date +%Y%m%d-%H%M%S).service"
RMMOD_UNIT="codex-safe-rmmod-$(date +%Y%m%d-%H%M%S).service"
RMMOD_TIMEOUT_SEC="${RMMOD_TIMEOUT_SEC:-15}"

sudo_cmd() {
	if [[ -n "$SUDO_PASSWORD" ]]; then
		printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@"
	else
		sudo "$@"
	fi
}

echo "[reboot] date=$(date -Is)"
echo "[reboot] boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
echo "[reboot] looking for transient amdgpu modprobe units"
systemctl list-units 'codex-amdgpu-modprobe-*.service' --all --no-legend || true
echo

while read -r unit _; do
	[[ -n "${unit:-}" ]] || continue
	echo "[reboot] stopping $unit"
	sudo_cmd systemctl stop "$unit" || true
done < <(systemctl list-units 'codex-amdgpu-modprobe-*.service' --all --no-legend 2>/dev/null || true)

echo
echo "[reboot] trying to unload amdgpu"
if sudo_cmd systemd-run \
	--unit="$RMMOD_UNIT" \
	--quiet \
	--collect \
	--service-type=exec \
	--property=TimeoutStopSec=5s \
	--property=KillMode=mixed \
	--property=SendSIGKILL=yes \
	rmmod amdgpu; then
	echo "[reboot] rmmod unit: $RMMOD_UNIT (timeout ${RMMOD_TIMEOUT_SEC}s)"
	for ((i = 0; i < RMMOD_TIMEOUT_SEC; i++)); do
		active="$(systemctl show "$RMMOD_UNIT" -p ActiveState --value 2>/dev/null || true)"
		if [[ "$active" != "active" && "$active" != "activating" ]]; then
			break
		fi
		sleep 1
	done
	sudo_cmd systemctl stop "$RMMOD_UNIT" >/dev/null 2>&1 || true
fi
echo

echo "[reboot] remaining gpu/modprobe tasks"
ps -eo pid,stat,comm,args | awk 'BEGIN{IGNORECASE=1} /modprobe|amdgpu/ && $3 != "awk" {print}' || true
echo

echo "[reboot] scheduling reboot via transient unit $REBOOT_UNIT"
sudo_cmd systemd-run \
	--unit="$REBOOT_UNIT" \
	--quiet \
	--collect \
	--service-type=exec \
	/usr/bin/systemctl reboot

echo "[reboot] request submitted"
