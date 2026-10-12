// Cloudflare Worker: сервер ИИ для наших приложений.
// Дикта: онлайн-итоги (/summarize). Адвокат (task 061): поле "system" = системный промпт.
// v3 (task 098, 12.10.2026): приём gzip-тел (Content-Encoding: gzip); режимы Дикты
//   mode:"chunk" (конспект фрагмента) и mode:"final" (итог по конспектам частей);
//   одиночный режим и Адвокат без изменений.
// Модель — Workers AI (llama-3.3-70b). Секрет APP_KEY — Variable (Secret) воркера.

const MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type,x-app-key,content-encoding",
  "Access-Control-Allow-Methods": "POST,OPTIONS"
};
const j = (o, s = 200) => new Response(JSON.stringify(o), {
  status: s, headers: { "content-type": "application/json", ...CORS }
});

// task 098: тело может прийти сжатым (Content-Encoding: gzip).
async function readJsonBody(request) {
  const enc = (request.headers.get("content-encoding") || "").toLowerCase();
  if (enc.includes("gzip")) {
    const stream = request.body.pipeThrough(new DecompressionStream("gzip"));
    const buf = await new Response(stream).arrayBuffer();
    return JSON.parse(new TextDecoder().decode(buf));
  }
  return await request.json();
}

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
    try { body = await readJsonBody(request); } catch (e) { return j({ error: "bad json" }, 400); }
    const text = (body.text || "").trim();
    const lang = body.lang || "ru";
    const mode = typeof body.mode === "string" ? body.mode : "";

    let sys, user, maxTokens;
    if (typeof body.system === "string" && body.system.trim()) {
      // Общий режим (Адвокат и другие задачи по системному промпту)
      if (text.length < 1) return j({ error: "text too short" }, 400);
      sys = body.system.trim();
      user = text.slice(0, 60000);
      maxTokens = Math.min(Number(body.max_tokens) || 3000, 4096);
    } else if (mode === "chunk") {
      // task 098: конспект одного фрагмента длинной записи
      if (text.length < 20) return j({ error: "text too short" }, 400);
      sys = "Ты делаешь краткий конспект фрагмента деловой расшифровки. Пиши только то, что есть в тексте, без выдумок и без вступлений.";
      user = `Язык ответа: ${lang}. Составь краткий конспект фрагмента: решения, договорённости, задачи (пунктами), цифры и даты. Только важное, кратко.\n\nФРАГМЕНТ:\n${text.slice(0, 20000)}`;
      maxTokens = 500;
    } else if (mode === "final") {
      // task 098: сводный итог по конспектам частей
      if (text.length < 10) return j({ error: "text too short" }, 400);
      sys = "Ты собираешь один сводный деловой итог из конспектов частей одной расшифровки. Пиши только то, что есть в материале, без выдумок; убирай повторы.";
      user = `Язык ответа: ${lang}. Ниже по порядку — конспекты частей одной записи. Собери ОДИН сводный итог по структуре: «О чём говорили», «О чём договорились», «Задачи» (пунктами), «Цифры и даты». Убери повторы, объедини близкие пункты.\n\nКОНСПЕКТЫ ЧАСТЕЙ:\n${text.slice(0, 60000)}`;
      maxTokens = 1100;
    } else {
      // Режим итогов (Дикта, короткие записи) — как было
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
