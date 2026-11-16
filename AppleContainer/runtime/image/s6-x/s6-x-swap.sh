#!/usr/bin/env bash
/s6-x/s6-add-run.sh swap 'oneshot' \
'/s6-x/x-setup-swap.sh'
