#!/usr/bin/env bash
. /s6-x/service-name.sh

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  printf '%s\n' "Usage: ${0} <service-name> <hostname-label>"
  exit 1
fi

dv::s6_hostname_label_validate() {
  case "${1:-}" in
    '')
      printf '%s\n' 'Hostname label is required.' >&2
      return 1
      ;;
    *.*)
      printf '%s\n' "Hostname label must not contain dots: ${1}" >&2
      return 1
      ;;
    *[!A-Za-z0-9-]*)
      printf '%s\n' "Unsupported hostname label: ${1}" >&2
      return 1
      ;;
    -*|*-)
      printf '%s\n' "Hostname label must not start or end with a hyphen: ${1}" >&2
      return 1
      ;;
  esac
}

SERVICENAME="${1}"
HOSTNAME_LABEL_RAW="${2}"
HOSTNAME_LABEL="$(printf '%s' "${HOSTNAME_LABEL_RAW}" | tr '[:upper:]' '[:lower:]')"
RUNDIR="$(dv::s6_service_dir "${SERVICENAME}")" || exit 1
HOSTNAME_FILE="${RUNDIR}/hostname.txt"

dv::s6_hostname_label_validate "${HOSTNAME_LABEL}" || exit 1

if [ ! -d "${RUNDIR}" ]; then
  printf '%s\n' "S6 service directory does not exist: ${RUNDIR}" >&2
  exit 1
fi

printf '%s\n' "Add S6 hostname, service: '${SERVICENAME}', file: '${HOSTNAME_FILE}', hostname: '${HOSTNAME_LABEL}'"
printf '%s\n' "${HOSTNAME_LABEL}" > "${HOSTNAME_FILE}"
chmod 640 "${HOSTNAME_FILE}"
