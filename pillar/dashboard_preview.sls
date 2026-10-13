# Everything site-specific lives here. Nothing in salt/ should need editing
# to stand up another instance.
#
# Secrets (site_password) live in pillar/secrets.sls, which is gitignored.
# Copy pillar/secrets.sls.example to get started.

name: 'dashboard-preview'
user: 'dashboard'

# The application repository. iati/dashboard-frontend is private, so this is
# an SSH URL and the deploy key is installed from salt/files/deploy (see
# README). Make it an https:// URL if the repository is ever made public,
# and the key states become unnecessary.
frontend_url: 'git@github.com:iati/dashboard-frontend'
frontend_branch: 'main'
frontend_codedir: '/home/dashboard/dashboard-frontend/'

servername: 'dashboard-preview.iatistandard.org'
serveraliases: []

# 'force' redirects http to https and obtains a certificate.
# Use 'no' for a host with no public DNS yet - nginx then listens on 80 only.
https: 'force'

# Who Let's Encrypt emails about expiry.
letsencrypt_email: 'CHANGE-ME@iatistandard.org'

# Port the Nuxt server listens on behind nginx. Only needs changing if
# something else on the host already uses it.
pm2_port: '3000'

# CI pins Node 24 and the repository has no .nvmrc, so nothing in the app
# declares this. Keep it in step with .github/workflows/.
node_version: '24'

##################################################################### App config
# These become NUXT_PUBLIC_* environment variables for the Node server, which
# Nuxt reads into runtimeConfig.public at runtime. Injecting them here rather
# than editing nuxt.config.ts keeps the deployed checkout identical to the
# repository.

# The IATI Dashboard API. Must go through a CORS proxy: dev2 returns 200 with
# no Access-Control-Allow-Origin on either a GET or a preflight, so a browser
# blocks every request. The symptom is a page that loads with every panel
# empty and errors only in the browser console - nothing server-side shows it.
# Point this straight at dev2 once the Dashboard sends CORS headers.
dashboard_base: 'https://black-math-8c4c.dashboard-cors-proxy.workers.dev'

# Register Your Data.
ryd_base: 'https://dev.api.registeryourdata.iatistandard.org'

# Asgardeo sign-in. The app derives its redirect URL from its own origin, and
# Asgardeo matches it exactly - so https://dashboard-preview.iatistandard.org/
# must be registered against this client, and the same origin allowlisted by
# Register Your Data, or sign-in fails with invalid_callback.
auth_client_id: ''
auth_base_url: ''
auth_scope: ''

# NB: NUXT_APP_BASE_URL is deliberately NOT set. CI sets it to
# /dashboard-frontend/ because GitHub Pages serves a project site under a
# path. On a domain root it must stay unset or every asset 404s.
