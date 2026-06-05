# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of standalone Ansible playbooks for provisioning Ubuntu 24.04 servers with a monitoring stack (Node Exporter + Prometheus + Grafana) and Docker. Each playbook is fully self-contained in its own directory.

## Running a playbook

Every playbook directory has a `run.sh` wrapper. Run it from the playbook's directory:

```bash
cd <playbook-dir>
./run.sh -h <host> -u <user> -p <password> [-s]
```

- `-s` is required on **Ubuntu 26+** targets: those ship `sudo-rs` by default, which breaks Ansible's privilege escalation. The flag switches `ansible_become_exe` to `/usr/bin/sudo.ws` (the classic C sudo still present on those systems).

No `ansible.cfg` inventory file setup is needed — inventory is passed inline as `"${HOST},"`.

## Prerequisites (control machine)

```bash
pipx install --include-deps ansible
sudo apt install -y sshpass   # for password-based SSH
```

## Architecture

Each playbook follows the same layout:

```
<name>/
├── run.sh                          # entry point, passes credentials to ansible-playbook
└── playbook/
    ├── ansible.cfg
    ├── inventory.ini               # unused at runtime; run.sh passes host inline
    ├── site.yml                    # imports the single role
    └── roles/<role>/
        ├── defaults/main.yml       # all tunable variables with defaults
        ├── handlers/main.yml
        ├── tasks/main.yml
        ├── templates/              # Jinja2 config files (.j2)
        └── files/                  # static assets (e.g. Grafana dashboard JSON)
```

**Key design choices:**
- Binary installs (Prometheus, Node Exporter) check the currently installed version before downloading; re-running is idempotent and skips downloads if the version matches.
- Prometheus config changes trigger a `reload` (SIGHUP); binary/service changes trigger a full `restart`.
- The Grafana role provisions both datasources and dashboards via Grafana's file-based provisioning (files dropped into `/etc/grafana/provisioning/`).

## Configuring scrape targets

Edit `prometheus/playbook/roles/prometheus/defaults/main.yml` → `prometheus_scrape_configs`, then re-run the prometheus playbook. The config is validated by `promtool check config` before being applied.

## Typical deployment order

1. `nodeexporter` — on every host to monitor
2. `prometheus` — on the monitoring server (add node exporter targets first)
3. `grafana` — on the monitoring server
4. `dockerinstall` — on any host that needs Docker

## Supported architectures

Prometheus and Node Exporter tasks detect the CPU architecture (`amd64` / `arm64` / `armv7`) and fetch the matching release binary from GitHub.
