# Macros shared by the states in this repo.

#-----------------------------------------------------------------------
# createuser
#-----------------------------------------------------------------------
{% macro createuser(user) %}

{{ user }}_user_exists:
  user.present:
    - name: {{ user }}
    - home: /home/{{ user }}
    - order: 1
    - shell: /bin/bash

{% endmacro %}


#-----------------------------------------------------------------------
# nginx: obtain a certificate (optionally) and enable the site
#-----------------------------------------------------------------------
{% macro nginx(name, servername, serveraliases=[], https='', letsencrypt_email='') %}

{% if https in ('yes', 'force', 'certonly') %}
{% set domainargs = "-d " + " -d ".join([servername] + serveraliases) %}

{{ servername }}_acquire_certs:
  cmd.run:
    - name: >
        certbot certonly --non-interactive --no-self-upgrade --expand
        --email {{ letsencrypt_email }} --agree-tos
        --webroot --webroot-path /var/www/html/ {{ domainargs }}
    - creates:
      - /etc/letsencrypt/live/{{ servername }}/fullchain.pem
      - /etc/letsencrypt/live/{{ servername }}/privkey.pem
    - require:
      - pkg: certbot
      - file: /etc/nginx/sites-available/{{ name }}.conf
      - file: /etc/nginx/sites-enabled/{{ name }}.conf
      - file: /var/www/html/.well-known/acme-challenge
    - watch_in:
      - service: nginx

{% endif %}

/etc/nginx/sites-enabled/{{ name }}.conf:
  file.symlink:
    - target: /etc/nginx/sites-available/{{ name }}.conf
    - require:
      - file: /etc/nginx/sites-available/{{ name }}.conf
    - makedirs: True
    - watch_in:
      - service: nginx

{% endmacro %}
