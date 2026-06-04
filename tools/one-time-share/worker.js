// One-time share Worker（閱後即焚 / 一次性連結）
//
// 用途：把任何測試內容（HTML、文字…）上傳，拿到一個隨機網址；
// 對方打開的「當下」就把內容讀出並立即刪除 → 再打開就失效。
// 也支援 TTL：建立後 N 秒自動過期（即使沒人看也會消失）。
//
// 端點：
//   POST /create            建立一次性連結（需帶 X-Auth: <SHARE_SECRET>）
//        ?ttl=60            （選填）N 秒後自動過期，最少 60、最多 86400
//        Header X-Content-Type（選填）回傳時的 content-type，預設 text/html
//        Body = 要分享的內容
//        回傳 { url, ttl }
//   GET  /v/<id>            觀看內容（讀取後立刻刪除，僅此一次）
//
// 安全提醒：Cloudflare KV 是「最終一致」，極端情況下「刪除」可能慢一拍，
//   理論上同一瞬間的兩個請求有機會都讀到。對個人測試分享足夠；
//   若要強一致的嚴格一次性，改用 Durable Objects（README 有說明）。

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const { pathname } = url;

    // ---- 建立一次性連結 ----
    if (request.method === "POST" && pathname === "/create") {
      const auth = request.headers.get("x-auth") || "";
      if (!env.SHARE_SECRET || auth !== env.SHARE_SECRET) {
        return json({ error: "unauthorized" }, 401);
      }
      const content = await request.text();
      if (!content) return json({ error: "empty body" }, 400);

      const contentType =
        request.headers.get("x-content-type") || "text/html; charset=utf-8";

      let ttl = parseInt(url.searchParams.get("ttl") || "0", 10);
      if (!Number.isFinite(ttl) || ttl < 0) ttl = 0;
      if (ttl > 0) ttl = Math.min(Math.max(ttl, 60), 86400); // 60s ~ 24h

      const id = crypto.randomUUID().replace(/-/g, "");
      const opts = { metadata: { contentType } };
      if (ttl > 0) opts.expirationTtl = ttl;

      await env.SHARES.put(id, content, opts);
      return json({ url: `${url.origin}/v/${id}`, ttl: ttl || null });
    }

    // ---- 觀看（讀取後立即刪除）----
    if (request.method === "GET" && pathname.startsWith("/v/")) {
      const id = pathname.slice(3);
      if (!/^[a-f0-9]{32}$/.test(id)) {
        return htmlResponse(expiredPage(), 404);
      }
      const { value, metadata } = await env.SHARES.getWithMetadata(id);
      if (value === null) {
        return htmlResponse(expiredPage(), 404);
      }
      // 一次性：先刪掉，確保不會被看第二次
      await env.SHARES.delete(id);

      const ct =
        (metadata && metadata.contentType) || "text/html; charset=utf-8";
      return new Response(value, {
        status: 200,
        headers: {
          "content-type": ct,
          "cache-control": "no-store, no-cache, must-revalidate, max-age=0",
          "x-robots-tag": "noindex, nofollow",
          "referrer-policy": "no-referrer",
        },
      });
    }

    // ---- 首頁說明 ----
    if (request.method === "GET" && pathname === "/") {
      return htmlResponse(indexPage(), 200);
    }

    return new Response("Not found", { status: 404 });
  },
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj, null, 2), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function htmlResponse(html, status = 200) {
  return new Response(html, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
  });
}

function expiredPage() {
  return `<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>連結已失效</title>
<style>html,body{height:100%;margin:0}body{display:flex;align-items:center;justify-content:center;
font-family:-apple-system,"PingFang TC","Microsoft JhengHei",system-ui,sans-serif;background:#0f1115;color:#e6e6e6}
.box{text-align:center;padding:2rem}.icon{font-size:3rem}h1{font-size:1.25rem;margin:.75rem 0 .25rem}
p{color:#9aa0a6;margin:0;font-size:.9rem}</style></head>
<body><div class="box"><div class="icon">🔥</div><h1>連結已失效</h1>
<p>這是一次性連結，內容已被讀取或已過期。</p></div></body></html>`;
}

function indexPage() {
  return `<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>一次性分享</title>
<style>html,body{height:100%;margin:0}body{display:flex;align-items:center;justify-content:center;
font-family:-apple-system,"PingFang TC","Microsoft JhengHei",system-ui,sans-serif;background:#0f1115;color:#e6e6e6}
.box{text-align:center;padding:2rem;max-width:34rem}h1{font-size:1.25rem}
code{background:#1c1f26;padding:.15rem .4rem;border-radius:.3rem}p{color:#9aa0a6;font-size:.9rem;line-height:1.6}</style></head>
<body><div class="box"><h1>🔥 一次性分享服務</h1>
<p>用 <code>POST /create</code> 建立連結，內容看過一次即焚毀。<br>請從 CLI / 腳本帶 <code>X-Auth</code> 建立，不對外開放上傳。</p></div></body></html>`;
}
