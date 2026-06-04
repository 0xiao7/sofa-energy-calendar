#!/usr/bin/env bash
# 把檔案上傳成「一次性連結」，印出網址。
#
# 用法：
#   export WORKER_URL="https://one-time-share.<你的子網域>.workers.dev"
#   export SHARE_SECRET="你設定的密鑰"
#   ./share.sh index.html            # 看一次即焚
#   ./share.sh index.html 60         # 看一次即焚，且 60 秒後自動過期
#
set -euo pipefail

: "${WORKER_URL:?請先 export WORKER_URL（你的 Worker 網址）}"
: "${SHARE_SECRET:?請先 export SHARE_SECRET（建立連結用的密鑰）}"

file="${1:?用法：./share.sh <檔案> [ttl秒數]}"
ttl="${2:-0}"

[ -f "$file" ] || { echo "找不到檔案：$file" >&2; exit 1; }

# 依副檔名猜 content-type（預設 HTML）
case "$file" in
  *.html|*.htm) ct="text/html; charset=utf-8" ;;
  *.txt)        ct="text/plain; charset=utf-8" ;;
  *.json)       ct="application/json; charset=utf-8" ;;
  *)            ct="text/html; charset=utf-8" ;;
esac

resp="$(curl -fsS -X POST "${WORKER_URL%/}/create?ttl=${ttl}" \
  -H "x-auth: ${SHARE_SECRET}" \
  -H "x-content-type: ${ct}" \
  --data-binary "@${file}")"

# 取出 url 欄位（無 jq 也能用）
url="$(printf '%s' "$resp" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [ -n "$url" ]; then
  echo "$url"
else
  echo "建立失敗，伺服器回應：" >&2
  printf '%s\n' "$resp" >&2
  exit 1
fi
