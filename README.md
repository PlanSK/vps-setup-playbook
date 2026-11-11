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

# VPS Setup Ansible

Ansible playbook for initial configuration of a Debian 13 VPS.

## What is configured

- `base` — package updates, swap, BBR, /etc/hosts
- `journald` — persistent journal, 500M limit
- `users` — admin user, zsh + oh-my-zsh, authorized_keys (YubiKey)
- `ssh_hardening` — custom SSH port, disable root/password auth, clean sshd_config.d, restore PQ defaults
- `firewall` — nftables
- `fail2ban` — SSH jail via nftables
- `unattended_upgrades` — automatic security updates, reboot at 02:00
- `docker` — Docker CE, compose plugin, registry mirrors

## Requirements

- Ansible >= 2.15 (install separately: `pacman -S ansible` / `apt install ansible`)
- Collections are installed automatically by `bootstrap.sh`

## Quick start

Make the script executable and run it:

```bash
    chmod +x bootstrap.sh
    ./bootstrap.sh
```

The script will interactively:

- install required collections from `requirements.yml`
- ask for the `ansible-vault` password and create `.vault_pass`
- generate and encrypt `vault.yml` with the admin user password hash
- generate `main.yml` (swap size, SSH port, admin user)
- collect one or more VPS hosts and generate `hosts.yml`
- prompt to fill `authorized_keys.pub`
- run `ansible-playbook --syntax-check`

Then run the playbook:

```bash
    ansible-playbook playbooks/site.yml --ask-become-pass
```

Or selectively:

```bash
    ansible-playbook playbooks/site.yml --limit vps1 --ask-become-pass
```

## Idempotency check

A second run should report `changed=0`:

```bash
    ansible-playbook playbooks/site.yml --ask-become-pass
```

## Structure

    .
    ├── ansible.cfg
    ├── bootstrap.sh
    ├── requirements.yml
    ├── inventories/production/
    │   ├── hosts.yml             (not in git)
    │   └── group_vars/all/
    │       ├── main.yml          (not in git)
    │       └── vault.yml         (encrypted, not in git)
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

## Notes

- `hosts.yml`, `main.yml`, `vault.yml` and `.vault_pass` are generated locally and excluded from git via `.gitignore`.
- Example templates (`*.example`) are committed to the repository.
- `roles/users/files/authorized_keys.pub` is excluded from git; use `authorized_keys.pub.example` as a placeholder.
