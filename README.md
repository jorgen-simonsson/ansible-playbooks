# Ansible Playbooks

A collection of Ansible playbooks for provisioning and monitoring Ubuntu 24.04 servers.

## Playbooks

| Playbook | Description | Default Port |
|----------|-------------|-------------|
| **dockerinstall** | Installs Docker CE, CLI, Buildx, and Compose plugin | — |
| **nodeexporter** | Installs Prometheus Node Exporter as a systemd service | 9100 |
| **prometheus** | Installs Prometheus server with configurable scrape targets | 9090 |
| **grafana** | Installs Grafana with auto-provisioned Prometheus datasource and Node Exporter dashboard | 3000 |

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

## Typical Setup Order

1. Install **Node Exporter** on all machines you want to monitor
2. Install **Prometheus** on your monitoring server, adding all node exporter targets
3. Install **Grafana** on the same (or different) server to visualize metrics
4. Optionally install **Docker** on any hosts that need it

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
├── prometheus/
│   ├── run.sh
│   └── playbook/
│       ├── site.yml
│       └── roles/prometheus/
└── grafana/
    ├── run.sh
    └── playbook/
        ├── site.yml
        └── roles/grafana/
```
