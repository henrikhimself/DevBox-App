#!/usr/bin/env sh
export DOTNET_ROOT="${HOME}/.dotnet"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export PATH="${PATH}:${DOTNET_ROOT}:${DOTNET_ROOT}/tools"

if [ -z "${SSL_CERT_DIR}" ]; then
  export SSL_CERT_DIR="/etc/ssl/certs:${HOME}/.aspnet/dev-certs/trust"
else
  export SSL_CERT_DIR="${SSL_CERT_DIR}:${HOME}/.aspnet/dev-certs/trust"
fi

export ASPIRE_ENABLE_CONTAINER_TUNNEL=true
