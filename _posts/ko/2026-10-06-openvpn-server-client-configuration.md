---
title: Ubuntu 24.04에서 OpenVPN 서버와 클라이언트 설정 파일 만들기
lang: ko-KR
permalink: /ko/openvpn-server-client-configuration
author: ramen
date: 2026-10-06 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, configuration, server, client]
---

### 인증서를 실제 VPN 설정에 연결하기

[소스 빌드와 make install](../openvpn-install-from-github-source/), [Easy-RSA 3 인증서 생성](../openvpn-ca-certificates-easyrsa3/) 다음 단계다. OpenVPN 공식 설정 안내를 참고해 Ubuntu 24.04용 예제를 정리했다. 실제 장비에서 연결 성공을 확인했다는 경험담은 아니며, 아래 연결 시험으로 각자의 환경을 확인해야 한다.

### 1. 실행 파일과 샘플 확인

앞 글에서 빌드한 OpenVPN 소스 디렉토리에서 실행한다.

```bash
command -v openvpn
openvpn --version
ls sample/sample-config-files/{server,client}.conf
```

`command -v`가 출력한 경로와 버전이 소스에서 설치한 실행 파일인지 확인한다. 아무것도 출력되지 않으면 설치 경로와 PATH부터 확인한다. 이 글은 설정을 직접 작성하므로 샘플을 통째로 복사할 필요는 없다. `make install`만으로 배포판의 systemd 서비스가 준비되었다고 가정하지 않고 우선 터미널에서 실행한다.

### 2. 서버 파일 준비

앞 글에서 만든 `ca.crt`, `server.crt`, `server.key`만 안전한 경로로 서버에 전달한다. 서버에서 이 세 파일이 있는 디렉토리로 이동한 뒤 실행한다. 아래는 새 구성용이며 기존 파일이 있다면 먼저 백업한다. **CA 개인키인 `ca.key`는 서버에 전달하지 않는다.**

```bash
sudo install -d -m 750 /etc/openvpn/server
sudo install -m 644 ca.crt server.crt /etc/openvpn/server/
sudo install -m 600 server.key /etc/openvpn/server/
sudoedit /etc/openvpn/server/server.conf
```

편집기에 다음 내용을 저장한다.

```conf
port 1194
proto udp
dev tun
topology subnet
server 10.8.0.0 255.255.255.0

ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh none
remote-cert-tls client

keepalive 10 120
persist-key
persist-tun
verb 3
```

`10.8.0.0/24`는 예시다. 서버 LAN과 클라이언트가 접속하는 LAN에 겹치지 않는 범위를 [사설 서브넷 설계](../vpn-private-subnet-planning/)에 따라 선택한다.

`dh none`은 유한체 DH 매개변수 파일을 사용하지 않는 설정이다. 현대적인 키 교환을 사용하며 앞 글의 RSA 인증서와 함께 사용할 수 있다. 인증서의 키 종류와 연결 시 사용하는 키 교환 방식은 구분해야 한다. 이 예제에는 `gen-dh`가 필요하지 않다.

### 3. 클라이언트 파일 준비

Ubuntu 클라이언트에는 `ca.crt`, `client1.crt`, `client1.key`를 전달한다. 이 파일들이 있는 디렉토리에서 실행한다.

```bash
sudo install -d -m 750 /etc/openvpn/client
sudo install -m 644 ca.crt client1.crt /etc/openvpn/client/
sudo install -m 600 client1.key /etc/openvpn/client/
sudoedit /etc/openvpn/client/client.conf
```

다음을 저장하되 `vpn.example.com`은 실제 서버의 도메인 또는 공인 IP로 교체한다.

```conf
client
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun

ca /etc/openvpn/client/ca.crt
cert /etc/openvpn/client/client1.crt
key /etc/openvpn/client/client1.key
remote-cert-tls server
verb 3
```

각 장치에는 고유한 인증서·개인키를 사용한다. `client2`라면 파일 이름과 설정 경로도 함께 바꾼다. `remote-cert-tls server`는 서버 용도로 발급된 인증서인지 검사하며, 서버 설정의 `remote-cert-tls client`는 클라이언트 용도를 검사한다.

### 4. 방화벽과 연결 시험

서버까지 UDP 1194가 도달해야 한다. UFW를 이미 사용하는 서버에서는 다음과 같이 허용하고 상태를 확인한다.

```bash
sudo ufw allow 1194/udp
sudo ufw status
```

클라우드 방화벽도 별도로 확인한다. 공유기 뒤의 서버라면 UDP 1194를 서버의 LAN 주소로 포트 포워딩한다. `remote`에는 외부에서 접근할 주소를 지정한다.

서버에서 실행한다.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

그다음 클라이언트에서 실행한다. 앞 글처럼 개인키에 암호를 설정했다면 프롬프트에서 입력한다.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/client/client.conf
```

연결 로그에서 `Initialization Sequence Completed`를 확인하고 클라이언트의 다른 터미널에서 시험한다.

```bash
ping -c 4 10.8.0.1
ip address show
ip route show
```

ping에 응답하지 않으면 연결 로그, 터널 주소, ICMP 허용 정책을 함께 확인한다. 종료는 각 실행 터미널에서 `Ctrl+C`를 누른다. 서버 프로세스의 초기화 완료만으로 클라이언트 연결까지 성공한 것은 아니다.

### 5. 기본 연결 다음에 적용할 항목

이 설정은 VPN 터널 연결을 확인하기 위한 출발점이다. 서버 뒤 LAN 접근이나 인터넷 전체 트래픽 전달에는 별도의 경로, IP 포워딩, 방화벽 및 필요에 따른 NAT 구성이 필요하다.

앞 글에서 CRL을 만들었다면 서버에 배치한 뒤 다음을 추가한다.

```conf
crl-verify /etc/openvpn/server/crl.pem
```

CRL 파일의 존재·읽기 권한·만료일을 확인하고, 인증서를 폐기할 때마다 갱신·배포한다. 이미 연결된 세션의 종료는 별도로 처리한다. 운영 시에는 `tls-crypt` 같은 제어 채널 보호와 서비스 실행·권한 축소도 함께 구성한다.

원문의 `comp-lzo`와 `fragment`를 새 구성에 그대로 추가하지 않는다. 특히 압축은 새 구성에서 활성화하지 않는다. 원문의 `group nobody`도 Ubuntu에 그대로 적용하지 말고 `getent group nogroup` 등으로 실제 계정을 확인한다. 이 예제는 권한 축소 옵션을 아직 포함하지 않았다.

실제 개인키·암호·PKI 자료는 블로그 저장소에 저장하지 않는다.

### 참고 자료

- [Creating Configuration Files for Server and Clients](https://openvpn.net/community-docs/creating-configuration-files-for-server-and-clients.html)
- [OpenVPN 2.7.7 server.conf](https://github.com/OpenVPN/openvpn/blob/v2.7.7/sample/sample-config-files/server.conf)
- [OpenVPN 2.7.7 TLS options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/tls-options.rst)
- [OpenVPN 2.6 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html)
