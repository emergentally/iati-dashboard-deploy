#!/bin/bash
# Deploy a site:  ./up.sh dashboard-preview
#
# Work around https://github.com/saltstack/salt/issues/68755: salt-ssh's thin
# payload bundles salt/utils/configparser.py into extmods/utils/, which
# shadows the stdlib configparser module and breaks pkg.* states entirely.
# This gets regenerated (and re-breaks) every time the thin payload is
# rebuilt, so clear it before every run rather than only when it bites.
set -u
TARGET="${1:?usage: ./up.sh <target-from-roster>}"

salt-ssh "$TARGET" cmd.run \
  "rm -f /var/tmp/.root_*_salt/running_data/var/cache/salt/minion/extmods/utils/configparser.py \
          /var/tmp/.root_*_salt/running_data/var/cache/salt/minion/extmods/utils/__pycache__/configparser*.pyc" -i

salt-ssh "$TARGET" state.highstate -v --state-output=mixed -i
