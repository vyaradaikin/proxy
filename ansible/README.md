# Xray Gateway Ansible

Reusable Ansible automation for a two-node gateway:

- RU gateway receives VLESS Reality client traffic.
- RU gateway sends non-RU traffic through a WireGuard tunnel.
- Non-RU exit node NATs WireGuard traffic to the public Internet.

The repository is intentionally parameterized. Public files contain safe examples; real hostnames, IP addresses, SSH settings, WireGuard keys, and Xray Reality keys live in ignored local files.

## Layout

- `ansible/group_vars/all.yml`: public defaults.
- `ansible/group_vars/all/local.yml`: ignored local overrides.
- `ansible/group_vars/all/vault.yml`: ignored encrypted secrets.
- `ansible/inventory/hosts.yml`: ignored local inventory.
- `ansible/inventory/hosts.yml.example`: public inventory example.

## Bootstrap Local Config

From the repository root:

```bash
make init-local
```

Then edit:

```bash
.env
ansible/inventory/hosts.yml
ansible/group_vars/all/local.yml
```

Typical `.env`:

```bash
VAULT_ARGS=--vault-password-file ~/.ansible/vault_password
LIMIT=
```

## Stage 1: Generate Secrets

Secret generation runs locally and requires:

- `wg` from `wireguard-tools`
- `xray` available at `xray_binary_path`, default `/usr/local/bin/xray`
- `openssl`
- `uuidgen`

Generate or refresh the encrypted vault locally:

```bash
make secrets
```

If `wg` and `xray` are already available on the target servers instead, use:

```bash
make secrets-remote
```

This is useful when bootstrapping from an operator laptop that does not have WireGuard tools or Xray installed locally.

Both secret targets preserve existing values from `ansible/group_vars/all/vault.yml` when present, generate missing values, write a temporary plaintext payload to `.ansible/generated-vault.yml`, encrypt it into the vault, and then remove the plaintext payload:

```bash
ansible/group_vars/all/vault.yml
```

The encrypted vault contains:

- `wg_ru_private_key`
- `wg_ru_public_key`
- `wg_non_ru_private_key`
- `wg_non_ru_public_key`
- `xray_client_id`
- `xray_reality_private_key`
- `xray_reality_public_key`
- `xray_short_id`

## Stage 2: Plan And Apply

Dry-run:

```bash
make plan-ru
make plan-non-ru
```

Apply:

```bash
make apply-ru
make apply-non-ru
```

WireGuard only:

```bash
make apply-wg
```

## Client Profile Notes

Client applications connect to the RU gateway with VLESS Reality over TCP. The client profile must include the generated `xray_client_id`, `xray_reality_public_key`, `xray_short_id`, `xray_sni`, and `flow=xtls-rprx-vision`.

This deployment is IPv4-only by design. In clients such as Streisand Desktop, disable IPv6 for the profile or application tunnel. Leaving IPv6 enabled can make the client try unreachable IPv6 routes or DNS answers, which may look like a broken Reality/Xray profile even when the server is healthy.

## Xray Split Routing

The RU gateway sends Russian and private destinations through the local `direct`
outbound, while the default outbound is marked for the Non-RU WireGuard policy
routing table. The default direct rules include `geosite:category-ru`, common
RU TLD suffixes, `geosite:yandex`, `geoip:ru`, and `geoip:private`.

Xray inbound sniffing is enabled by default for `http`, `tls`, and `quic`.
Without it, many clients send only already-resolved destination IPs to Xray, so
domain rules such as `.ru` cannot match reliably.

Client DNS ports `53` and `853` are routed through `direct` by default. This
helps phones that keep using Google DNS or Private DNS through the tunnel get
answers from the RU side before connecting to RU-local services.

For stricter DNS control, enable the RU split DNS forwarder:

```yaml
dns_non_ru_forwarder_enabled: true
dns_ru_split_forwarder_enabled: true
dns_ru_intercept_xray_dns_enabled: true
dns_ru_manage_resolv_conf: true
dns_ru_nameservers:
  - 127.0.0.1
```

RU `dnsmasq` then forwards normal queries to the Non-RU DNS forwarder over
WireGuard, but sends configured RU/Yandex zones to RU-side upstream resolvers.
`dns_ru_intercept_xray_dns_enabled` transparently redirects plain DNS/53
requests made by the Xray service user to the local split resolver.

Encrypted client DNS on `443`/`853` cannot be transparently split by `dnsmasq`
without terminating TLS. Known encrypted DNS providers are routed through
`direct` by default, so they at least see the RU source IP. Disable Private
DNS/DoH in the client profile when a phone insists on Google DNS and RU services
still behave strangely.

If a specific Russian service still leaves through the Non-RU tunnel, extend the
lists in `ansible/group_vars/all/local.yml`:

```yaml
xray_ru_domains:
  - geosite:category-ru
  - geosite:yandex
  - domain:ya.ru
  - domain:yandex.ru
  - domain:yandex.net
  - domain:yastatic.net
  - domain:yastat.net
  - regexp:.*\.ru$
  - regexp:.*\.su$
  - regexp:.*\.xn--p1ai$
  - domain:example.ru
xray_ru_ips:
  - geoip:ru
  - geoip:private
  - 203.0.113.20/32
```

When `routing_ru_service_egress_enabled` is enabled for server-side updates,
DNS, NTP, or similar local maintenance traffic, the firewall excludes
`routing_ru_service_egress_excluded_users` from marking. Keep the Xray service
user in this list, otherwise Xray `direct` outbound traffic will be marked and
sent through the Non-RU policy routing table.

## Optional Xray User UI

The RU gateway can run a small localhost-only UI for adding and removing VLESS
Reality users. It edits `xray_clients_path`, validates the generated Xray config,
and restarts Xray after each change. This keeps UI-created users compatible with
future Ansible runs.

Enable it in `ansible/group_vars/all/local.yml`:

```yaml
xray_user_ui_enabled: true
xray_user_ui_basic_auth_user: admin
```

Store the Basic Auth password in vault:

```yaml
xray_user_ui_basic_auth_password: "CHANGEME"
```

The UI is bound to localhost by default. Open it through an SSH tunnel:

```bash
ssh -L 19095:127.0.0.1:19095 ruvpn
```

Then browse to `http://127.0.0.1:19095`.

## Optional Xray User Backups

Xray user configuration can be backed up daily from the monitoring VM. The
monitoring host creates a dedicated SSH key, RU authorizes that key, and the
timer pulls:

- `xray_clients_path`, default `/usr/local/etc/xray/clients.json`
- `xray_config_path`, default `/usr/local/etc/xray/config.json`

Enable it in `ansible/group_vars/all/local.yml`:

```yaml
xray_user_backup_enabled: true
xray_user_backup_root: /backup/xray-users
xray_user_backup_interval: daily
xray_user_backup_retention_days: 30
```

Apply:

```bash
make apply-xray-backup
```

Backups are stored on the monitoring host:

```text
/backup/xray-users/<ru-host>/<timestamp>/
├── clients.json
├── config.json
└── SHA256SUMS
```

The `latest` symlink points to the newest backup.

Restore after service loss on RU:

```bash
backup=/backup/xray-users/ruvpn/latest
scp "${backup}/clients.json" ruvpn:/usr/local/etc/xray/clients.json
scp "${backup}/config.json" ruvpn:/usr/local/etc/xray/config.json
ssh ruvpn 'xray run -test -config /usr/local/etc/xray/config.json'
ssh ruvpn 'systemctl restart xray xray-user-ui'
```

After restoring, run `make apply-ru` once from the repository. Ansible will read
the restored `clients.json` and keep UI-created users intact.

## Optional WireGuard Transport Obfuscation

Default mode is plain WireGuard:

```yaml
wg_transport: direct
```

Experimental udp2raw transport can be enabled in `ansible/group_vars/all/local.yml`:

```yaml
wg_transport: udp2raw
wg_udp2raw_install: true
wg_udp2raw_public_port: 4433
wg_udp2raw_local_port: 51821
wg_udp2raw_raw_mode: faketcp
wg_udp2raw_mtu: 1200
wg_udp2raw_extra_args:
  - --fix-gro
```

The role installs `/usr/local/bin/udp2raw` automatically when `wg_udp2raw_install: true` and the binary is missing. Override the download source if you pin releases or mirror assets:

```yaml
wg_udp2raw_download_url: https://github.com/wangyu-/udp2raw-tunnel/releases/latest/download/udp2raw_binaries.tar.gz
```

The shared `wg_udp2raw_password` is generated by:

```bash
make secrets
# or
make secrets-remote
```

In udp2raw mode, the RU WireGuard peer endpoint becomes `127.0.0.1:wg_udp2raw_local_port`; udp2raw carries that traffic to the Non-RU host, where it forwards to the local WireGuard port.

The role automatically overrides WireGuard MTU to `wg_udp2raw_mtu` in udp2raw mode. This is intentionally lower than plain WireGuard because udp2raw adds transport overhead; too-large packets can make HTTPS traffic hang while small pings still work. The default extra argument `--fix-gro` avoids Linux GRO/GSO packet aggregation from producing oversized udp2raw packets.

## Optional RU Host Service Egress

By default, only explicitly proxied/marked traffic uses the Non-RU exit route. To let the RU host itself use the Non-RU internet for system needs such as package updates, DNS, and NTP, enable local service egress:

```yaml
common_apt_manage_force_ipv4: true
routing_ru_service_egress_enabled: true
routing_ru_service_egress_tcp_ports:
  - 80
  - 443
  - 53
routing_ru_service_egress_udp_ports:
  - 53
  - 123

dns_non_ru_forwarder_enabled: true
dns_non_ru_filter_aaaa: true
dns_ru_manage_resolv_conf: true
dns_ru_nameservers:
  - "{{ wg_non_ru_ip }}"
```

When enabled, the RU nftables ruleset marks local IPv4 `OUTPUT` packets for these destination ports with `routing_mark`; the existing policy routing rule then sends them through `routing_table`, and marked local packets are SNATed to `wg_ru_ip`. Private, loopback, documentation, multicast, reserved ranges, and the RU/Non-RU/WireGuard endpoint addresses are excluded so management and tunnel control traffic keep using the normal route.

DNS is handled by a small `dnsmasq` forwarder on the Non-RU host, bound only to `wg_non_ru_ip`. RU can then use `wg_non_ru_ip` as its resolver. `dns_non_ru_filter_aaaa` is useful for IPv4-only WireGuard tunnels because it prevents system tools such as apt from trying unreachable IPv6 addresses first.

## WireGuard Speed Tests

The `wg_speedtest` role installs an `iperf3` server bound only to each host's WireGuard IP and a helper script:

```bash
wg-speedtest
```

The script can be run on either side. It pings the opposite WireGuard IP, then runs forward and reverse iperf3 tests. From the operator machine:

```bash
make speed-ru
make speed-non-ru
```

Useful variables:

```yaml
wg_speedtest_enabled: true
wg_speedtest_port: 5201
wg_speedtest_duration: 10
wg_speedtest_parallel: 1
wg_speedtest_reverse: true
```

## Optional Monitoring

The monitoring stack is intentionally lightweight and can run either on the
Non-RU node or on a separate VM:

- `prometheus-node-exporter` on RU and Non-RU for CPU, RAM, disk, load, and
  textfile metrics.
- `prometheus-node-exporter` on the monitoring server itself for CPU, RAM, disk,
  and load alerts on the monitoring VM.
- custom WireGuard textfile metrics for handshake age, transfer counters, and
  tunnel ping.
- periodic iperf3 speedtest metrics through WireGuard.
- Prometheus for scraping and alert evaluation.
- blackbox_exporter for TCP/ICMP probes.
- Alertmanager plus a small Telegram webhook relay for notifications.

On a small `1 vCPU / 1 GiB RAM` Non-RU node this fits only if you keep the stack
minimal: do not install Grafana by default, keep Prometheus retention short, and
bind services to localhost/WireGuard addresses. If the node already runs other
containers or browsers, a dedicated monitoring VM is cleaner.

Enable monitoring on the Non-RU node:

```yaml
monitoring_server_hosts: non_ru
monitoring_server_enabled: true
monitoring_exporter_enabled: true
monitoring_telegram_enabled: true
```

Put Telegram secrets into `ansible/group_vars/all/vault.yml`, not into
`local.yml`:

```yaml
monitoring_telegram_bot_token: "CHANGEME"
monitoring_telegram_chat_id: "CHANGEME"
```

To use a dedicated monitoring VM, add a `monitoring` group to inventory and set:

```yaml
monitoring_server_hosts: monitoring
monitoring_scrape_source_ips:
  - 198.51.100.20
```

`monitoring_scrape_source_ips` should contain the IP address that RU/Non-RU see
as the source of Prometheus requests. For a standalone public VM this is usually
the VM public IPv4 address. For a private monitoring peer, use its WireGuard IP.

If the dedicated monitoring VM is not a WireGuard peer, scrape node exporters via
public server IPs and keep access restricted with `monitoring_scrape_source_ips`:

```yaml
monitoring_node_targets:
  - name: ru
    address: "{{ ru_public_ip }}:{{ monitoring_node_exporter_port }}"
  - name: non_ru
    address: "{{ non_ru_public_ip }}:{{ monitoring_node_exporter_port }}"
monitoring_blackbox_tcp_targets:
  - name: xray_ru
    address: "{{ ru_public_ip }}:{{ xray_port }}"
monitoring_blackbox_icmp_targets: []
```

WireGuard tunnel state is still monitored through node_exporter textfile metrics
generated locally on RU and Non-RU. To run blackbox probes against WireGuard IPs
from a dedicated VM, add that VM as a restricted WireGuard peer instead.

The default monitoring server ports are project-specific to avoid conflicts with
existing services:

```yaml
monitoring_prometheus_port: 19090
monitoring_alertmanager_port: 19093
monitoring_blackbox_port: 19115
monitoring_ui_port: 19094
```

The built-in monitoring UI shows all Prometheus series used by alert rules:
node availability, CPU load, RAM, root disk, WireGuard handshake/ping/speedtest,
and blackbox probe status. It is bound to localhost by default. Open it through
an SSH tunnel:

```bash
ssh -L 19094:127.0.0.1:19094 monitoring01
```

Then browse to `http://127.0.0.1:19094`.

To expose the UI through a public domain, enable the Nginx reverse proxy:

```yaml
monitoring_public_enabled: true
monitoring_public_domain: monitoring.example.com
monitoring_public_letsencrypt_email: admin@example.com
monitoring_public_basic_auth_user: admin
```

Store the Basic Auth password in vault:

```yaml
monitoring_public_basic_auth_password: "CHANGEME"
```

The role keeps the UI and Prometheus bound to localhost, exposes only Nginx,
uses HTTP-01 through `monitoring_public_acme_root`, then redirects HTTP to HTTPS
after the Let's Encrypt certificate is issued.

Apply:

```bash
make plan-monitoring
make apply-monitoring
```

Telegram parameters:

- `monitoring_telegram_enabled`: enable Alertmanager Telegram notifications;
  this can live in `local.yml`.
- `monitoring_telegram_bot_token`: bot token from `@BotFather`; store it in
  vault.
- `monitoring_telegram_chat_id`: target user, group, or channel chat ID; store
  it in vault if you do not want the chat ID public.
- `monitoring_telegram_api_url`: Telegram API URL, default
  `https://api.telegram.org`.
- `monitoring_telegram_parse_mode`: default `HTML`.

Recommended extra checks for a fuller setup:

- Xray process health and accepted connection rate.
- TLS/Reality TCP probe from outside the servers.
- DNS resolver health on RU and Non-RU.
- apt security update freshness.
- systemd failed units.
- log-based alerts for repeated Xray or udp2raw errors.
- Prometheus remote_write or backups if metrics history matters.
- Grafana on a separate monitoring VM if dashboards are needed.

Verification:

```bash
make verify-ru
make verify-non-ru
```

## Checks

```bash
make check
```

## Notes

The Non-RU firewall role uses a separate nftables overlay service and does not flush the whole ruleset. This avoids disrupting Docker or pre-existing WireGuard interfaces on the exit node.

## License

MIT. See `../LICENSE`.
