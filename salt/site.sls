# Deploys a Nuxt application behind nginx, run by pm2.
#
# Everything configurable lives in pillar/. Target Ubuntu 22.04 or 24.04.

{% from 'lib.sls' import createuser, nginx %}

include:
  - core
  - nginx
  - letsencrypt

{% set user          = pillar.user %}
{% set name          = pillar.name %}
{% set codedir       = pillar.frontend_codedir %}
{% set giturl        = pillar.frontend_url %}
{% set branch        = pillar.frontend_branch %}
{% set node_version  = pillar.get('node_version', '22') %}
{% set pm2_port      = pillar.pm2_port %}
{% set servername    = pillar.servername %}
{% set serveraliases = pillar.get('serveraliases', []) %}
{% set https         = pillar.https %}
{% set le_email      = pillar.get('letsencrypt_email', '') %}
{% set uses_ssh_key  = giturl.startswith('git@') %}

{{ createuser(user) }}

##################################################################### Packages
site-deps:
  pkg.installed:
    - pkgs:
      - gcc
      - make
      - ca-certificates
    - watch_in:
      - service: nginx

##################################################################### Node (nvm)
site-nvm-install:
  cmd.run:
    - name: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
    - runas: {{ user }}
    - shell: /bin/bash
    - unless: test -s "$HOME/.nvm/nvm.sh"
    - require:
      - pkg: site-deps
      - user: {{ user }}_user_exists

site-node-install:
  cmd.run:
    - name: . "$HOME/.nvm/nvm.sh" && nvm install {{ node_version }} && nvm use {{ node_version }}
    - runas: {{ user }}
    - shell: /bin/bash
    - unless: . "$HOME/.nvm/nvm.sh" && nvm ls {{ node_version }} >/dev/null 2>&1
    - require:
      - cmd: site-nvm-install

##################################################################### Yarn
# apt-key is deprecated and 24.04 ignores its keyring, so the repo fails to
# verify. Install the key to /usr/share/keyrings and reference it explicitly.
site-yarn-key:
  cmd.run:
    - name: >
        curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg
        | gpg --dearmor -o /usr/share/keyrings/yarnkey.gpg
    - runas: root
    - creates: /usr/share/keyrings/yarnkey.gpg
    - require:
      - pkg: site-deps

site-yarn-list:
  file.managed:
    - name: /etc/apt/sources.list.d/yarn.list
    - mode: 644
    - user: root
    - group: root
    - contents: |
        deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main
    - require:
      - cmd: site-yarn-key

site-yarn-refresh:
  cmd.run:
    - name: apt-get update
    - runas: root
    - onchanges:
      - file: site-yarn-list

site-yarn:
  pkg.installed:
    - pkgs:
      - yarn
    - require:
      - cmd: site-yarn-refresh

##################################################################### Deploy key
{% if uses_ssh_key %}
# Only needed while the application repository is private. Supply the key as
# salt/files/deploy (and .pub) - both are gitignored. Switch frontend_url to
# an https:// URL if the repository becomes public and this block is skipped.
/home/{{ user }}/.ssh:
  file.directory:
    - user: {{ user }}
    - group: {{ user }}
    - mode: 700
    - makedirs: True
    - require:
      - user: {{ user }}_user_exists

/home/{{ user }}/.ssh/deploy:
  file.managed:
    - source: salt://files/deploy
    - user: {{ user }}
    - group: {{ user }}
    - mode: 600
    - require:
      - file: /home/{{ user }}/.ssh

/home/{{ user }}/.ssh/config:
  file.managed:
    - user: {{ user }}
    - group: {{ user }}
    - mode: 600
    - contents: |
        Host github.com
          IdentityFile /home/{{ user }}/.ssh/deploy
          IdentitiesOnly yes
          StrictHostKeyChecking yes
    - require:
      - file: /home/{{ user }}/.ssh/deploy

# Pin github's host keys rather than trusting on first use.
/home/{{ user }}/.ssh/known_hosts:
  ssh_known_hosts.present:
    - name: github.com
    - user: {{ user }}
    - require:
      - file: /home/{{ user }}/.ssh
{% endif %}

##################################################################### Application
{{ codedir }}:
  git.latest:
    - name: {{ giturl }}
    - rev: {{ branch }}
    - target: {{ codedir }}
    - user: {{ user }}
    - force_fetch: True
    - force_reset: True
    - depth: 1
    - require:
      - pkg: git
{% if uses_ssh_key %}
      - file: /home/{{ user }}/.ssh/config
      - ssh_known_hosts: /home/{{ user }}/.ssh/known_hosts
{% endif %}

{{ codedir }}install-packages:
  cmd.run:
    - name: |
        set -e
        . "$HOME/.nvm/nvm.sh" && nvm use {{ node_version }}
        yarn install --frozen-lockfile
    - runas: {{ user }}
    - cwd: {{ codedir }}
    - shell: /bin/bash
    - require:
      - cmd: site-node-install
      - pkg: site-yarn
    - onchanges:
      - git: {{ codedir }}

# Build into .output, then swap .output-latest in one step. pm2 serves
# .output-latest, so a failed build leaves the previous one running rather
# than half-replacing it. The block scalar matters: without it YAML folds
# these lines into a single command and the copy never happens.
{{ codedir }}build:
  cmd.run:
    - name: |
        set -e
        . "$HOME/.nvm/nvm.sh" && nvm use {{ node_version }}
        yarn run build
        rm -rf .output-latest
        cp -r .output .output-latest
    - runas: {{ user }}
    - cwd: {{ codedir }}
    - shell: /bin/bash
    - require:
      - cmd: {{ codedir }}install-packages
    - onchanges:
      - git: {{ codedir }}

##################################################################### pm2
{{ codedir }}ecosystem.config.cjs:
  file.managed:
    - source: salt://files/ecosystem.config.cjs
    - user: {{ user }}
    - group: {{ user }}
    - template: jinja
    - context:
        pm2_port: {{ pm2_port | string }}
        name: {{ name }}
    - require:
      - git: {{ codedir }}

site-install-pm2:
  cmd.run:
    - name: . "$HOME/.nvm/nvm.sh" && nvm use {{ node_version }} && yarn global add pm2
    - runas: {{ user }}
    - shell: /bin/bash
    - unless: . "$HOME/.nvm/nvm.sh" && command -v pm2 >/dev/null 2>&1
    - require:
      - cmd: site-node-install
      - pkg: site-yarn

{{ codedir }}pm2-start:
  cmd.run:
    - name: |
        set -e
        . "$HOME/.nvm/nvm.sh" && nvm use {{ node_version }}
        export PATH="$HOME/.yarn/bin:$PATH"
        pm2 start ecosystem.config.cjs --update-env
        pm2 save
    - cwd: {{ codedir }}
    - runas: {{ user }}
    - shell: /bin/bash
    - require:
      - cmd: site-install-pm2
      - file: {{ codedir }}ecosystem.config.cjs
    - onchanges:
      - cmd: {{ codedir }}build
      - file: {{ codedir }}ecosystem.config.cjs

# Survive a reboot.
site-pm2-startup:
  cmd.run:
    - name: >
        export NVM_DIR="/home/{{ user }}/.nvm" && . "$NVM_DIR/nvm.sh"
        && nvm use {{ node_version }}
        && export PATH="/home/{{ user }}/.yarn/bin:$PATH"
        && pm2 startup systemd -u {{ user }} --hp /home/{{ user }}
    - runas: root
    - shell: /bin/bash
    - unless: test -f /etc/systemd/system/pm2-{{ user }}.service
    - require:
      - cmd: site-install-pm2

##################################################################### Logs
# pm2 writes under the app user's home, outside the /var/www/logs glob, so it
# needs its own rule or it grows without bound.
/etc/logrotate.d/pm2-{{ user }}:
  file.managed:
    - mode: 644
    - contents: |
        /home/{{ user }}/.pm2/logs/*.log {
            daily
            rotate 14
            maxsize 100M
            missingok
            notifempty
            compress
            delaycompress
            copytruncate
            su {{ user }} {{ user }}
        }

/etc/logrotate.d/{{ name }}-nginx:
  file.managed:
    - mode: 644
    - contents: |
        /var/www/logs/*.log {
            su root www-data
            daily
            rotate 14
            maxsize 200M
            missingok
            notifempty
            compress
            delaycompress
            copytruncate
            create 0640 root www-data
        }

##################################################################### nginx
{% set extracontext %}
user: {{ user }}
name: {{ name }}
servername: {{ servername }}
serveraliases: {{ serveraliases }}
pm2_port: {{ pm2_port }}
https: {{ https }}
{% endset %}

/etc/nginx/sites-available/{{ name }}.conf:
  file.managed:
    - source: salt://files/nginx.conf
    - template: jinja
    - context:
        {{ extracontext | indent(8) }}
    - watch_in:
      - service: nginx

{{ nginx(name=name,
         servername=servername,
         serveraliases=serveraliases,
         https=https,
         letsencrypt_email=le_email) }}
