---
title: OpenVPN으로 DNS 옵션 전달하기 — Ubuntu 24.04와 OpenVPN 2.7
lang: ko-KR
permalink: /ko/openvpn-push-dns-options
author: ramen
date: 2026-10-09 00:01:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, dns, dhcp, systemd-resolved]
---

### IP 연결 다음에는 이름 해석

[LAN 연결 글](../openvpn-connect-server-client-lans/)에서 내부 IP에 접근했다면, 이번에는 내부 이름을 DNS로 조회한다. **서버가 DNS 주소를 전달하는 것, 클라이언트 OS가 적용하는 것, DNS 서버까지 통신되는 것은 별개다.**

공식 문서를 Ubuntu 24.04와 앞 글의 소스 빌드 OpenVPN 2.7.7에 맞춰 정리했다. 아래는 구성 예시이며 실제 VPN에서 검증한 접속 기록은 아니다.

### 1. DNS 서버가 먼저 있어야 한다

예제는 서버 LAN의 `10.66.0.4`, `10.66.0.5`에서 DNS가 이미 동작하고, 양쪽 모두 `host.corp.example` 같은 내부 레코드를 알고 있다고 가정한다. `corp.example`은 설명용 도메인이므로 실제 관리하는 내부 도메인과 레코드로 바꾼다.

OpenVPN의 push는 DNS 서버나 레코드를 생성하지 않는다. `dhcp-option`이라는 이름도 TUN 환경에서 실제 DHCP 서버가 필요한 뜻은 아니다. WINS는 오래된 NetBIOS 이름 해석용으로, DNS의 대체 설정이 아니다. 필요한 기존 환경에서만 원문의 `push "dhcp-option WINS 10.66.0.8"`을 검토한다. [원문](https://openvpn.net/community-docs/pushing-dhcp-options-to-clients.html)

### 2. 원문의 dhcp-option 방식

서버의 `/etc/openvpn/server/server.conf`에 넣는 전통적인 예제다.

```conf
push "dhcp-option DNS 10.66.0.4"
push "dhcp-option DNS 10.66.0.5"
push "dhcp-option DOMAIN corp.example"
```

`DNS`는 DNS 서버 주소, `DOMAIN`은 연결별 DNS 접미사다. 접미사 전달만으로 모든 운영체제에서 특정 도메인만 VPN DNS로 보내는 split DNS가 완성되지는 않는다.

원문은 Windows의 기본 처리와 비Windows의 `foreign_option_n`·up 스크립트 방식을 설명한다. 그러나 2.7은 기본 `dns-updown` 훅과 기존 DNS 옵션 변환도 지원하므로, **Linux는 무조건 수동 스크립트가 필요하다고 일반화하면 안 된다.** [2.7 매뉴얼](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 3. 2.7 예제는 dns 방식으로 구분

2.7 클라이언트와 DNS 적용 경로를 확인한 환경에서는 위 DNS 관련 `dhcp-option` 줄 대신 다음을 사용한다. 두 예제를 동시에 넣지 않는다.

```conf
push "dns server 0 address 10.66.0.4 10.66.0.5"
push "dns server 0 resolve-domains corp.example"
push "dns search-domains corp.example"
```

이 구성은 `corp.example`과 그 하위 이름은 내부 DNS로 조회하고, 짧은 이름에는 검색 접미사를 제공하려는 의도다. 실제 지원은 클라이언트와 OS에 따라 달라진다. 다른 도메인은 기존 DNS 정책을 따른다. 두 DNS 주소는 동일한 내부 영역을 처리할 수 있어야 하며, 목록 순서만 보고 고정된 주·보조 전환을 보장한다고 생각하지 않는다.

`dns server` 옵션이 있으면 DNS 관련 `dhcp-option`보다 우선한다. 혼합 버전 클라이언트가 있다면 일괄 전환 전에 지원 여부를 확인한다. [2.7 매뉴얼](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 4. Ubuntu 클라이언트의 적용 경로 확인

VPN 연결 전 상태를 기록한다.

```bash
openvpn --version
systemctl is-active systemd-resolved
readlink -f /etc/resolv.conf
resolvectl status
ip -brief address
```

이 글은 systemd-resolved가 실행 중이고 `/etc/resolv.conf`가 그 관리 파일에 연결된 구성을 전제로 한다. 다른 DNS 관리자를 쓰고 있다면 먼저 그 구성에 맞는 연동 방법을 선택한다. `/etc/resolv.conf`를 무조건 덮어쓰지 않는다.

2.7.7의 Linux 소스는 기본 DNS 훅을 제공하며 `make install` 과정에서 선택된 `dns-updown`을 설치한다. 해당 훅은 환경에 따라 systemd-resolved, resolvconf, 파일 방식으로 처리한다. 빌드 옵션·설치 경로·권한에 따라 결과가 달라질 수 있으므로 연결 로그에서 DNS 훅 실행과 오류를 확인한다. [공식 스크립트](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/systemd-dns-updown.sh), [설치 규칙](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/Makefile.am)

기존 `up` 스크립트가 있으면 기본 DNS 훅이 억제될 수 있다. `dns-updown disable`이나 빌드 설정으로 비활성화된 경우도 점검한다. NetworkManager가 관리하는 프로필과 CLI·별도 스크립트가 동시에 DNS를 바꾸지 않게 한다.

2.6 등 기존 환경에서는 배포판 연동이나 [외부 update-systemd-resolved 도구](https://github.com/jonathanio/update-systemd-resolved)를 사용할 수 있다. 이 도구는 OpenVPN 자체가 아닌 별도 프로젝트다. 설치 경로와 연결·해제 훅, 실행 권한을 해당 설명대로 구성하고, 이미 동작하는 2.7 기본 훅과 중복 추가하지 않는다.

### 5. DNS까지의 경로와 방화벽도 필요

DNS 서버가 이전 글의 LAN에 있으므로 서버 설정의 다음 경로를 유지한다.

```conf
push "route 10.66.0.0 255.255.255.0"
```

앞 글의 IP 전달·반환 경로·방화벽 구성이 필요하다. DNS 서버에서는 VPN 클라이언트 대역의 질의를 허용하고 UDP와 TCP 53을 모두 검토한다. DNS 주소 push만으로 경로나 접근 허용이 생기지 않는다.

[프로세스 제어 글](../openvpn-control-running-process/)에 따라 서버 변경을 반영하고 클라이언트를 다시 연결한다. `SIGUSR1`은 변경한 서버 설정을 다시 읽지 않는다.

### 6. 전달·적용·응답을 따로 검사

VPN 연결 후 클라이언트에서 실행한다.

```bash
ip route get 10.66.0.4
ip route get 10.66.0.5
resolvectl status
resolvectl query host.corp.example
getent ahosts host.corp.example
```

`resolvectl status`에서 실제 VPN 링크의 DNS 서버와 도메인 경로를 확인한다. systemd-resolved에서는 `~corp.example`이 조회 경로만 지정하는 도메인이고, `corp.example`은 검색 접미사 역할도 할 수 있다. `~.`은 전체 DNS 질의를 그 링크로 보내는 정책이라 이번 split DNS 목적과 다르다. [resolvectl 설명](https://manpages.ubuntu.com/manpages/noble/man1/resolvectl.1.html)

DNS 서버 자체를 분리해서 시험하려면 다음을 사용한다.

```bash
sudo apt install dnsutils
dig @10.66.0.4 host.corp.example A
dig @10.66.0.5 host.corp.example A
dig +tcp @10.66.0.4 host.corp.example A
```

`dig @주소` 성공은 해당 DNS 서버가 응답한다는 증거이며, OS가 기본적으로 그 서버를 선택한다는 증거는 아니다. 실제 반환 레코드가 의도한 내부 주소인지도 확인한다.

| 증상 | 확인할 내용 |
|---|---|
| DNS 서버를 지정한 dig도 실패 | VPN 경로·반환 경로·53번 포트·DNS 질의 허용 정책 |
| 직접 질의는 성공, 일반 조회는 실패 | DNS 훅, resolver 연동, split DNS 도메인 |
| 전체 이름만 성공, 짧은 이름 실패 | 검색 접미사와 애플리케이션 동작 |
| 브라우저만 결과가 다름 | 브라우저의 별도 DoH 설정·캐시 |

Windows에서는 원문처럼 `ipconfig /all`을 확인하고 실제 질의도 시험한다. 최신 환경은 드라이버와 DNS 정책이 다르므로 TAP 어댑터 표시만으로 판정하지 않는다.

```text
ipconfig /all
nslookup host.corp.example
```


### 7. 연결 해제 후 복원 확인

정상적으로 VPN을 종료한 뒤 `resolvectl status`와 일반 도메인의 조회를 다시 확인한다. 내부 DNS 설정이 남아 인터넷 이름 해석을 방해하지 않아야 한다. `resolvectl revert 인터페이스명`은 수동 복구 수단이지만 해당 링크의 다른 수동 설정도 되돌리므로 대상 확인 후 사용한다.

이 설정만으로 모든 애플리케이션의 DNS 누출 방지가 보장되지는 않는다. 브라우저 DoH, 다른 링크의 DNS 정책, IPv6도 별도로 고려한다. 원문의 caveats 링크는 이번 확인에서 열리지 않아 최신 매뉴얼과 구현을 확인해 보완했다.

### 참고 자료

- [OpenVPN: Pushing DHCP Options to Clients](https://openvpn.net/community-docs/pushing-dhcp-options-to-clients.html)
- [OpenVPN 2.7 manual — dhcp-option, dns, dns-updown](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [OpenVPN 2.7.7 DNS helper](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/systemd-dns-updown.sh)
- [OpenVPN 2.7.7 DNS helper installation](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/Makefile.am)
- [Ubuntu 24.04: resolvectl](https://manpages.ubuntu.com/manpages/noble/man1/resolvectl.1.html)
- [update-systemd-resolved — third-party helper](https://github.com/jonathanio/update-systemd-resolved)
