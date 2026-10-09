---
title: OpenVPNでDNS設定を配布する — Ubuntu 24.04とOpenVPN 2.7
lang: ja-JP
permalink: /jp/openvpn-push-dns-options
author: ramen
date: 2026-10-09 00:01:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, dns, dhcp, systemd-resolved]
---

### IP接続の次は名前解決

[LAN接続の記事](../openvpn-connect-server-client-lans/)に続き、内部の名前をDNSで解決する。**DNSアドレスの通知、クライアントOSへの適用、DNSサーバーへの通信は別々の段階だ。**

公式ガイドをUbuntu 24.04と、前の記事でソースから導入したOpenVPN 2.7.7に合わせて整理した。以下は構成例であり、実際のVPNでの試験結果ではない。

### 1. DNSサーバーは別途必要

サーバーLANの`10.66.0.4`と`10.66.0.5`でDNSが稼働し、両方に`host.corp.example`などの内部レコードがある想定だ。説明用のドメインとレコードを、実際に管理するものへ置き換える。

OpenVPNのpushはDNSサービスやレコードを作らない。`dhcp-option`という名前でも、このTUN構成に実際のDHCPサーバーが必要という意味ではない。WINSは古いNetBIOSの名前解決用で、DNSの代わりではない。原文の`push "dhcp-option WINS 10.66.0.8"`は必要な既存環境だけで検討する。[原文](https://openvpn.net/community-docs/pushing-dhcp-options-to-clients.html)

### 2. 原文のdhcp-option方式

サーバーの`/etc/openvpn/server/server.conf`に記述する従来の例だ。

```conf
push "dhcp-option DNS 10.66.0.4"
push "dhcp-option DNS 10.66.0.5"
push "dhcp-option DOMAIN corp.example"
```

`DNS`はDNSサーバー、`DOMAIN`は接続固有のDNSサフィックスを通知する。サフィックスだけで、すべてのOSにおいてドメイン別のsplit DNSが完成するわけではない。

原文はWindowsの標準処理と、非Windowsでの`foreign_option_n`・upスクリプトを説明している。ただし2.7には標準の`dns-updown`フックと従来DNSオプションの変換もある。**Linuxでは必ず手動スクリプトを追加する必要がある、と一般化しない。** [2.7マニュアル](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 3. 2.7ではdns方式を別の例として使う

2.7クライアントとDNS連携を確認した環境では、上のDNS関連`dhcp-option`の代わりに次を使う。両方の例を同時に追加しない。

```conf
push "dns server 0 address 10.66.0.4 10.66.0.5"
push "dns server 0 resolve-domains corp.example"
push "dns search-domains corp.example"
```

`corp.example`とその配下を内部DNSへ問い合わせ、短い名前には検索サフィックスを提供する意図の設定だ。実際の対応はクライアントとOSに依存する。他のドメインは既存のDNS方針に従う。両DNSサーバーで同じ内部ゾーンを処理できるようにし、列挙順だけで固定の主系・副系切替が保証されるとは考えない。

`dns server`はDNS関連の`dhcp-option`より優先される。異なるバージョンが混在する場合、一括変更前に対応を確認する。[2.7マニュアル](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)

### 4. Ubuntu側の適用経路を確認する

接続前の状態を記録する。

```bash
openvpn --version
systemctl is-active systemd-resolved
readlink -f /etc/resolv.conf
resolvectl status
ip -brief address
```

この記事ではsystemd-resolvedが稼働し、`/etc/resolv.conf`がその管理ファイルを指す構成を想定する。他のDNS管理方式なら、先に適切な連携を選ぶ。`/etc/resolv.conf`を無条件に上書きしない。

2.7.7のLinuxソースには標準DNSフックがあり、選択された`dns-updown`が`make install`で導入される。環境に応じてsystemd-resolved、resolvconf、ファイル方式を使う。ビルド設定、配置先、権限で結果が変わるため、接続ログでフックの実行とエラーを確認する。[公式スクリプト](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/systemd-dns-updown.sh)、[インストール規則](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/Makefile.am)

既存の`up`スクリプトは標準DNSフックを抑制する場合がある。`dns-updown disable`やビルド時の無効化も確認する。同じプロファイルのDNSをNetworkManager、CLI、別スクリプトで重複管理しない。

2.6など従来の環境では、ディストリビューションの連携や[外部のupdate-systemd-resolved](https://github.com/jonathanio/update-systemd-resolved)を使える。OpenVPN本体とは別プロジェクトだ。導入先、接続・切断フック、実行権限をその説明に従って設定し、動作中の2.7標準フックへ重ねて追加しない。

### 5. DNSまでの経路と許可も必要

前の記事のサーバーLAN経路を維持する。

```conf
push "route 10.66.0.0 255.255.255.0"
```

IP転送、復路、ファイアウォールの設定も必要だ。DNS側ではVPNクライアントサブネットからの問い合わせを許可し、UDPとTCPの53番を確認する。DNSの通知だけで経路や許可は作られない。

[プロセス制御の記事](../openvpn-control-running-process/)に従ってサーバー変更を反映し、クライアントを再接続する。`SIGUSR1`はサーバー設定を再読込しない。

### 6. 通知・適用・応答を分けて確認する

VPN接続後、クライアントで実行する。

```bash
ip route get 10.66.0.4
ip route get 10.66.0.5
resolvectl status
resolvectl query host.corp.example
getent ahosts host.corp.example
```

`resolvectl status`で実際のVPNリンクのDNSとドメイン経路を見る。systemd-resolvedの`~corp.example`は経路専用ドメイン、`corp.example`は検索サフィックスにもなる。`~.`は一般のDNS問い合わせをそのリンクへ送る方針で、今回のsplit DNSとは異なる。[resolvectlの説明](https://manpages.ubuntu.com/manpages/noble/man1/resolvectl.1.html)

DNSサーバー自体を分けて試験する。

```bash
sudo apt install dnsutils
dig @10.66.0.4 host.corp.example A
dig @10.66.0.5 host.corp.example A
dig +tcp @10.66.0.4 host.corp.example A
```

`dig @アドレス`の成功は指定サーバーの応答を示すが、OSが標準でそのサーバーを選ぶ証拠ではない。返ったレコードが意図した内部アドレスかも確認する。

| 症状 | 確認対象 |
|---|---|
| 直接指定したdigも失敗 | VPN経路、復路、53番、DNSの問い合わせ許可 |
| 直接問い合わせは成功、通常の名前解決は失敗 | DNSフック、resolver連携、split DNSドメイン |
| 完全な名前だけ成功 | 検索サフィックス、アプリの動作 |
| ブラウザーだけ結果が違う | 独自のDoH設定、キャッシュ |

Windowsでは原文の`ipconfig /all`に加えて実際の名前解決も試す。現行環境はドライバーやDNSポリシーが異なるため、TAPの表示だけで判定しない。

```text
ipconfig /all
nslookup host.corp.example
```


### 7. 切断後の復元も確認する

VPNを正常終了し、`resolvectl status`と通常の公開ドメインの名前解決を再確認する。内部DNSの設定が残って一般の名前解決を妨げないことを確認する。`resolvectl revert インターフェース名`は手動復旧用だが、そのリンクの他の手動設定も戻すため対象を確認して使う。

この設定だけですべてのアプリのDNS漏えい防止を保証するものではない。ブラウザーDoH、他リンクのDNS方針、IPv6も別途考慮する。原文のcaveatsリンクは今回取得できなかったため、現行マニュアルと実装を確認して補足した。

### 参考資料

- [OpenVPN: Pushing DHCP Options to Clients](https://openvpn.net/community-docs/pushing-dhcp-options-to-clients.html)
- [OpenVPN 2.7 manual — dhcp-option, dns, dns-updown](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [OpenVPN 2.7.7 DNS helper](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/systemd-dns-updown.sh)
- [OpenVPN 2.7.7 DNS helper installation](https://github.com/OpenVPN/openvpn/blob/v2.7.7/distro/dns-scripts/Makefile.am)
- [Ubuntu 24.04: resolvectl](https://manpages.ubuntu.com/manpages/noble/man1/resolvectl.1.html)
- [update-systemd-resolved — third-party helper](https://github.com/jonathanio/update-systemd-resolved)
