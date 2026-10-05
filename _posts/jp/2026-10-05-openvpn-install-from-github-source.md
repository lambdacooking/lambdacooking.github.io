---
title: GitHubのソースからOpenVPNをmake installで導入する
lang: ja-JP
permalink: /jp/openvpn-install-from-github-source
author: ramen
date: 2026-10-05 14:00:00 +0900
categories: [OpenVPN]
tags: [vpn, linux, source-build]
---

### 対象環境とバージョン

[公式インストールガイド](https://openvpn.net/community-docs/installing-openvpn.html)をもとに、GitHubから取得したソースで導入する手順をまとめます。対象例はUbuntu 24.04です。Debian系の別バージョンではパッケージの調整が必要な場合があります。ここで導入するのは実行ファイルであり、VPNサービスの設定までは行いません。

コマンドは、2026年10月5日にGitHubで最新リリースとして確認した[v2.7.7](https://github.com/OpenVPN/openvpn/releases/tag/v2.7.7)に固定しています。後日導入する際はリリース情報を再確認してください。

### 1. ビルドに必要なパッケージを入れる

ツールとライブラリをAPTで導入し、OpenVPN本体はソースからビルドします。パッケージ選定はプロジェクトの[Linux CI](https://github.com/OpenVPN/openvpn/blob/v2.7.7/.github/workflows/build.yaml)を参考にしています。

```bash
sudo apt update
sudo apt install -y \
  git ca-certificates build-essential autoconf automake libtool pkg-config \
  libssl-dev liblzo2-dev liblz4-dev libcap-ng-dev libnl-genl-3-dev \
  libpam0g-dev libcmocka-dev python3-docutils
```

`libssl-dev`はOpenSSLのヘッダー、LZO/LZ4の開発パッケージは既定のライブラリ検出に対応します。ライブラリの導入だけでVPN通信の圧縮が有効になるわけではありません。`libcmocka-dev`は単体テスト、`python3-docutils`は文書生成に使われます。追加機能の要件は[`configure.ac`](https://github.com/OpenVPN/openvpn/blob/v2.7.7/configure.ac)で確認できます。

### 2. GitHubからソースを取得する

`openvpn-2.7.7`ディレクトリがまだ存在しない作業場所で実行します。

```bash
git clone --depth 1 --branch v2.7.7 \
  https://github.com/OpenVPN/openvpn.git openvpn-2.7.7
cd openvpn-2.7.7
git describe --tags --exact-match
git rev-parse HEAD
```

タグを指定した取得でdetached HEADの案内が出るのは正常です。コミットIDも作業記録に残します。タグは選択した版を示しますが、それだけで署名を検証したことにはなりません。

### 3. ビルドファイルの生成・設定・ビルド・検査

Gitから取得したソースでは、[`INSTALL`](https://github.com/OpenVPN/openvpn/blob/v2.7.7/INSTALL)に記載されたAutotoolsの生成処理が必要です。一般ユーザーで実行してください。`&&`により、途中で失敗した場合は後続処理に進みません。

```bash
autoreconf -ivf &&
./configure --prefix=/usr/local --with-crypto-library=openssl &&
make -j"$(nproc)" &&
make check
```

インストール先を`/usr/local`配下に指定しています。テストが失敗した場合は原因を確認してから次へ進みます。`make check`の成功は、実際のクライアント・サーバー間通信の成功を保証するものではありません。

### 4. インストールして実行ファイルを確認する

前の処理が成功したら、管理者権限でインストールします。

```bash
sudo make install
/usr/local/sbin/openvpn --version
```

出力に`2.7.7`が含まれることを確認します。パッケージ版が別の場所に存在する場合もあるため、実行ファイルのパスも確認してください。

```bash
type -a openvpn
/usr/local/sbin/openvpn --version
```

この方法で配置したファイルはAPTの管理対象にはなりません。保守のためにソースとビルド設定を残し、今後のOpenVPN更新も別途適用します。

### よくあるつまずき

| 症状 | 確認すること |
| --- | --- |
| `autoreconf: command not found` | 手順1のAutotools関連パッケージを導入する。 |
| `configure`がない | リポジトリ直下で`autoreconf -ivf`を実行する。 |
| ライブラリやヘッダーが見つからない | 最初のエラーと`config.log`を読み、対応する開発パッケージを確認する。 |
| 想定と異なるバージョンが出る | `/usr/local/sbin/openvpn`を直接実行する。 |

### インストール後に必要な作業

証明書・鍵、クライアントとサーバーの設定、ルーティング、ファイアウォール、systemdサービスの設定は別途必要です。この手順ではサービスの起動や経路変更は行いません。また、OpenVPNのビルドだけでLinuxのDCOカーネルモジュールが導入されるわけではなく、DCOの利用可否はカーネルと実行環境に依存します。
