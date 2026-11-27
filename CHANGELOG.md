# Changelog

## Unreleased

- Fleet: Google Chrome profiles are no longer read (`chrome_profiles`, off
  by default): Fleet's `google_chrome_profiles` detail query maps a host to
  the e-mail addresses of every local user's Chrome profiles, not only the
  owner's. The provisioning sends a `detail_query_overrides` entry of
  `null`; mappings stored before stay in Fleet's `host_emails` until removed.
- **MySQL service** (`:mysql`) next to MariaDB, with the server distribution
  as a field like the MongoDB service: `mysql_distribution: percona`
  (default) installs Percona Server for MySQL (component
  `percona_server@<series>`), `mysql` MySQL Community from MySQL's own
  repository (component `mysql@<series>`, amd64 only); default series 8.4 LTS, for applications in the same guest (localhost only, root
  over `auth_socket`, an empty data volume at `var/lib/mysql` is initialised
  on the first start, backups by `mysqldump`). Cannot share a guest with
  MariaDB.
- **Percona Server for MongoDB** as a choice of the MongoDB service
  (`mongodb_distribution: percona`, component `percona_server_mongodb@<line>`):
  a drop-in replacement of the same line, so a member switches by a redeploy
  (the data directory is handed to Percona's `mongod` user). The nightly
  `MongodbPatch` knows both package families. Percona publishes no arm64
  packages for Debian 12 (Ubuntu 22.04 has them).
- Percona's repositories share one setup (`PerconaRepository`: packaging key
  pinned by fingerprint, the `telemetry` repository the server packages
  depend on). Usage telemetry to Percona is a switch of each Percona service,
  off by default (server setting and telemetry agent).
- **Fleet service** (`:fleet`): the Fleet device management server (osquery).
  Its database comes from a `:mysql` service in the same guest
  (Fleet's migrations need MySQL 8, MariaDB fails them), Redis from a
  `:redis` service. Fleet creates its database and user, runs
  `fleet prepare db` before every start and provisions administrator, enroll
  secret and SAML settings itself; provisioning token and vulnerability feeds
  live at `var/lib/fleet`. Its usage statistics are a switch of the service,
  off by default. amd64 only (Fleet publishes no arm64 server).
- **Which server exists where**: `config/component_platforms.yml` lists per
  component (MongoDB, Percona Server for MongoDB, MySQL, Percona Server) the
  release lines the vendors publish per guest OS and architecture, read from
  their apt indexes by `rake cloudmodel:components:platforms` (prints the
  differences, `WRITE=1` rewrites the file). The MongoDB and MySQL services
  offer `available_servers` / `server` (`"<distribution>:<line>"`) for forms
  and reject a combination the vendor does not publish — only when it is
  chosen or changed, or the guest's OS changes, so guests from before stay
  editable. Notably: MongoDB publishes no server for Debian 13 (Percona
  Server for MongoDB 8.0 does, amd64 and arm64) and none for arm64 on
  Debian 12; MySQL and Fleet publish amd64 only.
- The MongoDB service defaults to the 8.0 line (was 5.0, which no current
  guest OS has).
- `CloudModel.mongodb_version_path` lists major releases only and ends with
  9.0 instead of 8.2: MongoDB stops patching a minor release once the next
  is out and, before 9.0, a set on a minor can only leave it through every
  later minor, while 8.0 upgrades to 9.0 directly. The FCV step
  (`MongodbReplicationSet#update_feature_compatibility_version!`) now sends
  `confirm: true`, which mongod requires from 7.0 on.
- Nginx reverse proxy (`proxy_conf`) talks HTTP/1.1 to the backend and passes
  the `Upgrade`/`Connection` headers on, so websockets work through it.

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
- **Unattended security upgrades** on hosts and guests (`unattended-upgrades`,
  Debian and Ubuntu security suites only, no automatic reboot; hosts never
  update ZFS or the kernel this way). Installed into the core templates,
  re-applied on every host and guest (re)deploy, pushed to running systems with `rake cloudmodel:host:deploy_unattended_upgrades`
  and `rake cloudmodel:guest:deploy_unattended_upgrades`; change reports
  go to `config.admin_email`. `config.unattended_upgrades = false` switches
  it off.
- Three review rounds before the first rollout, each fix with a spec:
  incremental volume sync with moved-aside leftovers, honest multi-arch
  build results, abandoned build claims taken over after three hours while
  live builds keep theirs, resumed template builds keep their volume,
  container-id ownership throughout, chroot mounts dropped before LXD
  attaches a device and the volume re-mounted after, undetachable mounts
  stop the flow, secrets written over SFTP, UTF-8 command output, escaped
  Jitsi/nginx values, config.ssh_key_file honoured everywhere.
- Rust build environments export `RUSTUP_HOME`/`CARGO_HOME` for every shell
  (the rustup proxies found no default toolchain otherwise); command output
  is returned as valid UTF-8; a busy chroot mount is detached lazily on
  cleanup instead of masking the real error.

## 0.4.0

Rails 8 support.

## 0.3.0

Rails 7.2 required.
