---
title: Ubuntu 24.04でOpenVPNを起動し、最初の接続を確認する
lang: ja-JP
permalink: /jp/openvpn-start-and-test-connectivity
author: ramen
date: 2026-10-07 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, troubleshooting, connectivity]
---

### 今回確認すること

[前の記事](../openvpn-server-client-configuration/)で作った設定を使い、サーバーとクライアントを起動してVPN内の通信を確認する。**サーバーの起動、クライアントの接続、実際の通信はそれぞれ確認する必要がある。**

公式ガイドをUbuntu 24.04向けに整理した手順であり、実機で接続に成功したという体験記ではない。コマンドは各自のサーバーとクライアントで実行する。原文の古いWindows XP向けの対処やOpenVPN 2.0のログは、現在の環境の基準として扱わない。

### 1. 起動前の準備

[GitHubのソースからビルドしてmake install](../openvpn-install-from-github-source/)を実行済みで、前の記事の`UDP 1194`、`dev tun`、`10.8.0.0/24`を使用する想定だ。ポートやサブネットを変更した場合は、以下のコマンドも合わせる。

両方の端末でインストール先とバージョンを確認する。

```bash
command -v openvpn
openvpn --version
```

ソースからインストールした実行ファイルか確認する。パスが出なければPATHとインストール先を調べる。CAや証明書を作り直す必要はない。

外部から接続するには、サーバーとクラウドのファイアウォールでUDP 1194を許可する。ルーター配下なら同じポートをサーバーのLANアドレスへ転送する。クライアントの`remote`には実際に到達できる接続先を指定する。

### 2. サーバーを先に起動する

サーバーのターミナルで実行し、ログを見える状態にしておく。

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

`Initialization Sequence Completed`はサーバーの初期化完了を示す。クライアントの接続成功までは意味しない。別のサーバーターミナルでポートも確認する。

```bash
sudo ss -lunp 'sport = :1194'
```

このコマンドはローカルのUDPソケットとプロセスを表示する。OpenVPNが意図したアドレスの1194番を使用しているか確認する。ソケットが見えるだけでは外部から到達可能とは判断できない。[ssの説明](https://manpages.ubuntu.com/manpages/noble/man8/ss.8.html)

### 3. クライアントを起動する

クライアントのターミナルで実行する。

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/client/client.conf
```

秘密鍵が暗号化されていればパスフレーズを入力する。クライアントでも初期化完了を確認し、その後エラーや再接続が繰り返されていないかを見る。最初はサービスよりターミナルで起動した方が問題を追いやすい。同じ設定をサービスとターミナルで二重に起動しない。

### 4. VPNのアドレスへ通信する

クライアントの別のターミナルで実行する。

```bash
ip -brief address
ip route get 10.8.0.1
ping -c 4 10.8.0.1
```

`ip -brief address`で割り当てられたアドレスを、`ip route get`で宛先に対して実際に選ばれる経路を確認する。`10.8.0.1`への経路がVPNインターフェースを使っているかを見る。名前は環境によって変わるため、`tun0`とは限らない。[ip-routeの説明](https://manpages.ubuntu.com/manpages/noble/man8/ip-route.8.html)

前の記事の設定では`10.8.0.1`がサーバーのVPNアドレスだ。VPN経路でpingの応答が返れば、そのアドレスまでトンネルを通じて往復できている。インターネット通信全体の転送やサーバーの背後のLANへのアクセスまで確認したわけではない。

### 5. 失敗した場合の確認順序

| 症状 | 最初に確認すること |
|---|---|
| サーバーが起動直後に終了する | ログの最初のエラー、設定パス、証明書・鍵の読み取り権限、ポートの重複 |
| TLSネゴシエーションがタイムアウトする | `remote`のアドレス・ポート・プロトコル、サーバーの起動状態、ファイアウォール、ポート転送、戻りの経路 |
| 証明書の検証に失敗する | 両側の信頼するCA、有効期限、端末の時刻、証明書の用途 |
| クライアントの初期化後にpingが失敗する | VPNアドレスと経路、サブネットの重複、両側のトンネル通信・ICMPのフィルタリング |

TLSタイムアウトだけで原因を断定しない。両側のログを比較して、どこまで処理が進んだかを調べる。`tls-auth`や`tls-crypt`を追加した場合は、設定と鍵の一致も確認する。

UFWを使っている場合は両側の現在のポリシーを確認する。

```bash
sudo ufw status verbose
```

ファイアウォール全体を無効にするのではなく、必要なトンネル通信やICMPを遮断している規則を調整する。pingが返らないだけではVPN接続自体の失敗とは断定できない。

### 6. 試験の終了と次の段階

それぞれのOpenVPN実行ターミナルで`Ctrl+C`を押して終了する。基本接続を確認した後で、自動起動、アクセス制御、LANへのルーティングを別途設定する。サーバー自身のVPNアドレスへのping試験には、インターネット共有用NATや転送用IPフォワーディングを先に有効化する必要はない。

ログを共有するときは公開したくないアドレスや証明書の識別情報を伏せる。秘密鍵、パスワード、実際のPKI資料はブログのリポジトリに保存しない。

### 参考資料

- [OpenVPN: Starting Up the VPN and Testing for Initial Connectivity](https://openvpn.net/community-docs/starting-up-the-vpn-and-testing-for-initial-connectivity.html)
- [Ubuntu 24.04: ss](https://manpages.ubuntu.com/manpages/noble/man8/ss.8.html)
- [Ubuntu 24.04: ip-route](https://manpages.ubuntu.com/manpages/noble/man8/ip-route.8.html)
