---
title: OpenVPN 실행과 첫 연결 확인 — Ubuntu 24.04
lang: ko-KR
permalink: /ko/openvpn-start-and-test-connectivity
author: ramen
date: 2026-10-07 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, troubleshooting, connectivity]
---

### 이번에 확인할 것

[이전 글](../openvpn-server-client-configuration/)에서 만든 설정으로 서버와 클라이언트를 실행하고, VPN 안에서 통신되는지 확인한다. **서버 시작, 클라이언트 연결, 실제 통신은 각각 확인해야 한다.**

공식 문서를 Ubuntu 24.04에 맞춰 요약한 절차다. 실기기에서 성공했다는 경험담은 아니며, 아래 명령은 독자의 서버와 클라이언트에서 실행한다. 원문의 오래된 Windows XP 조치와 OpenVPN 2.0 로그는 현재 환경의 기준으로 사용하지 않는다.

### 1. 실행 전 준비

[GitHub 소스 빌드와 make install](../openvpn-install-from-github-source/)을 마쳤고, 이전 글의 `UDP 1194`, `dev tun`, `10.8.0.0/24` 설정을 사용한다고 가정한다. 주소나 포트를 바꿨다면 아래 명령도 맞춰 바꾼다.

서버와 클라이언트 양쪽에서 설치 경로와 버전을 확인한다.

```bash
command -v openvpn
openvpn --version
```

출력된 실행 파일이 소스에서 설치한 버전인지 확인한다. 경로가 나오지 않으면 PATH와 설치 위치부터 점검한다. 인증서나 CA를 다시 만들 필요는 없다.

외부에서 접속하려면 서버 방화벽과 클라우드 방화벽에서 UDP 1194를 허용해야 한다. 공유기 뒤에 서버가 있다면 같은 포트를 서버의 LAN 주소로 전달한다. 클라이언트 설정의 `remote`에는 실제 접속 주소를 지정한다.

### 2. 서버를 먼저 실행

서버 터미널에서 실행하고 로그를 보이도록 유지한다.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

`Initialization Sequence Completed`는 서버 초기화가 완료되었다는 뜻이다. 아직 클라이언트 접속 성공을 뜻하지 않는다. 다른 서버 터미널에서 포트도 확인한다.

```bash
sudo ss -lunp 'sport = :1194'
```

이 명령은 로컬의 UDP 소켓과 프로세스를 보여준다. OpenVPN이 의도한 주소의 1194 포트를 사용하는지 확인한다. 소켓이 보인다는 사실만으로 외부에서 접근 가능하다고 판단할 수는 없다. [ss 명령 설명](https://manpages.ubuntu.com/manpages/noble/man8/ss.8.html)

### 3. 클라이언트를 실행

클라이언트 터미널에서 실행한다.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/client/client.conf
```

개인키가 암호화되어 있으면 프롬프트에서 암호를 입력한다. 클라이언트에서도 초기화 완료 메시지를 확인하고, 이후 재접속이나 오류가 반복되는지 살핀다. 처음에는 서비스 등록보다 터미널 실행이 오류 위치를 찾기 쉽다. 같은 설정을 서비스와 터미널에서 중복 실행하지 않는다.

### 4. VPN 내부 주소로 통신 확인

클라이언트의 다른 터미널에서 실행한다.

```bash
ip -brief address
ip route get 10.8.0.1
ping -c 4 10.8.0.1
```

`ip -brief address`로 할당된 주소를 보고, `ip route get`으로 목적지까지 실제로 선택되는 경로를 확인한다. `10.8.0.1`로 가는 경로가 VPN 인터페이스를 사용하는지 살핀다. 인터페이스 이름은 환경에 따라 달라질 수 있으므로 `tun0`이라고 단정하지 않는다. [ip-route 명령 설명](https://manpages.ubuntu.com/manpages/noble/man8/ip-route.8.html)

이전 설정에서 `10.8.0.1`은 서버의 VPN 주소다. ping 응답이 오고 경로도 VPN을 사용한다면, 해당 주소까지 터널을 통한 왕복 통신을 확인한 것이다. 인터넷 전체 트래픽 전송이나 서버 뒤 LAN 접근까지 검증한 것은 아니다.

### 5. 실패하면 이 순서로 확인

| 증상 | 먼저 확인할 내용 |
|---|---|
| 서버가 실행 직후 종료됨 | 로그의 첫 오류, 설정 파일 경로, 인증서·키 읽기 권한, 포트 중복 |
| TLS 협상 시간 초과 | `remote` 주소·포트·프로토콜, 서버 실행 여부, 방화벽, 포트 포워딩, 응답 경로 |
| 인증서 검증 오류 | 양쪽이 신뢰하는 CA, 인증서 유효기간, 장비 시각, 서버·클라이언트 인증서 용도 |
| 클라이언트 초기화 완료 후 ping 실패 | VPN 주소와 경로, 서브넷 중복, 양쪽의 터널 트래픽·ICMP 필터링 |

TLS 시간 초과만으로 원인을 확정하지 않는다. 서버와 클라이언트 로그를 함께 보며 어느 단계까지 진행됐는지 비교한다. `tls-auth`나 `tls-crypt`를 추가한 환경은 양쪽 설정과 키의 일치도 확인한다.

UFW를 사용한다면 양쪽에서 현재 정책을 확인한다.

```bash
sudo ufw status verbose
```

방화벽 전체를 끄기보다 필요한 터널 통신과 ICMP가 차단되는지 확인해 해당 규칙을 조정한다. ping 무응답만으로 VPN 연결 자체가 실패했다고 단정하지 않는다.

### 6. 시험 종료와 다음 단계

서버와 클라이언트 실행 터미널에서 각각 `Ctrl+C`로 종료한다. 기본 연결이 확인된 뒤 서비스 자동 시작, 접근 제어, LAN 라우팅 등을 별도로 구성한다. 서버 자신의 VPN 주소로 ping하는 시험에는 인터넷 공유용 NAT나 전달용 IP 포워딩을 먼저 켤 필요가 없다.

로그를 공유할 때는 공개하고 싶지 않은 주소와 인증서 식별 정보를 가리고, 개인키·암호·실제 PKI 자료는 블로그 저장소에 올리지 않는다.

### 참고 자료

- [OpenVPN: Starting Up the VPN and Testing for Initial Connectivity](https://openvpn.net/community-docs/starting-up-the-vpn-and-testing-for-initial-connectivity.html)
- [Ubuntu 24.04: ss](https://manpages.ubuntu.com/manpages/noble/man8/ss.8.html)
- [Ubuntu 24.04: ip-route](https://manpages.ubuntu.com/manpages/noble/man8/ip-route.8.html)
