# 介绍

## 按公网 IPv4 创建配置（txehq 分支）

创建配置时，可以选择本机已经配置的公网 IPv4 和对应接口。同一接口上的多个
IPv4 会分别列出，例如 `ens3` 上的 `74.219.23.240` 和 `74.219.23.237`。
选定后，客户端连接地址、服务端监听地址及代理出口 IPv4 使用同一个地址。
脚本不会修改 Netplan、申请 IP 或创建网络接口；请先按供应商说明配置地址和路由。

```bash
# 列出本机 UP 接口上已配置的公网 IPv4
sing-box ips

# 分别创建两套配置；auto 会为每个新配置生成新的密码 / UUID
sing-box add hy2 23626 auto --bind-ip 74.219.23.240
sing-box add hy2 23626 auto --bind-ip 74.219.23.237
sing-box add reality 4200 auto --bind-ip 74.219.23.240
sing-box add reality 4200 auto --bind-ip 74.219.23.237

# 导出其中一个配置的客户端链接
sing-box url Hysteria2-23626-74.219.23.237.json

# 修改密码后仍保留原来的 IP / 接口绑定
sing-box passwd Hysteria2-23626-74.219.23.237.json auto
```

- 交互式添加会显示 IP / 接口选择菜单，`0` 或回车保留原来的默认行为。
  无终端的命令、安装流程和 `gen` 不会自动询问；需要绑定时传入 `--bind-ip`。
- `--bind-ip auto` 仅在恰好检测到一个公网 IPv4 时选择它；多个候选时必须明确指定。
  `--bind-ip default` 使用原来的通配监听和系统默认出口。
- 需要 sing-box **1.12.0+**、`jq` 和支持 JSON 输出的 **iproute2**。
  检测排除私有、回环、链路本地、CGNAT、文档和其他保留网段，不证明供应商路由可达。
  NAT 后的公网地址若没有直接配置在本机接口上，不能用此功能选择。
- 绑定配置按 IPv4 解析目标域名，并拒绝 IPv6 目标，避免通过其他 IPv6 地址出站。
  DNS 沿用现有解析设置；此功能不承诺 DNS 查询也通过所选 IP 发出。
- 配置文件名包含 IP。同一端口可以用于不同 IP；通配监听、同 IP 上已有监听以及
  尚未运行的已保存配置仍会阻止端口冲突。默认行为仍使用原有的端口检查。
- 每个配置文件保存自己的监听、出口及路由；更改密码/端口、`fix`、`fix-all`
  和 `fix-config.json` 都保留绑定；删除配置时一并删除其绑定和路由。
  此功能不自动拆分以前手工合并了多个入站的配置文件。
- 当前支持直接由 sing-box 监听的协议，例如 Hysteria2、REALITY、TUIC、Trojan、
  Shadowsocks 和不带域名的 AnyTLS。由 Caddy/反向代理管理的 `*-TLS` 及带域名
  的 AnyTLS 不接受 `--bind-ip`，以免只绑定后端而误认为已隔离公网入口。
- 此分支的安装与更新下载来自 `txehq/sing-box`，避免更新时回到上游脚本。

验证：连接每个客户端配置后，通过代理访问 IP 查询服务，检查是否显示所选 IP。
本地测试：`bash tests/profile-binding.sh`；设置 `SING_BOX=/path/to/sing-box` 可额外
校验合并后的真实配置。测试使用模拟网卡和临时配置，不更改本机网络或启动代理服务。

最好用的 sing-box 一键安装脚本 & 管理脚本

# 特点

- 快速安装
- 无敌好用
- 零学习成本
- 自动化 TLS
- 简化所有流程
- 兼容 sing-box 命令
- 强大的快捷参数
- 支持所有常用协议
- 一键添加 VLESS-REALITY (默认)
- 一键添加 TUIC
- 一键添加 Trojan
- 一键添加 Hysteria2
- 一键添加 AnyTLS
- 一键添加 Shadowsocks 2022
- 一键添加 VMess-(TCP/HTTP/QUIC)
- 一键添加 VMess-(WS/H2/HTTPUpgrade)-TLS
- 一键添加 VLESS-(WS/H2/HTTPUpgrade)-TLS
- 一键添加 Trojan-(WS/H2/HTTPUpgrade)-TLS
- 一键启用 BBR
- 一键更改伪装网站
- 一键更改 (端口/UUID/密码/域名/路径/加密方式/SNI/等...)
- 还有更多...

# 设计理念

设计理念为：**高效率，超快速，极易用**

脚本基于作者的自身使用需求，以 **多配置同时运行** 为核心设计

并且专门优化了，添加、更改、查看、删除、这四项常用功能

你只需要一条命令即可完成 添加、更改、查看、删除、等操作

例如，添加一个配置仅需不到 1 秒！瞬间完成添加！其他操作亦是如此！

脚本的参数非常高效率并且超级易用，请掌握参数的使用

# 文档

安装及使用：https://233boy.com/sing-box/sing-box-script/

# 帮助

使用：`sing-box help`

```
sing-box script v1.0 by 233boy
Usage: sing-box [options]... [args]...

基本:
   v, version                                      显示当前版本
   ip                                              返回当前主机的 IP
   pbk                                             同等于 sing-box generate reality-keypair
   get-port                                        返回一个可用的端口
   ss2022                                          返回一个可用于 Shadowsocks 2022 的密码

一般:
   a, add [protocol] [args... | auto]              添加配置
   c, change [name] [option] [args... | auto]      更改配置
   d, del [name]                                   删除配置**
   i, info [name]                                  查看配置
   qr [name]                                       二维码信息
   url [name]                                      URL 信息
   log                                             查看日志
更改:
   full [name] [...]                               更改多个参数
   id [name] [uuid | auto]                         更改 UUID
   host [name] [domain]                            更改域名
   port [name] [port | auto]                       更改端口
   path [name] [path | auto]                       更改路径
   passwd [name] [password | auto]                 更改密码
   key [name] [Private key | auto] [Public key]    更改密钥
   method [name] [method | auto]                   更改加密方式
   sni [name] [ ip | domain]                       更改 serverName
   new [name] [...]                                更改协议
   web [name] [domain]                             更改伪装网站

进阶:
   dns [...]                                       设置 DNS
   dd, ddel [name...]                              删除多个配置**
   fix [name]                                      修复一个配置
   fix-all                                         修复全部配置
   fix-caddyfile                                   修复 Caddyfile
   fix-config.json                                 修复 config.json
   import                                          导入 sing-box/v2ray 脚本配置

管理:
   un, uninstall                                   卸载
   u, update [core | sh | caddy] [ver]             更新
   U, update.sh                                    更新脚本
   s, status                                       运行状态
   start, stop, restart [caddy]                    启动, 停止, 重启
   t, test                                         测试运行
   reinstall                                       重装脚本

测试:
   debug [name]                                    显示一些 debug 信息, 仅供参考
   gen [...]                                       同等于 add, 但只显示 JSON 内容, 不创建文件, 测试使用
   no-auto-tls [...]                               同等于 add, 但禁止自动配置 TLS, 可用于 *TLS 相关协议
其他:
   bbr                                             启用 BBR, 如果支持
   bin [...]                                       运行 sing-box 命令, 例如: sing-box bin help
   [...] [...]                                     兼容绝大多数的 sing-box 命令, 例如: sing-box generate uuid
   h, help                                         显示此帮助界面

谨慎使用 del, ddel, 此选项会直接删除配置; 无需确认
反馈问题) https://github.com/233boy/sing-box/issues
文档(doc) https://233boy.com/sing-box/sing-box-script/
```
