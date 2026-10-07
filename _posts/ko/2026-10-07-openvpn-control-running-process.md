---
title: 실행 중인 OpenVPN 제어하기 — 재시작, 상태 확인, 특정 클라이언트 차단
lang: ko-KR
permalink: /ko/openvpn-control-running-process
author: ramen
date: 2026-10-07 00:01:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, management, signals, certificates]
---

### 연결한 다음에는 운영 방법을 알아야 한다

[첫 연결 확인](../openvpn-start-and-test-connectivity/) 다음 단계다. 공식 본문과 그 안의 매뉴얼·Management Interface·인증서 폐기·Windows GUI 링크를 함께 확인했다. Ubuntu 24.04에서 소스 빌드 후 `make install`한 구성을 기준으로 설명한다. 명령은 운영 절차 예시이며 실제 VPN에서 실행한 시험 기록은 아니다.

핵심은 **조회, 재시작, 개별 연결 종료, 인증서 폐기를 구분하는 것**이다. 현재 VPN을 통해 서버에 접속 중이라면 재시작으로 관리 연결도 끊길 수 있으므로 콘솔 등 별도 접속 경로를 준비한다.

### 1. 시그널마다 영향이 다르다

| 시그널 | 동작 | 설정 파일 다시 읽기 |
|---|---|---|
| `SIGUSR2` | 현재 통계를 로그 출력 경로로 보냄 | 아니요 |
| `SIGUSR1` | 조건부 재시작; `persist-tun`, `persist-key` 등에 따라 자원을 유지 | 아니요 |
| `SIGHUP` | 연결과 터널을 다시 열고 설정을 다시 읽음 | 예 |
| `SIGTERM`, `SIGINT` | 정상 종료 | 해당 없음 |

`SIGUSR1`도 무중단 명령은 아니다. 서버 전체 재시작은 여러 클라이언트에 영향을 준다. `persist-tun`은 장치 유지 옵션이지 세션 무중단 보장이 아니다. 권한을 낮춘 프로세스는 `SIGHUP` 때 파일 재접근이나 장치 재생성에 실패할 수 있으므로, 이때는 실제 서비스 관리자나 권한 있는 실행 경로로 완전히 재시작한다. [시그널 설명](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/signals.rst)

### 2. PID와 상태 파일 준비

[이전 서버 설정](../openvpn-server-client-configuration/)처럼 아직 `user`·`group`으로 권한을 낮추지 않은 실습 구성을 가정한다. 기존 서버를 실행한 터미널에서 `Ctrl+C`로 종료한 뒤 준비한다. 서비스가 관리하는 서버라면 해당 서비스를 통해 변경하며 중복 실행하지 않는다.

```bash
sudo install -d -o root -g root -m 700 /run/openvpn-admin
sudoedit /etc/openvpn/server/server.conf
```

기존 설정은 유지하고 다음 항목을 추가한다. 이미 같은 옵션이 있다면 중복 추가하지 않고 수정한다.

```conf
writepid /run/openvpn-admin/server.pid
status /run/openvpn-admin/server.status 60
status-version 3
management /run/openvpn-admin/management.sock unix
management-client-user root
management-client-group root
```

`/run`의 파일은 재부팅 뒤 사라진다. 재부팅 후 디렉토리를 다시 만들고, 서비스로 전환할 때는 런타임 디렉토리 생성도 서비스에 맡긴다. 위 디렉토리는 root 전용이며, 향후 권한을 낮춘다면 파일·소켓 접근 권한을 함께 재설계한다.

서버를 다시 실행한다.

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

다른 서버 터미널에서 PID와 실행 인자를 확인한다.

```bash
vpn_pid=$(sudo cat /run/openvpn-admin/server.pid)
if [[ "$vpn_pid" =~ ^[1-9][0-9]*$ ]]; then
  sudo ps -p "$vpn_pid" -o pid,user,args
fi
```

출력이 실제 OpenVPN 서버와 올바른 설정 파일을 가리키는지 확인한 뒤 아래 명령 중 필요한 것만 실행한다. PID 파일은 오래되었거나 번호가 재사용될 수 있으므로 매번 확인한다.

| 목적 | 서버 셸에서 실행할 명령 |
|---|---|
| 통계 출력 | `sudo kill -USR2 "$vpn_pid"` |
| 조건부 재시작 | `sudo kill -USR1 "$vpn_pid"` |
| 설정 재읽기 | `sudo kill -HUP "$vpn_pid"` |
| 정상 종료 | `sudo kill -TERM "$vpn_pid"` |

셸의 `kill`은 시그널 전송 명령이다. 항상 강제 종료를 의미하지 않는다. 일반 운영에서 `kill -9`를 기본 종료 수단으로 사용하지 않는다. `make install`만으로 특정 systemd 서비스 이름이 생겼다고 가정하지도 않는다.

### 3. 상태 파일과 로그 구분

```bash
sudo cat /run/openvpn-admin/server.status
```

설정한 상태 파일은 60초 간격으로 갱신되므로 즉시 상황과 차이가 날 수 있다. `status-version 3`은 탭으로 구분된 형식이다. 접속자와 주소·전송량을 살펴볼 때 사용하며 이벤트 로그와는 다르다. `SIGUSR2` 출력은 이 글의 전경 실행에서는 터미널에서 확인한다. `log`, `log-append`, 데몬 실행 등을 사용하면 출력 위치가 달라진다. [매뉴얼](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 4. Management Interface는 관리자용 제어 통로

관리 프로토콜 자체에는 암호화 계층이 없다. 원문의 `management localhost 7505`는 로컬 사용자에게도 제어 권한을 노출할 수 있다. 이 글은 TCP 포트를 열지 않고 root 전용 디렉토리의 Unix 소켓과 사용자·그룹 제한을 함께 쓴다. Unix 소켓이라는 이유만으로 접근이 자동 제한되는 것은 아니다. TCP를 선택한다면 루프백 바인딩과 암호 파일을 사용하고 공인망에 노출하지 않는다. [관리 옵션](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/management-options.rst)

서버의 다른 터미널에서 연결한다.

```bash
sudo apt install socat
sudo socat STDIO UNIX-CONNECT:/run/openvpn-admin/management.sock
```

이제 아래는 **Linux 셸 명령이 아니라 관리 인터페이스 안에 입력하는 명령**이다.

```text
help
status 3
state
log 20
quit
```

`status 3`은 현재 연결 목록, `state`는 프로세스 상태, `log 20`은 캐시된 최근 로그를 확인한다. `quit`은 여기서 설정한 일반 관리 세션만 닫고 VPN은 계속 실행한다. 전체 서버를 종료하는 `signal SIGTERM`과 구분한다. 사용 가능한 명령은 실제 버전의 `help`로 확인한다. [관리 명령 문서](https://openvpn.net/community-docs/management-interface.html)

### 5. 서버 재시작 없이 반영되는 파일

이미 해당 지시어가 활성화되어 있다는 전제에서 CCD와 CRL 파일을 갱신할 수 있다. **지시어를 처음 추가하는 작업 자체는 서버 설정 반영이 필요하다.**

CCD를 사용하려면 실제 디렉토리를 준비하고 서버 설정에 다음을 넣는다.

```conf
client-config-dir /etc/openvpn/server/ccd
```

인증서 Common Name이 `client2`라면 보통 `ccd/client2` 파일을 읽는다. 허용된 클라이언트별 옵션만 넣는다. 변경은 다음 접속부터 적용되며 기존 세션의 설정은 자동 변경되지 않는다. 즉시 적용하려면 해당 세션을 종료하고 클라이언트가 다시 접속하게 한다. `kill` 자체가 클라이언트 프로그램의 재접속까지 보장하는 것은 아니다. [CCD 설명](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

CRL은 새 연결과 TLS 재협상 시 확인된다. 갱신 직후 모든 기존 세션이 즉시 끊기는 것은 아니므로 긴급 차단에서는 재협상까지 기다리지 않는다. [폐기 문서](https://openvpn.net/community-docs/revoking-certificates.html)

### 6. client2를 실제로 차단해야 할 때

다음은 실습용 조회가 아니라 **인증서를 폐기하는 작업**이다. 대상 확인 후 CA의 기존 Easy-RSA 3 작업 디렉토리에서 실행한다. 원문의 Easy-RSA 2 명령 `revoke-full` 대신 앞 글의 3 방식으로 정리했다.

```bash
./easyrsa revoke client2
./easyrsa gen-crl
openssl crl -in pki/crl.pem -noout -lastupdate -nextupdate
```

생성한 `pki/crl.pem`만 서버에 안전하게 전달한다. CA 개인키는 전달하지 않는다. 서버에서 전달받은 `crl.pem`이 있는 디렉토리에서 실행한다. 동일한 디렉토리 안의 임시 파일을 완성한 뒤 교체해, 읽는 도중 불완전한 파일이 보이지 않게 한다.

```bash
sudo install -m 644 crl.pem /etc/openvpn/server/crl.pem.new
sudo mv /etc/openvpn/server/crl.pem.new /etc/openvpn/server/crl.pem
```

서버에는 다음 설정이 이미 적용되어 있어야 한다.

```conf
crl-verify /etc/openvpn/server/crl.pem
```

CRL의 발급자·유효기간과 실행 사용자의 읽기 권한, 상위 디렉토리 통과 권한을 확인한다. 새 폐기 때마다 갱신하고 만료 전에도 재발급·배포한다.

이어서 관리 인터페이스에서 실제 Common Name을 확인하고 대상만 종료한다.

```text
status 3
kill client2
status 3
```

`kill client2`는 같은 이름의 인스턴스들을 종료할 수 있다. 한 세션만 선택할 때는 `status 3`에서 실제 Client ID를 확인하고 `client-kill CID`를 사용한다. 여기서 CID는 문자 그대로가 아니라 실제 숫자로 바꾼다. **연결 종료만 하면 다시 접속할 수 있으므로 CRL 배포와 세션 종료를 함께 수행한다.** 이후 대상이 목록에서 사라졌는지, 재접속이 인증서 폐기로 거부되는지 로그와 통제된 재접속 시험으로 확인한다.

### 7. Windows 참조 링크는 이렇게 구분

OpenVPN GUI에서는 프로필 단위 연결·해제·재연결과 상태 창을 제공한다. 예를 들어 실행 중인 GUI에 `openvpn-gui.exe --command disconnect office`로 `office` 프로필 해제를 요청할 수 있다. 이 명령은 Linux 시그널이나 별도 Windows 서비스 제어 명령이 아니다. 서비스로 실행하는 구성은 Windows 서비스 관리 또는 이미 설정한 관리 인터페이스를 사용한다. 원문의 F1~F4 설명은 Windows 콘솔 실행 맥락이며 모든 GUI의 공통 단축키로 보지 않는다. [OpenVPN GUI 문서](https://community.openvpn.net/Pages/OpenVPN-GUI-New)

상태 파일과 로그에는 접속자 이름·주소가 들어갈 수 있다. 공개 저장소에는 예제만 남기고 실제 운영 자료·개인키·암호는 저장하지 않는다.

### 참고 자료

- [Controlling a Running OpenVPN Process](https://openvpn.net/community-docs/controlling-a-running-openvpn-process.html)
- [OpenVPN 2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [OpenVPN 2.7.7 signals](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/signals.rst)
- [Management Interface](https://openvpn.net/community-docs/management-interface.html)
- [OpenVPN 2.7.7 management options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/management-options.rst)
- [Revoking Certificates](https://openvpn.net/community-docs/revoking-certificates.html)
- [OpenVPN GUI](https://community.openvpn.net/Pages/OpenVPN-GUI-New)
