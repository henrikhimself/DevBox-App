# DevBox Specification

## Scope of this document

This document stores knowledge that the source code does not show.
Read this document with the source code.
The source code shows the implementation. This document shows the decisions, the rationale, the constraints, and the verification policy.
If the source code disagrees with this document, then update both at the same time. The user must approve the change.
This document does not state the source code. It does not list installed packages. It does not record file modes or command options. The source code shows these details.

## 1. Purpose

The DevBox project builds two images. Both images are daily-use development environments. The two images share common requirements. The project keeps the common requirements in this document. The project also keeps two specialization documents.

The specialization split is a decision. The split reduces confusion about which image to use.

- `devbox-docker` targets native Linux amd64.
- `devbox-apple` targets Apple-silicon macOS arm64.

Linux arm64 is not a supported Docker target.
The Apple specialization requires macOS.
The Apple specialization is not a Linux arm64 fallback.
The specializations define platform-specific requirements. These requirements add to the common requirements.
This document does not say that the Docker specialization is implemented or verified.

## 2. Supported hosts and platforms

Apple Container is the only supported runtime for the Apple specialization.
The host must be Apple-silicon macOS (`arm64`).
Docker Engine and Docker Desktop are not alternative host runtimes for this specialization.
This restriction does not remove the common in-guest rootless Docker daemon.

Apple Container runs each Linux container in a lightweight VM. The guest kernel operations happen inside the VM. The operations do not happen in the Darwin host kernel.

The Docker specialization targets native Docker Engine on Linux hosts with amd64 processors.
The outer Docker daemon must be rootful.
The outer daemon must not use `userns-remap`.
Docker Desktop, a rootless outer daemon, and other host operating systems are out of scope.
Docker Engine uses the host kernel. This specialization does not start a VM for each container.

The build workflow is native and single-platform.
A build uses only the assigned architecture row.
The rows are not a list of architectures that both specializations support.

Multi-platform registry publication is out of scope.
Emulated builds are out of scope.
A build must not silently select an emulated platform.

## 3. Privilege and security baseline

Both launch workflows use `--cap-add ALL`.
This capability supports guest hostname setup and the in-guest rootless Docker daemon.
The capability does not by itself allow unrestricted device access.

The Docker specialization must also use `--privileged`.
The Apple specialization must not use `--privileged`.
Neither runtime may mount a host Docker socket.
The in-guest Docker CLI must talk to the in-guest rootless daemon, and it must not talk to a host daemon.

The `--privileged` requirement for the Docker specialization comes from feasibility results. The source code does not show these results.

- The nested rootless `dockerd` needs the rootlesskit detached-namespace bind mount.
- It needs nested mount and user-namespace operations.
- It needs cgroup and device access.

The Docker default confinement blocks these operations.
The blocks come from the `docker-default` AppArmor profile, the built-in seccomp profile, and the masked or read-only `/proc` and `/sys` paths.
These blocks happen even with `--cap-add ALL`.
Feasibility testing tested other options.
The option `--cap-add ALL` plus explicit FUSE and TUN devices plus seccomp and AppArmor exceptions was insufficient.
Apple Container has no such confinement.
The Apple specialization does not receive the `--privileged` flag.

`--privileged` makes the outer container effectively root on the host kernel.
The container has access to all host devices.
The container is a trusted development environment.
It is not an isolation boundary.
Do not run untrusted workloads in the container.

Do not add these things without approval:

- host namespaces (`--pid`, `--network`, `--ipc`, `--userns`)
- extra mounts
- host sysctl changes
- `--cap-drop`
- remote, rootless, or remapped outer engines
- automatic fallback to another runtime

If the guest daemon cannot start or run containers, report the blocker.
Do not silently add privileges.
Do not silently add device access, host namespaces, extra mounts, host sysctl changes, or further security exceptions.

## 4. Guest device handling

The Apple specialization does not use `--device` passthrough.
It does not use seccomp or AppArmor launch exceptions.
The `dockerd` service helper creates the guest devices inside the VM.
The helper creates `/dev/net/tun` and `/dev/fuse`.
These operations are guest-internal.
They do not require the Darwin host to expose device nodes.
The helper prepares the runtime directories with the specified ownership and mode.

The Docker specialization needs the host to provide `/dev/fuse` and `/dev/net/tun`.
The outer container gets these devices by explicit passthrough.
The preflight check reports a clear error if the devices are absent.
The guest hook validates the devices.
The guest service setup must use the devices that the launch provides.
The service setup must not unconditionally recreate the device nodes.

The Docker specialization must not change host security policy automatically.
Host restrictions such as SELinux policy need validation.
The approved flags do not show compatibility with every Linux distribution.

## 5. Swap and kernel behavior

The Apple specialization instantiates a `swap` service during build.
The service creates and starts `/swap/swapfile`.
The file size is twice the guest memory.
This swap belongs to the guest VM.
The helper does not provision macOS swap.
`/swap` is not a profile mount.
The profile backup does not include `/swap`.

The Docker specialization does not create a swap service.
It does not create `/swap/swapfile`.
Swap provisioning is the job of the Linux host.
The `procps` service must not depend on swap.

The `procps` service treats unsupported sysctl writes as non-fatal.
The service logs the writes.
The service must not fail on one unsupported key.

The Apple specialization must not work around denied sysctl writes by changing the Darwin host settings.
The kernel operations happen in the guest VM.

The Docker specialization does not use a separate VM.
The containers share the host kernel.
The launch scripts must not compensate for denied writes by granting host namespace access or changing host-wide settings.

## 6. Build and architecture mapping

The build workflow is native and single-platform.
Each specialization uses only its assigned architecture row.
The rows are not a list of architectures that both specializations support.
The architecture assignment is the specialization split (see section 2).
The default tag identifies the locally built image.

The build must match the selected platform for every architecture-dependent download.
The build uses a stamp under `tmp/state/` to decide whether to rebuild.
The stamp records fingerprints of the build inputs, the downloaded archives, the platform, and the image tag.
The build rebuilds if the stamp is missing or changed.
The generated build context is disposable.
The generated context is not an additional maintained source copy.
