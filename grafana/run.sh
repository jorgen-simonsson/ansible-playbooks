#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 -h <host> -u <user> -p <password> [-s]"
    echo ""
    echo "  -h  Target host (IP or hostname)"
    echo "  -u  SSH user"
    echo "  -p  SSH password"
    echo "  -s  Use /usr/bin/sudo.ws (workaround for Ubuntu 26 sudo-rs)"
    echo ""
    echo "Example:"
    echo "  $0 -h 192.168.1.100 -u ubuntu -p mypassword"
    exit 1
}

HOST=""
USER=""
PASSWORD=""
USE_SUDO_WS=0

while getopts "h:u:p:s" opt; do
    case "$opt" in
        h) HOST="$OPTARG" ;;
        u) USER="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        s) USE_SUDO_WS=1 ;;
        *) usage ;;
    esac
done

if [[ -z "$HOST" || -z "$USER" || -z "$PASSWORD" ]]; then
    echo "Error: All parameters (-h, -u, -p) are required."
    echo ""
    usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXTRA_ARGS=()
if [[ "$USE_SUDO_WS" -eq 1 ]]; then
    EXTRA_ARGS+=(-e "ansible_become_exe=/usr/bin/sudo.ws")
fi

ansible-playbook \
    -i "${HOST}," \
    -u "$USER" \
    -e "ansible_password=${PASSWORD}" \
    -e "ansible_become_password=${PASSWORD}" \
    -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
    "${SCRIPT_DIR}/playbook/site.yml"
