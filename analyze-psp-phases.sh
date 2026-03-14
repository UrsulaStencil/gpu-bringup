#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
	echo "usage: $0 <dmesg-log|smoke-log> [...]" >&2
	exit 1
fi

find_companion_smoke_log() {
	local log="$1"
	local dir base stamp candidate

	dir="$(dirname "$log")"
	base="$(basename "$log")"

	case "$base" in
	postcold-psp-dmesg-*.log)
		stamp="${base#postcold-psp-dmesg-}"
		stamp="${stamp%.log}"
		candidate="$dir/postcold-psp-smoke-$stamp.log"
		[[ -f "$candidate" ]] && printf '%s\n' "$candidate"
		;;
	postcold-psp-smoke-*.log)
		printf '%s\n' "$log"
		;;
	esac
}

extract_first() {
	local pattern="$1"
	local file="$2"

	rg -n -m1 --no-heading "$pattern" "$file" 2>/dev/null || true
}

extract_last() {
	local pattern="$1"
	local file="$2"

	rg -n --no-heading "$pattern" "$file" 2>/dev/null | tail -n1 || true
}

phase_line() {
	local label="$1"
	local entry="$2"

	if [[ -n "$entry" ]]; then
		printf 'PHASE %-18s OK   %s\n' "$label" "$entry"
	else
		printf 'PHASE %-18s MISS\n' "$label"
	fi
}

record_phase() {
	local label="$1"
	local entry="$2"

	((summary_total += 1))
	if [[ -n "$entry" ]]; then
		((summary_ok += 1))
		green_phases+="${green_phases:+, }$label"
	else
		red_phases+="${red_phases:+, }$label"
	fi

	phase_line "$label" "$entry"
}

print_run_summary() {
	local log="$1"
	local dmesg_log smoke_log
	local module_hash boot_id modprobe_args
	local pmfw_branch
	local discovery vbios post0 post1 vram reserve memtrain fwbuf ring_init ring_prewait
	local load_toc load_toc_post setup_tmr load_asd load_ta smc_prep smu_ok gfx_fail probe_fail
	local boot_kdb boot_spl boot_sys boot_sos
	local load_ip_fw_prep load_ip_fw_wait load_ip_fw_post vmc_fault_1g vmc_fault_2g ih_overflow
	local first_blocker blocker_phase
	local summary_ok=0
	local summary_total=0
	local green_phases=""
	local red_phases=""

	if [[ ! -f "$log" ]]; then
		echo "RUN $log"
		echo "  error: file not found"
		return 0
	fi

	dmesg_log="$log"
	smoke_log=""
	if [[ "$(basename "$log")" == postcold-psp-smoke-* ]]; then
		smoke_log="$log"
		dmesg_log="$(dirname "$log")/$(basename "$log" | sed 's/postcold-psp-smoke-/postcold-psp-dmesg-/')"
	fi

	if [[ -z "$smoke_log" ]]; then
		smoke_log="$(find_companion_smoke_log "$dmesg_log" || true)"
	fi

	module_hash=""
	boot_id=""
	modprobe_args=""
	pmfw_branch=""
	if [[ -n "$smoke_log" && -f "$smoke_log" ]]; then
		module_hash="$(sed -n 's/.*amdgpu\.ko sha256: //p' "$smoke_log" | head -n1)"
		boot_id="$(sed -n 's/.*boot_id: //p' "$smoke_log" | head -n1)"
		modprobe_args="$(sed -n 's/.*modprobe args: //p' "$smoke_log" | head -n1)"
	fi

	pmfw_branch="$(extract_first 'skipping early psp_load_smu_fw because PMFW already appears alive|forcing early psp_load_smu_fw despite PMFW alive quirk' "$dmesg_log")"

	discovery="$(extract_first 'using beige_goby static IP fallback' "$dmesg_log")"
	vbios="$(extract_first 'ATOM BIOS:' "$dmesg_log")"
	post0="$(extract_first 'post result C2PMSG_81=' "$dmesg_log")"
	post1="$(extract_first 'second post result C2PMSG_81=' "$dmesg_log")"
	vram="$(extract_first 'VRAM: [0-9]+M' "$dmesg_log")"
	reserve="$(extract_first 'reserve_tmr mem_train=' "$dmesg_log")"
	memtrain="$(extract_first 'memory training init' "$dmesg_log")"
	fwbuf="$(extract_first 'firmware.fw_buf domain=' "$dmesg_log")"
	ring_init="$(extract_first 'psp ring init:' "$dmesg_log")"
	ring_prewait="$(extract_first 'psp ring prewait:' "$dmesg_log")"
	boot_kdb="$(extract_first 'psp bootload cmd=524288 ' "$dmesg_log")"
	boot_spl="$(extract_first 'psp bootload cmd=268435456 ' "$dmesg_log")"
	boot_sys="$(extract_first 'psp bootload cmd=65536 ' "$dmesg_log")"
	boot_sos="$(extract_first 'psp bootload cmd=131072 ' "$dmesg_log")"
	load_toc="$(extract_first 'ID_LOAD_TOC' "$dmesg_log")"
	load_toc_post="$(extract_first 'submit-post: cmd=ID_LOAD_TOC' "$dmesg_log")"
	setup_tmr="$(extract_first 'SETUP_TMR' "$dmesg_log")"
	load_asd="$(extract_first 'LOAD_ASD' "$dmesg_log")"
	load_ta="$(extract_first 'LOAD_TA' "$dmesg_log")"
	load_ip_fw_prep="$(extract_first 'load_ip_fw prep ucode=' "$dmesg_log")"
	load_ip_fw_post="$(extract_first 'submit-post: cmd=LOAD_IP_FW' "$dmesg_log")"
	load_ip_fw_wait="$(extract_first 'PSP cmd wait expired for LOAD_IP_FW with no response' "$dmesg_log")"
	smc_prep="$(extract_first 'load_ip_fw prep ucode=SMC' "$dmesg_log")"
	smu_ok="$(extract_first 'SMU is initialized successfully!' "$dmesg_log")"
	gfx_fail="$(extract_first 'ring gfx_0\\.0\\.0 test failed' "$dmesg_log")"
	probe_fail="$(extract_last 'probe of 0000:03:00\\.0 failed with error' "$dmesg_log")"
	vmc_fault_1g="$(extract_first 'in page starting at address 0x0000000100000000' "$dmesg_log")"
	vmc_fault_2g="$(extract_first 'in page starting at address 0x0000000200000000' "$dmesg_log")"
	ih_overflow="$(extract_first 'IH ring buffer overflow' "$dmesg_log")"

	blocker_phase="unknown"
	first_blocker="$(extract_first 'PSP load kdb failed' "$dmesg_log")"
	if [[ -n "$first_blocker" ]]; then
		blocker_phase="kdb_bootstrap"
	else
		first_blocker="$(extract_first 'PSP load spl failed' "$dmesg_log")"
		if [[ -n "$first_blocker" ]]; then
			blocker_phase="spl_bootstrap"
		else
			first_blocker="$(extract_first 'PSP load sysdrv failed' "$dmesg_log")"
			if [[ -n "$first_blocker" ]]; then
				blocker_phase="sysdrv_bootstrap"
			else
				first_blocker="$(extract_first 'PSP load sos failed' "$dmesg_log")"
				if [[ -n "$first_blocker" ]]; then
					blocker_phase="sos_bootstrap"
				else
					first_blocker="$(extract_first 'PSP create ring failed' "$dmesg_log")"
					if [[ -n "$first_blocker" ]]; then
						blocker_phase="ring_create"
					else
						first_blocker="$(extract_first 'PSP tmr init failed' "$dmesg_log")"
						if [[ -n "$first_blocker" ]]; then
							blocker_phase="tmr_init"
						else
							first_blocker="$(extract_first 'PSP load tmr failed' "$dmesg_log")"
							if [[ -n "$first_blocker" ]]; then
								blocker_phase="tmr_load"
							else
							first_blocker="$(extract_first 'PSP load smu failed' "$dmesg_log")"
							if [[ -n "$first_blocker" ]]; then
								blocker_phase="smu_load"
							else
								first_blocker="$load_ip_fw_wait"
								if [[ -n "$first_blocker" ]]; then
									blocker_phase="load_ip_fw_wait"
								else
									if [[ -n "$load_ip_fw_prep" && -z "$load_ip_fw_post" && -n "$vmc_fault_2g" ]]; then
										first_blocker="$vmc_fault_2g"
										blocker_phase="load_ip_fw_fault_2g"
									elif [[ -n "$load_toc" && -z "$load_toc_post" && -n "$vmc_fault_1g" ]]; then
										first_blocker="$vmc_fault_1g"
										blocker_phase="load_toc_fault_1g"
									else
										first_blocker="$(extract_first 'SMC engine is not correctly up!' "$dmesg_log")"
									fi
									if [[ -n "$first_blocker" && "$blocker_phase" == "unknown" ]]; then
										blocker_phase="smu_engine"
									fi
									if [[ -z "$first_blocker" ]]; then
										first_blocker="$(extract_first 'ring gfx_0\\.0\\.0 test failed' "$dmesg_log")"
									fi
									if [[ -n "$first_blocker" ]]; then
										if [[ "$blocker_phase" == "unknown" ]]; then
											blocker_phase="gfx_ring"
										fi
									else
										first_blocker="$ih_overflow"
										if [[ -n "$first_blocker" ]]; then
											blocker_phase="ih_overflow"
										else
											first_blocker="$probe_fail"
											if [[ -n "$first_blocker" ]]; then
												blocker_phase="probe_fail"
											fi
										fi
									fi
								fi
							fi
							fi
						fi
					fi
				fi
			fi
		fi
	fi

	echo "RUN $dmesg_log"
	[[ -n "$smoke_log" ]] && echo "SMOKE $smoke_log"
	[[ -n "$module_hash" ]] && echo "MODULE $module_hash"
	[[ -n "$boot_id" ]] && echo "BOOT_ID $boot_id"
	[[ -n "$modprobe_args" ]] && echo "ARGS $modprobe_args"
	[[ -n "$pmfw_branch" ]] && echo "PMFW_BRANCH $pmfw_branch"
	record_phase "discovery" "$discovery"
	record_phase "vbios" "$vbios"
	record_phase "post-1" "$post0"
	record_phase "post-2" "$post1"
	record_phase "vram" "$vram"
	record_phase "reserve_tmr" "$reserve"
	record_phase "mem_training" "$memtrain"
	record_phase "fw_buf" "$fwbuf"
	record_phase "ring_init" "$ring_init"
	record_phase "ring_prewait" "$ring_prewait"
	record_phase "boot_kdb" "$boot_kdb"
	record_phase "boot_spl" "$boot_spl"
	record_phase "boot_sysdrv" "$boot_sys"
	record_phase "boot_sos" "$boot_sos"
	record_phase "ID_LOAD_TOC" "$load_toc"
	record_phase "SETUP_TMR" "$setup_tmr"
	record_phase "LOAD_ASD" "$load_asd"
	record_phase "LOAD_TA" "$load_ta"
	record_phase "SMC_prep" "$smc_prep"
	record_phase "SMU_ok" "$smu_ok"
	record_phase "gfx_ring" "$gfx_fail"
	echo "PHASE_SUMMARY ${summary_ok}/${summary_total} green"
	echo "GREEN_PHASES ${green_phases:-none}"
	echo "RED_PHASES ${red_phases:-none}"
	if [[ -n "$first_blocker" ]]; then
		echo "FIRST_BLOCKER $blocker_phase $first_blocker"
	else
		echo "FIRST_BLOCKER none-detected"
	fi
	echo
}

for log in "$@"; do
	print_run_summary "$log"
done
