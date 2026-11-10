# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of standalone Ansible playbooks for provisioning Ubuntu 24.04+ servers: a monitoring stack (Node Exporter + Mosquitto Exporter + Prometheus + Grafana), Docker, and a BeaconTower dev environment (`btk3s`). Each playbook is fully self-contained in its own directory.

## Running a playbook

Every playbook directory has a `run.sh` wrapper. Run it from the playbook's directory:

```bash
cd <playbook-dir>
./run.sh -h <host> -u <user> -p <password> [-s]
```

- `-s` is required on **Ubuntu 26+** targets: those ship `sudo-rs` by default, which breaks Ansible's privilege escalation. The flag switches `ansible_become_exe` to `/usr/bin/sudo.ws` (the classic C sudo still present on those systems).

No `ansible.cfg` inventory file setup is needed — inventory is passed inline as `"${HOST},"`.

Playbook-specific flags:
- `mosquittoexporter`: optional `-m <mqtt-user>` / `-w <mqtt-password>` for the broker; written to `/etc/mosquitto-exporter.env` and loaded by the systemd unit via `EnvironmentFile`.
- `btk3s`: `-l <lima-instance>` as an alternative to `-h/-u/-p`. It targets a Lima VM through `~/.lima/<instance>/ssh.config` (key auth, no password), then closes Lima's persistent SSH master connection so new shells pick up the new `docker` group membership.

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

`btk3s` deviates: `tasks/main.yml` sets shared facts and then `import_tasks` one file per component (`inotify.yml` — writes the inotify sysctl limits before the apt upgrade, `certs.yml` — installs `btk3s/certs/*.crt` into the system trust store right after the apt upgrade, `docker.yml`, `azure_cli.yml`, `dotnet.yml`, `apparmor.yml` — installs the containerd AppArmor profile override from `btk3s/APPARMOR.md` before k3s starts, `k3s.yml`, `k9s.yml`, `helm.yml`, `flux.yml`, `step.yml`, `claude.yml`, `btk3s.yml`, `git.yml`), and it has no `templates/` or `files/` (CA certs live in `btk3s/certs/`, outside the role).

**Key design choices:**
- Binary installs (Prometheus, Node Exporter) check the currently installed version before downloading; re-running is idempotent and skips downloads if the version matches.
- Mosquitto Exporter has no release binaries: it is built from source with `go install` (installs `golang-go`), and is skipped when `mosquitto-exporter --version` already matches `mosquitto_exporter_version`.
- Prometheus config changes trigger a `reload` (SIGHUP); binary/service changes trigger a full `restart`.
- The Grafana role provisions both datasources and dashboards via Grafana's file-based provisioning (files dropped into `/etc/grafana/provisioning/`). Dashboards shipped in `files/`: Node Exporter and Mosquitto.
- `btk3s` provisions for the SSH login user, not root: it resolves the user/home with `become: false` (`dev_user` / `dev_home` facts) and installs per-user tools (Claude CLI, btk3s) into `~/.local/bin`.

## Configuring scrape targets

Edit `prometheus/playbook/roles/prometheus/defaults/main.yml` → `prometheus_scrape_configs`, then re-run the prometheus playbook. The config is validated by `promtool check config` before being applied.

## Typical deployment order

1. `nodeexporter` — on every host to monitor
2. `mosquittoexporter` — on each MQTT broker host
3. `prometheus` — on the monitoring server (add exporter targets first)
4. `grafana` — on the monitoring server
5. `dockerinstall` — on any host that needs Docker

`btk3s` is independent of the monitoring stack (it installs its own Docker).

## Supported architectures

Prometheus and Node Exporter tasks detect the CPU architecture (`amd64` / `arm64` / `armv7`) and fetch the matching release binary from GitHub. `btk3s` handles only `amd64` / `arm64` (`dev_arch`). Mosquitto Exporter is compiled on the target, so it doesn't need an architecture mapping.
