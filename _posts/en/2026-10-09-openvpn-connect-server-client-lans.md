---
title: Connecting Server and Client LANs through OpenVPN
lang: en
permalink: /en/openvpn-connect-server-client-lans
author: ramen
date: 2026-10-09 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, routing, subnet, firewall]
---

### Reach machines beyond the VPN endpoints

The [initial connection test](../openvpn-start-and-test-connectivity/) reached the server's VPN address. Now extend access to its LAN and then to a LAN behind a client. **Forward routes, return routes, IP forwarding, and firewall permission must all agree.**

These IPv4 TUN examples assume Ubuntu 24.04 and [a source build installed with make install](../openvpn-install-from-github-source/). They are not results from a live network test. Substitute your own addresses and interfaces while retaining the existing certificate configuration.

### 1. Example addresses and assumptions

| Role | Address |
|---|---|
| VPN subnet | `10.8.0.0/24` |
| Server LAN / default gateway | `10.66.0.0/24` / `10.66.0.1` |
| OpenVPN server LAN address | `10.66.0.10` |
| Server LAN test host | `10.66.0.20` |
| Client LAN / default gateway | `192.168.4.0/24` / `192.168.4.1` |
| OpenVPN client2 LAN address | `192.168.4.10` |
| Client LAN test host | `192.168.4.20` |

This sketches routing roles, not separate physical segments between a LAN gateway and its VPN endpoint.

```text
10.66.0.20 -- 10.66.0.1 -- 10.66.0.10 [OpenVPN server]
                                   || VPN 10.8.0.0/24 ||
192.168.4.20 -- 192.168.4.1 -- 192.168.4.10 [client2]
```

The three ranges must not overlap, and each site's LAN must be unique. Give client2 a valid unique certificate and do not use `duplicate-cn`. **If you actually revoked client2 in the previous article, do not reuse that certificate.** Prepare a new certificate and match the CCD filename below to its actual Common Name.

For a predictable demonstration of traditional `route` and `iroute`, add this to the existing configurations of both the server and client2:

```conf
disable-dco
```

Disabling DCO is a learning choice here. With DCO, `iroute` can configure kernel routes and `client-to-client` behaves differently. The older guide's statement that both routes are always required is therefore not universal. [Server options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)

### 2. Reach the server LAN first

Add this to `/etc/openvpn/server/server.conf`:

```conf
push "route 10.66.0.0 255.255.255.0"
```

It tells clients to send server-LAN traffic through the VPN. Clients must not be configured to ignore those pushed routes.

Enable IPv4 forwarding on the OpenVPN server. Inspect any existing file with this name before overwriting it.

```bash
printf '%s\n' 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/90-openvpn-forward.conf
sudo sysctl -p /etc/sysctl.d/90-openvpn-forward.conf
sysctl net.ipv4.ip_forward
```

Check for `1`. Forwarding does not itself permit traffic through the firewall. Recheck after reboot or firewall reconfiguration in case another sysctl or UFW setting overrides it. [Kernel documentation](https://docs.kernel.org/networking/ip-sysctl.html)

**On the server LAN gateway, `10.66.0.1`,** add the return route to the VPN subnet. This command assumes that gateway runs Linux.

```bash
sudo ip route add 10.8.0.0/24 via 10.66.0.10
```

If OpenVPN itself is the LAN's default gateway, this separate next-hop route is unnecessary. On an appliance, enter the destination, mask, and next hop in its static-route interface. `ip route add` is temporary: persist verified routes through the gateway's Netplan or router configuration. Review an existing route before changing it.

On an OpenVPN server already using UFW, allow forwarding. All UFW examples below assume **VPN interface `tun0` and LAN interface `enp1s0`**. Replace them after checking `ip -brief address`.

```bash
sudo ufw route allow in on tun0 out on enp1s0 from 10.8.0.0/24 to 10.66.0.0/24
```

This differs from allowing incoming UDP 1194 to the server itself. Standard UFW established/related rules handle responses; review any custom policy too. Destination hosts must allow the desired service or ICMP. [UFW route rules](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)

### 3. Extend access to the client LAN

Client2 now routes for `192.168.4.0/24`. **Apply the IPv4 forwarding procedure from section 2 on client2 as well.** Prepare the CCD file on the server:

```bash
sudo install -d -m 750 /etc/openvpn/server/ccd
sudoedit /etc/openvpn/server/ccd/client2
```

Save this in the `client2` file:

```conf
iroute 192.168.4.0 255.255.255.0
```

Add the following to the server's `server.conf`, keeping the server-LAN push from section 2:

```conf
client-config-dir /etc/openvpn/server/ccd
route 192.168.4.0 255.255.255.0
```

`route` sends kernel traffic toward OpenVPN; `iroute` selects client2 inside OpenVPN. Store CCD on the **server**, not the client. If OpenVPN drops privileges, ensure it can read the CCD file and traverse its parent directories.

**On server LAN gateway `10.66.0.1`:**

```bash
sudo ip route add 192.168.4.0/24 via 10.66.0.10
```

**On client LAN gateway `192.168.4.1`:**

```bash
sudo ip route add 10.66.0.0/24 via 192.168.4.10
sudo ip route add 10.8.0.0/24 via 192.168.4.10
```

Each next hop is the local VPN endpoint's LAN address. Omit that side's separate gateway route when the VPN endpoint is already the default gateway. These are temporary Linux gateway examples too.

### 4. Permit forwarding between the LANs

These learning rules allow either LAN to initiate traffic. Narrow destinations and ports for operational use.

On the OpenVPN **server**:

```bash
sudo ufw route allow in on tun0 out on enp1s0 from 192.168.4.0/24 to 10.66.0.0/24
sudo ufw route allow in on enp1s0 out on tun0 from 10.66.0.0/24 to 192.168.4.0/24
```

On OpenVPN **client2**:

```bash
sudo ufw route allow in on enp1s0 out on tun0 from 192.168.4.0/24 to 10.66.0.0/24
sudo ufw route allow in on tun0 out on enp1s0 from 10.66.0.0/24 to 192.168.4.0/24
```

These rules cover the two LANs. Access from other VPN clients to client2's LAN needs separate policy. This example uses routing without NAT/MASQUERADE. NAT is a separate design option when return routes cannot be added and can obscure original source addresses.

### 5. Apply changes and test

Back up the existing configurations and apply changes on the server and client2 using the [process control guide](../openvpn-control-running-process/). `SIGUSR1` does not reread a changed server configuration. Restarting interrupts connections, so keep an alternate administrative path. CCD changes apply when the target reconnects.

First check `10.66.0.20` from an ordinary VPN client. Then test LAN-to-LAN communication. **On client LAN host `192.168.4.20`:**

```bash
ip route get 10.66.0.20
ping -c 4 10.66.0.20
```

**On server LAN host `10.66.0.20`,** test the reverse direction:

```bash
ip route get 192.168.4.20
ping -c 4 192.168.4.20
```

An ordinary LAN host need not show a VPN interface in `ip route get`: here it uses its default gateway, which forwards to the VPN endpoint. Inspect destination routes and logs on the actual VPN endpoints too.

| Symptom | Check first |
|---|---|
| Only the VPN server is reachable | Server-LAN push, server forwarding, UFW route rules |
| Requests arrive but replies do not | Return routes on LAN gateways, destination host firewall |
| Only client2's LAN fails | Certificate CN and CCD filename, `route`/`iroute`, client2 forwarding |
| Failure only at some locations | Overlapping LAN and VPN site subnets |

Do not rely on ping alone; test an allowed application service too. LAN connectivity does not establish full-tunnel internet access or DNS configuration.

### 6. Optional features and linked references

To expose client2's LAN to other VPN clients, the original guide suggests these options. They are not required for the basic two-LAN setup.

```conf
client-to-client
push "route 192.168.4.0 255.255.255.0"
```

Without DCO, `client-to-client` forwards internally and can bypass kernel rules intended to filter traffic between clients. With DCO it has no effect. Choose it together with an access policy rather than adding it automatically.

TAP bridging joins Ethernet networks. The [bridging guide](https://openvpn.net/community-docs/ethernet-bridging.html) and [INSTALL DHCP discussion](https://openvpn.net/community-docs/the-standard-install-file-included-in-the-source-distribution.html) assume bridge configuration, address planning, and DHCP planning. Changing `dev tun` to `dev tap` alone is insufficient. This article retains TUN routing between distinct LANs.

The original IP-forwarding reference could not be retrieved during this review, so kernel and Ubuntu documentation supplement it. Keep real PKI, private keys, and operational logs out of the repository.

### References

- [OpenVPN: Expanding the Scope of the VPN](https://openvpn.net/community-docs/expanding-the-scope-of-the-vpn-to-include-additional-machines-on-either-the-client-or-server-subnet.html)
- [OpenVPN 2.7.7 server options: route, iroute, CCD, client-to-client](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)
- [OpenVPN 2.7 manual: disable-dco](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [Linux kernel: IP sysctl](https://docs.kernel.org/networking/ip-sysctl.html)
- [Ubuntu 24.04: UFW](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)
- [OpenVPN: Ethernet Bridging](https://openvpn.net/community-docs/ethernet-bridging.html)
- [OpenVPN: INSTALL — DHCP and bridging](https://openvpn.net/community-docs/the-standard-install-file-included-in-the-source-distribution.html)
