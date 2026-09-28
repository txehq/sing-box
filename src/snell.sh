#!/bin/bash
# Snell is an independent server. Run its manager in a child process so neither
# its shell globals nor its profile lifecycle can overwrite sing-box settings.
# shellcheck disable=SC2154
SNELL_BRIDGE_REV=8031963f67d7532b661990017b34250ccc5b03a6
SNELL_BRIDGE_CONF=/etc/snell

snell_bridge_error() { printf 'Snell: %s\n' "$*" >&2; return 1; }
snell_bridge_hash() {
    case $1 in
        snell.sh) printf '%s\n' 8d602232b0560852f7dba7eb1a5fc6e37b14d793fb67abd3fd7067728e471e91;;
        ip-binding.sh) printf '%s\n' 91b9f6c55453dfd3b01b7501d1156af90ebe786dbdd704f4dc27122b81b9ce21;;
        *) return 1;;
    esac
}
snell_bridge_digest() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}
snell_bridge_download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fLsS --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 10 --max-time 120 "$1" -o "$2"
    else
        wget --https-only --timeout=30 --tries=3 -q -O "$2" "$1"
    fi
}
snell_bridge_fetch() (
    set -e
    umask 077
    local name=$1 expected cache stage
    expected=$(snell_bridge_hash "$name") || exit 1
    cache=$is_core_dir/snell-cache/$SNELL_BRIDGE_REV
    mkdir -p "$cache"
    chmod 700 "$is_core_dir/snell-cache" "$cache"
    if [[ -f $cache/$name && ! -L $cache/$name ]] &&
        [[ $(snell_bridge_digest "$cache/$name") == "$expected" ]]; then
        printf '%s\n' "$cache/$name"
        exit 0
    fi
    stage=$(mktemp "$cache/.download.XXXXXX")
    trap 'rm -f "$stage"' EXIT
    snell_bridge_download "https://raw.githubusercontent.com/txehq/snell.sh/$SNELL_BRIDGE_REV/$name" "$stage" || exit 1
    if [[ $(snell_bridge_digest "$stage") != "$expected" ]]; then
        snell_bridge_error '下载校验失败，未执行脚本。'
        exit 1
    fi
    bash -n "$stage" || exit 1
    chmod 600 "$stage"
    mv -f "$stage" "$cache/$name"
    printf '%s\n' "$cache/$name"
)
snell_bridge_platform() {
    local ID=''
    # shellcheck source=/dev/null
    [[ -r /etc/os-release ]] && . /etc/os-release
    case $ID in
        ubuntu|debian) ;;
        *) snell_bridge_error '此集成支持原生 Debian/Ubuntu + systemd 安装。'; return 1;;
    esac
    command -v systemctl >/dev/null 2>&1 || { snell_bridge_error '需要 systemd。'; return 1; }
    [[ $EUID == 0 ]] || { snell_bridge_error '请以 root 运行。'; return 1; }
}
snell_bridge_dependencies() {
    local command missing=''
    for command in curl jq nft ip openssl; do
        command -v "$command" >/dev/null 2>&1 || missing=1
    done
    [[ $missing ]] || return 0
    printf '安装 Snell 公网 IP 管理依赖...\n' >&2
    apt-get update && apt-get install -y curl jq nftables iproute2 openssl
}
snell_bridge_run() (
    local name=$1 cached session result
    shift
    cached=$(snell_bridge_fetch "$name") || exit 1
    # The native manager can update its own script. Give it a disposable copy
    # so that this release's verified cache remains immutable.
    session=$(mktemp -d "$is_core_dir/.snell-session.XXXXXX") || exit 1
    trap 'rm -rf "$session"' EXIT
    cp "$cached" "$session/$name" || exit 1
    bash "$session/$name" "$@"
    result=$?
    exit "$result"
)
snell_bridge_value() {
    awk -v key="$2" '
      {line=$0; sub(/^[ \t]+/, "", line); sub(/^#[ \t]+/, "#", line);
       at=index(line,"="); if (!at) next;
       name=substr(line,1,at-1); sub(/[ \t]+$/, "", name);
       if (name==key) {value=substr(line,at+1); sub(/^[ \t]+/, "", value);
         sub(/[ \t\r]+$/, "", value); print value; exit}}
    ' "$1"
}
snell_bridge_list() {
    local file name version listen exit_ip found=''
    local -a files=("$SNELL_BRIDGE_CONF"/users/snell-*.conf)
    if [[ ! -f $SNELL_BRIDGE_CONF/users/snell-main.conf && -f $SNELL_BRIDGE_CONF/snell-server.conf ]]; then
        files+=("$SNELL_BRIDGE_CONF/snell-server.conf")
    fi
    printf '%-12s %-8s %-28s %s\n' 'PROFILE' 'VERSION' 'LISTEN' 'EXIT IPv4'
    for file in "${files[@]}"; do
        [[ -f $file ]] || continue
        found=1
        name=${file##*/}; name=${name#snell-}; name=${name%.conf}
        [[ $name != server ]] || name=main
        version=$(snell_bridge_value "$file" '#version-choice')
        listen=$(snell_bridge_value "$file" listen)
        exit_ip=$(snell_bridge_value "$file" '#txehq-bind-ip')
        printf '%-12s %-8s %-28s %s\n' "$name" "${version:-unknown}" "$listen" "${exit_ip:-automatic}"
    done
    [[ $found ]] || printf '未检测到 Snell 配置。使用 sing-box snell install 打开安装菜单。\n'
}
snell_bridge_help() {
    cat <<'EOF'
sing-box snell                     Snell 统一管理菜单
sing-box snell install             原生 Snell 安装/版本管理菜单
sing-box snell list                列出现有配置和版本（不显示 PSK）
sing-box snell ips                 列出已配置的公网 IPv4 / 接口
sing-box snell add --version v5|v6 [--port PORT] [--bind-ip IP]
sing-box snell bind-ip main|PORT IP 保留现有端口/PSK，迁移监听和出口
sing-box snell profile main|PORT    显示 Surge 配置（含 PSK）
sing-box add snell-v5 [PORT|auto] [auto] [--bind-ip IP]
sing-box add snell-v6 [PORT|auto] [auto] [--bind-ip IP]

Snell 使用独立服务及 /etc/snell 配置，不写入 sing-box 的 JSON。
新配置需要已安装对应 v5/v6 通道；安装菜单中 1=安装，8=通道管理。
每个新配置生成独立 PSK；旧配置不会自动重建或更换凭据。
EOF
}
snell_bridge_menu() {
    local choice profile address
    printf '\nSnell 管理\n1) 现有配置/版本\n2) 新建 v5 配置\n3) 新建 v6 配置\n4) 迁移现有配置的 IP\n5) 显示客户端配置\n6) 安装/版本管理\n0) 返回\n'
    read -rp '选择: ' choice || return 1
    case $choice in
        1) snell_dispatch list;;
        2) snell_dispatch add --version v5;;
        3) snell_dispatch add --version v6;;
        4) snell_bridge_list
           read -rp '配置 (main 或端口): ' profile || return 1
           snell_dispatch ips || return 1
           read -rp '公网 IPv4: ' address || return 1
           snell_dispatch bind-ip "$profile" "$address";;
        5) snell_bridge_list
           read -rp '配置 (main 或端口): ' profile || return 1
           snell_dispatch profile "$profile";;
        6) snell_dispatch install;;
        0|'') return 0;;
        *) snell_bridge_error '无效选项。';;
    esac
}
snell_dispatch() {
    local action=${1:-menu}
    [[ $# == 0 ]] || shift
    case $action in
        menu) snell_bridge_menu;;
        help|-h|--help) snell_bridge_help;;
        list) snell_bridge_list;;
        ips) profile_public_ips;;
        install|manage)
            [[ $# == 0 ]] || { snell_bridge_error 'install 不接受其他参数。'; return 1; }
            snell_bridge_platform || return 1
            snell_bridge_dependencies || return 1
            printf '打开 Snell 原生菜单：1=安装，8=版本/通道管理。现有配置由原生管理器保留。\n'
            snell_bridge_run snell.sh
            ;;
        add|bind-ip)
            snell_bridge_platform || return 1
            snell_bridge_dependencies || return 1
            snell_bridge_run ip-binding.sh "$action" "$@"
            ;;
        profile)
            snell_bridge_platform || return 1
            snell_bridge_run ip-binding.sh profile "$@"
            ;;
        *) snell_bridge_error "未知命令: $action。使用 sing-box snell help。";;
    esac
}
