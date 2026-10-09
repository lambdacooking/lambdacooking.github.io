---
title: Pushing DNS Options with OpenVPN on Ubuntu 24.04 and OpenVPN 2.7
lang: en
permalink: /en/openvpn-push-dns-options
author: ramen
date: 2026-10-09 00:01:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, dns, dhcp, systemd-resolved]
---

### Name resolution after IP connectivity

After [connecting the LANs](../openvpn-connect-server-client-lans/), resolve internal names through DNS. **Advertising a DNS address, applying it in the client OS, and reaching that server are separate steps.**

This adapts the official guide to Ubuntu 24.04 and the source-built OpenVPN 2.7.7 used earlier. These are configuration examples, not results of a live VPN test.

### 1. A DNS service must already exist

Assume DNS servers at `10.66.0.4` and `10.66.0.5` on the server LAN both know an internal record such as `host.corp.example`. Replace the illustrative domain and record with ones you actually administer.

OpenVPN push does not create a DNS service or records. The name `dhcp-option` does not require a real DHCP server for this TUN configuration. WINS serves legacy NetBIOS naming; it is not a substitute for DNS. Consider the original `push "dhcp-option WINS 10.66.0.8"` only for a legacy environment that needs it. [Original guide](https://openvpn.net/community-docs/pushing-dhcp-options-to-clients.html)

### 2. The original dhcp-option approach

The traditional server-side example in `/etc/openvpn/server/server.conf` is:

```conf
push "dhcp-option DNS 10.66.0.4"
push "dhcp-option DNS 10.66.0.5"
push "dhcp-option DOMAIN corp.example"
```

`DNS` supplies server addresses; `DOMAIN` supplies a connection-specific suffix. A suffix alone does not establish domain-selective split DNS on every OS.

The original describes native Windows handling and the non-Windows `foreign_option_n`/up-script approach. Version 2.7 also supports a default `dns-updown` hook and conversion of older DNS options. **It is therefore inaccurate to say Linux always needs an added manual script.** [2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 3. A separate dns example for 2.7

With verified 2.7 clients and DNS integration, use these instead of the DNS-related `dhcp-option` lines above. Do not combine the two examples.

```conf
push "dns server 0 address 10.66.0.4 10.66.0.5"
push "dns server 0 resolve-domains corp.example"
push "dns search-domains corp.example"
```

The intention is to resolve `corp.example` and its subdomains through the internal DNS servers and provide a search suffix for short names. Actual support depends on the client and OS. Other domains retain their existing DNS policy. Both servers should serve the same internal zone; list order alone is not a guarantee of fixed primary/secondary failover.

A `dns server` option takes precedence over DNS-related `dhcp-option` settings. Check support before switching a mixed-version client fleet. [2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 4. Check Ubuntu's DNS integration

Record the state before connecting:

```bash
openvpn --version
systemctl is-active systemd-resolved
readlink -f /etc/resolv.conf
resolvectl status
ip -brief address
```

This article assumes systemd-resolved is active and `/etc/resolv.conf` links to a file it manages. If using another DNS manager, select integration appropriate to that setup first. Do not blindly overwrite `/etc/resolv.conf`.

The 2.7.7 Linux source provides a default DNS hook, with the selected `dns-updown` installed through `make install`. It can use systemd-resolved, resolvconf, or file-based handling depending on the environment. Build options, installation paths, and permissions matter; inspect connection logs for hook execution and errors. [Official helper](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/systemd-dns-updown.sh), [installation rules](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/Makefile.am)

An existing `up` script can suppress the default DNS hook. Check for `dns-updown disable` or build-time disabling too. Avoid having NetworkManager, a CLI process, and an extra script compete over DNS for the same profile.

Older setups such as 2.6 may use distribution integration or the [third-party update-systemd-resolved helper](https://github.com/jonathanio/update-systemd-resolved). This is a separate project, not OpenVPN itself. Follow its installation, connect/disconnect hook, and permission instructions. Do not add it on top of a working 2.7 default hook.

### 5. DNS still needs network access

Retain the server-LAN route from the previous post:

```conf
push "route 10.66.0.0 255.255.255.0"
```

The earlier forwarding, return routes, and firewall policy still apply. Permit DNS queries from the VPN client subnet and consider both UDP and TCP port 53. Advertising DNS addresses does not create routes or firewall permissions.

Apply server changes using the [process control guide](../openvpn-control-running-process/) and reconnect clients. `SIGUSR1` does not reread server configuration.

### 6. Verify delivery, application, and replies separately

After connecting, run on the client:

```bash
ip route get 10.66.0.4
ip route get 10.66.0.5
resolvectl status
resolvectl query host.corp.example
getent ahosts host.corp.example
```

In `resolvectl status`, inspect the actual VPN link's DNS servers and domain routing. With systemd-resolved, `~corp.example` is a route-only domain; `corp.example` can also act as a search suffix. `~.` directs general DNS traffic to that link and differs from this split-DNS goal. [resolvectl documentation](https://manpages.ubuntu.com/manpages/noble/man1/resolvectl.1.html)

Test the DNS service independently:

```bash
sudo apt install dnsutils
dig @10.66.0.4 host.corp.example A
dig @10.66.0.5 host.corp.example A
dig +tcp @10.66.0.4 host.corp.example A
```

A successful `dig @address` proves that the specified server answers, not that the OS selects it by default. Also check that returned records contain the intended internal addresses.

| Symptom | Check |
|---|---|
| Direct dig queries fail | VPN and return routes, port 53, DNS query access policy |
| Direct queries work but ordinary resolution fails | DNS hook, resolver integration, split-DNS domains |
| Full names work but short names fail | Search suffix and application behavior |
| Only the browser differs | Browser-specific DoH settings and caches |

On Windows, inspect `ipconfig /all` as the original suggests and test resolution too. Modern drivers and DNS policies vary; the TAP adapter display alone is not definitive.

```text
ipconfig /all
nslookup host.corp.example
```


### 7. Verify restoration after disconnecting

Stop the VPN normally, then recheck `resolvectl status` and resolution of an ordinary public domain. Stale internal DNS settings should not break public name resolution. `resolvectl revert INTERFACE` is a manual recovery tool, but also resets other manual settings on that link, so identify the target first.

These options alone do not guarantee prevention of DNS leaks from every application. Consider browser DoH, other links' policies, and IPv6 separately. The original caveats link could not be retrieved during this review; the current manual and implementation provide the corrections above.

### References

- [OpenVPN: Pushing DHCP Options to Clients](https://openvpn.net/community-docs/pushing-dhcp-options-to-clients.html)
- [OpenVPN 2.7 manual — dhcp-option, dns, dns-updown](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [OpenVPN 2.7.7 DNS helper](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/systemd-dns-updown.sh)
- [OpenVPN 2.7.7 DNS helper installation](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/Makefile.am)
- [Ubuntu 24.04: resolvectl](https://manpages.ubuntu.com/manpages/noble/man1/resolvectl.1.html)
- [update-systemd-resolved — third-party helper](https://github.com/jonathanio/update-systemd-resolved)
