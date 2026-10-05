---
title: GitHub 소스로 OpenVPN을 빌드하고 make install로 설치하기
lang: ko-KR
permalink: /ko/openvpn-install-from-github-source
author: ramen
date: 2026-10-05 14:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, source-build]
---

### 대상 환경과 버전

[공식 설치 문서](https://openvpn.net/community-docs/installing-openvpn.html)를 바탕으로, GitHub에서 소스를 받아 설치하는 과정을 정리합니다. 예시 환경은 Ubuntu 24.04이며, 다른 Debian 계열 버전에서는 패키지 조정이 필요할 수 있습니다. 여기서는 OpenVPN 실행 파일을 설치하며, VPN 서비스 설정까지 완료하는 것은 아닙니다.

명령은 2026년 10월 5일 GitHub에서 최신 릴리스로 확인한 [v2.7.7](https://github.com/OpenVPN/openvpn/releases/tag/v2.7.7)을 사용합니다. 나중에 설치한다면 이 버전이 계속 최신이라고 가정하지 말고 릴리스를 다시 확인하세요.

### 1. 빌드 의존성 설치

빌드 도구와 라이브러리는 APT로 설치하고, OpenVPN 본체는 소스에서 빌드합니다. 패키지 구성은 프로젝트의 [Linux CI 의존성](https://github.com/OpenVPN/openvpn/blob/v2.7.7/.github/workflows/build.yaml)을 참고했습니다.

```bash
sudo apt update
sudo apt install -y \
  git ca-certificates build-essential autoconf automake libtool pkg-config \
  libssl-dev liblzo2-dev liblz4-dev libcap-ng-dev libnl-genl-3-dev \
  libpam0g-dev libcmocka-dev python3-docutils
```

`libssl-dev`는 OpenSSL 헤더를 제공하고, LZO/LZ4 개발 패키지는 기본 라이브러리 검사에 대응합니다. 라이브러리를 설치한다고 VPN 연결의 압축이 활성화되는 것은 아닙니다. `libcmocka-dev`는 단위 테스트, `python3-docutils`는 문서 생성에 사용합니다. 선택 기능의 추가 요구 사항은 [`configure.ac`](https://github.com/OpenVPN/openvpn/blob/v2.7.7/configure.ac)에서 확인할 수 있습니다.

### 2. GitHub에서 소스 내려받기

`openvpn-2.7.7` 디렉토리가 아직 없는 작업 위치에서 실행합니다.

```bash
git clone --depth 1 --branch v2.7.7 \
  https://github.com/OpenVPN/openvpn.git openvpn-2.7.7
cd openvpn-2.7.7
git describe --tags --exact-match
git rev-parse HEAD
```

태그를 체크아웃하면 detached HEAD 안내가 나올 수 있으며, 정상적인 상태입니다. 빌드 기록에 커밋 ID도 남겨 두세요. 태그 지정은 사용할 버전을 선택하는 과정이며, 그 자체로 서명 검증을 완료했다는 뜻은 아닙니다.

### 3. 빌드 파일 생성·환경 설정·컴파일·검사

Git 소스에서는 [`INSTALL`](https://github.com/OpenVPN/openvpn/blob/v2.7.7/INSTALL)에 안내된 Autotools 생성 단계가 필요합니다. 일반 사용자 권한으로 실행합니다. `&&`로 연결했으므로 한 단계가 실패하면 다음 단계로 넘어가지 않습니다.

```bash
autoreconf -ivf &&
./configure --prefix=/usr/local --with-crypto-library=openssl &&
make -j"$(nproc)" &&
make check
```

설치 경로는 `/usr/local` 아래로 지정했습니다. 테스트가 실패하면 원인을 확인한 뒤 다음 단계로 진행하세요. `make check`가 성공했다고 실제 클라이언트와 서버 사이의 VPN 통신까지 검증된 것은 아닙니다.

### 4. 설치하고 정확한 실행 파일 확인

앞의 과정이 성공하면 관리자 권한으로 설치합니다.

```bash
sudo make install
/usr/local/sbin/openvpn --version
```

출력에서 `2.7.7` 버전을 확인합니다. 패키지로 설치한 다른 실행 파일이 존재할 수도 있으므로, 명령 이름만 믿지 말고 경로를 함께 확인하세요.

```bash
type -a openvpn
/usr/local/sbin/openvpn --version
```

이 방식으로 설치한 파일은 APT가 관리하지 않습니다. 유지보수를 위해 소스 디렉토리와 빌드 옵션을 보관하고, 이후 OpenVPN 업데이트도 별도로 적용해야 합니다.

### 자주 막히는 지점

| 증상 | 확인할 내용 |
| --- | --- |
| `autoreconf: command not found` | 1단계의 Autotools 관련 패키지를 설치합니다. |
| `configure` 파일이 없음 | 저장소 최상위에서 `autoreconf -ivf`를 실행합니다. |
| 라이브러리나 헤더를 찾지 못함 | 첫 오류와 `config.log`를 읽고 해당 개발 패키지를 확인합니다. |
| 예상과 다른 버전이 나옴 | `/usr/local/sbin/openvpn`을 직접 실행합니다. |

### 설치 후 남은 작업

인증서·키, 클라이언트와 서버 설정, 라우팅, 방화벽, systemd 서비스 설정은 별도 작업입니다. 이 글의 명령은 서비스를 시작하거나 네트워크 경로를 변경하지 않습니다. 또한 OpenVPN을 빌드한다고 Linux DCO 커널 모듈까지 설치되는 것은 아니며, DCO 사용 가능 여부는 실행 중인 커널과 환경에 달려 있습니다.
