# Config

Host-specific configuration and secret material for the `devbox-app`
specializations (`AppleContainer`, `Docker`).

This directory is **not** committed. Files are added to `.gitignore` and copied
verbatim into the build context by `Common/build/prepare-context.sh`, which
accepts only these allowlisted regular files. Their permissions in the built
image are set by the `Containerfile` `COPY --chmod` lines listed below.

## Files

| File | Image mode (COPY --chmod) | Installed to | Purpose |
|------|---------------------------|--------------|---------|
| `authorized_keys` | `0400` | `/opt/ssh/authorized_keys` | Approved SSH public keys for user login. |
| `ssh_host_ed25519_key` | `0600` | `/opt/ssh/ssh_host_ed25519_key` | SSH host private key. |
| `ssh_host_ed25519_key.pub` | `0644` | `/opt/ssh/ssh_host_ed25519_key.pub` | SSH host public key (mirrors the private key). |
| `sshd_config` | `0644` | `/opt/ssh/sshd_config` | SSH daemon configuration. |
| `docker-daemon.json` | `0444` | `/opt/docker/daemon.json` | Docker daemon configuration. |
| `root-ca.pem` | `0444` | `/usr/local/share/ca-certificates/PersonalCA.crt` | Root CA certificate to trust. |
| `unprivileged-ports.conf` | `0644` | `/etc/sysctl.d/90-unprivileged-ports.conf` | Sysctl allowing unprivileged users to bind low ports. |

## Conventions

- Keep each file minimal — the container is generated from these, so any change
  is rebuilt.
- Never commit real keys or secrets here; the `.gitignore` prevents it.
- Never print the contents of `authorized_keys`, the SSH host key pair, or
  `root-ca.pem`.
