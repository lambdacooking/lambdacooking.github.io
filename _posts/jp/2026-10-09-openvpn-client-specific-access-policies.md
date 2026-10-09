---
title: OpenVPNのクライアント別アクセス制御 — CCD固定IPとファイアウォール
lang: ja-JP
permalink: /jp/openvpn-client-specific-access-policies
author: ramen
date: 2026-10-09 00:02:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, firewall, access-control, ccd]
---

### VPNへの接続と資源へのアクセスは別

原文は利用者の区分をVPNアドレスに対応させ、ファイアウォールで宛先を制限する。この記事では既存のUbuntu 24.04・ソースインストール構成に合わせて説明する。実際のVPNへ適用して試験した記録ではない。

**CCDはクライアント設定を選び、ファイアウォールは通信を制限する。** pushする経路を消すだけではアクセス制御にならない。クライアント自身が経路を追加できるためだ。[公式原文](https://openvpn.net/community-docs/configuring-client-specific-rules-and-access-policies.html)

### 1. 今回の方針

[LAN接続の記事](../openvpn-connect-server-client-lans/)の`10.66.0.0/24`を維持するが、今回は**各クライアントが単一端末のリモートアクセス構成**に限定する。client2がLAN全体を中継する構成とそのまま組み合わせない。

| 証明書のCommon Name | VPN固定IP | 許可する宛先 |
|---|---|---|
| sysadmin1 | `10.8.0.10` | サーバーLAN全体 |
| employee1 | `10.8.0.20` | `10.66.0.20`のTCP 445・465・587・993 |
| contractor1 | `10.8.0.30` | `10.66.0.30`のTCP 443 |
| contractor2 | `10.8.0.31` | 同じHTTPSサーバー |
| 上記全員 | — | DNS `10.66.0.4`、`10.66.0.5`のUDP・TCP 53 |

宛先とポートは実際のサービスに合わせる。原文と異なり社員も固定IPにして、動的プールとの衝突を避け、明示的に登録した端末だけを接続させる。有効で固有の証明書を使い、失効済みのものは再利用しない。

### 2. topology subnetに合わせたCCD

設定をバックアップし、以下で**該当オプションを置き換える**。証明書、鍵、CRL、UDPポート、状態・管理設定は維持する。既存の`dev`、`server`、`ifconfig-pool`を重複させない。

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

`nopool`で自動プールを作らず、`ccd-exclusive`で対応するCCDのない接続を拒否する。これ自体がLANアクセスを許可するわけではない。ファイルを準備する。

```bash
sudo install -d -m 750 /etc/openvpn/server/ccd
sudoedit /etc/openvpn/server/ccd/sysadmin1
sudoedit /etc/openvpn/server/ccd/employee1
sudoedit /etc/openvpn/server/ccd/contractor1
sudoedit /etc/openvpn/server/ccd/contractor2
```

各ファイルに表の1行を保存する。

| サーバーのCCDファイル名 | 内容 |
|---|---|
| sysadmin1 | `ifconfig-push 10.8.0.10 255.255.255.0` |
| employee1 | `ifconfig-push 10.8.0.20 255.255.255.0` |
| contractor1 | `ifconfig-push 10.8.0.30 255.255.255.0` |
| contractor2 | `ifconfig-push 10.8.0.31 255.255.255.0` |

実際の証明書CNと名前を一致させる。権限を落としている場合は、読み取りと親ディレクトリの通過権限を確認する。`topology subnet`の第2引数はネットマスクだ。原文の`10.8.1.1 10.8.1.2`のような`/30`端点ペアをそのまま使わない。`ifconfig-pool-persist`も固定割り当てを保証する代替ではない。[サーバーオプション](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)

`duplicate-cn`と`client-to-client`は使わない。今回はDCOを無効にし、内部のクライアント転送がカーネルのフィルターを迂回しない構成に単純化する。`max-routes-per-client 1`は単一端末で追加アドレスの学習を制限する補助策だ。LAN中継クライアントに無条件で適用しない。IP規則で証明書検証を代替せず、偽装した送信元アドレスの拒否も運用検証に含める。

### 3. 既存の経路と広い許可を確認する

サーバーLANのゲートウェイには、`10.8.0.0/24`をOpenVPNサーバーのLANアドレスへ返す経路が必要だ。IP転送とDNSの問い合わせ許可も維持する。

サーバーで現在の規則を確認する。

```bash
sudo ufw status verbose
sudo ufw status numbered
sudo ufw show raw
```

**すでにUFWが有効で、このサーバーのファイアウォールを管理している**ことを前提とする。`tun0`はVPN、`enp1s0`はLANの例なので実際の名前へ置き換える。既存の`tun0`関連ユーザー規則を整理し、以下のブロックを一度だけ配置する。前の記事の広いLAN許可を新しい制限より前に残すと制限が効かない。UFWのbefore規則や他のnftables/iptables管理も確認する。

遠隔操作では別のSSH・コンソール経路と復旧手段を用意する。この記事の公開作業でVPNサーバーにこれらのコマンドを実行したわけではない。

### 4. 許可一覧の後に明示的な拒否

先にVPNからの転送を拒否し、その前に必要な許可を挿入する。途中では通信が一時的に止まる可能性がある。

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

`sudo ufw status numbered`で**8つの許可の後にtun0転送拒否**があることを確認する。異なる場合は進めず既存規則や重複を整理する。この拒否は指定外の宛先やカーネルを通るクライアント間転送も制限する。LANからVPNへ開始する新規接続は別の方針で扱う。

標準UFWのestablished/related処理で応答が通る。既存の接続追跡状態は変更後も残る場合があるため、新しい接続で検証する。緊急の権限剥奪では[CRLとセッション終了](../openvpn-control-running-process/)も行う。[UFWの説明](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)

### 5. VPNサーバー自身にはINPUT方針

`ufw route`はサーバーを**通過する**通信用だ。サーバー自身のSSHや管理ポートはINPUTで扱う。この実習ではVPN経由のサーバー自身へのアクセスを拒否する。

```bash
sudo ufw insert 1 deny in on tun0
```

そのため前の記事の`10.8.0.1`へのpingも拒否され得る。外側のUDP 1194許可とは別だ。サーバー自身のサービスが必要なら、送信元・宛先・ポートを限定した例外をこの拒否より前に設計する。

IPv4の例なので、IPv6トンネル、別のVPN、他の経路にも同等の方針を適用するか、使用しない構成にする。UFWのIPv6処理も確認する。

### 6. 許可と拒否の両方を試験する

[プロセス制御の記事](../openvpn-control-running-process/)に従って変更を反映し、各クライアントを再接続する。`SIGUSR1`だけでは設定を再読込しない。先に管理状態でCNと割り当てアドレスを確認する。

各クライアントで例のポートを試す。

```bash
sudo apt install netcat-openbsd
ip -brief address
nc -vz -w 3 10.66.0.20 445
nc -vz -w 3 10.66.0.30 443
nc -vz -w 3 10.66.0.20 22
```


| 試験 | 管理者 | 社員 | 協力会社 |
|---|---|---|---|
| `10.66.0.20:445` | 許可 | 許可 | 拒否 |
| `10.66.0.30:443` | 許可 | 拒否 | 許可 |
| `10.66.0.20:22` | 許可 | 拒否 | 拒否 |

許可の試験は実際のサービスが待ち受けている必要がある。失敗だけでファイアウォールの拒否と判断せず、経路、待受状態、ログも見る。CCDのない有効な試験証明書が拒否されることも確認する。DNSは[DNSの記事](../openvpn-push-dns-options/)に従い直接問い合わせと通常の名前解決を試す。

退職や契約終了で権限を外す場合、アドレス再割り当て前に既存セッションと証明書を整理する。CN・固定IP・規則の対応を一緒に管理し、実際の秘密鍵や運用ログは公開しない。

### 参考資料

- [OpenVPN: Configuring Client-Specific Rules and Access Policies](https://openvpn.net/community-docs/configuring-client-specific-rules-and-access-policies.html)
- [OpenVPN 2.7.7 server options](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)
- [OpenVPN 2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [Ubuntu 24.04: UFW](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)
