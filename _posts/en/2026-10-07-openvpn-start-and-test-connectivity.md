---
title: Starting OpenVPN and Testing the First Connection on Ubuntu 24.04
lang: en
permalink: /en/openvpn-start-and-test-connectivity
author: ramen
date: 2026-10-07 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, troubleshooting, connectivity]
---

### What this checks

Use the files from the [configuration post](../openvpn-server-client-configuration/) to start both peers and test communication inside the VPN. **Server startup, client connection, and actual traffic are separate checks.**

This is an Ubuntu 24.04 adaptation of the official guide, not a report of a successful test on real devices. Run the commands on your own server and client. The original Windows XP instructions and OpenVPN 2.0 log are not a baseline for this environment.

### 1. Prepare to start

This assumes [building from GitHub source and running make install](../openvpn-install-from-github-source/) and the previous post's `UDP 1194`, `dev tun`, and `10.8.0.0/24` settings. Adjust the commands if you changed the port or subnet.

Check the installation path and version on both machines.

```bash
command -v openvpn
openvpn --version
```

Confirm that this is the binary installed from source. If no path appears, check PATH and the installation location first. There is no need to recreate the CA or certificates.

For remote access, permit UDP 1194 in the server and cloud firewalls. If a router fronts the server, forward that port to its LAN address. Set the client's `remote` to the actual reachable address.

### 2. Start the server first

Run this in a server terminal and keep its log visible.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

`Initialization Sequence Completed` means the server has initialized; it does not prove a client has connected. Check the port from another server terminal.

```bash
sudo ss -lunp 'sport = :1194'
```

This displays local UDP sockets and their processes. Check that OpenVPN uses port 1194 on the intended address. A local socket does not prove external reachability. [ss reference](https://manpages.ubuntu.com/manpages/noble/man8/ss.8.html)

### 3. Start the client

Run this in a client terminal.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/client/client.conf
```

Enter the private-key passphrase if prompted. Check for the client's initialization-complete message and watch for repeated errors or reconnections afterward. Terminal startup makes initial diagnosis easier than service startup. Do not launch a service and a terminal process with the same configuration simultaneously.

### 4. Test the VPN address

From another terminal on the client, run:

```bash
ip -brief address
ip route get 10.8.0.1
ping -c 4 10.8.0.1
```

`ip -brief address` shows assigned addresses; `ip route get` shows the route actually selected for the destination. Check that the route to `10.8.0.1` uses the VPN interface. Its name can vary, so do not assume it is `tun0`. [ip-route reference](https://manpages.ubuntu.com/manpages/noble/man8/ip-route.8.html)

With the previous configuration, `10.8.0.1` is the server's VPN address. Replies over the VPN route confirm round-trip tunnel traffic to that address. They do not establish that all internet traffic or access to the server's LAN works.

### 5. If a check fails

| Symptom | Check first |
|---|---|
| Server exits immediately | First log error, configuration path, certificate/key readability, port conflicts |
| TLS negotiation times out | `remote` address, port and protocol; server process; firewalls; port forwarding; return path |
| Certificate verification fails | Trusted CA on both peers, certificate validity, device clocks, certificate purposes |
| Client initializes but ping fails | VPN addresses and routes, overlapping subnets, tunnel traffic and ICMP filtering on both peers |

A TLS timeout does not identify the cause by itself. Compare both logs to find how far the connection progressed. If you added `tls-auth` or `tls-crypt`, also check that the settings and keys match.

If using UFW, inspect the current policy on both machines.

```bash
sudo ufw status verbose
```

Adjust the rules blocking the required tunnel traffic or ICMP rather than disabling the entire firewall. A missing ping reply alone does not prove that the VPN connection failed.

### 6. Stop the test and continue

Press `Ctrl+C` in each OpenVPN terminal. After confirming the basic connection, configure service startup, access controls, and LAN routing separately. Pinging the server's own VPN address does not require enabling internet-sharing NAT or forwarding between interfaces first.

Before sharing logs, redact addresses and certificate identifiers you do not want public. Keep private keys, passwords, and real PKI material out of the blog repository.

### References

- [OpenVPN: Starting Up the VPN and Testing for Initial Connectivity](https://openvpn.net/community-docs/starting-up-the-vpn-and-testing-for-initial-connectivity.html)
- [Ubuntu 24.04: ss](https://manpages.ubuntu.com/manpages/noble/man8/ss.8.html)
- [Ubuntu 24.04: ip-route](https://manpages.ubuntu.com/manpages/noble/man8/ip-route.8.html)
