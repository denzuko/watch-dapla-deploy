# watch-dapla-deploy

Roswell/Consfigurator deploy of [Invidious](https://github.com/iv-org/invidious)
at `watch.dapla.net`. Invidious is a privacy-preserving alternative frontend to YouTube.

## Architecture

```
Cloudflare edge
  └── HAProxy (TLS termination, security headers, health check)
        └── invidious:3000 (127.0.0.1 only)
              └── invidious-db (internal Podman network, postgres:16-alpine)
```

All containers run rootless under the `invidious` service account. Two
AES-256-GCM-encrypted ZFS datasets back the service account home and the
PostgreSQL data directory. Images are mirrored via `oci.dapla.net`.

## Repository Layout

```
watch-dapla-deploy.ros   Thin Roswell entry point; dispatches to deploy or e2e
watch-dapla-deploy.asd   Umbrella ASDF system definition
qlfile                   Qlot dependency pins
src/deploy.lisp          Consfigurator properties and DEFHOST
src/docs.lisp            40ants-doc sections
t/e2e.lisp               Post-deploy FiveAM smoke tests
docs.ros                 Documentation generator
Makefile                 build / test / doc / dist / clean
```

## Prerequisites

- Roswell with SBCL
- Qlot (`ros install qlot`)
- Rootless Podman ≥ 4.4 with quadlet support
- Systemd user session with lingering enabled
- HAProxy ≥ 2.6
- ZFS with `storage/users` and `storage/containers` pools

## Installation

```sh
ros install qlot
qlot add cl-inix consfigurator fiveam dexador
./watch-dapla-deploy.ros
```

The script provisions the full stack via Consfigurator over a `:local` connection:
ZFS datasets (encrypted), service account, linger, DB secret, Invidious config,
image pulls, quadlet units, and HAProxy vhost.

## Runbook

Status, logs, restart, and image updates are all managed through the provisioned
service account's systemd user session:

```sh
machinectl shell invidious@ -- systemctl --user status invidious-db invidious
machinectl shell invidious@ -- journalctl --user -u invidious -u invidious-db -f
machinectl shell invidious@ -- systemctl --user restart invidious
machinectl shell invidious@ -- podman auto-update
```

Redeploy by re-running `./watch-dapla-deploy.ros`. Consfigurator's check/apply
cycle is idempotent; only changed properties are applied.

## Playbook

### ZFS replication (rsync.net)

```sh
zfs snapshot storage/containers/invidious@$(date +%Y%m%d)
zfs send -w storage/containers/invidious@$(date +%Y%m%d) | \
  ssh user@rsync.net zfs receive backup/invidious
```

Schedule via a systemd timer. Key files under `/etc/zfs-keys/` must be
backed up separately from the ZFS snapshots.

## Decommission

```sh
machinectl shell invidious@ -- systemctl --user stop invidious invidious-db
machinectl shell invidious@ -- systemctl --user disable invidious invidious-db
rm ~/.config/containers/systemd/invidious{,-db}.container ~/.config/containers/systemd/invidious.network
# Destroy datasets only when data loss is acceptable:
zfs destroy -r storage/users/invidious
zfs destroy -r storage/containers/invidious
```

## License

BSD 3-Clause. See [LICENSE](LICENSE).
