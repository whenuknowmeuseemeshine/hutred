"""Hutred relay: посредник для друзей, у которых сервисы заблокированы.

Принимает запрос вида  GET /r?u=<адрес>  от приложения Hutred, проверяет,
что это вошедший пользователь Hutred (через Supabase), и сам скачивает
адрес — только с музыкальных сервисов из списка ниже. Ответ отдаётся
потоком, с поддержкой перемотки (Range).
"""
import hashlib
import os
import time
from urllib.parse import urlsplit

from aiohttp import ClientSession, ClientTimeout, TCPConnector, web

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")

# Только эти сервисы — из сервера не сделать прокси «для всего интернета».
ALLOWED = (
    "youtube.com", "youtu.be", "googlevideo.com", "ytimg.com", "googleapis.com",
    "soundcloud.com", "sndcdn.com", "soundcloud.cloud",
    "spotify.com", "scdn.co", "spotifycdn.com",
    "genius.com", "groq.com", "lrclib.net",
    "itunes.apple.com", "mzstatic.com",
    "music.yandex.ru", "api.music.yandex.net",
)
# Эти заголовки не пересылаем ни туда, ни обратно.
HOP = {
    "host", "connection", "keep-alive", "proxy-authorization", "te", "trailer",
    "transfer-encoding", "upgrade", "content-length", "apikey", "x-hutred-user",
    "x-spotify-auth", "x-forwarded-for", "x-forwarded-proto", "x-forwarded-host",
    "via", "x-real-ip",
}
PASS_BACK = (
    "content-type", "content-length", "content-range", "accept-ranges",
    "content-encoding", "cache-control", "etag", "last-modified", "location",
)

_auth_cache: dict[str, float] = {}
stats = {"started": time.time(), "requests": 0, "bytes": 0, "denied": 0, "users": set()}


def allowed(url: str) -> bool:
    try:
        p = urlsplit(url)
    except ValueError:
        return False
    if p.scheme not in ("http", "https") or not p.hostname:
        return False
    h = p.hostname.lower()
    return any(h == d or h.endswith("." + d) for d in ALLOWED)


async def check_user(app: web.Application, token: str | None, key: str | None) -> bool:
    """Пускаем только вошедших в Hutred: токен проверяет сам Supabase."""
    if not token or not key:
        return False
    h = hashlib.sha256(token.encode()).hexdigest()
    exp = _auth_cache.get(h)
    if exp and exp > time.time():
        return True
    try:
        async with app["session"].get(
            f"{SUPABASE_URL}/auth/v1/user",
            headers={"apikey": key, "Authorization": f"Bearer {token}"},
            timeout=ClientTimeout(total=8),
        ) as r:
            if r.status != 200:
                return False
            data = await r.json()
            stats["users"].add(data.get("id"))
    except Exception:
        return False
    _auth_cache[h] = time.time() + 15 * 60
    if len(_auth_cache) > 5000:
        now = time.time()
        for k in [k for k, v in _auth_cache.items() if v < now]:
            _auth_cache.pop(k, None)
    return True


async def relay(req: web.Request) -> web.StreamResponse:
    target = req.query.get("u", "")
    if not allowed(target):
        stats["denied"] += 1
        return web.Response(status=403, text="host not allowed")
    token = req.headers.get("x-hutred-user") or req.query.get("t")
    key = req.headers.get("apikey") or req.query.get("k")
    if not await check_user(req.app, token, key):
        stats["denied"] += 1
        return web.Response(status=401, text="sign in to Hutred")

    headers = {k: v for k, v in req.headers.items() if k.lower() not in HOP}
    spotify_auth = req.headers.get("x-spotify-auth")
    if spotify_auth:
        headers["Authorization"] = spotify_auth
    body = await req.read() if req.can_read_body else None
    stats["requests"] += 1
    try:
        upstream = await req.app["session"].request(
            req.method, target, headers=headers, data=body or None,
            allow_redirects=True, timeout=ClientTimeout(total=None, sock_connect=15, sock_read=60),
        )
    except Exception as e:
        return web.Response(status=502, text=f"upstream error: {e}")
    async with upstream:
        resp = web.StreamResponse(status=upstream.status)
        for name in PASS_BACK:
            v = upstream.headers.get(name)
            if v is not None:
                resp.headers[name] = v
        await resp.prepare(req)
        async for chunk in upstream.content.iter_chunked(64 * 1024):
            stats["bytes"] += len(chunk)
            await resp.write(chunk)
        await resp.write_eof()
        return resp


async def health(_: web.Request) -> web.Response:
    up = int(time.time() - stats["started"])
    return web.json_response({
        "ok": True,
        "uptime_sec": up,
        "requests": stats["requests"],
        "gb_sent": round(stats["bytes"] / 1e9, 3),
        "users_seen": len(stats["users"]),
        "denied": stats["denied"],
    })


async def on_start(app: web.Application) -> None:
    app["session"] = ClientSession(
        connector=TCPConnector(limit=200, ttl_dns_cache=300),
        auto_decompress=False,
    )


async def on_stop(app: web.Application) -> None:
    await app["session"].close()


def main() -> None:
    app = web.Application(client_max_size=8 * 1024 * 1024)
    app.on_startup.append(on_start)
    app.on_cleanup.append(on_stop)
    app.router.add_route("*", "/r", relay)
    app.router.add_get("/health", health)
    web.run_app(app, host="127.0.0.1", port=8080, access_log=None)


if __name__ == "__main__":
    main()
