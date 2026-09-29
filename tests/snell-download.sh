#!/usr/bin/env bash
# Verify pinned downloads and exercise only the export helper with fake profiles.
set -e
repo=$(cd "$(dirname "$0")/.." && pwd)
. "$repo/src/snell.sh"
is_core_dir=$(mktemp -d)
trap 'rm -rf "$is_core_dir"' EXIT
for script in snell.sh ip-binding.sh; do
    path=$(snell_bridge_fetch "$script")
    [[ $(snell_bridge_digest "$path") == "$(snell_bridge_hash "$script")" ]]
    bash -n "$path"
done
printf 'PASS: pinned Snell installer and public-IP manager downloads\n'
(
    . "$is_core_dir/snell-cache/$SNELL_BRIDGE_REV/ip-binding.sh"
    SNELL_IP_CONF=$is_core_dir/fixture
    SNELL_IP_STATE=$is_core_dir/fixture-state
    mkdir -p "$SNELL_IP_CONF/users"
    cat > "$SNELL_IP_CONF/users/snell-55261.conf" <<'EOF'
#version-choice = v6
[snell-server]
listen = ::0:55261
psk = existing-fixture-PSK
mode = unshaped
EOF
    cp "$SNELL_IP_CONF/users/snell-55261.conf" "$is_core_dir/original.conf"
    ip() {
        printf '%s\n' '[{"ifname":"ens3","addr_info":[{"family":"inet","scope":"global","local":"74.219.23.237"},{"family":"inet","scope":"global","local":"74.219.23.240"}]}]'
    }
    systemctl() { echo 'Unexpected service operation during export' >&2; exit 1; }
    nft() { echo 'Unexpected network operation during export' >&2; exit 1; }
    sip_export 55261 > "$is_core_dir/export.txt" 2> "$is_core_dir/notice.txt"
    [[ $(wc -l < "$is_core_dir/export.txt" | tr -d ' ') == 2 ]]
    grep -q '74.219.23.237, 55261, psk = existing-fixture-PSK, version = 6, mode = unshaped' "$is_core_dir/export.txt"
    cmp "$SNELL_IP_CONF/users/snell-55261.conf" "$is_core_dir/original.conf"
    [[ ! -d $SNELL_IP_STATE ]]
)
printf 'PASS: pinned backend exports legacy port 55261 without mutation\n'
