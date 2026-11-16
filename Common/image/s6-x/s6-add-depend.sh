#!/usr/bin/env bash
# shellcheck disable=SC2310 # Validation helpers intentionally return non-zero for invalid service names.
set -eu
. /s6-x/service-name.sh

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  printf '%s\n' "Usage: ${0} <predecessor-service-name> <successor-service-name>"
  exit 1
fi

PREDECESSOR_SERVICENAME="${1}"
SUCCESSOR_SERVICENAME="${2}"
PREDECESSOR_SERVICE="$(dv::s6_service_name "${PREDECESSOR_SERVICENAME}")" || exit 1
PREDECESSOR_RUNDIR="$(dv::s6_service_dir "${PREDECESSOR_SERVICENAME}")" || exit 1
SUCCESSOR_SERVICE="$(dv::s6_service_name "${SUCCESSOR_SERVICENAME}")" || exit 1
SUCCESSOR_RUNDIR="$(dv::s6_service_dir "${SUCCESSOR_SERVICENAME}")" || exit 1

if [ ! -d "${PREDECESSOR_RUNDIR}" ]; then
  printf '%s\n' "S6 service directory does not exist: ${PREDECESSOR_RUNDIR}"
  exit 1
fi

if [ ! -d "${SUCCESSOR_RUNDIR}" ]; then
  printf '%s\n' "S6 service directory does not exist: ${SUCCESSOR_RUNDIR}"
  exit 1
fi

DEPENDENCIES_DIR="${SUCCESSOR_RUNDIR}/dependencies.d"
mkdir -p "${DEPENDENCIES_DIR}"
chmod 755 "${DEPENDENCIES_DIR}"
: > "${DEPENDENCIES_DIR}/${PREDECESSOR_SERVICE}"
chmod 644 "${DEPENDENCIES_DIR}/${PREDECESSOR_SERVICE}"

printf '%s\n' "Add S6 dependency, predecessor: '${PREDECESSOR_SERVICE}', successor: '${SUCCESSOR_SERVICE}'"
