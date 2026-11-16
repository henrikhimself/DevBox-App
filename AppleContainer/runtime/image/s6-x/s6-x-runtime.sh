#!/usr/bin/env bash
# Apple Container runtime assembly, run after the common services exist:
# instantiate the swap oneshot and order it before procps.
/s6-x/s6-x-swap.sh
/s6-x/s6-add-depend.sh swap procps
