#!/usr/bin/env bash
set -Eeuo pipefail

die(){ echo "Error: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

need nmap
need ip

read -rp "Output base folder (default: ~/scans): " OUTBASE
OUTBASE=${OUTBASE:-"$HOME/scans"}

read -rp "Engagement name (file prefix, e.g. 'lavelle-2025-08-27'): " NAME
[[ -n "${NAME// }" ]] || die "Engagement name cannot be empty"
NAME=$(echo "$NAME" | tr '[:space:]' '_' | tr -cd 'A-Za-z0-9_.-')

OUTDIR="$OUTBASE/$NAME"
mkdir -p "$OUTDIR" || die "Cannot create output directory: $OUTDIR"

read -rp "Target subnet CIDR (e.g. 192.168.1.0/24) or 'A' for auto-detect: " INPUT
if [[ "${INPUT^^}" == "A" ]]; then
  IFACE=$(ip -4 route show default | awk '{print $5; exit}') || true
  [[ -n "${IFACE:-}" ]] || die "Could not detect default interface"
  SUBNET=$(ip -4 route list dev "$IFACE" | awk '/proto kernel/ {print $1; exit}') || true
  if [[ -z "${SUBNET:-}" ]]; then
    SUBNET=$(ip -o -f inet addr show dev "$IFACE" | awk '{print $4; exit}') || true
  fi
  [[ -n "${SUBNET:-}" ]] || die "Could not determine subnet (CIDR) automatically"
  echo "Auto-detected subnet: $SUBNET"
else
  SUBNET="$INPUT"
fi

HOSTS_FILE="$OUTDIR/${NAME}-hosts.txt"

echo
echo "[1/1] Host discovery on $SUBNET"
echo "      -> $HOSTS_FILE"
nmap -sn -oN "$HOSTS_FILE" "$SUBNET" || die "nmap host discovery failed"

HOSTS_UP=$(grep -Eo '[0-9]+ hosts up' "$HOSTS_FILE" | awk '{print $1}' | tail -n1 || echo "?")
echo
echo "Done. Hosts up: ${HOSTS_UP:-?}"
echo "Saved: $HOSTS_FILE"