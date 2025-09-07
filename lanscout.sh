#!/usr/bin/env bash
set -Eeuo pipefail

die(){ echo "Error: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

need nmap
need ip
need date

# --- helpers ---
upper(){ tr '[:lower:]' '[:upper:]'; }

expand_path() {
  # Expand leading ~ to $HOME; leave other paths intact
  local p="$1"
  if [[ "$p" == "~" ]]; then
    printf "%s\n" "$HOME"
  elif [[ "$p" == ~/* ]]; then
    printf "%s/%s\n" "$HOME" "${p#~/}"
  else
    printf "%s\n" "$p"
  fi
}

confirm_loop() {
  # $1 = prompt, $2 = default (may be empty), echoes final value
  local prompt="$1" def="${2:-}" inp ans
  while true; do
    if [[ -n "$def" ]]; then
      read -rp "$prompt (default: $def): " inp
      [[ -z "$inp" ]] && inp="$def"
    else
      read -rp "$prompt: " inp
    fi
    echo "You entered: $inp"
    read -rp "Confirm? [Y]es / [N]o re-enter / [E]xit: " ans
    case "$(echo "${ans:-Y}" | upper)" in
      Y) echo "$inp"; return 0 ;;
      N) continue ;;
      E) echo "Aborted by user."; exit 0 ;;
      *) echo "Please type Y, N or E."; continue ;;
    esac
  done
}

# --- 1) output path (default: ~/Desktop/lanscout/YYYY-MM-DD) ---
DEFAULT_DATE="$(date +%F)"
DEFAULT_BASE="~/Desktop/lanscout/$DEFAULT_DATE"
OUTBASE_RAW="$(confirm_loop "Output base folder" "$DEFAULT_BASE")"
OUTBASE="$(expand_path "$OUTBASE_RAW")"

# --- 2) engagement prefix (for file names only) ---
NAME_RAW="$(confirm_loop "Engagement prefix (file prefix, e.g. 'lavelle-2025-08-27')" "")"
[[ -n "${NAME_RAW// }" ]] || die "Engagement prefix cannot be empty"
# safe filename chars only
NAME="$(echo "$NAME_RAW" | tr '[:space:]' '_' | tr -cd 'A-Za-z0-9_.-')"
[[ -n "$NAME" ]] || die "Prefix reduced to empty after sanitising; choose a different name."

OUTDIR="$OUTBASE"
mkdir -p "$OUTDIR" || die "Cannot create output directory: $OUTDIR"

# --- 3) subnet selection (manual or A for auto) ---
while true; do
  read -rp "Target subnet CIDR (e.g. 192.168.1.0/24) or 'A' for auto-detect: " INPUT
  [[ -n "${INPUT// }" ]] || { echo "Please enter a CIDR or 'A'."; continue; }
  if [[ "$(echo "$INPUT" | upper)" == "A" ]]; then
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
  # confirm the chosen subnet
  read -rp "Confirm subnet '$SUBNET'? [Y]es / [N]o re-enter / [E]xit: " ans
  case "$(echo "${ans:-Y}" | upper)" in
    Y) break ;;
    N) continue ;;
    E) echo "Aborted by user."; exit 0 ;;
    *) echo "Please type Y, N or E." ;;
  esac
done

# --- Run host discovery ---
HOSTS_FILE="$OUTDIR/${NAME}-hosts.txt"

echo
echo "[1/1] Host discovery on $SUBNET"
echo "      -> $HOSTS_FILE"
nmap -sn -oN "$HOSTS_FILE" "$SUBNET" || die "nmap host discovery failed"

HOSTS_UP=$(grep -Eo '[0-9]+ hosts up' "$HOSTS_FILE" | awk '{print $1}' | tail -n1 || echo "?")
echo
echo "Done. Hosts up: ${HOSTS_UP:-?}"
echo "Saved: $HOSTS_FILE"
echo "Folder: $OUTDIR"