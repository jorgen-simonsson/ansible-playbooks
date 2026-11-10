# AppArmor: containers can't signal themselves on kernel 7.0 / arm64


**TL;DR** — on the btk3s Lima VM (Ubuntu 26.04, kernel `7.0.0-*-generic`, arm64),
containerd's default AppArmor profile blocks signals between processes **inside the
same container**. PostgreSQL 18 depends on those signals, so every Postgres in the
cluster hangs during initdb and `btk3s up` fails. Run `./fixapparmor.sh` inside the
VM to fix it.

## Symptoms

`btk3s up` stalls in the data layer and finally fails with something like:

```
spicedb-migrate-…: job failed (Job has reached the specified backoff limit)
timescale-1-initdb-…: waiting for a node (… persistentvolumeclaim "timescale-1" is being deleted …)
timescale: Running 'install' action with timeout of 15m0s
Flux did not accept tenant-btk3s-data … context deadline exceeded
```

Looking closer:

- every CNPG cluster (`kubectl -n btk3s get cluster.postgresql.cnpg.io`) sits at
  **"Setting up primary"**;
- every `*-initdb-*` pod is `Running` but its log stops at
  `Configuring new PostgreSQL instance`;
- even `psql` over the local socket with `trust` auth hangs. Inside the pod the
  backends show as `postgres: … [local] authentication` forever;
- the kernel log is full of:

  ```
  apparmor="DENIED" operation="signal" class="signal" profile="cri-containerd.apparmor.d"
    comm="postgres" requested_mask="send" denied_mask="send" signal=urg
    peer="cri-containerd.apparmor.d//&unconfined"
  ```

  Check with: `sudo journalctl -k --since -10min | grep 'apparmor="DENIED"'`
  or `./fixapparmor.sh --check`.

Go programs (vault, the CNPG manager, kubectl, traefik, …) show the same denials
for `signal=urg`. They survive it, because Go only uses SIGURG for goroutine
preemption.

## Cause

containerd puts every container under its built-in profile
`cri-containerd.apparmor.d`, which permits in-container signals with:

```
signal (send,receive) peer=cri-containerd.apparmor.d,
```

On this kernel the *receiving* process is reported under the stacked label
`cri-containerd.apparmor.d//&unconfined`. That label doesn't match the rule, so
the signal is denied. An explicit rule naming the stacked label doesn't match
either; only a bare `signal,` rule does.

PostgreSQL ≥ 17 wakes latches (backends, PG18's I/O workers) with **SIGURG**.
With the signal dropped, a backend waits forever for an I/O worker, and initdb
never finishes.

What follows from that:

1. CNPG initdb never completes → no database is ever Ready.
2. `spicedb-migrate` can't reach its database → the job fails → the SpiceDB
   operator **pauses** the SpiceDBCluster (`authzed.com/controller-paused` label).
3. HelmReleases time out (15 min) → Flux uninstall remediation deletes the
   release *including its PVC* (seen with timescale) → the reinstall's initdb pod
   points at a PVC that no longer exists.
4. Later, user-service returns HTTP 500 on `/api/organizations` (gRPC to SpiceDB:
   connection refused) → the seed fails with `organization create failed`.

### Whose bug?

Not btk3s. Docker's default profile has the same problem: the enode provider's
integration tests already need `apparmor=unconfined` for the Postgres
Testcontainer (`btk3s/providers/enode/enode-provider/tests/Enode.IntegrationTests/ProviderFixture.cs`).
It's an incompatibility between AppArmor label stacking on this kernel (Ubuntu
26.04 / 7.0) and the container runtimes' default profiles. Why `unconfined` gets
stacked onto the container profile hasn't been pinned down. A bug report belongs
with Ubuntu (`apparmor` / `linux` on Launchpad) or containerd, and a heads-up via
`btk3s bug` so btk3s can apply the workaround when it provisions the VM.

## Fix

Inside the VM (the k3s node), from the repo root:

```bash
./fixapparmor.sh --check   # is this node affected?
./fixapparmor.sh           # install + load the override
```

What it does:

- writes `/etc/apparmor.d/cri-containerd.apparmor.d`: containerd's own profile
  template verbatim, plus a bare `signal,` rule;
- validates it (`apparmor_parser -QK`) and loads it (`apparmor_parser -r`).
  Replacing a loaded profile applies to **running** containers at once; no k3s
  restart needed.

It persists across reboots because `apparmor.service` loads `/etc/apparmor.d/*`
at boot, before k3s starts. containerd only loads its built-in profile when none
with that name is loaded yet, so it keeps the override.

**Security trade-off:** `signal,` lets container processes send signals without
AppArmor peer restrictions. Normal UID/capability checks still apply (pods here
run non-root with all capabilities dropped). That's acceptable for a local dev
VM and less permissive than `apparmor=unconfined`. Don't carry it to shared
clusters.

To undo: `./fixapparmor.sh --remove` (takes effect after the next reboot).

## Recovering a cluster that already failed

Fixing the profile doesn't wake processes that already lost a signal. After
running the script:

```bash
# 1. restart stuck CNPG initdb pods (CNPG re-creates them; they finish in seconds)
kubectl -n btk3s delete pod -l cnpg.io/jobRole=initdb
kubectl -n btk3s get cluster.postgresql.cnpg.io        # wait for "Cluster in healthy state"

# 2. un-pause SpiceDB: delete the failed migrate job FIRST, then drop the label
#    (in the other order the operator sees the old failed job and pauses again)
kubectl -n btk3s get jobs -o name | grep spicedb-migrate | xargs -r kubectl -n btk3s delete
kubectl -n btk3s label spicedbclusters spicedb authzed.com/controller-paused-

# 3. user-service caches the dead SpiceDB connection - restart it
kubectl -n btk3s rollout restart deploy/user-service

# 4. HelmReleases that exhausted their retries need a forced reconcile
#    (no flux CLI needed):
T=$(date +%s); kubectl -n <ns> annotate hr <name> --overwrite \
  reconcile.fluxcd.io/requestedAt=$T reconcile.fluxcd.io/forceAt=$T

# 5. re-run from the directory holding btk3s.yaml
cd btk3s/providers/enode && btk3s up
```

## Other things that went wrong in the same session (not AppArmor)

- **Stale ingress-nginx admission webhook** from an older install blocked
  kube-prometheus-stack (`service "ingress-nginx-…-admission" not found`). Fix:
  `kubectl delete validatingwebhookconfiguration ingress-nginx-ingress-nginx-admission`.
- **Image downloads froze at 0 bytes/s** after a short DNS outage in the Lima VM
  (`lookup registry-1.docker.io: no such host`). Deleting the pods didn't help
  (kubelet stays blocked on the pull). `sudo systemctl restart k3s` did. Containers
  keep running (`KillMode=process`).
- **Large images vs. the 15 min Helm timeout:** `timescale/timescaledb-ha` (~520 MB)
  took 20 min on the first pull, which on its own is enough to trigger the
  uninstall remediation described above.
