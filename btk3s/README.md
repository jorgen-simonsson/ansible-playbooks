# btk3s — BeaconTower Development Environment

Ansible playbook that provisions a BeaconTower development environment on an Ubuntu VM, typically a [Lima](https://lima-vm.io) VM named `btk3s`.

## What gets installed

The playbook runs these steps in order:

| # | Component | How | Installed to |
|---|-----------|-----|--------------|
| 1 | System updates | `apt update` + `apt upgrade` | — |
| 2 | CA certificates from `certs/*.crt` | `update-ca-certificates` | `/usr/local/share/ca-certificates` |
| 3 | btop | Ubuntu apt | system |
| 4 | Docker CE, Buildx, Compose | Official Docker apt repo | system |
| 5 | Azure CLI (`az`) | Microsoft apt repo | system |
| 6 | .NET 10 SDK (runtime + C# compiler, `dotnet` CLI) | Ubuntu apt; `ppa:dotnet/backports` on Ubuntu 24.04 | system |
| 7 | k3s | `https://get.k3s.io` installer | `/usr/local/bin/k3s` |
| 8 | k9s | GitHub release tarball | `/usr/local/bin/k9s` |
| 9 | Helm | Helm apt repo | system |
| 10 | Flux CLI | `https://fluxcd.io/install.sh` | `/usr/local/bin/flux` |
| 11 | step CLI | Smallstep apt repo | system |
| 12 | Claude CLI | `https://claude.ai/install.sh` (as login user) | `~/.local/bin/claude` |
| 13 | btk3s | GitHub release from `beacontower/tools` | `~/.local/bin/btk3s` |
| 14 | Git setup + `hemflex` clone | Global git config, credential store, `git clone` | `~/Projects/hemflex` |

The playbook also makes these changes:
- Raises the inotify limits (`fs.inotify.max_user_instances = 512`, `fs.inotify.max_user_watches = 524288`) in `/etc/sysctl.d/90-btk3s-inotify.conf`, before any of the steps above.
- Installs an override of containerd's AppArmor profile in `/etc/apparmor.d/cri-containerd.apparmor.d`, before k3s is installed. On kernel 7.0 the stock profile blocks signals inside a container, which hangs PostgreSQL's initdb. The override adds a bare `signal,` rule, which is fine for a dev VM but shouldn't be carried over to shared clusters. See [APPARMOR.md](APPARMOR.md).
- Adds the login user to the `docker` group.
- Sets the global git `user.name` / `user.email` and `credential.helper store`, and saves your GitLab credentials in `~/.git-credentials` (mode `0600`).
- Appends `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` to the login user's `~/.bashrc`, so `kubectl` and `k9s` work without extra setup.

The playbook supports both `amd64` and `arm64` targets (for example, Lima on Apple Silicon).

## Prerequisites

You need these on the control machine (your Mac or Linux host):

```bash
brew install ansible              # on macOS, or use pipx on either platform:
pipx install --include-deps ansible
brew install lima                 # if using a Lima VM
sudo apt install -y sshpass       # only for password mode (-h/-u/-p) on Linux
```

## Creating the Lima VM

If the VM doesn't exist yet, create it:

```bash
limactl create --name=btk3s --cpus=8 --memory=24 --disk=100 template:ubuntu-lts
limactl start btk3s
```

Check that it's running:

```bash
limactl list
```

## Running the playbook

Run the script from the `btk3s/` directory.

### Lima VM (recommended)

```bash
./run.sh -l btk3s
```

Lima mode uses the SSH config that Lima generates at `~/.lima/<instance>/ssh.config`. Authentication uses Lima's SSH key, and Lima users have passwordless sudo, so you don't need a password. If you've moved the Lima directory, set `LIMA_DIR`.

### GitLab credential prompts

At the start of each run the playbook asks for:

```
GitLab username (leave empty to skip saving credentials):
GitLab personal access token (scopes: read_repository, write_repository):
```

`git.eon-cds.de` doesn't accept account passwords over HTTPS, so use a **personal access token**. Create one under GitLab **User settings → Access tokens** with the scopes `read_repository` and `write_repository`.

The playbook saves these credentials in `~/.git-credentials` inside the VM, and git then uses them to clone `hemflex` and for later pulls and pushes. The password isn't echoed or logged.

If the credentials are already saved, press Enter at both prompts. The playbook keeps the existing entry, and repositories that are already cloned are skipped.

To skip the prompts entirely, for example in automation, run `ansible-playbook` directly and pass both values with `-e gitlab_user=... -e gitlab_password=...`. Values passed this way show up in your shell history and the process list.

### Any other Ubuntu host

```bash
./run.sh -h <host> -u <user> -p <password>
```

### Flags

| Flag | Description |
|------|-------------|
| `-l` | Lima instance name. Replaces `-h`/`-u`/`-p`. |
| `-h` | Target host (IP address or hostname) |
| `-u` | SSH user |
| `-p` | SSH password (also used for sudo) |
| `-s` | Use `/usr/bin/sudo.ws` instead of `sudo`. Required on **Ubuntu 26+**, which ships `sudo-rs` by default and breaks Ansible privilege escalation. |

## After provisioning

Open a new shell in the VM so the group membership, `PATH` and `KUBECONFIG` changes take effect:

```bash
limactl shell btk3s
```

Then check each tool:

```bash
docker run --rm hello-world   # Docker without sudo
kubectl get nodes             # k3s cluster (kubectl is bundled with k3s)
k9s                           # cluster TUI
helm version                  # Helm
flux --version                # Flux CLI
step version                  # step CLI
az version                    # Azure CLI
dotnet --list-sdks            # .NET SDK (should list 10.0.x)
claude --version              # Claude CLI
git config --global --list    # git identity + credential helper
ls ~/Projects/hemflex         # cloned repository
btk3s version                 # btk3s
btop                          # system monitor
```

Log in to the services that need accounts:

```bash
az login
claude                        # follow the login prompt on first start
```

## Using VS Code

Use the **Remote - SSH** extension (`ms-vscode-remote.remote-ssh`) to edit the repositories inside the VM.

### One-time setup

Make SSH on your Mac read the configs Lima generates. Add this as the **first** line of `~/.ssh/config`:

```
Include ~/.lima/*/ssh.config
```

Check that the connection works:

```bash
ssh lima-btk3s 'ls ~/Projects'
```

### Opening a repository

From the Mac terminal:

```bash
code --remote ssh-remote+lima-btk3s /home/<user>.guest/Projects/hemflex
```

Or from VS Code:

1. Open the Command Palette (`⌘⇧P`) and choose **Remote-SSH: Connect to Host…**, then **lima-btk3s**.
2. Choose **File → Open Folder** and open `~/Projects/hemflex`.

Lima names the VM home directory `/home/<user>.guest`, not `/home/<user>`.

### How it works

- The terminal, git, Docker, `kubectl`, `k9s` and `claude` all run **inside the VM**. Git uses the credentials stored in the VM's `~/.git-credentials`.
- Language extensions (C#, Go, Python, ...) must be installed on the remote side. VS Code shows an **Install in SSH: lima-btk3s** button for them.
- Ports that apps listen on in the VM are forwarded to the Mac automatically, so `http://localhost:<port>` works in your browser.

### Gotchas

- **New group memberships after a re-run**: The VS Code server in the VM keeps running between connections, so after re-running the playbook its terminals still have the old groups (for example no `docker`). Run **Remote-SSH: Kill VS Code Server on Host** and reconnect.
- **Duplicate `Host lima-btk3s` blocks** in `~/.ssh/config` (VS Code sometimes adds them) are harmless as long as the `Include` line comes first: SSH uses the first value it finds for each setting. Run `ssh -G lima-btk3s | grep -E '^(hostname|port) '` to check. It should print `127.0.0.1` and Lima's forwarded port.

## Configuration

All tunable variables are in `playbook/roles/btk3s/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `btk3s_version` | `btk3s-v0.7.5` | Release tag from `github.com/beacontower/tools` |
| `btk3s_certs_dir` | `btk3s/certs` | Directory on the control machine holding the `*.crt` CA certificates to trust |
| `k3s_install_exec` | empty | `INSTALL_K3S_EXEC` passed to the k3s installer |
| `k3s_kubeconfig_mode` | `644` | `K3S_KUBECONFIG_MODE` passed to the k3s installer |
| `k9s_version` | `latest` | k9s release tag (for example `v0.50.6`) or `latest` |
| `flux_version` | `latest` | Flux CLI release (for example `2.7.2`) or `latest` |
| `dotnet_sdk_package` | `dotnet-sdk-10.0` | .NET SDK apt package to install |
| `docker_apt_codename` | host's Ubuntu codename | Ubuntu codename for the Docker apt repo |
| `azure_cli_apt_codename` | host's Ubuntu codename | Ubuntu codename for the Azure CLI apt repo |
| `docker_daemon_config` | `{}` | Written to `/etc/docker/daemon.json` when non-empty |
| `git_user_name` | `72338` | Global git `user.name` |
| `git_user_email` | `jorgen.simonsson@eon.se` | Global git `user.email` |
| `git_server` | `git.eon-cds.de` | GitLab host whose credentials are stored |
| `git_projects_dir` | `~/Projects` | Directory that repositories are cloned into |
| `git_clone_repos` | `hemflex` | List of `{name, repo}` to clone. Add more entries to clone more repositories. |

You can also override a variable for a single run without editing the file:

```bash
cd btk3s/playbook
ansible-playbook -i lima-btk3s, \
  -e "ansible_ssh_common_args='-F $HOME/.lima/btk3s/ssh.config'" \
  -e btk3s_version=btk3s-v0.8.0 \
  site.yml
```

## Upgrading btk3s

1. Change `btk3s_version` in `playbook/roles/btk3s/defaults/main.yml`.
2. Re-run `./run.sh -l btk3s`.

The playbook runs `btk3s version` and downloads the binary again only if the output doesn't contain the configured version number.

## Re-running and idempotency

You can safely run the playbook again at any time:

| Component | Behavior on re-run |
|-----------|--------------------|
| apt packages (incl. .NET SDK, Helm, step CLI) | Upgraded to the latest available versions |
| CA certificates | Copied again and the trust store updated only if a certificate changed |
| .NET backports PPA | Added only if the SDK package isn't available from the configured apt repositories |
| AppArmor profile override | Rewritten and reloaded only if its content changed. The run fails if a profile not written by btk3s is already there. |
| k3s | Skipped if `/usr/local/bin/k3s` exists |
| Claude CLI | Skipped if `~/.local/bin/claude` exists. The CLI updates itself. |
| k9s | Skipped if installed. With a pinned `k9s_version`, a different installed version is replaced. |
| Flux CLI | Skipped if installed. With a pinned `flux_version`, a different installed version is replaced. |
| btk3s | Downloaded again only when the installed version doesn't match `btk3s_version` |
| git config | Re-applied (no change if values match) |
| GitLab credentials | Replaced if you enter new ones. Kept if you leave the prompts empty. |
| Repositories | Cloned only if missing. Existing clones are never pulled or modified. |

To force a fresh k3s or Claude CLI install, remove the binary inside the VM first, then re-run the playbook:
- k3s: run `/usr/local/bin/k3s-uninstall.sh`.
- Claude CLI: delete `~/.local/bin/claude`.

## Troubleshooting

**`ssh.config not found`**: The Lima instance isn't running or has a different name. Start it with `limactl start btk3s`, or run `limactl list` to find the correct name.

**Docker or Azure CLI repo returns 404 / no packages**: The vendor hasn't published packages for the VM's Ubuntu release yet. Set `docker_apt_codename` and/or `azure_cli_apt_codename` to the previous LTS codename (for example `noble`) and re-run.

**`hemflex` clone fails with an authentication error**: The GitLab username or password was wrong, or no credentials were saved. Re-run and enter them again; the stored entry is replaced. Inside the VM, `cat ~/.git-credentials` shows what's stored. `HTTP Basic: Access denied` means GitLab requires a personal access token, not your account password, or the token is expired or missing the `read_repository`/`write_repository` scopes. After a rejected login, git's credential store deletes the entry, so `~/.git-credentials` ends up empty. That's expected.

**.NET SDK package not found**: On Ubuntu 24.04 the playbook adds `ppa:dotnet/backports` because the SDK isn't in the main archive. If that PPA has no packages for your release, check `apt-cache policy dotnet-sdk-10.0` inside the VM, or set `dotnet_sdk_package` to an available version.

**Privilege escalation times out on Ubuntu 26+**: Add `-s` to use the classic `sudo.ws` instead of `sudo-rs`.

**`docker: permission denied`** (and `id` doesn't list `docker`): Lima's `ssh.config` uses `ControlMaster`/`ControlPersist`, so every `limactl shell` reuses one persistent SSH connection. That connection logged in before the playbook added you to the `docker` group, and logging out and back in doesn't close it. In Lima mode, `run.sh` closes this connection automatically when it finishes. If you still hit the problem, exit all VM shells and close the connection manually:

```bash
ssh -F ~/.lima/btk3s/ssh.config -O exit lima-btk3s
limactl shell btk3s -- id     # should now include "docker"
```

On a non-Lima host, log out and back in.

**VS Code: `docker: permission denied` in the integrated terminal**: Run **Remote-SSH: Kill VS Code Server on Host** and reconnect (see [Using VS Code](#using-vs-code)).

**`k9s` / `kubectl` can't connect**: Check that `echo $KUBECONFIG` prints `/etc/rancher/k3s/k3s.yaml` and that `sudo systemctl status k3s` shows the service running.

**`btk3s up` hangs at PostgreSQL initdb, with `apparmor="DENIED"` signal errors in the kernel log**: The AppArmor profile override is missing or isn't loaded. Run `./fixapparmor.sh --check` inside the VM to find out. A cluster that already failed needs the recovery steps in [APPARMOR.md](APPARMOR.md), because the override doesn't wake processes that are already stuck.

**`cri-containerd.apparmor.d exists and was not written by btk3s`**: Someone else installed a profile with that name, and the playbook won't overwrite it. Inspect `/etc/apparmor.d/cri-containerd.apparmor.d` inside the VM, remove it if it's not needed, and re-run.

## Layout

```
btk3s/
├── README.md
├── APPARMOR.md                     # containerd AppArmor problem and recovery steps
├── fixapparmor.sh                  # check, install or remove the override by hand
├── certs/                          # CA certificates (*.crt) trusted on the target
├── run.sh                          # entry point (Lima or host/user/password)
└── playbook/
    ├── ansible.cfg
    ├── inventory.ini               # unused at runtime; run.sh passes host inline
    ├── site.yml
    └── roles/btk3s/
        ├── defaults/main.yml       # tunable variables (btk3s_version, ...)
        ├── handlers/main.yml
        └── tasks/
            ├── main.yml            # facts, apt upgrade, base packages, includes
            ├── inotify.yml         # inotify sysctl limits
            ├── certs.yml           # CA certificates into the system trust store
            ├── docker.yml
            ├── azure_cli.yml
            ├── dotnet.yml          # .NET SDK (adds backports PPA if needed)
            ├── apparmor.yml        # containerd AppArmor profile override
            ├── k3s.yml
            ├── k9s.yml
            ├── helm.yml
            ├── flux.yml
            ├── step.yml
            ├── claude.yml
            ├── btk3s.yml
            └── git.yml             # git identity, credentials, repo clones
```
