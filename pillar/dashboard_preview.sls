# Everything site-specific lives here. Nothing below this file should need
# editing to stand up another instance.

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

# Node major version. The app's .nvmrc should agree with this.
node_version: '22'
