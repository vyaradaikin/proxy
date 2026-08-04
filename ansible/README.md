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
