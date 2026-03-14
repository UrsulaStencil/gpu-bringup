#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-/boot/armbianEnv.txt}"
DTB_ROOT="${2:-/boot/dtb}"
FALLBACK_DTB="${FALLBACK_DTB:-rockchip/rk3588-orangepi-5-plus.dtb}"

if [[ ! -f "$ENV_FILE" ]]; then
	echo "fdt-sanity: env file missing: $ENV_FILE" >&2
	exit 1
fi

if [[ ! -e "$DTB_ROOT/$FALLBACK_DTB" ]]; then
	echo "fdt-sanity: fallback dtb missing: $DTB_ROOT/$FALLBACK_DTB" >&2
	exit 1
fi

fdtfile="$(awk -F= '/^fdtfile=/{print $2; exit}' "$ENV_FILE" | tr -d '\r')"

if [[ -z "${fdtfile:-}" ]]; then
	echo "fdt-sanity: no fdtfile set, nothing to do."
	exit 0
fi

if [[ -e "$DTB_ROOT/$fdtfile" ]]; then
	echo "fdt-sanity: fdtfile ok: $fdtfile"
	exit 0
fi

timestamp="$(date +%Y-%m-%d-%H%M%S)"
backup="${ENV_FILE}.bak.${timestamp}.fdt-missing"
cp -a "$ENV_FILE" "$backup"

tmp="$(mktemp)"
awk -v fallback="$FALLBACK_DTB" '
BEGIN { replaced = 0 }
/^fdtfile=/ { print "fdtfile=" fallback; replaced = 1; next }
{ print }
END { if (!replaced) print "fdtfile=" fallback }
' "$ENV_FILE" >"$tmp"
mv "$tmp" "$ENV_FILE"

echo "fdt-sanity: missing fdtfile '$fdtfile' -> switched to '$FALLBACK_DTB'"
echo "fdt-sanity: backup written: $backup"
