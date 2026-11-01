// Ретранслятор Spotify для Hutred: из России Spotify напрямую не открывается
// (подменённый сертификат / замедление), а облако Hutred — открывается.
// Принимает ?u=<адрес Spotify> и пересылает запрос как есть.
const ALLOWED = new Set(["accounts.spotify.com", "api.spotify.com", "open.spotify.com"]);

Deno.serve(async (req) => {
  const target = new URL(req.url).searchParams.get("u");
  let url: URL;
  try {
    url = new URL(target ?? "");
  } catch {
    return new Response("bad url", { status: 400 });
  }
  if (url.protocol !== "https:" || !ALLOWED.has(url.hostname)) {
    return new Response("host not allowed", { status: 403 });
  }
  const headers = new Headers();
  for (const h of ["authorization", "content-type", "accept", "accept-language", "user-agent"]) {
    const v = req.headers.get(h === "authorization" ? "x-spotify-auth" : h);
    if (v) headers.set(h, v);
  }
  const res = await fetch(url, {
    method: req.method,
    headers,
    body: req.method === "GET" || req.method === "HEAD" ? undefined : await req.arrayBuffer(),
  });
  const out = new Headers();
  for (const h of ["content-type", "retry-after"]) {
    const v = res.headers.get(h);
    if (v) out.set(h, v);
  }
  return new Response(res.body, { status: res.status, headers: out });
});
