---
title: Controlling a Running OpenVPN Process — Restarts, Status, and Client Revocation
lang: en
permalink: /en/openvpn-control-running-process
author: ramen
date: 2026-10-07 00:01:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, management, signals, certificates]
---

### Operating the VPN after it connects

This follows the [initial connectivity test](../openvpn-start-and-test-connectivity/). It covers the guide and its linked manual, Management Interface, certificate revocation, and Windows GUI references. Examples assume Ubuntu 24.04 with OpenVPN built from source and installed using `make install`. They are procedures, not results of a live VPN test.

Distinguish **inspection, restart, disconnection, and certificate revocation**. If your administrative connection uses this VPN, prepare another access path such as a console before restarting it.

### 1. Signals have different effects

| Signal | Effect | Rereads configuration? |
|---|---|---|
| `SIGUSR2` | Sends current statistics to the logging destination | No |
| `SIGUSR1` | Conditional restart; resources may persist according to options such as `persist-tun` and `persist-key` | No |
| `SIGHUP` | Reopens connections and tunnel, rereading configuration | Yes |
| `SIGTERM`, `SIGINT` | Graceful exit | Not applicable |

`SIGUSR1` is not a zero-downtime operation. A server-wide restart affects multiple clients; keeping the tunnel device does not preserve every session. After dropping privileges, `SIGHUP` may fail to reopen protected files or recreate devices. Use the actual service manager or a privileged launch path for a full restart in that situation. [Signal reference](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/signals.rst)

### 2. Prepare PID and status files

This assumes the [previous server configuration](../openvpn-server-client-configuration/), which has not yet dropped privileges with `user` or `group`. Stop the foreground server with `Ctrl+C` before preparing these additions. If a service manages it, use that service and do not launch a duplicate process.

```bash
sudo install -d -o root -g root -m 700 /run/openvpn-admin
sudoedit /etc/openvpn/server/server.conf
```

Keep the existing configuration and add these options, replacing existing duplicates instead of adding them twice.

```conf
writepid /run/openvpn-admin/server.pid
status /run/openvpn-admin/server.status 60
status-version 3
management /run/openvpn-admin/management.sock unix
management-client-user root
management-client-group root
```

`/run` is temporary: recreate the directory after reboot. When adopting service management, arrange runtime directory creation there. This directory is root-only; redesign file and socket permissions if you later drop privileges.

Start the server again.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

In another server terminal, inspect the PID and arguments.

```bash
vpn_pid=$(sudo cat /run/openvpn-admin/server.pid)
if [[ "$vpn_pid" =~ ^[1-9][0-9]*$ ]]; then
  sudo ps -p "$vpn_pid" -o pid,user,args
fi
```

Verify that the output identifies the intended OpenVPN server and configuration before choosing one command below. Check every time: a stale PID file may refer to a reused process number.

| Purpose | Command in the server shell |
|---|---|
| Print statistics | `sudo kill -USR2 "$vpn_pid"` |
| Conditional restart | `sudo kill -USR1 "$vpn_pid"` |
| Reread configuration | `sudo kill -HUP "$vpn_pid"` |
| Graceful exit | `sudo kill -TERM "$vpn_pid"` |

The shell's `kill` sends a signal; it does not always mean forced termination. Do not make `kill -9` the routine shutdown method. Nor should you assume `make install` created a particular systemd unit.

### 3. Status snapshots are not event logs

```bash
sudo cat /run/openvpn-admin/server.status
```

The configured snapshot updates every 60 seconds, so it can lag behind events. Format version 3 uses tabs. It shows client, address, and traffic information; it is not the event log. With this foreground setup, look for `SIGUSR2` statistics in the terminal. `log`, `log-append`, or daemon mode can change the destination. [Manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 4. The Management Interface is an administrative channel

The protocol has no encryption layer of its own. The original passwordless `management localhost 7505` example may expose control to local users. Here we use a Unix socket inside a root-only directory plus explicit user/group restrictions, without opening a TCP port. Unix sockets are not automatically access-restricted. If choosing TCP, use loopback and a password file, and do not expose it publicly. [Management options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/management-options.rst)

Connect from another server terminal.

```bash
sudo apt install socat
sudo socat STDIO UNIX-CONNECT:/run/openvpn-admin/management.sock
```

The following are **management commands, not Linux shell commands**.

```text
help
status 3
state
log 20
quit
```

`status 3` lists current connections, `state` shows process state, and `log 20` shows recent cached messages. With this ordinary management setup, `quit` closes only the management session. The VPN continues running; `signal SIGTERM` would stop the entire process. Use the running version's `help` for available commands. [Management protocol](https://openvpn.net/community-docs/management-interface.html)

### 5. Files that can change without a server restart

CCD and CRL files can be updated when their directives are already active. **Adding the directives for the first time still requires applying the server configuration.**

For CCD, prepare the actual directory and configure:

```conf
client-config-dir /etc/openvpn/server/ccd
```

A certificate Common Name of `client2` normally selects `ccd/client2`. Use only supported per-client options. Changes apply on the next connection, not automatically to existing sessions. Disconnect that session when immediate application is needed and have the client reconnect; a management `kill` does not itself guarantee the client program will retry. [CCD reference](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

CRLs are checked for new connections and TLS renegotiations. Updating a CRL does not immediately disconnect every existing session. Do not wait for renegotiation when urgent removal is required. [Revocation reference](https://openvpn.net/community-docs/revoking-certificates.html)

### 6. When client2 really must be blocked

This is **certificate revocation**, not a read-only exercise. After identifying the target, run these in the CA's existing Easy-RSA 3 working directory. They replace the linked guide's older Easy-RSA 2 `revoke-full` workflow.

```bash
./easyrsa revoke client2
./easyrsa gen-crl
openssl crl -in pki/crl.pem -noout -lastupdate -nextupdate
```

Securely transfer only `pki/crl.pem` to the server, never the CA private key. On the server, run these from the directory containing the transferred `crl.pem`. Preparing a file beside its destination before renaming prevents readers from seeing a partially written replacement.

```bash
sudo install -m 644 crl.pem /etc/openvpn/server/crl.pem.new
sudo mv /etc/openvpn/server/crl.pem.new /etc/openvpn/server/crl.pem
```

The server must already have this directive active:

```conf
crl-verify /etc/openvpn/server/crl.pem
```

Check the issuer, validity dates, process read permissions, and parent-directory traversal permissions. Regenerate and deploy after each revocation and before expiration.

Then inspect the actual Common Name and disconnect the target in the management session.

```text
status 3
kill client2
status 3
```

`kill client2` can terminate multiple instances sharing that name. To select one session, obtain its actual Client ID from `status 3` and use `client-kill CID`, replacing CID with the number. **Disconnection alone allows another connection, so deploy the CRL and terminate the session.** Confirm removal from the list and verify rejection due to revocation using logs and a controlled reconnect test.

### 7. Understanding the Windows references

OpenVPN GUI provides profile connection, disconnection, reconnection, and status controls. For example, `openvpn-gui.exe --command disconnect office` asks a running GUI to disconnect its `office` profile. This is neither a Linux signal nor a command controlling an independent Windows service. Service deployments use Windows service management or an already configured management interface. The guide's F1–F4 instructions concern Windows console execution, not universal GUI shortcuts. [OpenVPN GUI documentation](https://community.openvpn.net/Pages/OpenVPN-GUI-New)

Status files and logs can contain client names and addresses. Publish examples only; keep operational data, private keys, and passwords out of the repository.

### References

- [Controlling a Running OpenVPN Process](https://openvpn.net/community-docs/controlling-a-running-openvpn-process.html)
- [OpenVPN 2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [OpenVPN 2.7.7 signals](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/signals.rst)
- [Management Interface](https://openvpn.net/community-docs/management-interface.html)
- [OpenVPN 2.7.7 management options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/management-options.rst)
- [Revoking Certificates](https://openvpn.net/community-docs/revoking-certificates.html)
- [OpenVPN GUI](https://community.openvpn.net/Pages/OpenVPN-GUI-New)
