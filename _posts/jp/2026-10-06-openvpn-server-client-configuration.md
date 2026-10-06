---
title: Ubuntu 24.04でOpenVPNサーバーとクライアントの設定ファイルを作る
lang: ja-JP
permalink: /jp/openvpn-server-client-configuration
author: ramen
date: 2026-10-06 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, configuration, server, client]
---

### 証明書をVPNの設定に組み込む

[ソースからのビルドとmake install](../openvpn-install-from-github-source/)、[Easy-RSA 3による証明書の作成](../openvpn-ca-certificates-easyrsa3/)に続く手順だ。公式の設定ガイドを参考に、Ubuntu 24.04向けの例をまとめた。実機で接続に成功したという体験記ではないため、以下の接続確認を各自の環境で行う。

### 1. 実行ファイルとサンプルを確認する

前の記事で使用したOpenVPNのソースディレクトリで実行する。

```bash
command -v openvpn
openvpn --version
ls sample/sample-config-files/{server,client}.conf
```

パスとバージョンがソースからインストールしたものか確認する。パスが表示されなければ、インストール先とPATHを確認する。今回は設定を直接記述するため、サンプル全体のコピーは不要だ。`make install`だけでディストリビューションのsystemdサービスも用意されたとは考えず、まずターミナルで起動する。

### 2. サーバーのファイルを準備する

前の記事で作成した`ca.crt`、`server.crt`、`server.key`だけを安全な経路でサーバーへ転送する。サーバー上でこの3ファイルのあるディレクトリに移動して実行する。新規構成を想定しているため、既存ファイルがあれば先にバックアップする。**CAの秘密鍵`ca.key`はサーバーに転送しない。**

```bash
sudo install -d -m 750 /etc/openvpn/server
sudo install -m 644 ca.crt server.crt /etc/openvpn/server/
sudo install -m 600 server.key /etc/openvpn/server/
sudoedit /etc/openvpn/server/server.conf
```

エディターで次の設定を保存する。

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

`10.8.0.0/24`は例だ。[プライベートサブネットの設計](../vpn-private-subnet-planning/)に従い、サーバー側とクライアント側のLANに重複しない範囲を選ぶ。

`dh none`は有限体DHのパラメーターファイルを使わず、現代的な鍵交換を利用する設定だ。前の記事のRSA証明書と併用できる。証明書の鍵の種類と接続時の鍵交換方式は別のものなので、この例では`gen-dh`は不要だ。

### 3. クライアントのファイルを準備する

Ubuntuクライアントに`ca.crt`、`client1.crt`、`client1.key`を転送し、それらがあるディレクトリで実行する。

```bash
sudo install -d -m 750 /etc/openvpn/client
sudo install -m 644 ca.crt client1.crt /etc/openvpn/client/
sudo install -m 600 client1.key /etc/openvpn/client/
sudoedit /etc/openvpn/client/client.conf
```

`vpn.example.com`を実際のサーバーのドメインまたはグローバルIPアドレスに置き換えて保存する。

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

端末ごとに固有の証明書と秘密鍵を使用する。`client2`ではファイル名と設定内のパスも変更する。`remote-cert-tls server`は証明書がサーバー用かを確認し、サーバー側の`remote-cert-tls client`はクライアント用途を確認する。

### 4. ファイアウォールと接続確認

UDP 1194がサーバーまで届く必要がある。すでにUFWを使用しているサーバーでは、次のように許可して状態を確認する。

```bash
sudo ufw allow 1194/udp
sudo ufw status
```

クラウドのファイアウォールも別途確認する。ルーターの配下ならUDP 1194をサーバーのLANアドレスへポート転送する。`remote`には外部から到達できるアドレスを指定する。

サーバーで起動する。

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/server/server.conf
```

続いてクライアントで起動する。前の記事のように秘密鍵を暗号化した場合は、プロンプトでパスフレーズを入力する。

```bash
sudo "$(command -v openvpn)" --config /etc/openvpn/client/client.conf
```

接続ログの`Initialization Sequence Completed`を確認し、クライアントの別のターミナルで試す。

```bash
ping -c 4 10.8.0.1
ip address show
ip route show
```

pingが失敗した場合は、接続ログ、トンネルのアドレス、ICMPの許可設定を合わせて確認する。終了はそれぞれのターミナルで`Ctrl+C`を押す。サーバーの初期化完了だけではクライアントの接続成功を意味しない。

### 5. 基本接続の次に行うこと

この設定はトンネル接続を確認する出発点だ。サーバーの背後にあるLANへのアクセスや、インターネット通信全体の転送には、経路、IPフォワーディング、ファイアウォール、必要に応じてNATの設定も必要になる。

前の記事でCRLを作成した場合はサーバーに配置し、次を追加する。

```conf
crl-verify /etc/openvpn/server/crl.pem
```

CRLの存在、読み取り権限、有効期限を確認する。証明書を失効させるたびに更新・配布し、接続中のセッションは別途終了する。運用時には`tls-crypt`などの制御チャネル保護、サービス管理、権限の縮小も整える。

古い説明にある`comp-lzo`や`fragment`を新規構成へそのまま追加しない。特に圧縮は有効にしない。`group nobody`もUbuntuへそのまま適用せず、`getent group nogroup`などで実際のアカウントを確認する。この例にはまだ権限を落とす設定を含めていない。

実際の秘密鍵、パスワード、PKIの資料はブログのリポジトリに保存しない。

### 参考資料

- [Creating Configuration Files for Server and Clients](https://openvpn.net/community-docs/creating-configuration-files-for-server-and-clients.html)
- [OpenVPN 2.7.7 server.conf](https://github.com/OpenVPN/openvpn/blob/v2.7.7/sample/sample-config-files/server.conf)
- [OpenVPN 2.7.7 TLS options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/tls-options.rst)
- [OpenVPN 2.6 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html)
