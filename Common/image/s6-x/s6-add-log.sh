#!/usr/bin/env bash
. /s6-x/service-name.sh

if [ -z "${1:-}" ]; then
  printf '%s\n' "Usage: ${0} <service-name>"
  exit 1
fi

SERVICENAME="${1}"
SERVICE="$(dv::s6_service_name "${SERVICENAME}")" || exit 1
RUNDIR="$(dv::s6_service_dir "${SERVICENAME}")" || exit 1
LOGSERVICE="$(dv::s6_log_service_name "${SERVICENAME}")" || exit 1
LOGRUNDIR="$(dv::s6_log_service_dir "${SERVICENAME}")" || exit 1
LOGRUNFILE="${LOGRUNDIR}/run"
LOGDIR="/var/log/s6/${SERVICENAME}"

if [ ! -d "${RUNDIR}" ]; then
  printf '%s\n' "S6 service directory does not exist: ${RUNDIR}"
  exit 1
fi

if [ ! -f "${RUNDIR}/type" ]; then
  printf '%s\n' "S6 service type does not exist: ${RUNDIR}/type"
  exit 1
fi

RUNTYPE="$(cat "${RUNDIR}/type")" || exit 1
if [ "${RUNTYPE}" != 'longrun' ]; then
  printf '%s\n' "S6 logging is only supported for longrun services: ${RUNDIR}"
  exit 1
fi

printf '%s\n' "Add S6 log pipeline, service: '${SERVICE}', logger: '${LOGSERVICE}', dir: '${LOGDIR}'"

rm -rf "${LOGRUNDIR}" && mkdir -p "${LOGRUNDIR}"

printf '%s\n' '#!/command/with-contenv sh' > "${LOGRUNFILE}"
printf '%s\n' "mkdir -p '${LOGDIR}'" >> "${LOGRUNFILE}"
printf '%s\n' "exec s6-log n20 s1000000 T '${LOGDIR}'" >> "${LOGRUNFILE}"
chmod 750 "${LOGRUNFILE}"

printf '%s\n' 'longrun' > "${LOGRUNDIR}/type"
chmod 640 "${LOGRUNDIR}/type"

printf '%s\n' "${SERVICE}" > "${LOGRUNDIR}/consumer-for"
chmod 640 "${LOGRUNDIR}/consumer-for"

printf '%s\n' "${LOGSERVICE}" > "${RUNDIR}/producer-for"
chmod 640 "${RUNDIR}/producer-for"

touch "/etc/s6-overlay/s6-rc.d/user/contents.d/${LOGSERVICE}"
