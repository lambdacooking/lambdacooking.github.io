---
title: Easy-RSA 3でOpenVPNのCAとサーバー・クライアント証明書を作成する
lang: ja-JP
permalink: /jp/openvpn-ca-certificates-easyrsa3
author: ramen
date: 2026-10-05 14:30:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, pki, easy-rsa, certificates]
---

### Ubuntu 24.04ではEasy-RSA 3を使う

Ubuntu 24.04でEasy-RSA 2を使ったところ問題が発生したため、今回はEasy-RSA 3を使用した。新しく構築するなら、できるだけ **Easy-RSA 3を推奨する。** この「3」はツールのバージョンであり、RSAの鍵長や別の暗号方式を指すものではない。

[OpenVPNの公式CAガイド](https://openvpn.net/community-docs/setting-up-your-own-certificate-authority--ca--and-generating-certificates-and-keys-for-an-openvpn-server-and-multiple-clients.html)もUnix系では3を参照するよう案内しているが、本文の `./build-ca` や `./build-key-server` は2の手順のままだ。現在の環境に合わせて更新されていない例が、問題に影響した可能性はある。ただし、エラーログを分析していないため、Ubuntu 24.04でEasy-RSA 2が必ず動かないとは断定しない。

ここでは2026年10月5日に最新と確認した [Easy-RSA 3.2.7](https://github.com/OpenVPN/easy-rsa/releases/tag/v3.2.7) を固定して使う。後日実行する場合は、新しいリリースも確認してほしい。

### 1. build-caの前に依存関係とファイルを準備

証明書の生成には **`openssl` コマンド** が必要だ。以下では前回のOpenVPNソースビルド環境も考慮して開発パッケージをまとめて入れるが、すべてが `build-ca` の必須条件という意味ではない。

| 確認した項目 | Ubuntuでのパッケージ・用途 |
|---|---|
| `pkg-config` | OpenVPNビルド時のライブラリ検出 |
| `libnl-genl-3.5.0` | そのままインストールするパッケージ名ではない。検出するモジュール名は `libnl-genl-3.0` で、バージョンは別途確認 |
| `libnl-3-dev`, `libnl-genl-3-dev` | Netlinkの開発ファイル。Linux DCOのビルド検査で使用 |
| `libcap-ng-dev` | Linuxの権限管理用開発ファイル |
| `libssl-dev` | OpenSSLの開発ヘッダー。`openssl` コマンドとは区別する |
| `liblz4-dev`, `liblzo2-dev` | 圧縮ライブラリのビルド依存関係 |
| `libpam-dev` | この例では実パッケージ `libpam0g-dev` を使用。PAMプラグインのビルド用 |

OpenVPNの [ビルド設定](https://github.com/OpenVPN/openvpn/blob/v2.7.7/configure.ac) と [Linux CI](https://github.com/OpenVPN/openvpn/blob/v2.7.7/.github/workflows/build.yaml) を参照した。ライブラリのインストールだけでVPN圧縮が有効になるわけではない。

```bash
sudo apt update
sudo apt install -y git ca-certificates openssl pkg-config \
  libnl-3-dev libnl-genl-3-dev libcap-ng-dev libssl-dev \
  liblz4-dev liblzo2-dev libpam0g-dev
openssl version
pkg-config --modversion libnl-genl-3.0
```

これだけでOpenVPNのビルドツールがすべて揃うわけではない。全体の手順は [前回の記事](../openvpn-install-from-github-source/) を参照する。CAを別のマシンに置く場合、そのマシンにOpenVPNの開発パッケージは不要だ。

### 2. Easy-RSA 3のソース一式を取得

ブログのリポジトリ外に専用の作業場所を用意し、一般ユーザーで実行する。以下の取得先ディレクトリは、まだ存在しないことを前提とする。

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

`easyrsa` だけをコピーせず、`openssl-easyrsa.cnf` と `x509-types/` も一緒に保持する。`vars.example` は設定例だ。Easy-RSA自体には `make install` は必要ない。[公式ドキュメント](https://easy-rsa.readthedocs.io/en/latest/)

### 3. 新しいPKIとCAを作る

新規CA向けの手順だ。**既存のPKIで `init-pki` を再実行しないこと。** 既存の `vars` も上書きしないよう確認する。

```bash
cat > vars <<'EOF'
set_var EASYRSA_ALGO rsa
set_var EASYRSA_KEY_SIZE 3072
set_var EASYRSA_DIGEST sha256
EOF
./easyrsa init-pki
./easyrsa build-ca
```

CA秘密鍵には強いパスフレーズを設定し、Common Nameには `SnackChocopie VPN CA` など識別できる名前を入力する。Easy-RSA 2のように `. ./vars` は実行しない。

`pki/ca.crt` は信頼の基準となる公開証明書、`pki/private/ca.key` は署名権限を持つ秘密鍵だ。CA秘密鍵をVPNサーバーやクライアントに配布してはいけない。可能ならCAをサーバーから分離し、オフラインで管理する。

### 4. サーバーと複数クライアントへ発行

以下は流れを理解するため、CAの作業場所で鍵生成と署名をまとめて行う例だ。本番では各端末で秘密鍵とCSRを生成し、CAにはCSRだけを渡す構成を推奨する。

```bash
./easyrsa build-server-full server nopass
./easyrsa build-client-full client1
./easyrsa build-client-full client2
./easyrsa build-client-full client3
```

確認内容を読んで承認し、要求されたらCAのパスフレーズを入力する。各クライアントにはそれぞれ秘密鍵のパスフレーズを設定する。ユーザーや端末ごとに一意な証明書名を使い、同じ鍵を共有しない。

サーバーの `nopass` は無人起動のために **サーバー秘密鍵の暗号化を省く** 選択だ。ファイルの読み取り権限を厳しく制限する。起動時にパスフレーズを入力できる運用なら省略できる。CAには `nopass` を使わない。各コマンドは [3.2.7のスクリプト](https://github.com/OpenVPN/easy-rsa/blob/v3.2.7/easyrsa3/easyrsa) で確認できる。

### 5. 検証し、必要なファイルだけを配布

```bash
openssl verify -CAfile pki/ca.crt -purpose sslserver pki/issued/server.crt
openssl verify -CAfile pki/ca.crt -purpose sslclient \
  pki/issued/client1.crt pki/issued/client2.crt pki/issued/client3.crt
openssl x509 -in pki/issued/server.crt -noout -subject -issuer -dates
```

結果が `OK` であることと有効期限を確認する。実際のVPN接続試験は別途必要だ。

| 配布先 | ファイル |
|---|---|
| VPNサーバー | `pki/ca.crt`, `pki/issued/server.crt`, `pki/private/server.key` |
| client1 | `pki/ca.crt`, `pki/issued/client1.crt`, `pki/private/client1.key` |
| client2 / client3 | CA証明書と、それぞれ専用の証明書・秘密鍵 |
| CA保管場所のみ | `pki/private/ca.key` と、発行DBを含むPKI全体の安全なバックアップ |

秘密鍵は安全な経路で転送し、必要なアカウントだけが読めるようにする。PKIやパスフレーズをGitHubへ公開しない。VPNサーバー設定、ルーティング、ファイアウォールは別途構成する。

従来の `build-dh` は `./easyrsa gen-dh` に相当する。有限体DHを使うサーバー設定なら、生成された `pki/dh.pem` を指定する。現在のOpenVPNでECDHなどを使う場合は `dh none` を選択でき、DHファイルが必須とは限らない。[OpenVPNのTLS設定](https://github.com/OpenVPN/openvpn/blob/v2.7.7/doc/man-sections/tls-options.rst)

### 6. 紛失したクライアントの証明書を失効

次の例はclient2を実際に失効させる場合だけ実行する。

```bash
./easyrsa revoke client2
./easyrsa gen-crl
openssl crl -in pki/crl.pem -noout -lastupdate -nextupdate
```

`pki/crl.pem` をVPNサーバーへ配布し、サーバーの `crl-verify` がそのファイルを読むように設定する。CAで失効処理を行うだけではサーバーに伝わらない。CRLの期限を管理し、追加の失効時にも再生成・配布する。接続中のセッションを切断する必要があれば別途対応する。

以後はCAを作り直さず、既存PKIを保管しながらクライアントの追加、有効期限、失効を管理する。
