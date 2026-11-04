#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 -l <lima-instance> [-s]"
    echo "       $0 -h <host> -u <user> -p <password> [-s]"
    echo ""
    echo "  -l  Lima instance name (uses ~/.lima/<instance>/ssh.config, key auth)"
    echo "  -h  Target host (IP or hostname)"
    echo "  -u  SSH user"
    echo "  -p  SSH password"
    echo "  -s  Use /usr/bin/sudo.ws (workaround for Ubuntu 26 sudo-rs)"
    echo ""
    echo "Examples:"
    echo "  $0 -l btk3s"
    echo "  $0 -h 192.168.1.100 -u ubuntu -p mypassword"
    exit 1
}

LIMA_INSTANCE=""
HOST=""
USER=""
PASSWORD=""
USE_SUDO_WS=0

while getopts "l:h:u:p:s" opt; do
    case "$opt" in
        l) LIMA_INSTANCE="$OPTARG" ;;
        h) HOST="$OPTARG" ;;
        u) USER="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        s) USE_SUDO_WS=1 ;;
        *) usage ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXTRA_ARGS=()
if [[ "$USE_SUDO_WS" -eq 1 ]]; then
    EXTRA_ARGS+=(-e "ansible_become_exe=/usr/bin/sudo.ws")
fi

if [[ -n "$LIMA_INSTANCE" ]]; then
    SSH_CONFIG="${LIMA_DIR:-$HOME/.lima}/${LIMA_INSTANCE}/ssh.config"
    if [[ ! -f "$SSH_CONFIG" ]]; then
        echo "Error: $SSH_CONFIG not found. Is the Lima instance '${LIMA_INSTANCE}' running?"
        exit 1
    fi
    ansible-playbook \
        -i "lima-${LIMA_INSTANCE}," \
        -e "ansible_ssh_common_args='-F ${SSH_CONFIG}'" \
        ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
        "${SCRIPT_DIR}/playbook/site.yml"
    # Lima multiplexes `limactl shell` over a persistent SSH master connection,
    # so new shells inherit its stale group list (e.g. missing "docker").
    # Close it so the next shell logs in fresh with the new group memberships.
    ssh -F "$SSH_CONFIG" -O exit "lima-${LIMA_INSTANCE}" 2>/dev/null || true
    exit 0
fi

if [[ -z "$HOST" || -z "$USER" || -z "$PASSWORD" ]]; then
    echo "Error: Either -l, or all of -h, -u, -p are required."
    echo ""
    usage
fi

ansible-playbook \
    -i "${HOST}," \
    -u "$USER" \
    -e "ansible_password=${PASSWORD}" \
    -e "ansible_become_password=${PASSWORD}" \
    -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
    "${SCRIPT_DIR}/playbook/site.yml"
