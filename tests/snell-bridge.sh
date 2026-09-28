#!/usr/bin/env bash
set -e
repo=$(cd "$(dirname "$0")/.." && pwd)
. "$repo/src/core.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
is_core_dir=$scratch/sing-box
SNELL_BRIDGE_CONF=$scratch/snell
mkdir -p "$is_core_dir/conf" "$SNELL_BRIDGE_CONF/users"
printf '{"keep":"existing sing-box credentials"}' > "$is_core_dir/config.json"
printf '{"keep":"existing inbound"}' > "$is_core_dir/conf/Hysteria2.json"
for profile in main 15562 55261; do
    version=v5
    [[ $profile != 55261 ]] || version=v6
    printf '#version-choice = %s\n[snell-server]\nlisten = 74.219.23.240:%s\npsk = private-%s\n' \
        "$version" "${profile/main/6160}" "$profile" > "$SNELL_BRIDGE_CONF/users/snell-$profile.conf"
done
printf '#version-choice = v4\npsk = obsolete-secret\n' > "$SNELL_BRIDGE_CONF/snell-server.conf"
cp -a "$SNELL_BRIDGE_CONF" "$scratch/snell-before"
cp -a "$is_core_dir" "$scratch/sing-box-before"
export FAKE_LOG=$scratch/arguments FAKE_STATUS=0
cat > "$scratch/backend" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$FAKE_LOG"
exit "$FAKE_STATUS"
EOF
snell_bridge_hash() { snell_bridge_digest "$scratch/backend"; }
snell_bridge_download() { printf '%s\n' "$1" >> "$scratch/downloads"; cp "$scratch/backend" "$2"; }
snell_bridge_platform() { printf 'platform\n' >> "$scratch/platform"; }
snell_bridge_dependencies() { printf 'dependencies\n' >> "$scratch/dependencies"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
run() { local name=$1; shift; ( "$@" ); printf 'PASS: %s\n' "$name"; }

listing() {
    main snell list > "$scratch/list"
    grep -Eq '^main +v5 +74.219.23.240:6160' "$scratch/list"
    grep -Eq '^15562 +v5 ' "$scratch/list"
    grep -Eq '^55261 +v6 ' "$scratch/list"
    [[ $(wc -l < "$scratch/list" | tr -d ' ') == 4 ]]
    ! grep -q 'private\|obsolete' "$scratch/list"
    [[ ! -f $scratch/downloads && ! -f $scratch/platform ]]
    diff -r "$SNELL_BRIDGE_CONF" "$scratch/snell-before"
    diff -r "$is_core_dir" "$scratch/sing-box-before"
}
legacy_listing() {
    rm "$SNELL_BRIDGE_CONF/users/snell-main.conf"
    snell_bridge_list > "$scratch/legacy-list"
    grep -Eq '^main +v4 ' "$scratch/legacy-list"
    cp "$scratch/snell-before/users/snell-main.conf" "$SNELL_BRIDGE_CONF/users/"
}
forward_commands() {
    main snell bind-ip main 74.219.23.240
    [[ $(cat "$FAKE_LOG") == $'bind-ip\nmain\n74.219.23.240' ]]
    main snell profile 55261
    [[ $(cat "$FAKE_LOG") == $'profile\n55261' ]]
    main snell add --version v6 --bind-ip 'argument with spaces'
    [[ $(cat "$FAKE_LOG") == $'add\n--version\nv6\n--bind-ip\nargument with spaces' ]]
    # One verified backend is reused for all three operations.
    [[ $(wc -l < "$scratch/downloads" | tr -d ' ') == 1 ]]
    diff -r "$SNELL_BRIDGE_CONF" "$scratch/snell-before"
    cmp "$is_core_dir/config.json" "$scratch/sing-box-before/config.json"
}
protocol_shortcuts() {
    add snell-v5 auto auto --bind-ip 74.219.23.237
    [[ $(cat "$FAKE_LOG") == $'add\n--version\nv5\n--port\nauto\n--bind-ip\n74.219.23.237' ]]
    add snell-v6 28000 --bind-ip=74.219.23.240
    [[ $(cat "$FAKE_LOG") == $'add\n--version\nv6\n--port\n28000\n--bind-ip\n74.219.23.240' ]]
    [[ ${protocol_list[*]} == *Snell-v5* && ${protocol_list[*]} == *Snell-v6* ]]
}
no_destructive_conversion() {
    cp "$FAKE_LOG" "$scratch/last-call"
    ! (main gen snell-v5 auto --bind-ip 74.219.23.237) >/dev/null 2>&1
    ! (is_change=1; add snell-v6 auto) >/dev/null 2>&1
    ! (add snell-v5 auto custom-password) >/dev/null 2>&1
    cmp "$FAKE_LOG" "$scratch/last-call"
    diff -r "$SNELL_BRIDGE_CONF" "$scratch/snell-before"
    diff -r "$is_core_dir/conf" "$scratch/sing-box-before/conf"
}
native_installer() {
    main snell install >/dev/null
    [[ $(cat "$FAKE_LOG") == '' ]]
    grep -q '/snell.sh$' "$scratch/downloads"
    [[ $(wc -l < "$scratch/downloads" | tr -d ' ') == 2 ]]
}
tampered_cache() {
    local cached=$is_core_dir/snell-cache/$SNELL_BRIDGE_REV/ip-binding.sh
    printf 'echo should-not-run\n' > "$cached"
    main snell profile main
    cmp "$cached" "$scratch/backend"
    [[ $(wc -l < "$scratch/downloads" | tr -d ' ') == 3 ]]
}
bad_download() {
    local cached=$is_core_dir/snell-cache/$SNELL_BRIDGE_REV/ip-binding.sh
    rm "$cached"
    snell_bridge_download() { printf 'echo wrong-script\n' > "$2"; }
    ! main snell profile main >/dev/null 2>&1
    [[ ! -f $cached ]]
}
failure_status() {
    export FAKE_STATUS=37
    local result=0
    main snell profile main || result=$?
    [[ $result == 37 ]]
    [[ -z $(find "$is_core_dir" -maxdepth 1 -name '.snell-session.*' -print) ]]
}
installer_flag() {
    eval "$(sed -n '/^pass_args() {/,/^}/p' "$repo/install.sh")"
    pass_args --with-snell -v 1.14.0 || :
    [[ $with_snell == 1 && $is_core_ver == v1.14.0 ]]
}
run existing-profile-inventory-without-secrets listing
run legacy-main-profile-discovery legacy_listing
run command-forwarding-and-cache forward_commands
run unified-add-v5-and-v6 protocol_shortcuts
run refuse-conversion-and-preview no_destructive_conversion
run native-install-menu native_installer
run tampered-cache-replaced-before-execution tampered_cache
run wrong-download-never-executed bad_download
run preserve-backend-error-status failure_status
run optional-installer-flag installer_flag
