---
title: OpenVPN 클라이언트별 접근 정책 — CCD 고정 IP와 방화벽
lang: ko-KR
permalink: /ko/openvpn-client-specific-access-policies
author: ramen
date: 2026-10-09 00:02:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, firewall, access-control, ccd]
---

### 접속 허용과 자원 접근 허용은 다르다

VPN 인증에 성공했다고 모든 내부 장비를 사용할 수 있어야 하는 것은 아니다. 원문은 사용자 그룹을 VPN 주소로 나누고 방화벽에서 목적지를 제한한다. 이번 글은 그 원리를 기존 Ubuntu 24.04·소스 설치 구성에 맞춰 설명한다. 실제 방화벽이나 VPN에 적용한 시험 기록은 아니다.

**CCD는 클라이언트 설정을 선택하고, 방화벽은 실제 통신을 제한한다.** route push를 빼는 것만으로 접근을 차단할 수는 없다. 클라이언트가 직접 경로를 추가할 수 있기 때문이다. [공식 원문](https://openvpn.net/community-docs/configuring-client-specific-rules-and-access-policies.html)

### 1. 이번 실습의 정책

[LAN 연결 글](../openvpn-connect-server-client-lans/)의 `10.66.0.0/24`를 유지하되, 이번에는 **각 클라이언트가 단일 장비인 원격 접속 구성**으로 한정한다. client2 뒤의 LAN을 중계하던 구성과 그대로 합치지 않는다.

| 인증서 Common Name | VPN 고정 IP | 허용 대상 |
|---|---|---|
| sysadmin1 | `10.8.0.10` | 서버 LAN 전체 |
| employee1 | `10.8.0.20` | `10.66.0.20`의 TCP 445·465·587·993 |
| contractor1 | `10.8.0.30` | `10.66.0.30`의 TCP 443 |
| contractor2 | `10.8.0.31` | 같은 HTTPS 서버 |
| 위 클라이언트 공통 | — | DNS `10.66.0.4`, `10.66.0.5`의 UDP·TCP 53 |

서비스 주소와 포트는 예시다. 실제 서비스에 맞춰 조정한다. 원문과 달리 직원도 고정 IP를 주어 동적 풀과 예약 주소의 충돌을 피하고, 명시적으로 등록한 장비만 접속시킨다. 고유하고 유효한 인증서가 필요하며 폐기한 인증서는 재사용하지 않는다.

### 2. topology subnet에 맞춰 CCD 설정

기존 서버 설정을 백업하고 아래 항목으로 **해당 옵션을 교체**한다. 인증서·키·CRL·UDP 포트·상태 및 관리 설정은 유지한다. 기존 `dev`, `server`, `ifconfig-pool`을 중복으로 남기지 않는다.

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

`nopool`로 자동 주소 풀을 만들지 않고 `ccd-exclusive`로 대응 CCD가 없는 클라이언트를 거부한다. 이것은 LAN 접근 권한 자체를 부여하는 옵션은 아니다. 각 CCD는 다음과 같이 준비한다.

```bash
sudo install -d -m 750 /etc/openvpn/server/ccd
sudoedit /etc/openvpn/server/ccd/sysadmin1
sudoedit /etc/openvpn/server/ccd/employee1
sudoedit /etc/openvpn/server/ccd/contractor1
sudoedit /etc/openvpn/server/ccd/contractor2
```

각 파일에는 표의 한 줄을 저장한다.

| 서버의 CCD 파일명 | 내용 |
|---|---|
| sysadmin1 | `ifconfig-push 10.8.0.10 255.255.255.0` |
| employee1 | `ifconfig-push 10.8.0.20 255.255.255.0` |
| contractor1 | `ifconfig-push 10.8.0.30 255.255.255.0` |
| contractor2 | `ifconfig-push 10.8.0.31 255.255.255.0` |

이름은 실제 인증서 CN과 정확히 일치시킨다. 권한을 낮춘 OpenVPN이면 파일 읽기와 상위 디렉토리 통과 권한도 확인한다. `topology subnet`에서 두 번째 인자는 넷마스크다. 원문의 `10.8.1.1 10.8.1.2` 같은 `/30` 끝점 쌍을 그대로 사용하지 않는다. `ifconfig-pool-persist`도 고정 할당을 보장하는 대체 수단은 아니다. [서버 옵션](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)

`duplicate-cn`과 `client-to-client`는 사용하지 않는다. 이번 예제는 DCO를 꺼 내부 전달이 커널 필터를 우회하지 않도록 구성을 단순화한다. `max-routes-per-client 1`은 단일 장비 예제에서 추가 주소 학습을 제한하는 보완책이며, LAN 중계 클라이언트에 무작정 적용하면 안 된다. IP 기반 규칙만으로 인증서 검증을 대신하지 말고, 변조된 출발지 주소에 대한 거부도 운영 검증에 포함한다.

### 3. 기존 경로와 넓은 허용 규칙 점검

서버 LAN 게이트웨이에는 `10.8.0.0/24`를 OpenVPN 서버 LAN 주소로 돌려보내는 경로가 필요하다. IP 전달과 DNS 서버의 질의 허용도 앞 글대로 유지한다.

서버에서 먼저 현재 규칙을 확인한다.

```bash
sudo ufw status verbose
sudo ufw status numbered
sudo ufw show raw
```

이번 예제는 **이미 활성화된 UFW가 방화벽을 관리하는 서버**를 전제로 한다. `tun0`는 VPN, `enp1s0`는 서버 LAN 인터페이스 예시다. 다른 이름이면 바꾼다. 기존 `tun0` 관련 사용자 규칙을 검토·정리하고 아래 정책 블록을 한 번만 배치한다. 이전 글의 전체 LAN 허용을 새 제한보다 앞에 남기면 제한이 무력화된다. UFW의 before 규칙이나 다른 nftables/iptables 관리자도 확인한다.

원격 SSH를 유지할 별도 관리 경로와 복구 수단을 확보하고, 아래 규칙을 실제 운영 서버에 무검토로 복사하지 않는다. VPN 장비의 설정을 변경하는 작업이며 블로그 게시 과정에서는 실행하지 않았다.

### 4. 허용 목록 뒤에 명시적 거부

먼저 VPN에서 들어온 전달 트래픽의 거부 규칙을 맨 앞에 놓고, 필요한 허용 규칙을 그 앞에 삽입한다. 중간 단계에는 통신이 일시 차단될 수 있다.

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

완료 후 `sudo ufw status numbered`에서 **허용 8개 다음에 tun0 전달 거부**가 오는지 확인한다. 예상 순서가 아니면 계속 진행하지 말고 기존 규칙과 중복을 정리한다. 이 거부 규칙은 명시한 목적지 외의 전달과 커널을 통한 클라이언트 간 전달도 제한한다. LAN에서 VPN으로 새로 시작하는 연결은 별도 정책 범위다.

기본 UFW의 established/related 처리로 허용된 연결의 응답이 통과한다. 기존 연결 추적 상태는 정책 변경 후에도 남을 수 있으므로, 차단 검증은 새 연결로 수행한다. 긴급 권한 회수는 [CRL과 세션 종료 절차](../openvpn-control-running-process/)도 함께 적용한다. [UFW 문서](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)

### 5. VPN 서버 자체는 INPUT 정책

위 `ufw route`는 서버를 **통과하는** 트래픽이다. VPN 서버 자신의 SSH·관리 포트는 별도 INPUT 정책이다. 이 실습은 VPN을 통한 서버 자체 접근을 막는다.

```bash
sudo ufw insert 1 deny in on tun0
```

따라서 `10.8.0.1`로 ping하는 앞 글의 시험도 차단될 수 있다. VPN의 바깥쪽 UDP 1194 허용과는 다르다. 서버 자체의 서비스를 허용하려면 목적지·출발지·포트를 한정한 예외를 이 거부보다 앞에 설계한다.

이 글은 IPv4 예제다. IPv6 터널·다른 VPN·별도 경로가 있다면 동일한 접근 정책을 적용하거나 해당 경로를 사용하지 않도록 구성한다. UFW의 IPv6 처리도 확인한다.

### 6. 허용되는 것과 막히는 것을 모두 시험

[프로세스 제어 글](../openvpn-control-running-process/)에 따라 변경을 반영하고 각 클라이언트를 재접속시킨다. `SIGUSR1`만으로 서버 설정은 다시 읽히지 않는다. 관리 상태의 CN과 할당 주소를 먼저 확인한다.

각 클라이언트에서 아래 명령으로 예제 포트를 시험한다.

```bash
sudo apt install netcat-openbsd
ip -brief address
nc -vz -w 3 10.66.0.20 445
nc -vz -w 3 10.66.0.30 443
nc -vz -w 3 10.66.0.20 22
```


| 시험 | 관리자 | 직원 | 협력사 |
|---|---|---|---|
| `10.66.0.20:445` | 허용 | 허용 | 거부 |
| `10.66.0.30:443` | 허용 | 거부 | 허용 |
| `10.66.0.20:22` | 허용 | 거부 | 거부 |

허용 시험은 실제 서비스가 듣고 있어야 성공한다. 실패만으로 방화벽이 차단했다고 단정하지 말고 경로·서버 리스닝·로그를 함께 본다. CCD가 없는 유효한 시험 인증서도 거부되는지 확인한다. DNS는 [DNS 글](../openvpn-push-dns-options/)의 직접 질의와 일반 조회를 각각 시험한다.

정책 변경으로 접속자를 퇴사·계약 종료 처리하는 경우에는 주소를 재할당하기 전에 기존 세션과 인증서를 정리한다. 인증서 CN, 고정 주소, 방화벽 정책의 대응표를 함께 관리하고 실제 개인키·운영 로그는 공개하지 않는다.

### 참고 자료

- [OpenVPN: Configuring Client-Specific Rules and Access Policies](https://openvpn.net/community-docs/configuring-client-specific-rules-and-access-policies.html)
- [OpenVPN 2.7.7 server options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)
- [OpenVPN 2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [Ubuntu 24.04: UFW](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)
