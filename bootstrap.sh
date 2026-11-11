#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

command -v ansible-vault >/dev/null 2>&1 || error "ansible-vault not found."
command -v ansible >/dev/null 2>&1 || error "ansible not found."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

VAULT_PASS_FILE="$ROOT_DIR/.vault_pass"
VAULT_YML="inventories/production/group_vars/all/vault.yml"
VAULT_EXAMPLE="inventories/production/group_vars/all/vault.yml.example"
HOSTS_YML="inventories/production/hosts.yml"
MAIN_YML="inventories/production/group_vars/all/main.yml"
MAIN_EXAMPLE="inventories/production/group_vars/all/main.yml.example"
KEYS_PUB="roles/users/files/authorized_keys.pub"
KEYS_EXAMPLE="roles/users/files/authorized_keys.pub.example"

# ---------------------------------------------------------------
# 0. Install dependencies
# ---------------------------------------------------------------
info "Installing Ansible collections from requirements.yml..."
[[ -f requirements.yml ]] || error "requirements.yml not found."
ansible-galaxy collection install -r requirements.yml

# ---------------------------------------------------------------
# 1. Ansible-vault password
# ---------------------------------------------------------------
if [[ -f "$VAULT_PASS_FILE" ]]; then
    warn ".vault_pass already exists, using it."
else
    while true; do
        read -rsp "Enter password for ansible-vault (vault_pass): " VAULT_PASS; echo
        read -rsp "Repeat password: " VAULT_PASS2; echo
        [[ "$VAULT_PASS" == "$VAULT_PASS2" ]] && break
        warn "Passwords do not match, try again."
    done
    echo "$VAULT_PASS" > "$VAULT_PASS_FILE"
    chmod 600 "$VAULT_PASS_FILE"
    info ".vault_pass created."
fi

export ANSIBLE_VAULT_PASSWORD_FILE="$VAULT_PASS_FILE"

# ---------------------------------------------------------------
# 2. vault.yml from example
# ---------------------------------------------------------------
[[ -f "$VAULT_EXAMPLE" ]] || error "Missing $VAULT_EXAMPLE"

if [[ -f "$VAULT_YML" ]]; then
    warn "$VAULT_YML already exists, skipping."
    read -rp "Admin username [admin]: " ADMIN_USER
    ADMIN_USER="${ADMIN_USER:-admin}"
else
    read -rp "Admin username [admin]: " ADMIN_USER
    ADMIN_USER="${ADMIN_USER:-admin}"

    while true; do
        read -rsp "Enter password for user $ADMIN_USER: " ADMIN_PASS; echo
        read -rsp "Repeat password: " ADMIN_PASS2; echo
        [[ "$ADMIN_PASS" == "$ADMIN_PASS2" ]] && break
        warn "Passwords do not match, try again."
    done

    ADMIN_HASH=$(ansible localhost -i localhost, -c local -m ansible.builtin.debug \
        -a "msg={{ '$ADMIN_PASS' | password_hash('sha512') }}" \
        | grep -o '\$6\$[^"]*' | head -n1)

    [[ -n "$ADMIN_HASH" ]] || error "Failed to generate password hash."

    sed "s|vault_admin_password_hash:.*|vault_admin_password_hash: \"$ADMIN_HASH\"|" \
        "$VAULT_EXAMPLE" > "$VAULT_YML"

    ansible-vault encrypt "$VAULT_YML"
    info "$VAULT_YML created and encrypted."
fi

# ---------------------------------------------------------------
# 3. main.yml from example
# ---------------------------------------------------------------
[[ -f "$MAIN_EXAMPLE" ]] || error "Missing $MAIN_EXAMPLE"

if [[ -f "$MAIN_YML" ]]; then
    warn "$MAIN_YML already exists, skipping."
else
    read -rp "SWAP size in GB [2]: " SWAP_SIZE
    SWAP_SIZE="${SWAP_SIZE:-2}"

    read -rp "SSH port [1111]: " SSH_PORT
    SSH_PORT="${SSH_PORT:-1111}"

    cat > "$MAIN_YML" <<EOF
---
swap_size_gb: $SWAP_SIZE
ssh_port: $SSH_PORT
admin_user: $ADMIN_USER
EOF
    info "$MAIN_YML created."
fi

# ---------------------------------------------------------------
# 4. Collect VPS list
# ---------------------------------------------------------------
if [[ -f "$HOSTS_YML" ]]; then
    warn "$HOSTS_YML already exists, skipping host collection."
else
    declare -a VPS_NAMES=()
    declare -a VPS_HOSTS=()
    declare -a VPS_USERS=()
    declare -a VPS_AUTHS=()

    echo
    info "Add VPS hosts. Leave name empty to finish."
    while true; do
        echo
        read -rp "Host name (e.g. vps1, vps2) [empty to finish]: " VPS_NAME
        [[ -z "$VPS_NAME" ]] && break

        for existing in "${VPS_NAMES[@]:-}"; do
            [[ "$existing" == "$VPS_NAME" ]] && { warn "Host '$VPS_NAME' already added."; continue 2; }
        done

        read -rp "  IP or hostname: " VPS_HOST
        [[ -z "$VPS_HOST" ]] && { warn "IP cannot be empty, skipping."; continue; }

        read -rp "  SSH user [root]: " VPS_USER
        VPS_USER="${VPS_USER:-root}"

        if [[ "$VPS_USER" == "root" ]]; then
            read -rsp "  Root password: " VPS_PASS; echo
            AUTH_BLOCK="          ansible_password: \"$VPS_PASS\""
        else
            read -rp "  Path to private SSH key [~/.ssh/id_ed25519]: " VPS_KEY
            VPS_KEY="${VPS_KEY:-$HOME/.ssh/id_ed25519}"
            VPS_KEY="${VPS_KEY/#\~/$HOME}"
            AUTH_BLOCK="          ansible_ssh_private_key_file: $VPS_KEY"
        fi

        VPS_NAMES+=("$VPS_NAME")
        VPS_HOSTS+=("$VPS_HOST")
        VPS_USERS+=("$VPS_USER")
        VPS_AUTHS+=("$AUTH_BLOCK")
        info "Host '$VPS_NAME' added."
    done

    [[ ${#VPS_NAMES[@]} -eq 0 ]] && error "No hosts added."

    # Generate hosts.yml
    {
        echo "---"
        echo "all:"
        echo "  children:"
        echo "    vps_server:"
        echo "      hosts:"
        for i in "${!VPS_NAMES[@]}"; do
            echo "        ${VPS_NAMES[$i]}:"
            echo "          ansible_host: ${VPS_HOSTS[$i]}"
            echo "          ansible_user: ${VPS_USERS[$i]}"
            echo "${VPS_AUTHS[$i]}"
            echo "          ansible_python_interpreter: /usr/bin/python3"
        done
    } > "$HOSTS_YML"

    info "$HOSTS_YML created (${#VPS_NAMES[@]} host(s))."
fi

# ---------------------------------------------------------------
# 5. authorized_keys.pub from example
# ---------------------------------------------------------------
if [[ -f "$KEYS_EXAMPLE" && ! -f "$KEYS_PUB" ]]; then
    warn "File $KEYS_PUB is missing."
    read -rp "Open $KEYS_PUB to insert keys now? [y/N]: " EDIT_NOW
    if [[ "$EDIT_NOW" =~ ^[Yy]$ ]]; then
        cp "$KEYS_EXAMPLE" "$KEYS_PUB"
        "${EDITOR:-vi}" "$KEYS_PUB"
        info "$KEYS_PUB created."
    else
        warn "Remember to create $KEYS_PUB before running the playbook."
    fi
fi

# ---------------------------------------------------------------
# 6. Syntax check
# ---------------------------------------------------------------
info "Checking playbook syntax..."
ansible-playbook playbooks/site.yml --syntax-check

info "Done. To run:"
echo "  ansible-playbook playbooks/site.yml --ask-become-pass"
echo "  or selectively: ansible-playbook playbooks/site.yml --limit vps1 --ask-become-pass"
