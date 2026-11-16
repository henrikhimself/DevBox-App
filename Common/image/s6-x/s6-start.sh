#!/usr/bin/env bash
. /s6-x/service-name.sh

if [ -z "${1:-}" ]; then
  printf '%s\n' "Usage: ${0} <service-name>"
  exit 1
fi

SERVICENAME="${1}"
SERVICE="$(dv::s6_service_name "${SERVICENAME}")" || exit 1
RUNDIR="$(dv::s6_service_dir "${SERVICENAME}")" || exit 1

if [ ! -d "${RUNDIR}" ]; then
  printf '%s\n' "S6 service directory does not exist: ${RUNDIR}"
  exit 1
fi

printf '%s\n' "Starting S6 service: '${SERVICE}'"
exec s6-rc -u change "${SERVICE}"
