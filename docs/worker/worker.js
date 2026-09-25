// Cloudflare Worker: сервер онлайн-итогов для Дикты (task 059)
// Модель — Workers AI (llama-3.3-70b), ключ z.ai не нужен.
// Секрет APP_KEY задаётся в Settings -> Variables (Secret) при создании воркера.

const MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type,x-app-key",
  "Access-Control-Allow-Methods": "POST,OPTIONS"
};
const j = (o, s = 200) => new Response(JSON.stringify(o), {
  status: s, headers: { "content-type": "application/json", ...CORS }
});

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    const url = new URL(request.url);
    if (url.pathname === "/health") return j({ ok: true, model: MODEL });
    if (url.pathname !== "/summarize") return j({ error: "not found" }, 404);
    if (request.method !== "POST") return j({ error: "method" }, 405);
    if (!env.APP_KEY || (request.headers.get("x-app-key") || "") !== env.APP_KEY)
      return j({ error: "unauthorized" }, 401);

    let body = {};
    try { body = await request.json(); } catch (e) { return j({ error: "bad json" }, 400); }
    const text = (body.text || "").trim();
    const lang = body.lang || "ru";
    if (text.length < 20) return j({ error: "text too short" }, 400);

    const sys = "Ты собираешь краткие деловые итоги по расшифровке. Пиши только то, что есть в тексте, без выдумок.";
    const user = `Язык ответа: ${lang}. Сделай конспект: «О чём договорились», «Задачи» (пунктами), «Цифры и даты».\n\nТЕКСТ:\n${text.slice(0, 60000)}`;
    try {
      const out = await env.AI.run(MODEL, {
        messages: [{ role: "system", content: sys }, { role: "user", content: user }],
        max_tokens: 900
      });
      return j({ summary: (out && (out.response || out.result || out)) || "", model: MODEL });
    } catch (e) {
      return j({ error: String(e) }, 502);
    }
  }
};
