#!/usr/bin/env bash
. /s6-x/service-name.sh

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  printf '%s\n' "Usage: ${0} <service-name> <check-command>"
  exit 1
fi

SERVICENAME="${1}"
SERVICE="$(dv::s6_service_name "${SERVICENAME}")" || exit 1
RUNDIR="$(dv::s6_service_dir "${SERVICENAME}")" || exit 1
RUNFILE="${RUNDIR}/run"
WRAPPED_RUNFILE="${RUNDIR}/run.original"
CHECKDIR="${RUNDIR}/data"
CHECKFILE="${CHECKDIR}/check"
CHECKCMD="${2}"

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
  printf '%s\n' "Readiness checks are only supported for longrun services: ${RUNDIR}"
  exit 1
fi

if [ ! -f "${RUNFILE}" ] && [ ! -f "${WRAPPED_RUNFILE}" ]; then
  printf '%s\n' "Run file does not exist for service: ${RUNDIR}"
  exit 1
fi

if [ ! -f "${WRAPPED_RUNFILE}" ]; then
  mv "${RUNFILE}" "${WRAPPED_RUNFILE}"
fi

mkdir -p "${CHECKDIR}"

printf '%s\n' '#!/command/with-contenv sh' > "${CHECKFILE}"
printf '%s\n' "${CHECKCMD}" >> "${CHECKFILE}"
chmod 750 "${CHECKFILE}"

printf '%s\n' '3' > "${RUNDIR}/notification-fd"

printf '%s\n' '#!/command/with-contenv sh' > "${RUNFILE}"
printf '%s\n' "exec s6-notifyoncheck -n 0 ${WRAPPED_RUNFILE} \"\$@\"" >> "${RUNFILE}"
chmod 750 "${RUNFILE}"

printf '%s\n' "Add S6 readiness check, service: '${SERVICE}', run: '${RUNFILE}', check: '${CHECKFILE}'"
