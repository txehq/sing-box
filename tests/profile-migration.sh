#!/usr/bin/env bash
set -e
repo=$(cd "$(dirname "$0")/.." && pwd)
PROFILE_TEST_LIBRARY=1 . "$repo/tests/profile-binding.sh"

is_systemd=1
profile_restart_service() { printf 'restart\n' >> "$scratch/restarts"; }

# Reproduce the two original installer-generated profiles, not replacements.
(
    is_port_used() { return 1; }
    add hy2 23626 existing-password --bind-ip default >/dev/null || exit 1
)
(
    is_port_used() { return 1; }
    add reality 4200 12345678-1234-4234-8234-123456789012 www.example.com \
        --bind-ip default >/dev/null || exit 1
)
cp -a "$is_conf_dir" "$scratch/original"

migrate_originals() {
    for file in Hysteria2-23626.json VLESS-REALITY-4200.json; do
        main bind-ip "$file" 74.219.23.240 >/dev/null || exit 1
        [[ $(jq -S '.inbounds[0] | del(.listen)' "$scratch/original/$file") == \
           "$(jq -S '.inbounds[0] | del(.listen)' "$is_conf_dir/$file")" ]]
        assert_json '.inbounds[0].listen == "74.219.23.240"' "$is_conf_dir/$file"
        assert_json '.outbounds[-1].inet4_bind_address == "74.219.23.240" and .outbounds[-1].bind_interface == "ens3"' "$is_conf_dir/$file"
        [[ $(jq -S '.outbounds // []' "$scratch/original/$file") == \
           "$(jq -S '[.outbounds[] | select((.tag // "") | startswith("profile-direct-") | not)]' "$is_conf_dir/$file")" ]]
    done
    [[ $(find "$scratch" -maxdepth 1 -type d -name 'backup-bind-ip.*' | wc -l | tr -d ' ') == 2 ]]
    [[ $(wc -l < "$scratch/restarts" | tr -d ' ') == 2 ]]
}
rerun_is_idempotent() {
    local file=Hysteria2-23626.json before
    before=$(jq -S . "$is_conf_dir/$file")
    profile_bind_existing "$file" 74.219.23.240 >/dev/null || exit 1
    [[ $(jq -S . "$is_conf_dir/$file") == "$before" ]]
}
preserve_companion() {
    local file=Hysteria2-23626.json
    jq '.inbounds += [(.inbounds[0] | .tag += "-ip237" |
      .listen = "74.219.23.237" | .users[0].password = "companion-password")]
      | .outbounds += [{type:"direct",tag:"custom-direct"}]
      | .route.rules += [{domain:["example.org"],action:"route",outbound:"custom-direct"}]
    ' "$is_conf_dir/$file" > "$scratch/multi.json"
    cp "$scratch/multi.json" "$is_conf_dir/$file"
    profile_bind_existing "$file" 74.219.23.240 >/dev/null || exit 1
    [[ $(jq -S '.inbounds[1]' "$scratch/multi.json") == \
       "$(jq -S '.inbounds[1]' "$is_conf_dir/$file")" ]]
    assert_json '.route.rules[-1].outbound == "custom-direct" and .outbounds[-2].tag == "custom-direct"' "$is_conf_dir/$file"
    local before
    before=$(cat "$is_conf_dir/$file")
    ! (change "$file" passwd replacement) >/dev/null
    [[ $(cat "$is_conf_dir/$file") == "$before" ]]
}
explicit_companion() {
    local file=Hysteria2-23626.json before
    before=$(jq -S '.inbounds[0]' "$is_conf_dir/$file")
    profile_bind_existing "$file" 74.219.23.237 Hysteria2-23626.json-ip237 >/dev/null || exit 1
    [[ $(jq -S '.inbounds[0]' "$is_conf_dir/$file") == "$before" ]]
    assert_json '.inbounds[1].users[0].password == "companion-password" and .outbounds[-1].inet4_bind_address == "74.219.23.237"' "$is_conf_dir/$file"
}
reject_collision() {
    local file=Hysteria2-23626.json before
    before=$(cat "$is_conf_dir/$file")
    ! profile_bind_existing "$file" 74.219.23.237 >/dev/null
    [[ $(cat "$is_conf_dir/$file") == "$before" ]]
}
validation_failure() {
    local file=VLESS-REALITY-4200.json before
    before=$(cat "$is_conf_dir/$file")
    is_core_bin=$scratch/fail-validation
    printf '#!/bin/sh\nexit 1\n' > "$is_core_bin"
    chmod +x "$is_core_bin"
    ! profile_bind_existing "$file" 74.219.23.237 >/dev/null
    [[ $(cat "$is_conf_dir/$file") == "$before" ]]
}
restart_failure() {
    local file=VLESS-REALITY-4200.json before
    before=$(cat "$is_conf_dir/$file")
    profile_restart_service() {
        if [[ ! -f $scratch/failed-once ]]; then
            touch "$scratch/failed-once"
            return 1
        fi
        touch "$scratch/restored-service"
    }
    ! profile_bind_existing "$file" 74.219.23.237 >/dev/null
    [[ $(cat "$is_conf_dir/$file") == "$before" ]]
    [[ -f $scratch/restored-service ]]
}
invalid_target() {
    ! profile_bind_existing ../config.json 74.219.23.240 >/dev/null
    ! profile_bind_existing missing.json 74.219.23.240 >/dev/null
    ! profile_bind_existing Hysteria2-23626.json 74.219.23.240 missing-tag >/dev/null
    ! profile_bind_existing Hysteria2-23626.json default >/dev/null
    ! profile_bind_existing Hysteria2-23626.json '' >/dev/null
}
new_profile_after_migration() {
    # The existing REALITY profile no longer occupies .237:4200.
    add reality 4200 auto www.example.com --bind-ip 74.219.23.237 >/dev/null || exit 1
    local file=$is_conf_dir/VLESS-REALITY-4200-74.219.23.237.json
    assert_json '.inbounds[0].users[0].uuid != "12345678-1234-4234-8234-123456789012" and .inbounds[0].listen == "74.219.23.237"' "$file"
    # A real creation generates its own key pair. The test stub uses a fixed
    # pair, so replace only its public-key marker to avoid duplicate test tags.
    jq '.outbounds[1].tag = "public_key_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"' "$file" > "$scratch/fresh-reality.json"
    mv "$scratch/fresh-reality.json" "$file"
}

run_test migrate-originals-without-client-changes migrate_originals
run_test idempotent-migration rerun_is_idempotent
run_test preserve-manually-added-companion preserve_companion
run_test migrate-explicit-companion explicit_companion
run_test reject-migration-collision reject_collision
run_test validation-failure-leaves-original validation_failure
run_test restart-failure-restores-original restart_failure
run_test invalid-migration-targets invalid_target
run_test new-profile-after-migration new_profile_after_migration
if [[ $SING_BOX ]]; then
    "$SING_BOX" check -c "$is_config_json" -C "$is_conf_dir"
    printf 'PASS: real sing-box migrated and new profiles check\n'
fi
