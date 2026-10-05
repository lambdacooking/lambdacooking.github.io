---
title: Creating an OpenVPN CA and Server and Client Certificates with Easy-RSA 3
lang: en
permalink: /en/openvpn-ca-certificates-easyrsa3
author: ramen
date: 2026-10-05 14:30:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, pki, easy-rsa, certificates]
---

### Use Easy-RSA 3 on Ubuntu 24.04

I ran into trouble using Easy-RSA 2 on Ubuntu 24.04, so I used Easy-RSA 3 for this setup. **Prefer Easy-RSA 3 for a new deployment.** The number refers to the tool version, not the RSA key size or a separate cryptographic algorithm.

The [OpenVPN CA guide](https://openvpn.net/community-docs/setting-up-your-own-certificate-authority--ca--and-generating-certificates-and-keys-for-an-openvpn-server-and-multiple-clients.html) already points Unix users toward version 3, but its `./build-ca` and `./build-key-server` walkthrough still follows version 2. Examples that have not been updated for the current environment may have contributed to the issue. Without analyzing the error logs, I cannot conclude that Easy-RSA 2 always fails on Ubuntu 24.04.

This walkthrough pins [Easy-RSA 3.2.7](https://github.com/OpenVPN/easy-rsa/releases/tag/v3.2.7), the latest release checked on October 5, 2026. Check releases again when using this guide later.

### 1. Prepare dependencies before build-ca

Certificate generation requires the **`openssl` executable**. The command below also includes development packages for the OpenVPN source-build environment from the previous post. They are not all prerequisites for `build-ca`.

| Item from my dependency notes | Ubuntu package or purpose |
|---|---|
| `pkg-config` | Library discovery during the OpenVPN build |
| `libnl-genl-3.5.0` | Not the package name to install; the build queries the `libnl-genl-3.0` module and checks its version separately |
| `libnl-3-dev`, `libnl-genl-3-dev` | Netlink development files used by Linux DCO build checks |
| `libcap-ng-dev` | Linux capability management development files |
| `libssl-dev` | OpenSSL headers, distinct from the `openssl` command |
| `liblz4-dev`, `liblzo2-dev` | Compression-library build dependencies |
| `libpam-dev` | Use the concrete `libpam0g-dev` package here for building the PAM plugin |

See the OpenVPN [build configuration](https://github.com/OpenVPN/openvpn/blob/v2.7.7/configure.ac) and [Linux CI](https://github.com/OpenVPN/openvpn/blob/v2.7.7/.github/workflows/build.yaml). Installing compression libraries does not enable VPN compression.

```bash
sudo apt update
sudo apt install -y git ca-certificates openssl pkg-config \
  libnl-3-dev libnl-genl-3-dev libcap-ng-dev libssl-dev \
  liblz4-dev liblzo2-dev libpam0g-dev
openssl version
pkg-config --modversion libnl-genl-3.0
```

This is not the complete OpenVPN compiler toolchain; see the [source installation post](../openvpn-install-from-github-source/) for that procedure. A separate CA machine does not need the OpenVPN development packages.

### 2. Download the complete Easy-RSA source

Use a normal user account and a dedicated location outside the blog repository. The checkout directory below must not already exist.

```bash
umask 077
mkdir -p "$HOME/vpn-pki-work"
cd "$HOME/vpn-pki-work"
git clone --depth 1 --branch v3.2.7 \
  https://github.com/OpenVPN/easy-rsa.git easy-rsa-3.2.7
cd easy-rsa-3.2.7/easyrsa3
./easyrsa --version
ls easyrsa openssl-easyrsa.cnf vars.example x509-types
```

Keep `openssl-easyrsa.cnf` and `x509-types/` alongside `easyrsa`; do not copy only the script. `vars.example` provides configuration examples. Easy-RSA itself does not require `make install`. [Official documentation](https://easy-rsa.readthedocs.io/en/latest/)

### 3. Initialize a new PKI and create the CA

These commands are for a new CA. **Do not rerun `init-pki` on an existing PKI**, and do not overwrite an existing `vars` file.

```bash
cat > vars <<'EOF'
set_var EASYRSA_ALGO rsa
set_var EASYRSA_KEY_SIZE 3072
set_var EASYRSA_DIGEST sha256
EOF
./easyrsa init-pki
./easyrsa build-ca
```

Choose a strong CA private-key passphrase and a recognizable Common Name, such as `SnackChocopie VPN CA`. Do not run the Easy-RSA 2 command `. ./vars`.

`pki/ca.crt` is the public trust certificate; `pki/private/ca.key` is the secret signing key. Never distribute the CA key to VPN servers or clients. Prefer a separate, offline CA.

### 4. Issue a server certificate and multiple client certificates

For a compact demonstration, these commands generate keys and sign them in the CA workspace. In production, preferably generate each private key and CSR on its own device and send only the CSR to the CA.

```bash
./easyrsa build-server-full server nopass
./easyrsa build-client-full client1
./easyrsa build-client-full client2
./easyrsa build-client-full client3
```

Review confirmation prompts and enter the CA passphrase when requested. Set a separate private-key passphrase for each client. Use a unique certificate name per user or device; do not share a single key.

The server's `nopass` option leaves **that private key unencrypted** to support unattended startup. Restrict file access carefully. Omit it if your operation supports entering a key passphrase. Do not use it for the CA. Command behavior is defined in the [3.2.7 script](https://github.com/OpenVPN/easy-rsa/blob/v3.2.7/easyrsa3/easyrsa).

### 5. Verify and distribute only the required files

```bash
openssl verify -CAfile pki/ca.crt -purpose sslserver pki/issued/server.crt
openssl verify -CAfile pki/ca.crt -purpose sslclient \
  pki/issued/client1.crt pki/issued/client2.crt pki/issued/client3.crt
openssl x509 -in pki/issued/server.crt -noout -subject -issuer -dates
```

Expect `OK` and review validity dates. This does not replace an actual VPN connection test.

| Destination | Files |
|---|---|
| VPN server | `pki/ca.crt`, `pki/issued/server.crt`, `pki/private/server.key` |
| client1 | `pki/ca.crt`, `pki/issued/client1.crt`, `pki/private/client1.key` |
| client2 / client3 | The CA certificate and that client's own certificate and private key |
| CA storage only | `pki/private/ca.key` and a secure backup of the entire PKI, including the issuance database |

Transfer private keys securely and allow only the necessary account to read them. Never publish the PKI or passphrases to GitHub. Server configuration, routing and firewall setup remain separate tasks.

The old `build-dh` command becomes `./easyrsa gen-dh`. If your server uses finite-field DH, use the resulting `pki/dh.pem`. Modern OpenVPN can use `dh none` with ECDH or other supported modern key agreement, so a DH file is not universally required. [OpenVPN TLS options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/tls-options.rst)

### 6. Revoke a lost client's certificate

Run this example only when client2 should actually be revoked.

```bash
./easyrsa revoke client2
./easyrsa gen-crl
openssl crl -in pki/crl.pem -noout -lastupdate -nextupdate
```

Deploy `pki/crl.pem` to the VPN server and configure `crl-verify` to read it. Revoking on the CA alone does not inform the server. Track the CRL expiry and regenerate and distribute it after subsequent revocations. Terminate existing sessions separately when required.

Keep the existing PKI for future client issuance and certificate maintenance instead of recreating the CA.
