#!/bin/bash
# Globals are supplied by core.sh/init.sh.
# shellcheck disable=SC2154

# Only addresses assigned to an UP interface are candidates. This deliberately
# does not infer local addresses from an external IP service (NAT is different).
profile_public_ips() {
    command -v ip >/dev/null 2>&1 || return 1
    local addresses
    addresses=$(ip -j -4 address show up) || return 1
    jq -r '
      def public_v4:
        split(".") | map(tonumber) as $o |
        ($o | length) == 4 and
        ($o[0] > 0 and $o[0] < 224) and
        ($o[0] != 10 and $o[0] != 127) and
        ([$o[0], $o[1]] != [169,254]) and
        ([$o[0], $o[1]] != [192,168]) and
        ([$o[0], $o[1], $o[2]] != [192,0,0]) and
        ([$o[0], $o[1], $o[2]] != [192,0,2]) and
        ([$o[0], $o[1], $o[2]] != [192,88,99]) and
        ([$o[0], $o[1], $o[2]] != [198,51,100]) and
        ([$o[0], $o[1], $o[2]] != [203,0,113]) and
        (($o[0] == 100 and $o[1] >= 64 and $o[1] <= 127) | not) and
        (($o[0] == 172 and $o[1] >= 16 and $o[1] <= 31) | not) and
        (($o[0] == 198 and ($o[1] == 18 or $o[1] == 19)) | not);
      [.[] | .ifname as $iface | .addr_info[]? |
        select(.family == "inet" and .scope == "global") |
        select(.local | public_v4) | {ip: .local, interface: $iface}]
      | unique_by([.ip, .interface])[] | [.ip, .interface] | @tsv
    ' <<<"$addresses"
}

profile_select_ip() {
    local requested=$1 candidates choice address iface index=0
    local -a ips=() interfaces=()
    if [[ $requested == default ]]; then
        unset is_profile_ip is_profile_interface
        return 0
    fi
    # Editing/fixing keeps the binding loaded from the existing profile.
    # These transports terminate at a shared reverse proxy or domain endpoint.
    # Binding only their loopback backend would give a false isolation guarantee.
    if [[ $is_use_tls || $is_anytls_domain ]]; then
        if [[ ( $requested && $requested != default ) || $is_profile_ip ]]; then
            err "--bind-ip 暂不支持由域名或反向代理管理入口的 TLS 配置."
            return 1
        fi
        return 0
    fi
    [[ $is_change && ! $requested ]] && return 0
    unset is_profile_ip is_profile_interface
    [[ $requested == default ]] && return 0
    [[ ! $requested && ( ! -t 0 || $is_gen ) ]] && return 0
    if ! candidates=$(profile_public_ips); then
        if [[ $requested ]]; then
            err "无法检测本机公网 IPv4，请安装支持 JSON 输出的 iproute2."
            return 1
        fi
        warn "无法检测本机公网 IPv4，保留默认监听/出口. 可安装 iproute2 后使用 --bind-ip."
        return 0
    fi
    while IFS=$'\t' read -r address iface; do
        [[ $address ]] || continue
        ips+=("$address")
        interfaces+=("$iface")
    done <<<"$candidates"

    if [[ $requested == auto ]]; then
        if [[ ${#ips[@]} != 1 ]]; then
            err "检测到 ${#ips[@]} 个公网 IPv4，请通过 --bind-ip IP 明确选择."
            return 1
        fi
        requested=${ips[0]}
    fi
    if [[ $requested ]]; then
        for index in "${!ips[@]}"; do
            [[ ${ips[$index]} == "$requested" ]] || continue
            if [[ $is_profile_ip ]]; then
                err "此 IP 出现在多个接口上，无法唯一确定接口: $requested"
                return 1
            fi
            is_profile_ip=${ips[$index]}
            is_profile_interface=${interfaces[$index]}
        done
        if [[ ! $is_profile_ip ]]; then
            err "所选地址不是 UP 接口上已配置的公网 IPv4: $requested"
            return 1
        fi
        return 0
    fi
    [[ ${#ips[@]} == 0 ]] && return 0
    msg "\n请选择此配置的监听和出口 IP (需由供应商配置可用的路由):"
    msg "0) 默认 (所有地址监听，系统选择出口)"
    for index in "${!ips[@]}"; do
        msg "$((index + 1))) ${ips[$index]} (${interfaces[$index]})"
    done
    while :; do
        printf '选择 [0]: '
        read -r choice || return 1
        choice=${choice:-0}
        [[ $choice == 0 ]] && return 0
        if [[ $choice =~ ^[1-9][0-9]*$ && ${#choice} -le 5 ]] &&
            ((choice <= ${#ips[@]})); then
            is_profile_ip=${ips[$((choice - 1))]}
            is_profile_interface=${interfaces[$((choice - 1))]}
            return 0
        fi
        msg "请输入列表中的编号."
    done
}

# Keep binding and routing in the profile itself: change/fix/delete need no
# separate global registry, and resetting config.json cannot erase the route.
profile_bind_json() {
    jq --arg ip "$is_profile_ip" --arg iface "$is_profile_interface" '
      .inbounds[0].listen = $ip
      | .inbounds[0].tag as $inbound
      | ("profile-direct-" + $inbound) as $outbound
      | .outbounds += [{type: "direct", tag: $outbound,
          bind_interface: $iface, inet4_bind_address: $ip}]
      | .route.rules += [
          {inbound: [$inbound], ip_version: 6, action: "reject"},
          {inbound: [$inbound], action: "resolve", strategy: "ipv4_only"},
          {inbound: [$inbound], action: "route", outbound: $outbound}]
    '
}

profile_load_binding() {
    unset is_profile_ip is_profile_interface
    local binding
    binding=$(jq -r '
      .inbounds[0].tag as $tag | .outbounds[]? |
      select(.tag == ("profile-direct-" + $tag)) |
      [.inet4_bind_address, .bind_interface] | @tsv
    ' <<<"$is_json_str")
    [[ $binding ]] && IFS=$'\t' read -r is_profile_ip is_profile_interface <<<"$binding"
    return 0
}

# Address-aware collision checks allow the same port on different public IPs.
# Wildcards (including IPv6 wildcards) still conflict. Also check saved profiles
# so a stopped service cannot cause accidental endpoint duplication.
profile_port_used() {
    local port=$1 endpoints endpoint file
    if command -v ss >/dev/null 2>&1; then
        endpoints=$(ss -H -lntu) || { err "无法读取监听端口 (ss)."; return 1; }
        endpoints=$(awk '{print $5}' <<<"$endpoints")
    elif command -v netstat >/dev/null 2>&1; then
        endpoints=$(netstat -lntu) || { err "无法读取监听端口 (netstat)."; return 1; }
        endpoints=$(awk '/^(tcp|udp)/ {print $4}' <<<"$endpoints")
    else
        err "绑定 IP 时需要 ss (iproute2) 或 netstat 来检查端口."
        # is_port_used callers inspect stdout rather than the exit status.
        printf '%s\n' "$port"
        return 1
    fi
    while read -r endpoint; do
        [[ ${endpoint##*:} == "$port" ]] || continue
        case ${endpoint%:*} in
        "$is_profile_ip" | "[$is_profile_ip]" | '0.0.0.0' | '*' | '[::]' | '::')
            printf '%s\n' "$port"
            return 0
            ;;
        esac
    done <<<"$endpoints"
    for file in "$is_conf_dir"/*.json; do
        [[ -f $file ]] || continue
        [[ $is_change && ${file##*/} == "$is_config_file" ]] && continue
        if jq -e --arg ip "$is_profile_ip" --argjson port "$port" '
          any(.inbounds[]?; .listen_port == $port and
            (.listen == $ip or .listen == "::" or .listen == "0.0.0.0" or .listen == ""))
        ' "$file" >/dev/null; then
            printf '%s\n' "$port"
            return 0
        fi
    done
    return 1
}
