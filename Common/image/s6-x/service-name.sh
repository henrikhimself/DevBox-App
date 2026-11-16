#!/usr/bin/env bash

dv::s6_service_name_validate() {
  case "${1:-}" in
    '')
      printf '%s\n' 'Service name is required.' >&2
      return 1
      ;;
    *[!A-Za-z0-9._-]*)
      printf '%s\n' "Unsupported service name: ${1}" >&2
      return 1
      ;;
  esac
}

dv::s6_service_name() {
  dv::s6_service_name_validate "${1}" || return 1
  printf 'service-%s\n' "${1}"
}

dv::s6_service_dir() {
  dv::s6_service_name_validate "${1}" || return 1
  SERVICE_NAME="$(dv::s6_service_name "${1}")" || return 1
  printf '/etc/s6-overlay/s6-rc.d/%s\n' "${SERVICE_NAME}"
}

dv::s6_log_service_name() {
  dv::s6_service_name_validate "${1}" || return 1
  printf 'log-%s\n' "${1}"
}

dv::s6_log_service_dir() {
  dv::s6_service_name_validate "${1}" || return 1
  LOG_SERVICE_NAME="$(dv::s6_log_service_name "${1}")" || return 1
  printf '/etc/s6-overlay/s6-rc.d/%s\n' "${LOG_SERVICE_NAME}"
}
