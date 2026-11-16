# DevBox-AppleContainer

A development environment that runs as a container on **Apple Container**
(Apple-silicon macOS).

## Prerequisites

- macOS (Apple-silicon)
- [Apple Container](https://github.com/apple/container)
- SSH client
- Bash
- jq
- curl
- tar
- sha256sum

## Building the image

```sh
make build
```

The build creates a build context in `tmp/`. The image tag is read from `../Common/image/tag.txt`:

```
localhost:5000/hj/devbox-apple
```
