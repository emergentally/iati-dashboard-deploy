# Certificate issuance and renewal. The 'nginx' macro in lib.sls does the
# initial issuance; this keeps it renewed.

certbot:
  pkg.installed

/var/www/html/.well-known/acme-challenge:
  file.directory:
    - user: www-data
    - group: www-data
    - makedirs: True

cron-letsencrypt-renew:
  cron.present:
    - identifier: letsencrypt-renew
    - name: certbot renew --nginx --no-self-upgrade >/dev/null 2>&1
    - user: root
    - minute: random
    - hour: 7
    - require:
      - pkg: certbot
