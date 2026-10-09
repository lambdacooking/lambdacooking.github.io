---
title: OpenVPNでサーバーとクライアントの背後のLANを接続する
lang: ja-JP
permalink: /jp/openvpn-connect-server-client-lans
author: ramen
date: 2026-10-09 00:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, routing, subnet, firewall]
---

### VPN端末の先にあるコンピューターへ接続する

[最初の接続試験](../openvpn-start-and-test-connectivity/)ではサーバーのVPNアドレスまで確認した。今回はサーバー側LAN、続いてクライアント側LANへ範囲を広げる。**往路、復路、IP転送、ファイアウォールの許可がすべて必要だ。**

Ubuntu 24.04で[ソースからビルドしてmake install](../openvpn-install-from-github-source/)した環境のIPv4・TUNルーティング例だ。実ネットワークでの試験記録ではない。アドレスとインターフェースを自分の環境に合わせ、証明書の設定は既存のものを維持する。

### 1. アドレスと前提

| 役割 | アドレス |
|---|---|
| VPNサブネット | `10.8.0.0/24` |
| サーバーLAN / デフォルトゲートウェイ | `10.66.0.0/24` / `10.66.0.1` |
| OpenVPNサーバーのLANアドレス | `10.66.0.10` |
| サーバーLANの試験端末 | `10.66.0.20` |
| クライアントLAN / デフォルトゲートウェイ | `192.168.4.0/24` / `192.168.4.1` |
| OpenVPN client2のLANアドレス | `192.168.4.10` |
| クライアントLANの試験端末 | `192.168.4.20` |

次は経路上の役割を示す図だ。同じLANのゲートウェイとVPN端末が別々の物理区間に分かれるという意味ではない。

```text
10.66.0.20 -- 10.66.0.1 -- 10.66.0.10 [OpenVPN server]
                                   || VPN 10.8.0.0/24 ||
192.168.4.20 -- 192.168.4.1 -- 192.168.4.10 [client2]
```

3つの範囲は重複させず、各拠点のLANも固有にする。client2には有効な固有の証明書を使い、`duplicate-cn`は使用しない。**前の記事でclient2を実際に失効させた場合、その証明書は再利用できない。** 新しい証明書を準備し、以下のCCDファイル名を実際のCommon Nameに合わせる。

従来の`route`と`iroute`の役割を再現するため、この実習ではサーバーとclient2の既存設定に次を追加する。

```conf
disable-dco
```

DCOを無効にするのは学習上の選択だ。DCOでは`iroute`でカーネル経路も構成できる場合があり、`client-to-client`の動作も異なる。原文の「両方が常に必要」をすべての構成に一般化しない。[サーバーオプション](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)

### 2. まずサーバーLANへ接続する

サーバーの`/etc/openvpn/server/server.conf`に追加する。

```conf
push "route 10.66.0.0 255.255.255.0"
```

サーバーLAN宛ての通信をVPNへ送るようクライアントに通知する。クライアント側でpushされた経路を無視する設定にしていないことを確認する。

OpenVPNサーバーでIPv4転送を有効にする。同名のファイルがあれば上書き前に確認する。

```bash
printf '%s\n' 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/90-openvpn-forward.conf
sudo sysctl -p /etc/sysctl.d/90-openvpn-forward.conf
sysctl net.ipv4.ip_forward
```

値が`1`か確認する。転送の有効化とファイアウォールの許可は別だ。他のsysctlやUFW設定に上書きされていないか、再起動・ファイアウォール再適用後にも確認する。[カーネルの説明](https://docs.kernel.org/networking/ip-sysctl.html)

**サーバーLANのゲートウェイ`10.66.0.1`で**VPNサブネットへの復路を追加する。以下はゲートウェイがLinuxの場合だ。

```bash
sudo ip route add 10.8.0.0/24 via 10.66.0.10
```

OpenVPNサーバー自身がLANのデフォルトゲートウェイなら、この別のnext hopへの経路は不要だ。ルーター機器なら静的経路の画面で宛先、マスク、next hopを設定する。`ip route add`は一時設定なので、確認後にNetplanやルーター設定へ永続化する。既存経路がある場合は先に確認する。

すでにUFWを使用しているOpenVPNサーバーで転送を許可する。以降は**VPNが`tun0`、LANが`enp1s0`**という例だ。`ip -brief address`で実際の名前を調べて置き換える。

```bash
sudo ufw route allow in on tun0 out on enp1s0 from 10.8.0.0/24 to 10.66.0.0/24
```

サーバー自身へのUDP 1194許可とは別の規則だ。標準UFWのestablished/related規則が応答を扱うが、独自ポリシーがあれば併せて確認する。宛先端末のファイアウォールでもサービスやICMPを許可する。[UFW route規則](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)

### 3. クライアントLANまで広げる

client2を`192.168.4.0/24`のVPN中継端末にする。**client2でも2節のIPv4転送設定を行う。** サーバーにCCDファイルを用意する。

```bash
sudo install -d -m 750 /etc/openvpn/server/ccd
sudoedit /etc/openvpn/server/ccd/client2
```

`client2`ファイルに次を保存する。

```conf
iroute 192.168.4.0 255.255.255.0
```

サーバーの`server.conf`に次を追加し、2節のサーバーLAN向けpushも残す。

```conf
client-config-dir /etc/openvpn/server/ccd
route 192.168.4.0 255.255.255.0
```

`route`はカーネルからOpenVPNへ、`iroute`はOpenVPN内部からclient2へ送る役割だ。CCDはクライアントではなく**サーバーに保存**する。権限を落としている場合は、CCDと親ディレクトリへのアクセスを確認する。

**サーバーLANゲートウェイ`10.66.0.1`で：**

```bash
sudo ip route add 192.168.4.0/24 via 10.66.0.10
```

**クライアントLANゲートウェイ`192.168.4.1`で：**

```bash
sudo ip route add 10.66.0.0/24 via 192.168.4.10
sudo ip route add 10.8.0.0/24 via 192.168.4.10
```

next hopはそれぞれ同じLAN内のVPN端末のLANアドレスだ。VPN端末自身がデフォルトゲートウェイなら、その側の別ゲートウェイ用経路は省略する。これらもLinuxゲートウェイの一時経路例だ。

### 4. LAN間の転送を許可する

両LANから通信を開始できる実習用の規則だ。運用では宛先やポートを必要な範囲に絞る。

OpenVPNの**サーバー**で：

```bash
sudo ufw route allow in on tun0 out on enp1s0 from 192.168.4.0/24 to 10.66.0.0/24
sudo ufw route allow in on enp1s0 out on tun0 from 10.66.0.0/24 to 192.168.4.0/24
```

OpenVPNの**client2**で：

```bash
sudo ufw route allow in on enp1s0 out on tun0 from 192.168.4.0/24 to 10.66.0.0/24
sudo ufw route allow in on tun0 out on enp1s0 from 10.66.0.0/24 to 192.168.4.0/24
```

この規則は2つのLAN間の通信を扱う。他のVPNクライアントにもclient2のLANを公開する場合は別途ポリシーが必要だ。この例は純粋なルーティングなのでNAT/MASQUERADEは追加しない。NATは復路を追加できない場合の別設計で、元の送信元アドレスが隠れる場合がある。

### 5. 設定を反映して試す

既存設定をバックアップし、[プロセス制御の記事](../openvpn-control-running-process/)に従ってサーバーとclient2の変更を反映する。`SIGUSR1`は変更した設定を再読込しない。再起動は接続を切るため、別の管理経路を確保する。CCDの変更は対象の次回接続時に反映される。

まず通常のVPNクライアントから`10.66.0.20`へ接続し、次にLAN間を試す。**クライアントLAN端末`192.168.4.20`で：**

```bash
ip route get 10.66.0.20
ping -c 4 10.66.0.20
```

**サーバーLAN端末`10.66.0.20`で**逆方向も試す。

```bash
ip route get 192.168.4.20
ping -c 4 192.168.4.20
```

通常のLAN端末の`ip route get`にVPNインターフェースが出る必要はない。この構成ではデフォルトゲートウェイを使い、そこからVPN端末へ転送される。実際のVPN端末でも宛先経路とログを確認する。

| 症状 | 最初に確認すること |
|---|---|
| VPNサーバーにしか届かない | サーバーLANのpush、サーバーの転送設定、UFW route規則 |
| 要求は届くが応答がない | 両LANゲートウェイの復路、宛先端末のファイアウォール |
| client2のLANだけ届かない | 実際のCNとCCD名、`route`・`iroute`、client2の転送設定 |
| 特定の場所だけ失敗する | LANとVPN拠点のサブネット重複 |

pingだけで断定せず、許可された実際のサービスも試す。LAN接続の成功は、インターネット全体の転送やDNS設定の完了を意味しない。

### 6. 原文の選択項目と参照リンク

他のVPNクライアントにもclient2のLANを公開する場合、原文は次を提示する。基本のLAN間接続に必須ではない。

```conf
client-to-client
push "route 192.168.4.0 255.255.255.0"
```

DCOなしの`client-to-client`は内部転送を行うため、クライアント間を制限するカーネルの規則を迂回する場合がある。DCOではこのオプションは効果を持たない。自動的に追加せず、アクセス方針と合わせて選ぶ。

TAPブリッジはEthernetレベルでネットワークをつなぐ。[ブリッジの説明](https://openvpn.net/community-docs/ethernet-bridging.html)と[INSTALLのDHCP説明](https://openvpn.net/community-docs/the-standard-install-file-included-in-the-source-distribution.html)は、ブリッジ構成、アドレス配置、DHCP計画を前提にしている。`dev tun`を`dev tap`へ変えるだけでは完成しない。今回は異なるLANを接続するTUNルーティングを維持する。

原文のIP forwarding参照リンクは今回取得できなかったため、カーネルとUbuntuの公式資料で補足した。実際のPKI、秘密鍵、運用ログはリポジトリに含めない。

### 参考資料

- [OpenVPN: Expanding the Scope of the VPN](https://openvpn.net/community-docs/expanding-the-scope-of-the-vpn-to-include-additional-machines-on-either-the-client-or-server-subnet.html)
- [OpenVPN 2.7.7 server options: route, iroute, CCD, client-to-client](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/server-options.rst)
- [OpenVPN 2.7 manual: disable-dco](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual.html)
- [Linux kernel: IP sysctl](https://docs.kernel.org/networking/ip-sysctl.html)
- [Ubuntu 24.04: UFW](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)
- [OpenVPN: Ethernet Bridging](https://openvpn.net/community-docs/ethernet-bridging.html)
- [OpenVPN: INSTALL — DHCP and bridging](https://openvpn.net/community-docs/the-standard-install-file-included-in-the-source-distribution.html)
