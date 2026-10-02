// Cloudflare Worker: сервер ИИ для наших приложений.
// Дикта: онлайн-итоги (/summarize, режим конспекта — поведение не менялось).
// Адвокат (task 061): генерация документов — если в теле есть "system",
//   он используется как системный промпт, а "text" — как пользовательский.
// Модель — Workers AI (llama-3.3-70b). Секрет APP_KEY — в Variables (Secret) воркера.

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
    if (url.pathname !== "/summarize" && url.pathname !== "/ai")
      return j({ error: "not found" }, 404);
    if (request.method !== "POST") return j({ error: "method" }, 405);
    if (!env.APP_KEY || (request.headers.get("x-app-key") || "") !== env.APP_KEY)
      return j({ error: "unauthorized" }, 401);

    let body = {};
    try { body = await request.json(); } catch (e) { return j({ error: "bad json" }, 400); }
    const text = (body.text || "").trim();
    const lang = body.lang || "ru";

    let sys, user, maxTokens;
    if (typeof body.system === "string" && body.system.trim()) {
      // Общий режим (Адвокат: документы и другие задачи по системному промпту)
      if (text.length < 1) return j({ error: "text too short" }, 400);
      sys = body.system.trim();
      user = text.slice(0, 60000);
      maxTokens = Math.min(Number(body.max_tokens) || 3000, 4096);
    } else {
      // Режим итогов (Дикта) — как было
      if (text.length < 20) return j({ error: "text too short" }, 400);
      sys = "Ты собираешь краткие деловые итоги по расшифровке. Пиши только то, что есть в тексте, без выдумок.";
      user = `Язык ответа: ${lang}. Сделай конспект: «О чём договорились», «Задачи» (пунктами), «Цифры и даты».\n\nТЕКСТ:\n${text.slice(0, 60000)}`;
      maxTokens = 900;
    }

    try {
      const out = await env.AI.run(MODEL, {
        messages: [{ role: "system", content: sys }, { role: "user", content: user }],
        max_tokens: maxTokens
      });
      const result = (out && (out.response || out.result || out)) || "";
      return j({ summary: result, result: result, model: MODEL });
    } catch (e) {
      return j({ error: String(e) }, 502);
    }
  }
};
