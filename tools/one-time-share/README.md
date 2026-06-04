# 一次性分享（閱後即焚）

把任何測試內容變成一個**只能看一次**的連結：對方打開的當下，內容就被讀出並從伺服器刪除；再打開就顯示「已失效」。也可設 TTL，建立後 N 秒自動過期。

> 為什麼需要後端？靜態網址（GitHub Pages / raw.githack）沒有狀態，無法知道「已經被看過了」，所以做不到自動刪除。這裡用一個極小的 Cloudflare Worker + KV 來控管一次性 token。

## 一次性部署（約 5 分鐘）

需要一個免費的 [Cloudflare 帳號](https://dash.cloudflare.com/sign-up)。

```bash
cd tools/one-time-share

# 1) 登入
npx wrangler login

# 2) 建立內容儲存區（KV），把回傳的 id 貼進 wrangler.toml 的 [[kv_namespaces]].id
npx wrangler kv namespace create SHARES

# 3) 設定建立連結用的密鑰（只有你知道，避免別人拿你的 Worker 亂上傳）
npx wrangler secret put SHARE_SECRET
#    輸入一段自訂密碼

# 4) 部署
npx wrangler deploy
#    部署完會印出網址，例如 https://one-time-share.<你的子網域>.workers.dev
```

## 每次使用

```bash
export WORKER_URL="https://one-time-share.<你的子網域>.workers.dev"
export SHARE_SECRET="你剛剛設定的密鑰"

# 看一次即焚
./share.sh ../../index.html

# 看一次即焚，且 60 秒後自動過期（沒人看也會消失）
./share.sh ../../index.html 60
```

腳本會印出一個網址，把它丟給對方在手機/瀏覽器打開即可。打開後內容立刻失效。

## 安全範圍（誠實說明）

- **一次性**靠 KV 的「讀取後立即刪除」。Cloudflare KV 是**最終一致**，極端情況下刪除可能慢一拍，理論上同一瞬間的兩個請求有機會都讀到。對個人測試分享足夠。
- 想要**嚴格**一次性（強一致），把儲存改成 **Durable Objects** 或 **D1**，在同一個物件內「讀+刪」原子化。需要時可再加。
- 回應已加 `no-store` 與 `noindex`，避免快取與被搜尋引擎收錄。
- 內容存在你自己的 Cloudflare 帳號裡，不經第三方分享服務。
