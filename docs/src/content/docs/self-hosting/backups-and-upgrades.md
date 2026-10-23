---
title: Backups and upgrades
description: Back up and restore a self-hosted opendesk, move between releases, and let it update itself.
---

## What to back up

| What | Why |
| --- | --- |
| The Postgres database | Everything except files. |
| The data volume (`/data`) | Attachments and raw email with the `local` storage driver. |
| `.env` | Secrets. **`CREDENTIALS_KEY` cannot be recovered**, and without it stored mailbox credentials cannot be decrypted. |

## Back up

```sh
/opt/opendesk/opendesk-ctl backup [dir]
```

This writes `backups/<UTC time>/` (or under `dir`) containing:

- `db.dump`: a `pg_dump` in custom format
- `data.tar.gz`: the opendesk data volume
- `env`: a copy of `.env`
- `VERSION`: the running release
- `SHA256SUMS`: a checksum of each file, which `restore` checks before it changes anything

The directory is created with mode `0700`. The backup is taken while opendesk keeps running: `pg_dump` reads one consistent snapshot of the database, and files written during the copy may be missing from `data.tar.gz`. An [upgrade](#upgrade) stops the app first, so its backup holds every write. Schedule it with cron:

```sh
0 3 * * * /opt/opendesk/opendesk-ctl backup >> /var/log/opendesk-backup.log 2>&1
```

If you use an external database or S3 storage, back those up with your provider's tools as well.

## Off-site copies

A backup is a complete restore set: the database, the files and `.env`, which holds `CREDENTIALS_KEY`, the key that decrypts the stored mailbox credentials. Anyone holding a copy can read all of it, so treat it like the server itself. Encrypt it before it leaves the machine, with a key that is not stored on the server or next to the copies.

With [age](https://age-encryption.org), generate a key pair once on a machine you trust, and keep the private key there (a password manager, or offline):

```sh
age-keygen -o opendesk-backup.key    # prints the public key, age1...
```

Only the public key goes on the server. Encrypt each backup into one file and copy that:

```sh
cd /opt/opendesk/backups
tar -cf - 20261011T030000Z | age -r age1yourpublickey... > 20261011T030000Z.tar.age
sha256sum 20261011T030000Z.tar.age > 20261011T030000Z.tar.age.sha256
# copy both files off-site (rclone, rsync, aws s3 cp, restic...), then:
rm 20261011T030000Z.tar.age
```

The server can write new encrypted copies but cannot read old ones. Keep the private key and its recovery separate from the copies: losing it makes every encrypted backup unreadable, and keeping it beside them makes the encryption pointless.

- Check `sha256sum -c` on the `.sha256` file after each transfer, and again before a restore.
- Use storage that keeps old versions or locks them for a while (object lock, versioning), so a compromised server cannot delete its own history.
- Decide how long to keep copies and delete older ones on that schedule. A copy keeps the credentials and customer data it was taken with until it is deleted.
- A transfer that stopped part way leaves an incomplete file whose checksum fails. Copy it again rather than keeping it.

`gpg --encrypt --recipient` or an encrypting backup tool such as restic work the same way.

## Restore drill

Restore a backup on a separate, disposable machine every few months, so you know the copies work and how long a restore takes. The restored copy holds production's mailbox credentials and would fetch mail and send queued replies, so cut it off from the internet before it starts:

1. Install opendesk on the spare machine with the [installer](/self-hosting/install-script/), with no DNS pointed at it, and run `docker pull alpine:3.22` (the restore unpacks files with it).
2. Block outgoing connections from the machine, for example with a firewall that allows only your SSH session.
3. Copy an encrypted backup there, check its checksum, then decrypt and unpack it with the private key:

   ```sh
   sha256sum -c 20261011T030000Z.tar.age.sha256
   age -d -i opendesk-backup.key 20261011T030000Z.tar.age | tar -xf -
   ```

   A wrong or missing key stops here with an error, and nothing is written.
4. Put the backup's `env` in place (`cp 20261011T030000Z/env /opt/opendesk/.env`) so stored credentials decrypt, and restore it as below.
5. Sign in over an SSH tunnel, and open a few tickets and their attachments.
6. Destroy the machine, and delete the private key's copy from it.

## Restore

```sh
/opt/opendesk/opendesk-ctl restore /path/to/backups/20261011T030000Z
```

It checks the files against `SHA256SUMS`, stops the app, replaces the database and the data volume, and asks you to type `restore` first (`OPENDESK_YES=1` skips the prompt). A file that does not match its checksum stops the restore before anything changes. Keep the same `CREDENTIALS_KEY` and `AUTH_SECRET` as the backup.

## Upgrade

```sh
/opt/opendesk/opendesk-ctl upgrade            # the newest release
/opt/opendesk/opendesk-ctl upgrade v1.2.3     # a specific release
```

An upgrade:

1. pulls the new images while the current version keeps serving
2. stops the app and takes a backup, so it holds every write (skip with `OPENDESK_SKIP_BACKUP=1`)
3. downloads that release's installer, checks it against its published SHA-256 and reruns it in place with `--version`, keeping every secret and setting
4. waits up to five minutes for the new version to answer its health check
5. if it does not, puts the previous release's files back, restores the backup when the new version's migrations ran, and starts the previous version again

Migrations run when opendesk starts, so there is no separate migration step. Releases do not skip migrations, so upgrading across several versions at once is fine; read the [release notes](https://github.com/useopendesk/opendesk/releases) first.

To roll back later by hand, restore the backup taken before the upgrade, then install the earlier version with `--version`.

## Automatic updates

The installer turns automatic updates on (`--no-auto-update` skips it). Each night around 04:00, server time, a systemd timer (or a cron entry where there is no systemd) runs `opendesk-ctl auto-update run`. When a newer release is out, it runs the [upgrade](#upgrade) above, with its backups in `backups/auto/` (the newest three are kept).

A run never installs:

- a new **major** version (`v1.x` to `v2.0.0`): those can need you to change something, so the admin panel and an email tell you, and you run `opendesk-ctl upgrade v2.0.0` after reading the release notes
- a **pre-release** (`v1.3.0-rc.1`)
- a release that already **failed** on this server: after going back, it waits for the next release (`opendesk-ctl upgrade <version>` tries it again by hand)
- anything when `OPENDESK_VERSION` is not a release (`latest`, or your own build)

```sh
/opt/opendesk/opendesk-ctl auto-update status   # on or off, the schedule, newest release, last runs
/opt/opendesk/opendesk-ctl auto-update off      # stop, and remove the schedule
/opt/opendesk/opendesk-ctl auto-update on       # start again
/opt/opendesk/opendesk-ctl auto-update run      # run now, as the timer does
```

`on` and `off` set `AUTO_UPDATE` in `.env` and add or remove the schedule (the systemd timer needs root, so they use `sudo`). The timer logs to the journal (`journalctl -u opendesk-update`); a cron entry to `auto-update.log` in the install directory. The app is down for the backup and the new version's first start, usually under a minute. Mail forwarded to opendesk and webhooks from mail providers are retried by their senders.

Each run is reported to the instance: the admin panel's **Health** page shows whether automatic updates are on and how the last run went, and the super admins get an email when one fails.

## Update notices

A release build looks for the newest release on GitHub every six hours (a plain request that carries nothing about your instance). When one is out:

- the admin panel's **Health** page says so, with the release notes and the command to run, and **Check now** looks again
- the [super admins](/self-hosting/admin-panel/) get one email per release, unless automatic updates will install it anyway
- the opendesk log has a line saying so

This works however you run opendesk, including your own Compose file or Kubernetes. Set `UPDATE_CHECK=false` to turn it off, for example on a server without internet access.

### Your own Compose file

Without `opendesk-ctl`, pin `OPENDESK_VERSION` (or the image tag) to a release, and upgrade by changing it:

```sh
docker compose pull && docker compose up -d
```

Back up first. Tools that follow the `latest` tag (Watchtower and the like) also work, but they take no backup and do not go back when a release fails, so prefer `opendesk-ctl`.
