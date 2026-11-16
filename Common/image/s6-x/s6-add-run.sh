#!/usr/bin/env bash
# Runefile `oneshot` requires a shell script whereas `longrun` can be a script block.
. /s6-x/service-name.sh

if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
  printf '%s\n' "Usage: ${0} <service-name> <run-type> <run-command>"
  exit 1
fi

SERVICENAME="${1}"
SERVICE="$(dv::s6_service_name "${SERVICENAME}")" || exit 1
RUNDIR="$(dv::s6_service_dir "${SERVICENAME}")" || exit 1
RUNTYPE="${2}"
RUNFILE="${RUNDIR}/$( [ "${RUNTYPE}" = "oneshot" ] && printf '%s' up || printf '%s' run )"
RUNCMD="${3}"
printf '%s\n' "Add S6 service, name: '${SERVICE}', run: '${RUNFILE}', type: '${RUNTYPE}', cmd: '${RUNCMD}'"

rm -rf "${RUNDIR}" && mkdir -p "${RUNDIR}"
printf '%s\n' '#!/command/with-contenv sh' > "${RUNFILE}"
if [ "${RUNTYPE}" = "longrun" ]; then
  printf '%s\n' 'exec 2>&1' >> "${RUNFILE}"
fi
printf '%s\n' "${RUNCMD}" >> "${RUNFILE}"
chmod 750 "${RUNFILE}"

printf '%s\n' "${RUNTYPE}" > "${RUNDIR}/type"
chmod 640 "${RUNDIR}/type"

touch "/etc/s6-overlay/s6-rc.d/user/contents.d/${SERVICE}"
