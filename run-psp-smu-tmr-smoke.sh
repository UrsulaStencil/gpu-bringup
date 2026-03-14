#!/usr/bin/env bash
set -euo pipefail

SMOKE_WRAPPER="${SMOKE_WRAPPER:-/home/orange/gpu-bringup/run-postcold-psp-smoke.sh}"
PHASE_ANALYZER="${PHASE_ANALYZER:-/home/orange/gpu-bringup/analyze-psp-phases.sh}"
TMP_OUTPUT="$(mktemp)"

cleanup() {
	rm -f "$TMP_OUTPUT"
}
trap cleanup EXIT

extract_first() {
	local pattern="$1"
	local file="$2"

	rg -n -m1 --no-heading "$pattern" "$file" 2>/dev/null || true
}

if [[ ! -x "$SMOKE_WRAPPER" ]]; then
	echo "[boundary] missing smoke wrapper: $SMOKE_WRAPPER" >&2
	exit 1
fi

"$SMOKE_WRAPPER" "$@" | tee "$TMP_OUTPUT"

DMESG_LOG="$(sed -n 's/^LIVE_DMESG_FILE=//p' "$TMP_OUTPUT" | tail -n1)"
SMOKE_LOG="$(sed -n 's/^LOG_FILE=//p' "$TMP_OUTPUT" | tail -n1)"

if [[ -z "$DMESG_LOG" || ! -f "$DMESG_LOG" ]]; then
	echo "[boundary] unable to locate dmesg log from smoke output" >&2
	exit 1
fi

MODULE_HASH=""
BOOT_ID=""
if [[ -n "$SMOKE_LOG" && -f "$SMOKE_LOG" ]]; then
	MODULE_HASH="$(sed -n 's/.*amdgpu\.ko sha256: //p' "$SMOKE_LOG" | head -n1)"
	BOOT_ID="$(sed -n 's/.*boot_id: //p' "$SMOKE_LOG" | head -n1)"
fi

PMFW_BRANCH="$(extract_first 'skipping early psp_load_smu_fw because PMFW already appears alive|forcing early psp_load_smu_fw despite PMFW alive quirk' "$DMESG_LOG")"
SMU_PRECHECK="$(extract_first 'PMFW/SMU already responds; skip early psp_load_smu_fw reload|PMFW alive but SMU precheck failed ret=' "$DMESG_LOG")"
SMC_PREP="$(extract_first 'load_ip_fw prep ucode=SMC' "$DMESG_LOG")"
LOAD_IP_FW_POST="$(extract_first 'submit-post: cmd=LOAD_IP_FW' "$DMESG_LOG")"
LOAD_IP_FW_WAIT="$(extract_first 'PSP cmd wait expired for LOAD_IP_FW with no response' "$DMESG_LOG")"
SETUP_TMR_PREP="$(extract_first 'SETUP_TMR using' "$DMESG_LOG")"
SETUP_TMR_POST="$(extract_first 'submit-post: cmd=SETUP_TMR' "$DMESG_LOG")"
SETUP_TMR_WAIT="$(extract_first 'PSP cmd wait expired for SETUP_TMR with no response' "$DMESG_LOG")"
FIRST_BLOCKER=""
if [[ -x "$PHASE_ANALYZER" ]]; then
	FIRST_BLOCKER="$("$PHASE_ANALYZER" "$DMESG_LOG" | rg '^FIRST_BLOCKER' || true)"
fi

echo
echo "[boundary] module: ${MODULE_HASH:-unknown}"
echo "[boundary] boot_id: ${BOOT_ID:-unknown}"
echo "[boundary] dmesg: $DMESG_LOG"
echo "[boundary] smoke: ${SMOKE_LOG:-unknown}"
echo "[boundary] pmfw_branch: ${PMFW_BRANCH:-MISS}"
echo "[boundary] smu_precheck: ${SMU_PRECHECK:-MISS}"
echo "[boundary] smc_prep: ${SMC_PREP:-MISS}"
echo "[boundary] load_ip_fw_post: ${LOAD_IP_FW_POST:-MISS}"
echo "[boundary] load_ip_fw_wait: ${LOAD_IP_FW_WAIT:-MISS}"
echo "[boundary] setup_tmr_prep: ${SETUP_TMR_PREP:-MISS}"
echo "[boundary] setup_tmr_post: ${SETUP_TMR_POST:-MISS}"
echo "[boundary] setup_tmr_wait: ${SETUP_TMR_WAIT:-MISS}"
echo "[boundary] ${FIRST_BLOCKER:-FIRST_BLOCKER unknown}"
