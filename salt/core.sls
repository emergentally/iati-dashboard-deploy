# A minimal baseline for the host. Deliberately smaller than a general-purpose
# server baseline: this box serves one static-ish Node app and nothing else.

git:
  pkg.installed

useful-shell-commands:
  pkg.installed:
    - pkgs:
      - curl
      - unzip
      - vim
      - logrotate

# fail2ban: ssh only. There is no application login to protect here.
fail2ban:
  pkg.installed

f2b-startup:
  service.running:
    - name: fail2ban
    - enable: True
    - require:
      - pkg: fail2ban

# Keys only - no password login.
/etc/ssh/sshd_config:
  file.replace:
    - pattern: '^#?PasswordAuthentication .*'
    - repl: 'PasswordAuthentication no'
    - append_if_not_found: True

ssh:
  service.running:
    - name: ssh
    - reload: True
    - watch:
      - file: /etc/ssh/sshd_config

# Security updates without manual intervention.
unattended-upgrades:
  pkg.installed

/etc/apt/apt.conf.d/10periodic:
  file.managed:
    - mode: 644
    - contents: |
        APT::Periodic::Update-Package-Lists "1";
        APT::Periodic::Download-Upgradeable-Packages "1";
        APT::Periodic::AutocleanInterval "7";
        APT::Periodic::Unattended-Upgrade "1";
    - require:
      - pkg: unattended-upgrades

# A crash writes a core file into the process cwd - always the app directory -
# and they are large enough to fill the disk.
/etc/sysctl.d/60-no-core-dumps.conf:
  file.managed:
    - mode: 644
    - contents: |
        kernel.core_pattern=|/bin/false
        fs.suid_dumpable=0

apply-no-core-dumps:
  cmd.run:
    - name: sysctl --system
    - onchanges:
      - file: /etc/sysctl.d/60-no-core-dumps.conf

# Shared log directory, so nginx and the app logs land somewhere logrotate
# knows about.
/var/www/logs/:
  file.directory:
    - user: www-data
    - group: www-data
    - mode: 775
    - makedirs: True

# Maintenance page, served as a 503 while /var/www/maintenance/<name>.on
# exists. See the comment in salt/files/nginx.conf.
/var/www/maintenance/:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

/var/www/maintenance/maintenance.html:
  file.managed:
    - source: salt://files/maintenance.html
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: /var/www/maintenance/
