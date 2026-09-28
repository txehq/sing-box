#!/usr/bin/env bash
# No root privileges or changes to the host network/services are required.
set -e
repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

. "$repo/src/core.sh"

IP_FIXTURE='[{"ifname":"ens3","addr_info":[
 {"family":"inet","scope":"global","local":"74.219.23.240"},
 {"family":"inet","scope":"global","local":"74.219.23.237"},
 {"family":"inet","scope":"global","local":"10.0.0.1"},
 {"family":"inet","scope":"global","local":"172.18.0.1"},
 {"family":"inet","scope":"global","local":"100.64.1.1"},
 {"family":"inet","scope":"global","local":"192.168.1.1"},
 {"family":"inet","scope":"global","local":"192.0.2.1"},
 {"family":"inet","scope":"global","local":"198.51.100.1"},
 {"family":"inet","scope":"global","local":"203.0.113.1"},
 {"family":"inet","scope":"link","local":"169.254.1.1"}]},
 {"ifname":"ens4","addr_info":[{"family":"inet","scope":"global","local":"8.8.4.4"}]}]'
ip() { printf '%s\n' "$IP_FIXTURE"; }
ss() { printf '%s\n' "$SS_FIXTURE"; }
err() { printf 'ERROR: %s\n' "$*"; exit 1; }
warn() { printf 'WARNING: %s\n' "$*"; }
_green() { printf '%s\n' "$*"; }
_red_bg() { printf '%s\n' "$*"; }
get_ip() { ip=9.9.9.9; }
get_uuid() { printf -v tmp_uuid '00000000-0000-4000-8000-%012d' "$((++uuid_count))"; }
get_pbk() {
    is_private_key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    is_public_key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
}
manage() { :; }
footer_msg() { :; }

is_core=sing-box
is_core_ver=1.14.0
is_core_dir=$scratch
is_conf_dir=$scratch/conf
is_config_json=$scratch/config.json
is_tls_cer=$scratch/bin/tls.cer
is_tls_key=$scratch/bin/tls.key
is_core_bin=${SING_BOX:-/bin/true}
mkdir -p "$is_conf_dir" "$scratch/bin"
printf '{"outbounds":[{"type":"direct","tag":"direct"}]}' > "$is_config_json"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$is_tls_key" \
    -out "$is_tls_cer" -subj /CN=profile-test -days 1 >/dev/null 2>&1

run_test() {
    local name=$1
    shift
    ( "$@" )
    printf 'PASS: %s\n' "$name"
}
assert_json() { jq -e "$1" "$2" >/dev/null; }

discovery() {
    [[ $(profile_public_ips | wc -l | tr -d ' ') == 3 ]]
    [[ $(profile_public_ips) == *$'74.219.23.237\tens3'* ]]
    [[ $(profile_public_ips) == *$'74.219.23.240\tens3'* ]]
    [[ $(profile_public_ips) == *$'8.8.4.4\tens4'* ]]
}
selection() {
    profile_select_ip 74.219.23.237
    [[ $is_profile_ip == 74.219.23.237 && $is_profile_interface == ens3 ]]
    profile_select_ip 8.8.4.4
    [[ $is_profile_interface == ens4 ]]
    ! (profile_select_ip 10.0.0.1) >/dev/null
    ! (profile_select_ip 1.1.1.1) >/dev/null
    ! (profile_select_ip auto) >/dev/null
    IP_FIXTURE='[{"ifname":"ens3","addr_info":[{"family":"inet","scope":"global","local":"74.219.23.240"}]}]'
    profile_select_ip auto
    [[ $is_profile_ip == 74.219.23.240 ]]
    IP_FIXTURE='[]'
    ! (profile_select_ip auto) >/dev/null
    profile_select_ip default
    [[ ! $is_profile_ip ]]
}
default_noninteractive() {
    profile_select_ip '' </dev/null
    [[ ! $is_profile_ip ]]
}
unsupported() {
    is_use_tls=1
    ! (profile_select_ip 74.219.23.237) >/dev/null
    is_change=1 is_profile_ip=74.219.23.237
    ! (profile_select_ip '') >/dev/null
}
ports() {
    is_profile_ip=74.219.23.237
    SS_FIXTURE='tcp LISTEN 0 128 74.219.23.240:4200 0.0.0.0:*'
    [[ ! $(profile_port_used 4200) ]]
    SS_FIXTURE='tcp LISTEN 0 128 74.219.23.237:4200 0.0.0.0:*'
    [[ $(profile_port_used 4200) == 4200 ]]
    SS_FIXTURE='udp UNCONN 0 0 0.0.0.0:23626 0.0.0.0:*'
    [[ $(profile_port_used 23626) == 23626 ]]
    SS_FIXTURE='tcp LISTEN 0 128 [::]:4200 [::]:*'
    [[ $(profile_port_used 4200) == 4200 ]]
}
create_hysteria() {
    add hy2 23626 'new-secret' --bind-ip 74.219.23.237 >/dev/null || exit 1
    local file=$is_conf_dir/Hysteria2-23626-74.219.23.237.json
    assert_json '.inbounds[0].listen == "74.219.23.237" and .inbounds[0].users[0].password == "new-secret"' "$file"
    assert_json '.outbounds[0].inet4_bind_address == "74.219.23.237" and .outbounds[0].bind_interface == "ens3"' "$file"
    assert_json '.route.rules[1].strategy == "ipv4_only" and .route.rules[1].action == "resolve" and .route.rules[0].ip_version == 6 and .route.rules[0].action == "reject"' "$file"
    [[ $is_url == hysteria2://new-secret@74.219.23.237:23626* ]]
}
create_reality() {
    add reality 4200 auto www.example.com --bind-ip=74.219.23.240 >/dev/null || exit 1
    local file=$is_conf_dir/VLESS-REALITY-4200-74.219.23.240.json
    assert_json '.inbounds[0].listen == "74.219.23.240" and (.outbounds[1].tag | startswith("public_key_"))' "$file"
    assert_json '.outbounds[2].inet4_bind_address == "74.219.23.240"' "$file"
    [[ $is_url == vless://*@74.219.23.240:4200*pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA* ]]
}
preserve_binding() {
    change Hysteria2-23626-74.219.23.237.json passwd changed-secret >/dev/null || exit 1
    local file=$is_conf_dir/Hysteria2-23626-74.219.23.237.json
    assert_json '.inbounds[0].listen == "74.219.23.237" and .inbounds[0].users[0].password == "changed-secret"' "$file"
    assert_json '.route.rules[2].outbound == .outbounds[0].tag' "$file"
    [[ $is_url == hysteria2://changed-secret@74.219.23.237:23626* ]]
}
same_port_different_ip() {
    add hy2 23626 auto --bind-ip 74.219.23.240 >/dev/null || exit 1
    [[ -f $is_conf_dir/Hysteria2-23626-74.219.23.237.json ]]
    [[ -f $is_conf_dir/Hysteria2-23626-74.219.23.240.json ]]
    assert_json '.inbounds[0].users[0].password != "changed-secret"' "$is_conf_dir/Hysteria2-23626-74.219.23.240.json"
}
saved_collision() {
    ! (add hy2 23626 auto --bind-ip 74.219.23.237) >/dev/null
    assert_json '.inbounds[0].users[0].password == "changed-secret"' "$is_conf_dir/Hysteria2-23626-74.219.23.237.json"
}
fix_all() {
    main fix-all >/dev/null || exit 1
    assert_json '.inbounds[0].listen == "74.219.23.240" and .outbounds[2].inet4_bind_address == "74.219.23.240"' "$is_conf_dir/VLESS-REALITY-4200-74.219.23.240.json"
    assert_json '.inbounds[0].listen == "74.219.23.237"' "$is_conf_dir/Hysteria2-23626-74.219.23.237.json"
}
legacy() {
    # Do not inspect the developer machine's sockets in this legacy-path test.
    is_port_used() { return 1; }
    add hy2 23627 legacy-secret --bind-ip default >/dev/null || exit 1
    local file=$is_conf_dir/Hysteria2-23627.json
    assert_json '.inbounds[0].listen == "::" and .route == null' "$file"
    [[ $is_url == hysteria2://legacy-secret@9.9.9.9:23627* ]]
}
version_guard() {
    is_core_ver=1.11.0
    ! (add hy2 23628 auto --bind-ip 74.219.23.237) >/dev/null
    [[ ! -f $is_conf_dir/Hysteria2-23628-74.219.23.237.json ]]
}
parser() {
    ! (add hy2 --bind-ip) >/dev/null
    ! (add hy2 --bind-ip=) >/dev/null
    main gen hy2 23629 'password with spaces' --bind-ip 74.219.23.237 > "$scratch/preview" || exit 1
    [[ $(cat "$scratch/preview") == *'password with spaces'* ]]
    [[ ! -f $is_conf_dir/Hysteria2-23629-74.219.23.237.json ]]
}
port_change() {
    change Hysteria2-23626-74.219.23.237.json port 23630 >/dev/null || exit 1
    [[ ! -f $is_conf_dir/Hysteria2-23626-74.219.23.237.json ]]
    local file=$is_conf_dir/Hysteria2-23630-74.219.23.237.json
    assert_json '.inbounds[0].listen_port == 23630 and .inbounds[0].listen == "74.219.23.237" and .inbounds[0].users[0].password == "changed-secret"' "$file"
    assert_json '.route.rules[2].inbound[0] == .inbounds[0].tag and .route.rules[2].outbound == .outbounds[0].tag' "$file"
}
reset_global_config() {
    main fix-config.json >/dev/null || exit 1
    assert_json '.route.rules[2].outbound == .outbounds[0].tag' "$is_conf_dir/Hysteria2-23630-74.219.23.237.json"
}
delete_profile() {
    # Legacy del returns its final optional-condition status; assert filesystem
    # behavior instead of treating that status as a failed deletion.
    del Hysteria2-23630-74.219.23.237.json >/dev/null || :
    [[ ! -f $is_conf_dir/Hysteria2-23630-74.219.23.237.json ]]
    [[ -f $is_conf_dir/Hysteria2-23626-74.219.23.240.json ]]
}
duplicate_address() {
    IP_FIXTURE='[{"ifname":"ens3","addr_info":[{"family":"inet","scope":"global","local":"74.219.23.240"}]},{"ifname":"ens4","addr_info":[{"family":"inet","scope":"global","local":"74.219.23.240"}]}]'
    ! (profile_select_ip 74.219.23.240) >/dev/null
}
failed_discovery() {
    ip() { return 1; }
    ! (profile_select_ip 74.219.23.240) >/dev/null
}
failed_socket_inspection() {
    ss() { return 1; }
    ! (add hy2 23631 auto --bind-ip 74.219.23.237) >/dev/null
    [[ ! -f $is_conf_dir/Hysteria2-23631-74.219.23.237.json ]]
}

[[ ${PROFILE_TEST_LIBRARY:-} ]] && return 0

if [[ ${1:-} == --menu ]]; then
    profile_select_ip ''
    printf 'SELECTED=%s@%s\n' "$is_profile_ip" "$is_profile_interface"
    exit
fi

run_test discovery discovery
run_test selection selection
run_test noninteractive-default default_noninteractive
run_test reverse-proxy-rejection unsupported
run_test live-port-collisions ports
run_test hysteria-create-and-url create_hysteria
run_test reality-create-and-url create_reality
run_test password-change-preserves-binding preserve_binding
run_test same-port-different-ip same_port_different_ip
run_test saved-port-collision saved_collision
run_test fix-all-preserves-bindings fix_all
run_test legacy-profile legacy
run_test old-core-guard version_guard
run_test argument-parsing parser
run_test port-change-preserves-binding port_change
run_test reset-global-config-preserves-binding reset_global_config
run_test duplicate-address-rejected duplicate_address
run_test failed-discovery-rejected failed_discovery
run_test failed-socket-inspection-rejected failed_socket_inspection
if [[ $SING_BOX ]]; then
    "$SING_BOX" check -c "$is_config_json" -C "$is_conf_dir"
    printf 'PASS: real sing-box merged configuration check\n'
fi
run_test delete-profile-cleans-binding delete_profile
