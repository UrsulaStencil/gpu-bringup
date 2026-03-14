# RK3588 AMDGPU Bring-up

Dieses Repo ist der kanonische Arbeitsstand fuer den AMDGPU-Bring-up auf dem RK3588-System.

## Ziel

- reproduzierbare Dokumentation aller relevanten Iterationen
- versionierte Smoke-Skripte, Analysatoren und Zustandssnapshots
- Nachvollziehbarkeit von Hypothesen, Gegenbeweisen und aktuell geschuetzten Baselines
- Trennung zwischen kleinem Bring-up-Repo und grosser `armbian-build`-Arbeitskopie

## Was in diesem Repo bewusst versioniert wird

- Bring-up-Skripte:
  - `run-postcold-psp-smoke.sh`
  - `run-psp-smu-tmr-smoke.sh`
  - `run-rk3588-amdgpu-bringup.sh`
  - `gpu-safe-reboot.sh`
  - `analyze-psp-phases.sh`
- Arbeitsdokumentation:
  - `SESSION_STATE_RK3588_AMDGPU_2026-03-11.md`
  - `RK3588_AMDGPU_PATCHSET_RUNBOOK.md`
- Logs:
  - `logs/`
- Patch-/Diff-Snapshots:
  - `state-snapshots/`
- kleine, reproduzierbare Patchquellen:
  - `armbian-userpatches/`
- Recherche-Artefakte:
  - `research/`
- relevante VBIOS-Artefakte:
  - `vbios/`

## Was bewusst nicht versioniert wird

- `armbian-build/`

Grund:
- die Arbeitskopie ist sehr gross
- sie ist bereits ein eigenes Git-Repo
- der fuer diesen Bring-up relevante Zustand wird hier ueber:
  - `state-snapshots/*.patch`
  - `armbian-userpatches/`
  - Session-/Resume-Dokumentation
  nachvollziehbar festgehalten

## Aktueller Stand

- bevorzugter PSP-Arbeitspfad:
  - `fw_load_type=1`
- historische tiefere DIRECT-Referenz:
  - `fw_load_type=0`
  - dort wurde bereits `SMU is initialized successfully!` erreicht
- aktueller on-disk Modulstand:
  - `08efc87519f2614e748f177d3bb3c060818f2f7571e3b81ed9be948245d27290`
  - auf frischem Cold Boot validiert
  - frischer Boot:
    - `52e121c3-b4be-4f41-bb1e-996c7249d5bb`
  - frischer erster Blocker:
    - `smu_load`
  - einziger Verhaltensunterschied gegenueber dem vorherigen on-disk Stand:
    - lokale PMFW/SMU-Sonderlogik in `psp_hw_start()` entfernt
  - vorheriger on-disk Backup-Stand:
    - `/lib/modules/6.1.115-vendor-rk35xx/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.bak-20260314-152903`

Die aktuelle Wahrheit steht in:
- `SESSION_STATE_RK3588_AMDGPU_2026-03-11.md`

Die schnelle Wiederaufnahme nach Reboot steht ausserhalb des Repos gespiegelt in:
- `/home/orange/RESUME_RK3588_AMDGPU_AFTER_REBOOT.md`

## Wichtigste Referenzen im Repo

- frische PSP-Referenz:
  - `logs/postcold-psp-dmesg-20260314-153451.log`
- same-boot Richtungsbeweis fuer `LOAD_IP_FW(SMC)=0`:
  - `logs/postcold-psp-dmesg-20260314-135942.log`
- bewusst verworfene same-boot Verschmutzung:
  - `logs/postcold-psp-dmesg-20260314-140252.log`
- aktueller Quellzustand als Patch:
  - `state-snapshots/amdgpu-psp-current-diff-20260314-153451.patch`
  - Basis-Kontext weiter in:
    - `state-snapshots/amdgpu-worktree-diff-20260314-iteration36.patch`

## Arbeitsregeln

Die verbindlichen Bring-up-Regeln liegen in:
- `/home/orange/AGENTS.md`

Kernaussagen:
- frische und same-boot Ergebnisse strikt trennen
- geschuetzte Baselines vor jeder Aenderung benennen
- jede neue Frontier mit eigenem Boundary-Smoke absichern
- keine unbounded waits oder offenen Hangs in Smoke/Shutdown-Pfaden

## Schnellstart nach Reboot

```bash
cd /home/orange/gpu-bringup
SUDO_PASSWORD=orange SMOKE_DEADLINE_SEC=120 MODPROBE_TIMEOUT_SEC=30 RMMOD_TIMEOUT_SEC=10 STORM_SAMPLE_SEC=2 MMHUB_FAULT_GUARD_THRESHOLD=32 IH_OVERFLOW_GUARD_THRESHOLD=6 PRE_MODPROBE_RESET=none MODPROBE_ARGS='fw_load_type=1 async_gfx_ring=0 num_kcq=0 mes=0 msi=1' ./run-psp-smu-tmr-smoke.sh
```
