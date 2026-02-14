#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 -h <host> -u <user> -p <password>"
    echo ""
    echo "  -h  Target host (IP or hostname)"
    echo "  -u  SSH user"
    echo "  -p  SSH password"
    echo ""
    echo "Example:"
    echo "  $0 -h 192.168.1.100 -u ubuntu -p mypassword"
    exit 1
}

HOST=""
USER=""
PASSWORD=""

while getopts "h:u:p:" opt; do
    case "$opt" in
        h) HOST="$OPTARG" ;;
        u) USER="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$HOST" || -z "$USER" || -z "$PASSWORD" ]]; then
    echo "Error: All parameters (-h, -u, -p) are required."
    echo ""
    usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ansible-playbook \
    -i "${HOST}," \
    -u "$USER" \
    -e "ansible_password=${PASSWORD}" \
    -e "ansible_become_password=${PASSWORD}" \
    -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'" \
    "${SCRIPT_DIR}/playbook/site.yml"
