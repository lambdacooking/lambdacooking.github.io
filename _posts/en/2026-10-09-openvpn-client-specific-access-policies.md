---
title: OpenVPN Client-Specific Access Policies with CCD and Firewall Rules
lang: en
permalink: /en/openvpn-client-specific-access-policies
author: ramen
date: 2026-10-09 00:02:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, firewall, access-control, ccd]
---

### VPN admission is not access to every resource

The official guide maps user classes to VPN addresses and restricts destinations with a firewall. Here that principle is adapted to the existing Ubuntu 24.04 source installation. This is not a record of applying or testing rules on a live VPN.

**CCD selects client configuration; the firewall restricts traffic.** Removing a pushed route is not an access-control boundary because a client can add its own route. [Original guide](https://openvpn.net/community-docs/configuring-client-specific-rules-and-access-policies.html)

### 1. Example policy

Retain `10.66.0.0/24` from the [LAN guide](../openvpn-connect-server-client-lans/), but limit this example to **individual remote-access devices**. Do not combine it unchanged with client2 routing a whole LAN.

| Certificate Common Name | Fixed VPN IP | Permitted destination |
|---|---|---|
| sysadmin1 | `10.8.0.10` | Entire server LAN |
| employee1 | `10.8.0.20` | TCP 445, 465, 587, 993 on `10.66.0.20` |
| contractor1 | `10.8.0.30` | TCP 443 on `10.66.0.30` |
| contractor2 | `10.8.0.31` | Same HTTPS server |
| All listed clients | — | UDP/TCP 53 on DNS servers `10.66.0.4` and `10.66.0.5` |

Substitute real service addresses and ports. Unlike the original example, employees also receive fixed addresses, avoiding pool/reservation collisions and admitting only explicitly enrolled devices. Use unique valid certificates, never revoked ones.

### 2. Use CCD with topology subnet

Back up the server configuration and **replace the corresponding options** with these. Retain certificates, keys, CRL, UDP port, status, and management settings. Do not retain duplicate `dev`, `server`, or old `ifconfig-pool` entries.

```conf
dev tun0
topology subnet
server 10.8.0.0 255.255.255.0 nopool
disable-dco
client-config-dir /etc/openvpn/server/ccd
ccd-exclusive
max-routes-per-client 1
push "route 10.66.0.0 255.255.255.0"
```

`nopool` avoids an automatic address pool; `ccd-exclusive` rejects clients without a corresponding CCD file. Neither option grants LAN access by itself. Prepare the files:

```bash
sudo install -d -m 750 /etc/openvpn/server/ccd
sudoedit /etc/openvpn/server/ccd/sysadmin1
sudoedit /etc/openvpn/server/ccd/employee1
sudoedit /etc/openvpn/server/ccd/contractor1
sudoedit /etc/openvpn/server/ccd/contractor2
```

Save the corresponding line in each file.

| Server CCD filename | Contents |
|---|---|
| sysadmin1 | `ifconfig-push 10.8.0.10 255.255.255.0` |
| employee1 | `ifconfig-push 10.8.0.20 255.255.255.0` |
| contractor1 | `ifconfig-push 10.8.0.30 255.255.255.0` |
| contractor2 | `ifconfig-push 10.8.0.31 255.255.255.0` |

Match the actual certificate CN exactly. After privilege reduction, OpenVPN must still read files and traverse their parent directories. Under `topology subnet`, the second argument is a netmask: do not copy the original `/30` endpoint pairs such as `10.8.1.1 10.8.1.2`. `ifconfig-pool-persist` is not a guaranteed fixed-address substitute. [Server options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)

Do not use `duplicate-cn` or `client-to-client`. DCO is disabled to keep this example's forwarding path simple and avoid internal client forwarding bypassing kernel filtering. `max-routes-per-client 1` limits additional address learning for these single-device clients; it must not be blindly applied to a LAN gateway client. IP rules do not replace certificate verification. Include rejection of forged source addresses in operational validation.

### 3. Review existing routes and broad permissions

The server LAN gateway still needs a route for `10.8.0.0/24` through the OpenVPN server's LAN address. Retain forwarding and DNS query permissions from earlier posts.

Inspect the server's current rules first.

```bash
sudo ufw status verbose
sudo ufw status numbered
sudo ufw show raw
```

This assumes **UFW is already active and manages this server's firewall**. Replace example interfaces `tun0` and `enp1s0` with the VPN and LAN names. Review and remove superseded user rules involving `tun0`, then install the policy block once. A broad LAN allowance from the previous post must not precede the new restrictions. Inspect UFW before-rules and other nftables/iptables managers too.

Have another SSH/console path and a recovery plan before changing a remote firewall. These commands were not executed on a VPN server while publishing this article.

### 4. Allow listed traffic, then explicitly deny

Insert a VPN forwarding deny first, then insert the required allowances ahead of it. Traffic may temporarily stop during these intermediate steps.

```bash
sudo ufw route insert 1 deny in on tun0
sudo ufw route insert 1 allow in on tun0 out on enp1s0 from 10.8.0.10 to 10.66.0.0/24
sudo ufw route insert 2 allow in on tun0 out on enp1s0 proto tcp from 10.8.0.20 to 10.66.0.20 port 445,465,587,993
sudo ufw route insert 3 allow in on tun0 out on enp1s0 proto tcp from 10.8.0.30 to 10.66.0.30 port 443
sudo ufw route insert 4 allow in on tun0 out on enp1s0 proto tcp from 10.8.0.31 to 10.66.0.30 port 443
sudo ufw route insert 5 allow in on tun0 out on enp1s0 proto udp from 10.8.0.0/24 to 10.66.0.4 port 53
sudo ufw route insert 6 allow in on tun0 out on enp1s0 proto tcp from 10.8.0.0/24 to 10.66.0.4 port 53
sudo ufw route insert 7 allow in on tun0 out on enp1s0 proto udp from 10.8.0.0/24 to 10.66.0.5 port 53
sudo ufw route insert 8 allow in on tun0 out on enp1s0 proto tcp from 10.8.0.0/24 to 10.66.0.5 port 53
```

Afterward, `sudo ufw status numbered` should show **eight allowances followed by the tun0 forwarding deny**. If not, stop and resolve existing rules or duplicates. The deny also restricts other forwarded destinations and client-to-client traffic traversing the kernel. New connections initiated from the LAN toward VPN clients require a separate policy.

Standard UFW established/related handling permits replies. Existing connection-tracking state can survive a policy change, so test with new connections. For urgent revocation, also follow the [CRL and session termination procedure](../openvpn-control-running-process/). [UFW documentation](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)

### 5. The VPN server itself needs INPUT policy

`ufw route` handles traffic passing **through** the server. Its own SSH and management services need separate INPUT rules. This exercise denies access to the server itself over the VPN.

```bash
sudo ufw insert 1 deny in on tun0
```

The earlier ping test to `10.8.0.1` may consequently fail. This differs from allowing external UDP 1194. If a local server service is required, design a narrow source/destination/port exception ahead of this deny.

This is an IPv4 example. Apply equivalent policy to IPv6 tunnels, other VPNs, and alternate paths, or configure them out of use. Check UFW's IPv6 handling too.

### 6. Test both permitted and forbidden access

Apply changes using the [process control guide](../openvpn-control-running-process/) and reconnect each client. `SIGUSR1` alone does not reread the server configuration. First verify each CN and assigned address in management status.

On each client, test the example ports:

```bash
sudo apt install netcat-openbsd
ip -brief address
nc -vz -w 3 10.66.0.20 445
nc -vz -w 3 10.66.0.30 443
nc -vz -w 3 10.66.0.20 22
```


| Test | Administrator | Employee | Contractor |
|---|---|---|---|
| `10.66.0.20:445` | Allow | Allow | Deny |
| `10.66.0.30:443` | Allow | Deny | Allow |
| `10.66.0.20:22` | Allow | Deny | Deny |

An allowed test succeeds only if a service is listening. Failure alone does not prove firewall rejection: check routes, listeners, and logs. Also verify rejection of a valid test certificate without a CCD file. Test DNS both directly and through normal resolution as in the [DNS guide](../openvpn-push-dns-options/).

When removing an employee or contractor, retire sessions and certificates before reassigning addresses. Maintain the CN/address/policy mapping together and keep private keys and operational logs out of the public repository.

### References

- [OpenVPN: Configuring Client-Specific Rules and Access Policies](https://openvpn.net/community-docs/configuring-client-specific-rules-and-access-policies.html)
- [OpenVPN 2.7.7 server options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)
- [OpenVPN 2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [Ubuntu 24.04: UFW](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)
