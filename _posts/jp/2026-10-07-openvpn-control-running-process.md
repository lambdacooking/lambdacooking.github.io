---
title: 実行中のOpenVPNを制御する — 再起動・状態確認・クライアントの失効
lang: ja-JP
permalink: /jp/openvpn-control-running-process
author: ramen
date: 2026-10-07 00:01:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, management, signals, certificates]
---

### 接続後の運用を理解する

[最初の接続確認](../openvpn-start-and-test-connectivity/)に続く内容だ。公式本文に加え、リンク先のマニュアル、Management Interface、証明書失効、Windows GUIの説明も確認した。Ubuntu 24.04でソースからビルドし、`make install`した構成を想定する。コマンドは運用手順の例であり、実際のVPNで試験した記録ではない。

大切なのは**参照、再起動、個別切断、証明書失効の区別**だ。管理接続もこのVPNを通る場合、再起動前にコンソールなど別の接続手段を用意する。

### 1. シグナルによって影響が異なる

| シグナル | 動作 | 設定を再読込するか |
|---|---|---|
| `SIGUSR2` | 現在の統計をログ出力先へ送る | しない |
| `SIGUSR1` | 条件付き再起動。`persist-tun`や`persist-key`などに応じて資源を維持 | しない |
| `SIGHUP` | 接続とトンネルを開き直し、設定を再読込 | する |
| `SIGTERM`、`SIGINT` | 正常終了 | 対象外 |

`SIGUSR1`も無停止の操作ではない。サーバー全体の再起動は複数のクライアントに影響する。トンネルデバイスの維持はセッション継続の保証ではない。権限を落とした後の`SIGHUP`では、ファイルの再読込やデバイスの再作成に失敗する場合がある。その場合は実際のサービス管理機構や権限のある起動方法で完全に再起動する。[シグナルの説明](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/signals.rst)

### 2. PIDと状態ファイルを準備する

[前のサーバー設定](../openvpn-server-client-configuration/)と同じく、まだ`user`・`group`で権限を落としていない実習構成を想定する。起動したターミナルで`Ctrl+C`を押して停止してから準備する。サービス管理下ならそのサービスを使い、二重起動しない。

```bash
sudo install -d -o root -g root -m 700 /run/openvpn-admin
sudoedit /etc/openvpn/server/server.conf
```

既存の設定を維持して次を追加する。同じ項目があれば重複させず修正する。

```conf
writepid /run/openvpn-admin/server.pid
status /run/openvpn-admin/server.status 60
status-version 3
management /run/openvpn-admin/management.sock unix
management-client-user root
management-client-group root
```

`/run`は再起動で消えるため、ディレクトリを作り直す。サービス化するときはランタイムディレクトリの作成もサービス側で管理する。この例はroot専用だ。後で権限を落とすならファイルとソケットの権限も見直す。

サーバーを再度起動する。

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

別のサーバーターミナルでPIDと起動引数を確認する。

```bash
vpn_pid=$(sudo cat /run/openvpn-admin/server.pid)
if [[ "$vpn_pid" =~ ^[1-9][0-9]*$ ]]; then
  sudo ps -p "$vpn_pid" -o pid,user,args
fi
```

意図したOpenVPNサーバーと設定ファイルか確認し、次のうち必要な操作だけを実行する。古いPIDファイルやPIDの再利用があり得るため、毎回確認する。

| 目的 | サーバーのシェルで実行するコマンド |
|---|---|
| 統計を出力 | `sudo kill -USR2 "$vpn_pid"` |
| 条件付き再起動 | `sudo kill -USR1 "$vpn_pid"` |
| 設定の再読込 | `sudo kill -HUP "$vpn_pid"` |
| 正常終了 | `sudo kill -TERM "$vpn_pid"` |

シェルの`kill`はシグナルを送るコマンドで、常に強制終了を意味するわけではない。通常の停止に`kill -9`を使わない。`make install`で特定のsystemdユニットが作られたとも仮定しない。

### 3. 状態ファイルとログを区別する

```bash
sudo cat /run/openvpn-admin/server.status
```

この状態ファイルは60秒間隔の更新なので、現在の状況とずれる場合がある。形式3はタブ区切りだ。接続者、アドレス、転送量の確認用で、イベントログとは異なる。この前景実行では`SIGUSR2`の統計をターミナルで確認する。`log`、`log-append`、デーモン化などによって出力先は変わる。[マニュアル](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 4. Management Interfaceは管理者用の制御経路

管理プロトコル自体には暗号化層がない。原文のパスワードなしの`management localhost 7505`は、ローカルユーザーにも制御権限を公開する可能性がある。ここではTCPポートを開かず、root専用ディレクトリ内のUnixソケットとユーザー・グループ制限を併用する。Unixソケットだけで自動的にアクセスが制限されるわけではない。TCPを選ぶならループバックとパスワードファイルを使用し、公開ネットワークへ露出させない。[管理オプション](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/management-options.rst)

別のサーバーターミナルで接続する。

```bash
sudo apt install socat
sudo socat STDIO UNIX-CONNECT:/run/openvpn-admin/management.sock
```

以下は**Linuxシェルではなく管理インターフェース内で入力するコマンド**だ。

```text
help
status 3
state
log 20
quit
```

`status 3`は現在の接続一覧、`state`はプロセスの状態、`log 20`はキャッシュされた直近のログを表示する。この通常の管理設定では`quit`は管理セッションだけを閉じ、VPNは動き続ける。プロセス全体を停止する`signal SIGTERM`とは異なる。利用可能なコマンドは実行中のバージョンの`help`で確認する。[管理コマンドの説明](https://openvpn.net/community-docs/management-interface.html)

### 5. サーバー再起動なしで更新できるファイル

対応するディレクティブがすでに有効なら、CCDとCRLのファイルを更新できる。**ディレクティブを初めて追加する場合はサーバー設定の反映が必要だ。**

CCDを使う場合は実際のディレクトリを準備し、次を設定する。

```conf
client-config-dir /etc/openvpn/server/ccd
```

証明書のCommon Nameが`client2`なら、通常は`ccd/client2`を読む。対応するクライアント別オプションだけを記述する。変更は次回接続時からで、既存セッションへ自動反映されない。すぐ反映する場合は対象を切断してクライアントを再接続させる。`kill`自体がクライアントプログラムの再接続を保証するわけではない。[CCDの説明](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

CRLは新規接続とTLS再ネゴシエーション時に確認される。更新だけで既存接続がすぐすべて切れるわけではない。緊急の遮断では再ネゴシエーションを待たない。[失効の説明](https://openvpn.net/community-docs/revoking-certificates.html)

### 6. client2を実際に遮断するとき

これは参照だけの実習ではなく、**証明書を失効させる操作**だ。対象を確認し、CAの既存Easy-RSA 3作業ディレクトリで実行する。リンク先の古いEasy-RSA 2の`revoke-full`を、前の記事の3の手順に置き換えている。

```bash
./easyrsa revoke client2
./easyrsa gen-crl
openssl crl -in pki/crl.pem -noout -lastupdate -nextupdate
```

生成した`pki/crl.pem`だけを安全にサーバーへ転送し、CA秘密鍵は渡さない。サーバー上の転送済み`crl.pem`があるディレクトリで実行する。同じディレクトリ内に一時ファイルを完成させてから置き換え、途中の不完全なファイルが読まれないようにする。

```bash
sudo install -m 644 crl.pem /etc/openvpn/server/crl.pem.new
sudo mv /etc/openvpn/server/crl.pem.new /etc/openvpn/server/crl.pem
```

サーバーでは次がすでに有効になっている必要がある。

```conf
crl-verify /etc/openvpn/server/crl.pem
```

発行者、有効期限、実行ユーザーの読み取り権限、親ディレクトリの通過権限を確認する。失効のたびに更新し、期限前にも再生成・配布する。

続いて管理インターフェースで実際のCommon Nameを確認し、対象を切断する。

```text
status 3
kill client2
status 3
```

`kill client2`は同じ名前の複数インスタンスを切断する場合がある。1セッションだけを選ぶには`status 3`の実際のClient IDを使い、`client-kill CID`のCIDを数値に置き換える。**切断だけなら再接続できるため、CRLの配布とセッション終了を両方行う。** 一覧から消えたことを確認し、管理下での再接続試験とログで証明書失効による拒否を確認する。

### 7. Windowsの参照リンクの読み方

OpenVPN GUIにはプロファイルの接続・切断・再接続と状態表示がある。例えば`openvpn-gui.exe --command disconnect office`は実行中のGUIに`office`プロファイルの切断を要求する。Linuxのシグナルでも、独立したWindowsサービスの制御コマンドでもない。サービス構成ではWindowsのサービス管理か設定済みの管理インターフェースを使う。原文のF1〜F4はWindowsコンソール実行の説明で、すべてのGUI共通のショートカットではない。[OpenVPN GUIの説明](https://community.openvpn.net/Pages/OpenVPN-GUI-New)

状態ファイルやログには接続者名やアドレスが含まれる。公開リポジトリには例だけを置き、実運用データ、秘密鍵、パスワードは保存しない。

### 参考資料

- [Controlling a Running OpenVPN Process](https://openvpn.net/community-docs/controlling-a-running-openvpn-process.html)
- [OpenVPN 2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [OpenVPN 2.7.7 signals](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/signals.rst)
- [Management Interface](https://openvpn.net/community-docs/management-interface.html)
- [OpenVPN 2.7.7 management options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/management-options.rst)
- [Revoking Certificates](https://openvpn.net/community-docs/revoking-certificates.html)
- [OpenVPN GUI](https://community.openvpn.net/Pages/OpenVPN-GUI-New)
