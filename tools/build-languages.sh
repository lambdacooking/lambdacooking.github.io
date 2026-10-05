#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle exec jekyll build --destination _site/jp
bundle exec jekyll build --config _config.yml,_config.en.yml --destination _site/en
bundle exec jekyll build --config _config.yml,_config.ko.yml --destination _site/ko
cp tools/root-index.html _site/index.html
cp tools/retire-root-sw.js _site/sw.min.js
touch _site/.nojekyll
cat > _site/404.html <<'HTML'
<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><title>ページが見つかりません</title>
<meta http-equiv="refresh" content="0; url=/jp/404.html">
<script>location.replace(location.pathname.startsWith('/ko/') ? '/ko/404.html' : location.pathname.startsWith('/en/') ? '/en/404.html' : '/jp/404.html');</script>
</head><body><a href="/jp/">ホームへ</a></body></html>
HTML
