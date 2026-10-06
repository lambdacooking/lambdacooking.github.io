---
title: Creating OpenVPN Server and Client Configuration Files on Ubuntu 24.04
lang: en
permalink: /en/openvpn-server-client-configuration
author: ramen
date: 2026-10-06 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, configuration, server, client]
---

### Connect the certificates to a VPN configuration

This follows [building from source and running make install](../openvpn-install-from-github-source/) and [creating certificates with Easy-RSA 3](../openvpn-ca-certificates-easyrsa3/). These Ubuntu 24.04 examples adapt the official configuration guide. They are not a report of a successful connection test on real machines; use the checks below to validate your environment.

### 1. Check the binary and samples

Run these commands from the OpenVPN source directory used in the earlier post.

```bash
command -v openvpn
openvpn --version
ls sample/sample-config-files/{server,client}.conf
```

Check that the path and version belong to your source installation. If no path appears, check the installation location and PATH first. We will write the configuration explicitly, so copying the entire sample is unnecessary. Start in a terminal rather than assuming that `make install` also installed a distribution systemd service.

### 2. Prepare the server files

Securely transfer only `ca.crt`, `server.crt`, and `server.key` from the previous workflow to the server. On the server, enter the directory containing these three files. These commands assume a new configuration; back up existing files first. **Do not transfer the CA private key, `ca.key`, to the server.**

```bash
sudo install -d -m 750 /etc/openvpn/server
sudo install -m 644 ca.crt server.crt /etc/openvpn/server/
sudo install -m 600 server.key /etc/openvpn/server/
sudoedit /etc/openvpn/server/server.conf
```

Save the following configuration in the editor.

```conf
port 1194
proto udp
dev tun
topology subnet
server 10.8.0.0 255.255.255.0

ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh none
remote-cert-tls client

keepalive 10 120
persist-key
persist-tun
verb 3
```

`10.8.0.0/24` is an example. Choose a range that overlaps neither the server LAN nor client LANs, following the [private subnet planning post](../vpn-private-subnet-planning/).

`dh none` avoids a finite-field DH parameter file and allows modern key agreement. It can be used with the RSA certificates from the previous post: certificate keys and session key agreement are separate choices. This example does not require `gen-dh`.

### 3. Prepare the client files

Transfer `ca.crt`, `client1.crt`, and `client1.key` to the Ubuntu client. Run these commands from their directory.

```bash
sudo install -d -m 750 /etc/openvpn/client
sudo install -m 644 ca.crt client1.crt /etc/openvpn/client/
sudo install -m 600 client1.key /etc/openvpn/client/
sudoedit /etc/openvpn/client/client.conf
```

Save the following, replacing `vpn.example.com` with the actual server domain or public IP address.

```conf
client
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun

ca /etc/openvpn/client/ca.crt
cert /etc/openvpn/client/client1.crt
key /etc/openvpn/client/client1.key
remote-cert-tls server
verb 3
```

Give every device its own certificate and private key. For `client2`, change both the filenames and configuration paths. `remote-cert-tls server` checks the server certificate purpose; the server's `remote-cert-tls client` checks the client certificate purpose.

### 4. Firewall and connection checks

UDP 1194 must reach the server. If the server already uses UFW, allow it and inspect the status:

```bash
sudo ufw allow 1194/udp
sudo ufw status
```

Check cloud firewall rules separately. Behind a router, forward UDP 1194 to the server's LAN address. Set `remote` to an externally reachable address.

Start the server:

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

Then start the client. Enter the private-key passphrase when prompted if you encrypted it as in the previous post.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/client/client.conf
```

Look for `Initialization Sequence Completed` in the connection log, then test from another terminal on the client:

```bash
ping -c 4 10.8.0.1
ip address show
ip route show
```

If ping fails, inspect the connection log, tunnel addresses, and ICMP filtering together. Stop each process with `Ctrl+C` in its terminal. Server initialization alone does not prove that a client has connected.

### 5. After the basic connection

This is a starting point for testing the tunnel. Reaching the server LAN or routing all internet traffic through the VPN also requires routes, IP forwarding, firewall rules, and NAT where appropriate.

If you generated a CRL in the previous post, deploy it to the server and add:

```conf
crl-verify /etc/openvpn/server/crl.pem
```

Check the CRL's presence, readability, and expiration. Refresh and deploy it after every revocation; terminate existing sessions separately. An operational setup should also address control-channel protection such as `tls-crypt`, service management, and privilege reduction.

Do not copy the older guide's `comp-lzo` and `fragment` options into a new setup automatically. In particular, leave compression disabled. Before using the guide's `group nobody` on Ubuntu, check actual accounts, for example with `getent group nogroup`. This example does not yet drop privileges.

Keep real private keys, passwords, and PKI material out of the blog repository.

### References

- [Creating Configuration Files for Server and Clients](https://openvpn.net/community-docs/creating-configuration-files-for-server-and-clients.html)
- [OpenVPN 2.7.7 server.conf](https://github.com/OpenVPN/openvpn/blob/v2.7.7/sample/sample-config-files/server.conf)
- [OpenVPN 2.7.7 TLS options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/tls-options.rst)
- [OpenVPN 2.6 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html)
