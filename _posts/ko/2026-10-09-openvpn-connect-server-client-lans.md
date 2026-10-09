---
title: OpenVPN으로 서버와 클라이언트 뒤의 LAN까지 연결하기
lang: ko-KR
permalink: /ko/openvpn-connect-server-client-lans
author: ramen
date: 2026-10-09 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, routing, subnet, firewall]
---

### VPN 장비 너머의 컴퓨터에 접근하기

[첫 연결 시험](../openvpn-start-and-test-connectivity/)에서는 서버의 VPN 주소까지 확인했다. 이번에는 서버 뒤 LAN, 이어서 클라이언트 뒤 LAN으로 범위를 넓힌다. **가는 경로, 돌아오는 경로, IP 전달, 방화벽 허용이 모두 필요하다.**

Ubuntu 24.04에서 [소스 빌드 후 make install](../openvpn-install-from-github-source/)한 환경의 IPv4·TUN 라우팅 예제다. 실제 네트워크에서 시험한 기록은 아니며, 아래 주소와 인터페이스를 자신의 환경에 맞춰야 한다. 인증서·키는 기존 구성을 유지한다.

### 1. 예제 주소와 전제

| 역할 | 주소 |
|---|---|
| VPN 대역 | `10.8.0.0/24` |
| 서버 LAN / 기본 게이트웨이 | `10.66.0.0/24` / `10.66.0.1` |
| OpenVPN 서버의 LAN 주소 | `10.66.0.10` |
| 서버 LAN 시험 장비 | `10.66.0.20` |
| 클라이언트 LAN / 기본 게이트웨이 | `192.168.4.0/24` / `192.168.4.1` |
| OpenVPN client2의 LAN 주소 | `192.168.4.10` |
| 클라이언트 LAN 시험 장비 | `192.168.4.20` |

다음은 경로의 역할을 나타낸 그림이다. 같은 LAN의 게이트웨이와 VPN 장비가 별도의 물리 구간으로 분리된다는 뜻은 아니다.

```text
10.66.0.20 -- 10.66.0.1 -- 10.66.0.10 [OpenVPN server]
                                   || VPN 10.8.0.0/24 ||
192.168.4.20 -- 192.168.4.1 -- 192.168.4.10 [client2]
```

세 대역은 서로 겹치면 안 된다. 각 VPN 사이트의 LAN도 고유해야 한다. client2에는 유효한 고유 인증서를 쓰고 `duplicate-cn`은 사용하지 않는다. **앞 글에서 client2를 실제 폐기했다면 그 인증서는 재사용할 수 없다.** 새 인증서를 준비하고 아래 CCD 파일명을 실제 Common Name과 맞춘다.

원문의 전통적인 `route`·`iroute` 구분을 재현하기 위해 이 실습에서는 서버와 client2의 기존 설정에 각각 다음을 추가한다.

```conf
disable-dco
```

이는 학습을 위한 선택이다. DCO에서는 `iroute`만으로 커널 경로가 구성되는 경우가 있고 `client-to-client` 동작도 달라진다. 따라서 원문의 “둘 다 항상 필요”를 모든 버전에 일반화하지 않는다. [공식 서버 옵션](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)

### 2. 서버 LAN에 먼저 접근하기

서버의 `/etc/openvpn/server/server.conf`에 다음을 추가한다.

```conf
push "route 10.66.0.0 255.255.255.0"
```

클라이언트가 서버 LAN 목적지를 VPN으로 보내도록 안내하는 설정이다. 클라이언트가 push 경로를 무시하도록 구성되어 있지 않아야 한다.

OpenVPN 서버에서 IPv4 전달을 활성화한다. 같은 이름의 파일이 이미 있으면 덮어쓰기 전에 내용을 확인한다.

```bash
printf '%s\n' 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/90-openvpn-forward.conf
sudo sysctl -p /etc/sysctl.d/90-openvpn-forward.conf
sysctl net.ipv4.ip_forward
```

`1`인지 확인한다. 이것은 방화벽 허용과 별개다. 다른 sysctl 또는 UFW 설정이 값을 덮어쓰지 않는지도 재부팅·방화벽 재적용 후 확인한다. [커널 설명](https://docs.kernel.org/networking/ip-sysctl.html)

**서버 LAN 게이트웨이 `10.66.0.1`에서** VPN 대역의 반환 경로를 추가한다. 아래는 그 게이트웨이가 Linux일 때의 명령이다.

```bash
sudo ip route add 10.8.0.0/24 via 10.66.0.10
```

OpenVPN 서버 자체가 LAN의 기본 게이트웨이라면 이 별도 next-hop 경로는 필요 없다. 공유기라면 관리자 화면의 정적 경로에 목적지·마스크·다음 홉을 입력한다. `ip route add`는 임시 설정이므로 검증 후 해당 장비의 Netplan 또는 라우터 설정으로 영구 저장한다. 기존 경로가 있으면 먼저 검토한다.

UFW를 이미 사용하는 OpenVPN 서버에서 전달 트래픽을 허용한다. 이후 모든 UFW 예제는 **VPN 인터페이스 `tun0`, LAN 인터페이스 `enp1s0`**를 가정한다. `ip -brief address`로 실제 이름을 확인해 바꾼다.

```bash
sudo ufw route allow in on tun0 out on enp1s0 from 10.8.0.0/24 to 10.66.0.0/24
```

서버 자체로 들어오는 UDP 1194 허용과 다른 규칙이다. 기본 UFW의 established/related 허용이 응답을 처리하며, 사용자 정의 정책이 있으면 함께 검토한다. LAN 장비의 호스트 방화벽도 목적 서비스나 ICMP를 허용해야 한다. [UFW route 규칙](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)

### 3. 클라이언트 LAN까지 확장하기

이제 client2가 `192.168.4.0/24`의 VPN 중계 장비가 된다. **client2에서도 2절의 IPv4 전달 설정을 수행한다.** 서버에서는 CCD 파일을 준비한다.

```bash
sudo install -d -m 750 /etc/openvpn/server/ccd
sudoedit /etc/openvpn/server/ccd/client2
```

편집한 `client2` 파일에는 다음을 저장한다.

```conf
iroute 192.168.4.0 255.255.255.0
```

서버의 `server.conf`에는 다음을 추가하고, 2절의 서버 LAN push도 유지한다.

```conf
client-config-dir /etc/openvpn/server/ccd
route 192.168.4.0 255.255.255.0
```

`route`는 커널에서 OpenVPN 쪽으로, `iroute`는 OpenVPN 내부에서 client2 쪽으로 보내는 역할이다. CCD는 클라이언트가 아니라 **서버에 저장**한다. 권한을 낮춘 OpenVPN이라면 CCD와 상위 디렉토리를 읽을 수 있게 해야 한다.

**서버 LAN 게이트웨이 `10.66.0.1`에서** 다음을 추가한다.

```bash
sudo ip route add 192.168.4.0/24 via 10.66.0.10
```

**클라이언트 LAN 게이트웨이 `192.168.4.1`에서** 다음을 추가한다.

```bash
sudo ip route add 10.66.0.0/24 via 192.168.4.10
sudo ip route add 10.8.0.0/24 via 192.168.4.10
```

양쪽 모두 next hop은 같은 LAN에 있는 VPN 장비의 LAN 주소다. 해당 VPN 장비가 원래 기본 게이트웨이라면 그쪽의 별도 게이트웨이 경로는 생략한다. 이 명령들도 Linux 게이트웨이의 임시 경로 예제다.

### 4. 양쪽 LAN 사이의 전달 허용

양쪽 LAN에서 연결을 시작할 수 있게 하는 실습 규칙이다. 운영에서는 필요한 목적지와 포트로 더 좁힌다.

OpenVPN **서버**에서:

```bash
sudo ufw route allow in on tun0 out on enp1s0 from 192.168.4.0/24 to 10.66.0.0/24
sudo ufw route allow in on enp1s0 out on tun0 from 10.66.0.0/24 to 192.168.4.0/24
```

OpenVPN **client2**에서:

```bash
sudo ufw route allow in on enp1s0 out on tun0 from 192.168.4.0/24 to 10.66.0.0/24
sudo ufw route allow in on tun0 out on enp1s0 from 10.66.0.0/24 to 192.168.4.0/24
```

이 규칙은 두 LAN 간 통신용이다. 다른 VPN 클라이언트까지 client2 LAN에 접근시키려면 별도 정책이 필요하다. 순수 라우팅을 사용하므로 이 예제에는 NAT/MASQUERADE를 추가하지 않는다. NAT는 반환 경로를 추가하기 어려운 경우의 별도 설계이며 원래 출발지 주소가 가려질 수 있다.

### 5. 설정 반영과 시험

기존 설정을 백업하고 [프로세스 제어 글](../openvpn-control-running-process/)에 따라 서버와 client2의 변경을 반영한다. 서버 설정을 바꿨는데 `SIGUSR1`만 보내면 다시 읽지 않는다. 재시작은 연결을 끊으므로 별도 관리 경로를 확보한다. CCD 변경은 대상 클라이언트의 다음 접속 때 적용된다.

먼저 일반 VPN 클라이언트에서 `10.66.0.20` 접근을 확인한 뒤 LAN 간 시험으로 넘어간다. **클라이언트 LAN 장비 `192.168.4.20`에서** 실행한다.

```bash
ip route get 10.66.0.20
ping -c 4 10.66.0.20
```

**서버 LAN 장비 `10.66.0.20`에서** 역방향도 시험한다.

```bash
ip route get 192.168.4.20
ping -c 4 192.168.4.20
```

일반 LAN 장비의 `ip route get`에 VPN 인터페이스가 보일 필요는 없다. 이 구성에서는 기본 게이트웨이를 가리키고, 게이트웨이가 VPN 장비로 전달한다. 실제 VPN 장비에서도 목적지 경로와 로그를 확인한다.

| 증상 | 우선 확인 |
|---|---|
| VPN 서버만 접근 가능 | 서버 LAN push, 서버 IP 전달, UFW route 규칙 |
| 요청은 도착하지만 응답 없음 | 양쪽 LAN 게이트웨이의 반환 경로, 대상 호스트 방화벽 |
| client2 LAN만 접근 불가 | 실제 CN과 CCD 파일명, `route`·`iroute`, client2의 전달 설정 |
| 일부 장소에서만 실패 | 기존 LAN과 VPN 사이트의 서브넷 중복 |

ping 실패만으로 단정하지 말고, 허용된 실제 서비스도 시험한다. 기본 LAN 연결은 인터넷 전체 트래픽 전달이나 DNS 설정까지 의미하지 않는다.

### 6. 원문의 선택 사항과 참조 링크

다른 VPN 클라이언트에도 client2 LAN을 공개하려는 경우 원문은 다음을 제안한다. 기본 LAN 간 연결에 필수는 아니다.

```conf
client-to-client
push "route 192.168.4.0 255.255.255.0"
```

DCO를 끈 경우 `client-to-client`는 OpenVPN 내부에서 전달하므로 커널의 클라이언트 간 방화벽 정책을 우회할 수 있다. DCO에서는 이 옵션이 효과가 없다. 단순히 편리하다는 이유로 추가하지 말고 접근 정책과 함께 결정한다.

TAP 브리징은 Ethernet 수준으로 네트워크를 잇는다. [브리징 문서](https://openvpn.net/community-docs/ethernet-bridging.html)와 [INSTALL의 DHCP 설명](https://openvpn.net/community-docs/the-standard-install-file-included-in-the-source-distribution.html)은 브리지 구성, 주소 배치, DHCP 계획을 전제로 한다. `dev tun`을 `dev tap`으로 바꾸는 것만으로 완성되지 않는다. 이번 글은 서로 다른 LAN을 연결하는 TUN 라우팅을 유지한다.

원문의 IP forwarding 참조 링크는 이번 확인에서 열리지 않아, 커널과 Ubuntu 공식 문서로 보완했다. 실제 PKI·개인키·운영 로그는 저장소에 포함하지 않는다.

### 참고 자료

- [OpenVPN: Expanding the Scope of the VPN](https://openvpn.net/community-docs/expanding-the-scope-of-the-vpn-to-include-additional-machines-on-either-the-client-or-server-subnet.html)
- [OpenVPN 2.7.7 server options: route, iroute, CCD, client-to-client](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)
- [OpenVPN 2.7 manual: disable-dco](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [Linux kernel: IP sysctl](https://docs.kernel.org/networking/ip-sysctl.html)
- [Ubuntu 24.04: UFW](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)
- [OpenVPN: Ethernet Bridging](https://openvpn.net/community-docs/ethernet-bridging.html)
- [OpenVPN: INSTALL — DHCP and bridging](https://openvpn.net/community-docs/the-standard-install-file-included-in-the-source-distribution.html)
