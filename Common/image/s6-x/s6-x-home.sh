#!/usr/bin/env bash
/s6-x/s6-add-run.sh home 'oneshot' \
'/s6-x/x-setup-home.sh'
