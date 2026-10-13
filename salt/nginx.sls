# nginx resolves proxy_pass hostnames once, at startup, and the stock unit
# only orders itself after network.target, which says nothing about DNS being
# usable - so on a cold boot it can start too early and exit. Wait for DNS,
# and retry rather than giving up after one failure.
/etc/systemd/system/nginx.service.d/wait-for-dns.conf:
  file.managed:
    - makedirs: True
    - mode: 644
    - user: root
    - group: root
    - contents: |
        [Unit]
        After=network-online.target nss-lookup.target
        Wants=network-online.target
        StartLimitIntervalSec=300
        StartLimitBurst=5

        [Service]
        Restart=on-failure
        RestartSec=10s

# The stock combined format records no timings, so a slow site cannot be told
# apart from a slow link after the fact. $request_time covers sending the
# response to the client, $upstream_response_time only our own work.
/etc/nginx/conf.d/log_format.conf:
  file.managed:
    - mode: 644
    - user: root
    - group: root
    - contents: |
        log_format timed '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         'rt=$request_time urt=$upstream_response_time';
    - watch_in:
      - service: nginx

nginx-daemon-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/nginx.service.d/wait-for-dns.conf

nginx:
  pkg:
    - installed
  service.running:
    - watch:
      - pkg: nginx
    - require:
      - file: /etc/systemd/system/nginx.service.d/wait-for-dns.conf
