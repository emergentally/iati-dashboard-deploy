# IATI Dashboard — deployment

Salt states to deploy [iati/dashboard-frontend](https://github.com/iati/dashboard-frontend),
a Nuxt application, behind nginx and run by pm2.

Self-contained: it needs nothing outside this repository.

## What it does

Given a bare Ubuntu 22.04 or 24.04 host it installs Node (via nvm),
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

3. **Set the site password.** Copy `pillar/secrets.sls.example` to
   `pillar/secrets.sls` and fill it in. That file is gitignored. Leave the
   value empty to disable the password gate.

   It is a deterrent, not access control: `NUXT_PUBLIC_*` values are inlined
   into the client bundle and readable by anyone who looks.

4. **Supply a deploy key**, while `iati/dashboard-frontend` is private.
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

## Before it will work

Two things must be arranged on the IATI side, and neither can be done from
here:

- **Asgardeo** must have `https://dashboard-preview.iatistandard.org/`
  registered as a redirect URL for the client, and Register Your Data must
  allowlist the same origin. The app derives its redirect URL from its own
  origin and Asgardeo matches it exactly, so sign-in fails with
  `invalid_callback` until both are done.
- **CORS.** The IATI Dashboard at `dev2.dashboard.iatistandard.org` returns
  200 with no `Access-Control-Allow-Origin`, on GETs and preflights alike, so
  a browser blocks every request to it. `dashboard_base` in the pillar
  therefore points at a CORS proxy. The failure mode if you point it straight
  at dev2 is quiet: the page loads, every panel stays empty, and the only
  sign is in the browser console.

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
salt/site.sls                the application: Node, npm, build, pm2, nginx
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

Node version is set in the pillar (`node_version`). The application has no
`.nvmrc` and no `engines` field, so nothing in the repository declares it -
keep this in step with `node-version` in the app's GitHub workflow.

The application uses **npm**, not yarn: it has a `package-lock.json` and no
`yarn.lock`, and `yarn install` would resolve a different dependency tree.

`nuxt.config.ts` is never edited. The values under "App config" in the pillar
become `NUXT_PUBLIC_*` environment variables in the pm2 config, which Nuxt
reads into `runtimeConfig.public` at startup - so the deployed checkout stays
byte-identical to the repository. `NUXT_APP_BASE_URL` is deliberately not set;
CI sets it to `/dashboard-frontend/` for GitHub Pages, which would 404 every
asset at a domain root.

The build writes to `.output`, then swaps `.output-latest` into place in a
single step. pm2 serves `.output-latest`, so a failed build leaves the
previous release running rather than half-replacing it.

`up.sh` clears a stale file from salt-ssh's thin payload before each run.
This works around [saltstack/salt#68755](https://github.com/saltstack/salt/issues/68755),
where a bundled `configparser.py` shadows the standard library module and
breaks all `pkg.*` states. It is regenerated on every run, so it is cleared
every time rather than once.
