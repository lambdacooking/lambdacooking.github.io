---
title: Installing OpenVPN from GitHub Source with make install
lang: en
permalink: /en/openvpn-install-from-github-source
author: ramen
date: 2026-10-05 14:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, source-build]
---

### Scope and version

This walkthrough adapts the [official installation guide](https://openvpn.net/community-docs/installing-openvpn.html) to a GitHub checkout. The example targets Ubuntu 24.04; Debian-family releases may require package adjustments. It installs the OpenVPN executable, not a configured VPN service.

The commands pin [v2.7.7](https://github.com/OpenVPN/openvpn/releases/tag/v2.7.7), the latest GitHub release checked on October 5, 2026. Recheck releases before a later installation; do not assume this tag remains current.

### 1. Install build dependencies

Use APT for the toolchain and libraries, then build OpenVPN itself from source. The package selection follows the project's [Linux CI dependencies](https://github.com/OpenVPN/openvpn/blob/v2.7.7/.github/workflows/build.yaml).

```bash
sudo apt update
sudo apt install -y \
  git ca-certificates build-essential autoconf automake libtool pkg-config \
  libssl-dev liblzo2-dev liblz4-dev libcap-ng-dev libnl-genl-3-dev \
  libpam0g-dev libcmocka-dev python3-docutils
```

`libssl-dev` provides OpenSSL headers; the LZO/LZ4 packages satisfy the default compression-library checks. Installing those libraries does not enable compression in a VPN connection. `libcmocka-dev` supports unit tests, and `python3-docutils` supplies documentation generators. Optional features have additional requirements in [`configure.ac`](https://github.com/OpenVPN/openvpn/blob/v2.7.7/configure.ac).

### 2. Download the GitHub source

Run this from a working directory where `openvpn-2.7.7` does not already exist:

```bash
git clone --depth 1 --branch v2.7.7 \
  https://github.com/OpenVPN/openvpn.git openvpn-2.7.7
cd openvpn-2.7.7
git describe --tags --exact-match
git rev-parse HEAD
```

A detached-HEAD notice is expected when checking out a tag. Record the commit ID with your build notes. A version tag identifies the selected source; it is not, by itself, signature verification.

### 3. Generate, configure, build and check

A Git checkout needs the Autotools generation step described in [`INSTALL`](https://github.com/OpenVPN/openvpn/blob/v2.7.7/INSTALL). Run the following as your normal user; `&&` stops the sequence if a step fails.

```bash
autoreconf -ivf &&
./configure --prefix=/usr/local --with-crypto-library=openssl &&
make -j"$(nproc)" &&
make check
```

The chosen prefix keeps this build under `/usr/local`. Review test failures before continuing. `make check` is not proof that your real client/server network works.

### 4. Install and verify the exact binary

After the previous sequence succeeds, install with administrator privileges:

```bash
sudo make install
/usr/local/sbin/openvpn --version
```

Check for version `2.7.7` in the output. An existing package installation may provide another executable, so compare paths rather than trusting an unqualified command:

```bash
type -a openvpn
/usr/local/sbin/openvpn --version
```

APT does not track files installed this way. Keep the source tree and build options for maintenance, and apply future OpenVPN updates deliberately.

### Common stopping points

| Symptom | What to check |
| --- | --- |
| `autoreconf: command not found` | Install the Autotools packages from step 1. |
| Missing `configure` | Run `autoreconf -ivf` in the repository root. |
| Missing library or header | Inspect the first configure error and `config.log`; check the matching development package. |
| Unexpected version | Use `/usr/local/sbin/openvpn` explicitly. |

### What remains after installation

Certificates/keys, client and server configuration, routing, firewall rules and any systemd service setup are separate tasks. This article does not start a service or modify network routes. Building OpenVPN also does not install a Linux DCO kernel module; DCO availability depends on the running kernel and environment.
