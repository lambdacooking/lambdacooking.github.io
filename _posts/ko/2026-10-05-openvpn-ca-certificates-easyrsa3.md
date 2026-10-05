---
title: Easy-RSA 3로 OpenVPN CA와 서버·클라이언트 인증서 만들기
lang: ko-KR
permalink: /ko/openvpn-ca-certificates-easyrsa3
author: ramen
date: 2026-10-05 14:30:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, pki, easy-rsa, certificates]
---

### Ubuntu 24.04에서는 Easy-RSA 3으로 진행

Ubuntu 24.04에서 Easy-RSA 2를 사용하다가 문제가 생겨, 이번에는 Easy-RSA 3을 사용했다. 새로 구성한다면 가급적 **Easy-RSA 3을 권장한다.** 여기서 말하는 3은 도구의 버전이며, RSA 키 길이나 암호 알고리즘 이름이 아니다.

[OpenVPN 공식 CA 문서](https://openvpn.net/community-docs/setting-up-your-own-certificate-authority--ca--and-generating-certificates-and-keys-for-an-openvpn-server-and-multiple-clients.html)도 Unix 계열에서는 3을 살펴보라고 안내하지만, 본문의 `./build-ca`, `./build-key-server` 예제는 여전히 2 방식이다. 예제가 현재 환경에 맞게 갱신되지 않은 부분이 문제에 영향을 주었을 수 있다. 다만 오류 로그를 분석한 것은 아니므로 Ubuntu 24.04에서 Easy-RSA 2가 항상 동작하지 않는다고 단정하지는 않는다.

이 글은 2026년 10월 5일 확인한 최신 릴리스 [Easy-RSA 3.2.7](https://github.com/OpenVPN/easy-rsa/releases/tag/v3.2.7)을 고정해서 사용한다. 나중에 따라 할 때는 새 릴리스도 확인하자.

### 1. build-ca 전에 의존성과 파일 준비

먼저 의존성을 준비한다. **인증서 생성에는 `openssl` 실행 파일이 필요하다.** 아래 명령은 앞 글의 OpenVPN 소스 빌드를 이어가는 환경을 고려해 개발 패키지도 함께 설치한다. 개발 패키지 전체가 `build-ca`의 필수 조건이라는 뜻은 아니다.

| 확인했던 항목 | Ubuntu에서 사용할 패키지·역할 |
|---|---|
| `pkg-config` | OpenVPN 빌드 시 라이브러리 탐색 |
| `libnl-genl-3.5.0` | 그대로 설치할 패키지 이름이 아니다. 빌드가 찾는 모듈명은 `libnl-genl-3.0`이며 버전은 별도로 확인 |
| `libnl-3-dev`, `libnl-genl-3-dev` | Netlink 및 Generic Netlink 개발 파일, Linux DCO 빌드 검사에 사용 |
| `libcap-ng-dev` | Linux 권한 관리 개발 파일 |
| `libssl-dev` | OpenSSL 개발 헤더; `openssl` 명령 자체와 구분 |
| `liblz4-dev`, `liblzo2-dev` | OpenVPN 압축 라이브러리 빌드 의존성 |
| `libpam-dev` | 이 예제에서는 실제 패키지 `libpam0g-dev` 사용; PAM 플러그인 빌드용 |

패키지 구분은 OpenVPN의 [빌드 설정](https://github.com/OpenVPN/openvpn/blob/v2.7.7/configure.ac)과 [Linux CI](https://github.com/OpenVPN/openvpn/blob/v2.7.7/.github/workflows/build.yaml)를 참고했다. 라이브러리 설치 자체가 VPN 압축을 활성화하지는 않는다.

```bash
sudo apt update
sudo apt install -y git ca-certificates openssl pkg-config \
  libnl-3-dev libnl-genl-3-dev libcap-ng-dev libssl-dev \
  liblz4-dev liblzo2-dev libpam0g-dev
openssl version
pkg-config --modversion libnl-genl-3.0
```

이 명령만으로 OpenVPN 소스 빌드 도구가 모두 설치되는 것은 아니다. 전체 빌드 과정은 [이전 글](../openvpn-install-from-github-source/)을 참고한다. CA를 별도 컴퓨터에 둘 경우 그 컴퓨터에는 OpenVPN 개발 패키지가 필요하지 않다.

### 2. Easy-RSA 3 전체 소스 받기

블로그 저장소 밖의 전용 디렉토리에서 일반 사용자로 실행한다. 다음 예제의 디렉토리는 아직 존재하지 않는 것을 전제로 한다.

```bash
umask 077
mkdir -p "$HOME/vpn-pki-work"
cd "$HOME/vpn-pki-work"
git clone --depth 1 --branch v3.2.7 \
  https://github.com/OpenVPN/easy-rsa.git easy-rsa-3.2.7
cd easy-rsa-3.2.7/easyrsa3
./easyrsa --version
ls easyrsa openssl-easyrsa.cnf vars.example x509-types
```

`easyrsa` 하나만 복사하지 말고 `openssl-easyrsa.cnf`와 `x509-types/`도 함께 보관한다. `vars.example`은 설정 참고용이다. Easy-RSA 자체에는 `make install`이 필요하지 않다. [공식 사용 설명](https://easy-rsa.readthedocs.io/en/latest/)

### 3. 새 PKI와 CA 생성

다음은 새 CA를 만드는 절차다. **기존 PKI에 `init-pki`를 다시 실행하지 않는다.** 기존 `vars`도 덮어쓰지 않도록 확인한다.

```bash
cat > vars <<'EOF'
set_var EASYRSA_ALGO rsa
set_var EASYRSA_KEY_SIZE 3072
set_var EASYRSA_DIGEST sha256
EOF
./easyrsa init-pki
./easyrsa build-ca
```

CA 개인키에는 강한 암호를 지정한다. Common Name에는 `SnackChocopie VPN CA`처럼 구분할 수 있는 이름을 입력한다. Easy-RSA 2와 달리 `. ./vars`를 실행하지 않는다.

`pki/ca.crt`는 신뢰 기준이 되는 공개 인증서이고 `pki/private/ca.key`는 인증서 서명 권한을 가진 비밀키다. CA 키는 서버나 클라이언트에 배포하지 않는다. 가능하면 CA를 VPN 서버와 분리해 오프라인으로 관리한다.

### 4. 서버와 여러 클라이언트 발급

아래는 흐름을 이해하기 위해 CA 작업 공간에서 키 생성과 서명을 한 번에 수행하는 예제다. 실제 운영에서는 각 장치에서 개인키와 CSR을 만들고, CA에는 CSR만 전달하는 구성을 권장한다.

```bash
./easyrsa build-server-full server nopass
./easyrsa build-client-full client1
./easyrsa build-client-full client2
./easyrsa build-client-full client3
```

각 명령의 확인 요청을 읽고 승인하며 CA 암호를 입력한다. `client1`~`client3`에는 각각 별도의 개인키 암호를 설정한다. 사용자나 장치마다 고유한 인증서 이름을 사용하고 하나의 키를 공유하지 않는다.

서버의 `nopass`는 무인 시작을 위한 선택으로, **서버 개인키의 암호화를 생략한다.** 파일 접근 권한을 엄격히 제한해야 한다. 암호 입력이 가능한 운영이라면 이를 생략해도 된다. CA에는 `nopass`를 사용하지 않는다. 명령과 옵션은 [3.2.7 스크립트](https://github.com/OpenVPN/easy-rsa/blob/v3.2.7/easyrsa3/easyrsa)에 정의되어 있다.

### 5. 검증하고 필요한 파일만 배포

```bash
openssl verify -CAfile pki/ca.crt -purpose sslserver pki/issued/server.crt
openssl verify -CAfile pki/ca.crt -purpose sslclient \
  pki/issued/client1.crt pki/issued/client2.crt pki/issued/client3.crt
openssl x509 -in pki/issued/server.crt -noout -subject -issuer -dates
```

검증 결과가 `OK`인지 확인하고 유효기간도 살핀다. 이 검사는 실제 VPN 연결 시험을 대신하지 않는다.

| 대상 | 전달할 파일 |
|---|---|
| VPN 서버 | `pki/ca.crt`, `pki/issued/server.crt`, `pki/private/server.key` |
| client1 | `pki/ca.crt`, `pki/issued/client1.crt`, `pki/private/client1.key` |
| client2 / client3 | 같은 CA 인증서와 각자 이름의 인증서·개인키 |
| CA 보관소만 | `pki/private/ca.key`, 발급 DB를 포함한 전체 PKI의 안전한 백업 |

개인키는 안전한 경로로 전달하고 필요한 사용자만 읽을 수 있게 한다. PKI와 암호를 GitHub나 블로그에 올리지 않는다. 인증서는 신원을 증명하는 자료이므로 VPN 서버 설정, 라우팅, 방화벽 구성은 별도로 필요하다.

기존 문서의 `build-dh`는 Easy-RSA 3에서 `./easyrsa gen-dh`에 해당한다. 유한체 DH를 쓰는 서버 설정이라면 생성한 `pki/dh.pem`을 사용한다. 최신 OpenVPN에서 ECDH 등을 사용하는 경우 `dh none`을 선택할 수 있어 DH 파일이 항상 필요한 것은 아니다. [OpenVPN TLS 설정](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/tls-options.rst)

### 6. 분실한 클라이언트 인증서 폐기

다음은 client2를 실제로 차단해야 할 때만 실행하는 예제다.

```bash
./easyrsa revoke client2
./easyrsa gen-crl
openssl crl -in pki/crl.pem -noout -lastupdate -nextupdate
```

생성된 `pki/crl.pem`을 VPN 서버로 전달하고 서버 설정의 `crl-verify`가 해당 파일을 읽도록 해야 폐기 정보가 적용된다. CA에서 폐기만 하고 끝내면 서버는 이를 알 수 없다. CRL의 만료일을 관리하고 새 폐기 때마다 갱신·배포한다. 이미 연결된 세션의 종료는 별도로 처리한다.

이후에는 CA를 다시 만드는 대신 기존 PKI를 보관하면서 새 클라이언트를 추가하고 인증서 만료·폐기를 관리한다.
