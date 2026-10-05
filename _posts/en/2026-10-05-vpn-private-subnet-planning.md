---
title: Planning Private Subnets for a VPN
lang: en
permalink: /en/vpn-private-subnet-planning
author: ramen
date: 2026-10-05 14:00:00 +0900
categories: [OpenVPN]
tags: [vpn, networking, subnet]
---

### Why the address plan matters

VPN-connected networks need distinct subnets. Overlap between sites, or between a remote user's local network and the VPN, can cause routing conflicts. OpenVPN recommends avoiding common defaults such as `192.168.0.0/24` and choosing less commonly used subnets within `10.0.0.0/8`. NAT can accommodate overlapping sites, but adds complexity. [Source: OpenVPN](https://openvpn.net/community-docs/numbering-private-subnets.html)

### Private IPv4 ranges

[RFC 1918](https://www.rfc-editor.org/rfc/rfc1918.html) reserves these blocks for private networks:

| CIDR block | Address range |
| --- | --- |
| `10.0.0.0/8` | `10.0.0.0`–`10.255.255.255` |
| `172.16.0.0/12` | `172.16.0.0`–`172.31.255.255` |
| `192.168.0.0/16` | `192.168.0.0`–`192.168.255.255` |

### An illustrative address plan

The following is my own example, not a configuration prescribed by OpenVPN:

| Purpose | Example subnet |
| --- | --- |
| Home LAN | `10.83.21.0/24` |
| Lab LAN | `10.83.22.0/24` |
| VPN client tunnel addresses | `10.83.23.0/24` |

These three ranges do not overlap. Before adopting them, compare them with your actual LANs and routes: they are examples, not guaranteed conflict-free assignments. Keep a record of each subnet's purpose when adding networks.

*This post summarizes the linked documentation; it is not a full translation or a complete OpenVPN configuration guide.*
