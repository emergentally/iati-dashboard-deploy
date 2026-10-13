# IATI Dashboard — deployment

Salt states to deploy [iati/dashboard-frontend](https://github.com/iati/dashboard-frontend),
a Nuxt application, behind nginx and run by pm2.

Self-contained: it needs nothing outside this repository.

## What it does

Given a bare Ubuntu 22.04 or 24.04 host it installs Node (via nvm), yarn,
nginx and certbot; clones the application; builds it; runs it under pm2 with
a systemd unit so it survives a reboot; and configures nginx to proxy to it
with a Let's Encrypt certificate.

Re-running it deploys the current branch: the checkout is reset, rebuilt, and
pm2 restarted — but only if something actually changed.

## Prerequisites

- `salt-ssh` on your machine (`apt install salt-ssh` / `brew install saltstack`)
- root SSH access to the target host
- DNS for your hostname already pointing at the host, if you want a
  certificate — certbot validates over HTTP and will fail otherwise

## Setup

1. **Point it at your host.** Edit `salt-config/roster`:

   ```yaml
   dashboard-preview:
     host: 203.0.113.10
     user: root
   ```

2. **Set the site details.** Edit `pillar/dashboard_preview.sls` — at minimum
   `servername` and `letsencrypt_email`.

3. **Supply a deploy key**, while `iati/dashboard-frontend` is private.
   Generate one, add the public half to the repository's Deploy keys
   (Settings → Deploy keys, read-only is enough), and put the private half at
   `salt/files/deploy`:

   ```bash
   ssh-keygen -t ed25519 -f salt/files/deploy -N '' -C 'dashboard-preview deploy'
   cat salt/files/deploy.pub     # paste into GitHub
   ```

   Both files are gitignored. If the repository is ever made public, change
   `frontend_url` in the pillar to the `https://` URL and the key becomes
   unnecessary — the states skip it automatically.

## Deploying

```bash
./up.sh dashboard-preview
```

The argument is the roster entry name. First run takes a few minutes
(compiling Node, installing packages); later runs are quicker.

## Taking the site down for maintenance

```bash
ssh root@host touch /var/www/maintenance/dashboard-preview.on   # 503 for visitors
ssh root@host rm    /var/www/maintenance/dashboard-preview.on   # back up
```

Requests from `127.0.0.1` bypass it, so you can verify a deploy from the host
before lifting the flag.

## Layout

```
up.sh                        deploy one target
Saltfile                     points salt-ssh at salt-config/
salt-config/roster           which host, how to reach it
pillar/dashboard_preview.sls all site-specific values
salt/top.sls                 which states apply to which target
salt/site.sls                the application: Node, yarn, build, pm2, nginx
salt/core.sls                host baseline: packages, fail2ban, ssh, updates
salt/nginx.sls               nginx service, log format, DNS-wait fix
salt/letsencrypt.sls         certbot and renewal
salt/lib.sls                 shared macros
salt/files/                  templates: nginx.conf, pm2 config, maintenance page
```

## Adding another instance

Add a roster entry, a pillar file, and a line in both `pillar/top.sls` and
`salt/top.sls`. Nothing in `salt/` should need editing.

## Notes

Node version is set in the pillar (`node_version`) and should match the
application's `.nvmrc`.

The build writes to `.output`, then swaps `.output-latest` into place in a
single step. pm2 serves `.output-latest`, so a failed build leaves the
previous release running rather than half-replacing it.

`up.sh` clears a stale file from salt-ssh's thin payload before each run.
This works around [saltstack/salt#68755](https://github.com/saltstack/salt/issues/68755),
where a bundled `configparser.py` shadows the standard library module and
breaks all `pkg.*` states. It is regenerated on every run, so it is cleared
every time rather than once.
