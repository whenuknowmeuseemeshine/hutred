// Сервер Hutred: то, что нельзя доверять приложению.
//   POST /hutred/login          — вход по логину или почте (лимит попыток)
//   POST /hutred/spotify-token  — токен Spotify; секрет остаётся на сервере
//   POST /hutred/ai             — распознавание речи; ключ ИИ остаётся на сервере
// Ключи лежат в таблице app_secrets (её видит только админ и сервер).
import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });

const SECURITY_HEADERS = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "cache-control": "no-store",
};

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...SECURITY_HEADERS, ...extra },
  });
}

const fail = (status: number, error: string) => json({ error }, status);

function clientIp(req: Request) {
  return (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
}

/** true — можно, false — слишком часто. */
async function allow(bucket: string, max: number, seconds: number) {
  const { data, error } = await admin.rpc("rate_hit", { p_bucket: bucket, p_max: max, p_seconds: seconds });
  if (error) {
    console.error("rate_hit", error.message);
    return true; // лимиты не должны ломать приложение, если таблицы ещё нет
  }
  return data === true;
}

async function userOf(req: Request) {
  const h = req.headers.get("authorization") ?? "";
  const jwt = h.toLowerCase().startsWith("bearer ") ? h.slice(7) : "";
  if (!jwt || jwt === ANON) return null;
  const { data, error } = await admin.auth.getUser(jwt);
  return error ? null : data.user;
}

async function secret(key: string): Promise<Record<string, string> | null> {
  const { data } = await admin.from("app_secrets").select("value").eq("key", key).maybeSingle();
  return (data?.value as Record<string, string>) ?? null;
}

// ---------- Вход ----------

async function login(req: Request) {
  let body: { login?: unknown; password?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail(400, "bad json");
  }
  const loginRaw = typeof body.login === "string" ? body.login.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!loginRaw || loginRaw.length > 254 || !password || password.length > 200) {
    return fail(400, "Введи логин и пароль");
  }
  const ip = clientIp(req);
  if (!(await allow(`login-ip:${ip}`, 10, 300)) || !(await allow(`login:${loginRaw.toLowerCase()}`, 8, 300))) {
    return fail(429, "Слишком много попыток. Подожди 5 минут");
  }
  let email = loginRaw;
  if (!loginRaw.includes("@")) {
    if (!/^[A-Za-z0-9_.]{3,24}$/.test(loginRaw)) return fail(400, "Неверный логин или пароль");
    const { data } = await admin.rpc("email_for_username", { p_username: loginRaw });
    if (typeof data !== "string" || !data) return fail(400, "Неверный логин или пароль");
    email = data;
  }
  const res = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { "content-type": "application/json", apikey: ANON },
    body: JSON.stringify({ email, password }),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) {
    const code = String(j.error_code ?? j.code ?? "");
    if (code === "email_not_confirmed") return fail(400, "Сначала подтверди почту — ссылка в письме");
    return fail(400, "Неверный логин или пароль");
  }
  // Отдаём только то, что нужно приложению, чтобы восстановить сессию.
  return json({ refresh_token: j.refresh_token, access_token: j.access_token });
}

// ---------- Spotify ----------

let spotifyCache: { token: string; until: number } | null = null;

async function spotifyToken(req: Request) {
  const user = await userOf(req);
  if (!user) return fail(401, "Войди в аккаунт");
  if (!(await allow(`spotify:${user.id}`, 20, 60))) return fail(429, "Слишком часто");
  if (spotifyCache && spotifyCache.until > Date.now() + 120_000) {
    return json({ access_token: spotifyCache.token, expires_in: Math.floor((spotifyCache.until - Date.now()) / 1000) });
  }
  const s = await secret("spotify");
  if (!s?.id || !s?.secret) return fail(503, "Spotify не настроен админом");
  const res = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      authorization: "Basic " + btoa(`${s.id}:${s.secret}`),
      "content-type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (!res.ok) return fail(502, `Spotify не принял ключи (${res.status})`);
  const j = await res.json();
  const ttl = Number(j.expires_in ?? 3600);
  spotifyCache = { token: j.access_token, until: Date.now() + ttl * 1000 };
  return json({ access_token: j.access_token, expires_in: ttl });
}

// ---------- ИИ ----------

const MAX_AUDIO = 25 * 1024 * 1024;

async function ai(req: Request) {
  const user = await userOf(req);
  if (!user) return fail(401, "Войди в аккаунт");
  if (!(await allow(`ai-min:${user.id}`, 4, 60)) || !(await allow(`ai-day:${user.id}`, 60, 86400))) {
    return fail(429, "Лимит ИИ: 4 трека в минуту и 60 в день");
  }
  const len = Number(req.headers.get("content-length") ?? "0");
  if (len > MAX_AUDIO + 1024 * 1024) return fail(413, "Файл больше 25 МБ");
  const s = await secret("ai");
  if (!s?.key || !s?.baseUrl) return fail(503, "ИИ не настроен админом");
  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return fail(400, "bad form");
  }
  const file = form.get("file");
  if (!(file instanceof File) || file.size === 0 || file.size > MAX_AUDIO) return fail(400, "Нужен звуковой файл до 25 МБ");
  const out = new FormData();
  out.append("file", file, file.name || "track.mp3");
  out.append("model", s.model || "whisper-large-v3");
  out.append("response_format", "verbose_json");
  out.append("timestamp_granularities[]", "word");
  for (const k of ["prompt", "language"]) {
    const v = form.get(k);
    if (typeof v === "string" && v.length > 0 && v.length <= 4000) out.append(k, v);
  }
  const base = s.baseUrl.replace(/\/+$/, "");
  if (!base.startsWith("https://")) return fail(503, "Адрес ИИ должен быть https");
  const res = await fetch(`${base}/audio/transcriptions`, {
    method: "POST",
    headers: { authorization: `Bearer ${s.key}` },
    body: out,
  });
  const text = await res.text();
  if (!res.ok) return fail(502, `Сервис ИИ ответил ${res.status}`);
  return new Response(text, { status: 200, headers: { "content-type": "application/json", ...SECURITY_HEADERS } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "POST only");
  const path = new URL(req.url).pathname.replace(/\/+$/, "");
  try {
    if (path.endsWith("/login")) return await login(req);
    if (path.endsWith("/spotify-token")) return await spotifyToken(req);
    if (path.endsWith("/ai")) return await ai(req);
    return fail(404, "not found");
  } catch (e) {
    console.error(e);
    return fail(500, "Ошибка сервера");
  }
});
