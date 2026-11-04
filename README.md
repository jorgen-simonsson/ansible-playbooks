# Ansible Playbooks

A collection of Ansible playbooks for provisioning and monitoring Ubuntu 24.04 servers.

## Playbooks

| Playbook | Description | Default Port |
|----------|-------------|-------------|
| **dockerinstall** | Installs Docker CE, CLI, Buildx, and Compose plugin | — |
| **nodeexporter** | Installs Prometheus Node Exporter as a systemd service | 9100 |
| **mosquittoexporter** | Installs Prometheus Mosquitto Exporter as a systemd service | 9234 |
| **prometheus** | Installs Prometheus server with configurable scrape targets | 9090 |
| **grafana** | Installs Grafana with auto-provisioned Prometheus datasource and Node Exporter dashboard | 3000 |
| **btk3s** | BeaconTower dev environment: Docker, Azure CLI, btop, k3s, k9s, Claude CLI, btk3s, git + hemflex clone | — |

## Prerequisites

- **Ansible** installed on the control machine:
  ```bash
  pipx install --include-deps ansible
  ```
- **sshpass** for password-based SSH authentication:
  ```bash
  sudo apt install -y sshpass
  ```
- SSH access to the target host(s)

## Usage

Each playbook includes a `run.sh` script that takes three parameters:

```bash
./run.sh -h <host> -u <user> -p <password> [-s]
```

| Flag | Description |
|------|-------------|
| `-h` | Target host (IP address or hostname) |
| `-u` | SSH user |
| `-p` | SSH password (also used for sudo) |
| `-s` | Optional. Use `/usr/bin/sudo.ws` instead of the default `sudo`. Required for **Ubuntu 26+** targets, which ship `sudo-rs` (Rust rewrite) as the default `sudo`. `sudo-rs` does not fully support the `-p` flag that Ansible uses to detect the password prompt, causing privilege escalation to time out. The traditional C sudo is still available at `/usr/bin/sudo.ws`. |

### Install Docker

```bash
cd dockerinstall
./run.sh -h myserver -u ubuntu -p mypassword
```

Installs Docker CE from the official Docker repository. The SSH user is automatically added to the `docker` group (log out and back in for it to take effect).

### Install Node Exporter

```bash
cd nodeexporter
./run.sh -h myserver -u ubuntu -p mypassword
```

Downloads and installs Prometheus Node Exporter as a systemd service. Metrics are exposed at `http://<host>:9100/metrics`.

**Configurable variables** in `nodeexporter/playbook/roles/node_exporter/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `node_exporter_version` | `1.8.2` | Version to install |
| `node_exporter_listen_address` | `0.0.0.0:9100` | Listen address and port |

### Install Mosquitto Exporter

```bash
cd mosquittoexporter
./run.sh -h myserver -u ubuntu -p mypassword -m mqttuser -w mqttpassword
```

Builds and installs the [sapcc/mosquitto-exporter](https://github.com/sapcc/mosquitto-exporter) from source (requires `golang-go` on the target, installed automatically). The exporter subscribes to Mosquitto's `$SYS/#` topic tree and exposes broker metrics at `http://<host>:9234/metrics`.

MQTT credentials are stored in `/etc/mosquitto-exporter.env` (mode 0600, root-only) and never written to the systemd unit file.

**Flags:**

| Flag | Description |
|------|-------------|
| `-m` | MQTT broker username (optional) |
| `-w` | MQTT broker password (optional) |

**Configurable variables** in `mosquittoexporter/playbook/roles/mosquitto_exporter/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `mosquitto_exporter_version` | `0.8.0` | Version to build and install |
| `mosquitto_exporter_listen_address` | `0.0.0.0:9234` | Listen address and port |
| `mosquitto_exporter_broker_endpoint` | `tcp://127.0.0.1:1883` | MQTT broker endpoint |
| `mosquitto_exporter_mqtt_user` | `""` | MQTT username (set via `-m` flag) |
| `mosquitto_exporter_mqtt_password` | `""` | MQTT password (set via `-w` flag) |

**Note:** Mosquitto must have `sys_interval` set to a non-zero value in its config (the default is 10 seconds). Verify the broker is publishing stats with:
```bash
mosquitto_sub -u <user> -P <password> -t '$SYS/#' -v -C 5
```

After deploying, add a scrape target in `prometheus/playbook/roles/prometheus/defaults/main.yml`:
```yaml
- job_name: "mosquitto"
  static_configs:
    - targets:
        - "myserver:9234"
```

To enable the **Mosquitto MQTT Broker** Grafana dashboard, set `grafana_provisioned_mosquitto_dashboard: true` in `grafana/playbook/roles/grafana/defaults/main.yml` and re-run the Grafana playbook. The dashboard includes panels for connected clients, subscriptions, message rates, publish rates, network throughput, and stored messages.

### Install Prometheus

```bash
cd prometheus
./run.sh -h myserver -u ubuntu -p mypassword
```

Installs Prometheus server with a web UI at `http://<host>:9090`.

**To add scrape targets**, edit `prometheus/playbook/roles/prometheus/defaults/main.yml`:

```yaml
prometheus_scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets:
          - "localhost:9090"
  - job_name: "node"
    static_configs:
      - targets:
          - "server1:9100"
          - "server2:9100"
```

Then re-run the playbook to apply.

**Configurable variables** in `prometheus/playbook/roles/prometheus/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `prometheus_version` | `2.54.1` | Version to install |
| `prometheus_listen_address` | `0.0.0.0:9090` | Listen address and port |
| `prometheus_retention_time` | `30d` | Data retention period |
| `prometheus_global_scrape_interval` | `15s` | How often to scrape targets |

### Install Grafana

```bash
cd grafana
./run.sh -h myserver -u ubuntu -p mypassword
```

Installs Grafana with a web UI at `http://<host>:3000`. Default login is **admin / admin**.

Comes pre-configured with:
- A **Prometheus datasource** pointing to `localhost:9090`
- A **Node Exporter Overview dashboard** with CPU, memory, disk, and network panels

**Configurable variables** in `grafana/playbook/roles/grafana/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `grafana_http_port` | `3000` | Listen port |
| `grafana_admin_user` | `admin` | Admin username |
| `grafana_admin_password` | `admin` | Admin password |
| `grafana_datasources` | Prometheus on localhost:9090 | List of datasources to provision |
| `grafana_plugins` | `[]` | Grafana plugins to install |

### Install btk3s Development Environment

```bash
cd btk3s
./run.sh -l btk3s                                  # Lima VM named "btk3s"
./run.sh -h myserver -u ubuntu -p mypassword       # any other Ubuntu host
```

Provisions a BeaconTower development environment. The `-l <instance>` flag targets a [Lima](https://lima-vm.io) VM using the SSH config Lima generates at `~/.lima/<instance>/ssh.config` (key-based auth, no password needed).

Installs, in order:
1. `apt update` + `apt upgrade`
2. Docker CE (SSH user added to the `docker` group)
3. Azure CLI (`az`)
4. btop
5. k3s (with Traefik disabled, kubeconfig mode `644`; `KUBECONFIG` is exported in the user's `~/.bashrc`)
6. k9s
7. Claude CLI (to `~/.local/bin/claude`)
8. btk3s binary (to `~/.local/bin/btk3s`)
9. Git identity (`72338` / `jorgen.simonsson@eon.se`), on-disk credential store, and a clone of `hemflex` into `~/Projects` (prompts for GitLab username and password)

**Configurable variables** in `btk3s/playbook/roles/btk3s/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `btk3s_version` | `btk3s-v0.7.4` | Release tag from `beacontower/tools` |
| `k3s_install_exec` | `--disable traefik` | `INSTALL_K3S_EXEC` passed to the k3s installer |
| `k3s_kubeconfig_mode` | `644` | `K3S_KUBECONFIG_MODE` passed to the k3s installer |
| `k9s_version` | `latest` | k9s release tag, or `latest` (only installed if missing) |
| `docker_apt_codename` / `azure_cli_apt_codename` | host's Ubuntu codename | Override if a vendor repo lacks packages for a new Ubuntu release |

Re-running is idempotent: k3s and Claude CLI are skipped if already installed, and btk3s is only re-downloaded when `btk3s version` doesn't match `btk3s_version`.

## Typical Setup Order

1. Install **Node Exporter** on all machines you want to monitor
2. Install **Mosquitto Exporter** on the host running the Mosquitto broker
3. Install **Prometheus** on your monitoring server, adding all node exporter and mosquitto exporter targets
4. Install **Grafana** on the same (or different) server to visualize metrics
5. Optionally install **Docker** on any hosts that need it

## Project Structure

```
ansible-playbooks/
├── dockerinstall/
│   ├── run.sh
│   └── playbook/
│       ├── site.yml
│       └── roles/docker/
├── nodeexporter/
│   ├── run.sh
│   └── playbook/
│       ├── site.yml
│       └── roles/node_exporter/
├── mosquittoexporter/
│   ├── run.sh
│   └── playbook/
│       ├── site.yml
│       └── roles/mosquitto_exporter/
├── prometheus/
│   ├── run.sh
│   └── playbook/
│       ├── site.yml
│       └── roles/prometheus/
├── grafana/
│   ├── run.sh
│   └── playbook/
│       ├── site.yml
│       └── roles/grafana/
└── btk3s/
    ├── run.sh
    └── playbook/
        ├── site.yml
        └── roles/btk3s/
```
