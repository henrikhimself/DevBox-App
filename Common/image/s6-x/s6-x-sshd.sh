#!/usr/bin/env bash
/s6-x/s6-add-run.sh sshd 'longrun' \
'install -d -m 755 /run/sshd
mkdir -m 755 -p /home/bob && chown bob:bob /home/bob
mkdir -m 700 -p /home/bob/.ssh && chown bob:bob /home/bob/.ssh
exec s6-setuidgid bob /usr/sbin/sshd -D -e -f /opt/ssh/sshd_config'

/s6-x/s6-add-log.sh sshd

# shellcheck disable=SC2016
/s6-x/s6-add-readiness.sh sshd \
'test -s /opt/ssh/sshd.pid && kill -0 "$(cat /opt/ssh/sshd.pid)"'
