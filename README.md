# VPS Setup Ansible

Ansible playbook for initial configuration of a Debian 13 VPS.

## What is configured

- `base` — package updates, swap, BBR, /etc/hosts
- `journald` — persistent journal, 500M limit
- `users` — `admin` user, zsh + oh-my-zsh, authorized_keys (YubiKey)
- `ssh_hardening` — port 2022, disable root/password auth, clean sshd_config.d
- `firewall` — nftables
- `fail2ban` — SSH jail via nftables
- `unattended_upgrades` — automatic security updates
- `docker` — Docker CE, compose plugin, registry mirrors

## Requirements

- Ansible >= 2.15
- Collections from `requirements.yml`

## Install collections

```bash
ansible-galaxy collection install -r requirements.yml
```

## Preparation

1. Copy the example inventory:
   ```bash
   cp inventories/production/hosts.yml.example inventories/production/hosts.yml
   ```
   Edit IP, user, and port.

2. Create `vault.yml` from the example:
   ```bash
   cp inventories/production/group_vars/all/vault.yml.example \
      inventories/production/group_vars/all/vault.yml
   ansible-vault encrypt inventories/production/group_vars/all/vault.yml
   ```

3. Put your YubiKey public keys into `roles/users/files/authorized_keys.pub` (one per line).

## Usage

```bash
ansible-playbook playbooks/site.yml --ask-become-pass
```

## Idempotency check

A second run should report `changed=0`:

```bash
ansible-playbook playbooks/site.yml --ask-become-pass
```

## Structure

```
.
├── ansible.cfg
├── requirements.yml
├── inventories/production/
│   ├── hosts.yml             (not in git)
│   └── group_vars/all/
│       ├── main.yml
│       └── vault.yml         (encrypted in git)
├── playbooks/site.yml
└── roles/
    ├── base/
    ├── journald/
    ├── users/
    ├── ssh_hardening/
    ├── firewall/
    ├── fail2ban/
    ├── unattended_upgrades/
    └── docker/
```
