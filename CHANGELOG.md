# Changelog

## 0.5.1 — review fixes before the first ZFS rollout

Three review rounds over 0.5.0, each fix with a spec:

- Volume sync: incremental sends from the target's newest snapshot; a
  dataset without a common snapshot is moved aside (clones stay valid) and
  reclaimed later; transfer failures surface instead of triggering rebuilds;
  the direct hop addresses the peer by its private address.
- Builds: a failed arch fails the image; build claims are kept alive per
  step and abandoned ones taken over after three hours; a resumed template
  build keeps its half-built volume; the workspace detaches its mountpoint.
- Deploys: files in the unshifted clone are owned by container ids, the
  attached release clone through the container's idmap; a leftover clone
  is removed with a proper error; chroot mounts are dropped before LXD
  attaches a device and the volume is re-mounted afterwards; an
  undetachable mount stops the flow instead of being walked over.
- Config safety: the master key is written over SFTP, command output is
  UTF-8, Jitsi branding and nginx env values are escaped or refused,
  config.ssh_key_file is honoured everywhere, primarycache reaches
  existing volumes, a plain-string build host serves only its own arch.
- Rust build environments export RUSTUP_HOME/CARGO_HOME.

## 0.5.0 — ZFS-volume deploys

Guest templates, guest containers and web-image releases moved from image
tarballs to ZFS volumes. This is the first release that changes what lives on
the hosts, so read the migration notes before updating a running cloud.

### What changes on the hosts

- **Templates are ZFS build volumes.** A guest template is built in a dataset
  under `config.build_dataset` (default `guests/build`) and snapshotted as
  `@ready`; a container is a `zfs clone` of that snapshot instead of an LXD
  image. Templates missing on a host are synced from a host that has them, or
  built on the arch's build host.
- **Web images are ZFS artifacts.** A web image is built once per
  (template, arch) in a shared build environment; each guest gets a clone of
  the artifact attached as `releases/<id>` and activated through the `current`
  symlink. Rollback is re-pointing `current`; the newest three clones are kept.
- **Hosts stream volumes to each other.** The first sync between two hosts
  installs a dedicated sync key: a private key under `/root/.ssh/zfs_sync`,
  an entry in root's `authorized_keys` bound with `restrict` to the forced
  command `/usr/local/sbin/zfs-receive-only`, which only accepts
  `zfs receive`, `zfs create -p` and `zfs list` inside the build dataset tree.
  Hosts that cannot be prepared keep the old route through the controller.
  `rake cloudmodel:host:deploy_zfs_sync_key` rolls the key out ahead of time.
  A dataset the target already holds (an earlier web-image artifact with
  release clones on it) receives new versions incrementally from its newest
  snapshot; one without a snapshot in common is moved aside as
  `<dataset>-stale-<ts>` (its clones stay valid) and removed once nothing
  depends on it. A transfer failure surfaces as such instead of triggering
  a rebuild, and a build claim with no state change for three hours is
  treated as abandoned and taken over.
- **Secrets stay out of the console.** `Host#exec` echoes commands into the
  live log, so the Rails master key is written over SFTP instead of through
  a shell command; `Host#exec(quiet: true)` is there for any command that
  has to carry a secret.
- **Controller keys are created on demand.** The controller's host key and the
  sync key pair are generated when first needed (`SshKeyPair`).
- **File ownership uses container ids.** The template-volume clone is
  unshifted when the deploy writes into it (LXD maps it on first start), so
  rendered files are left root-owned and non-root owners (`www`, config
  owners from web app definitions, Solr's user) are set with container ids
  or by name. The old host-range chowns (`100000 + id`) would have landed
  as foreign ids inside the container. The web release clone, attached as a
  raw disk device, is owned through the container's actual idmap base
  (read from LXD); an artifact built for another base is re-owned once.
- The guest's `/etc/hosts` carries `config.additional_hosts`.

### Behaviour changes

- **Web image rollouts to guests on the old layout are refused.** A container
  created from an image keeps its releases as directories in the rootfs; the
  rollout cannot update that in place. The nginx service then shows the state
  `guest_redeploy_required` with the reason, and `force` does not override it.
  One full guest redeploy moves the guest to the volume layout and deploys the
  web image on the way. Every other operation on such a guest (start, stop,
  monitoring, backups, nginx config sync) works unchanged.
- Each container records where its rootfs came from
  (`LxdContainer#rootfs_origin`); containers from before this release are
  probed once via the dataset's ZFS origin.
- The ZFS backup snapshot prefix is configurable
  (`config.backup_snapshot_prefix`, default `cm-bkp-`). Set it to the prefix
  of existing snapshots to keep incremental chains and pruning intact.
- Per-service ZFS volumes can cache metadata only (`primarycache`), and hosts
  can cap the ARC (`zfs_arc_max`).

### Migrating a running cloud

1. Deploy the new version; nothing happens to running guests by itself.
2. `rake cloudmodel:zfs:status` — read-only report: container layout per
   guest, the template a redeploy would clone on each host, web images without
   artifacts. `PROBE=0` skips host access.
3. `rake cloudmodel:migrate:templates_to_zfs` (dry run; `CONFIRM=1` applies) —
   turns the existing template tarballs into build volumes on the build host,
   so no redeploy has to rebuild a template from scratch.
4. `rake cloudmodel:host:prepare_zfs_templates` — makes sure every host has
   the volumes its guests need.
5. Redeploy guests one by one; the first guest of each web image also builds
   that image's artifact. Rollouts to not-yet-migrated guests are refused
   until then.
6. `rake cloudmodel:cleanup:templates` (dry run; `CONFIRM=1` applies) — only
   after the last guest is migrated; it removes the tarballs.

Guests whose component set changed since their template was built (for
example a Java upgrade) have no finished template of their new type; their
redeploy builds one on the guest's own host first. The status report lists
them.

### Also in this release

- Forgejo and Jitsi service components, including OpenID Connect login for
  Forgejo and re-pointing a Jitsi deployment to a new domain.
- Nginx: live config sync with edit detection, request timing metrics, OCSP
  stapling and Passenger pool size per service, `passenger_env_vars`,
  rollback-friendly release cleanup, a start-pre that cannot wedge on a large
  www root.
- Monitoring: live OS/kernel/ZFS/LXD versions and package inventory, Collabora,
  Jitsi and Rake service checks, md recovery/resync parsing.
- Backups: per-subject state tracking and on-demand backup jobs.
- Live console for deploys and template/image builds.
- Polymorphic web app classes are eager-loaded so rake tasks resolve them.
- Rust build environments export `RUSTUP_HOME`/`CARGO_HOME` for every shell
  (the rustup proxies found no default toolchain otherwise); command output
  is returned as valid UTF-8; a busy chroot mount is detached lazily on
  cleanup instead of masking the real error.

## 0.4.0

Rails 8 support.

## 0.3.0

Rails 7.2 required.
