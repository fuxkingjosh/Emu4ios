// Emu4ios theme gallery — Cloudflare Worker + D1.
// Browse, download, upload, like and report themes. No accounts: each device has a random ID.

const MAX_THEME_BYTES = 1_800_000;   // D1 rows are capped at ~2 MB
const MAX_PREVIEW_BYTES = 200_000;
const UPLOADS_PER_DAY = 10;
const HIDE_AFTER_REPORTS = 3;
const BLOCKED_WORDS = ["nigg", "fag", "retard", "kys", "nazi", "hitler", "porn", "sex", "nude", "rape", "cunt"];

const json = (data, status = 200, extra = {}) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "access-control-allow-origin": "*", ...extra },
  });
const error = (message, status = 400) => json({ error: message }, status);

async function sha256(text) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const deviceHash = (device) => sha256("emu4ios-device:" + String(device || "").slice(0, 100));
const clean = (s, max) => String(s ?? "").replace(/[\u0000-\u001f]/g, "").trim().slice(0, max);
const isOffensive = (s) => BLOCKED_WORDS.some((w) => s.toLowerCase().replace(/[^a-z]/g, "").includes(w));

function fromBase64(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const SUMMARY = "id, name, author, systems, size, likes, downloads, created_at";

async function list(url, env) {
  const sort = url.searchParams.get("sort") === "new" ? "created_at DESC" : "likes DESC, downloads DESC, created_at DESC";
  const limit = Math.min(Number(url.searchParams.get("limit")) || 30, 60);
  const offset = Math.max(Number(url.searchParams.get("offset")) || 0, 0);
  const system = clean(url.searchParams.get("system"), 8);
  const q = clean(url.searchParams.get("q"), 40);
  let sql = `SELECT ${SUMMARY} FROM themes WHERE hidden = 0`;
  const args = [];
  if (system) { sql += " AND (systems = '' OR systems LIKE ?)"; args.push(`%${system}%`); }
  if (q) { sql += " AND (name LIKE ? OR author LIKE ?)"; args.push(`%${q}%`, `%${q}%`); }
  sql += ` ORDER BY ${sort} LIMIT ? OFFSET ?`;
  args.push(limit + 1, offset);
  const { results } = await env.DB.prepare(sql).bind(...args).all();
  const more = results.length > limit;
  return json({ themes: results.slice(0, limit), next: more ? offset + limit : null }, 200,
              { "cache-control": "public, max-age=30" });
}

async function getTheme(id, env) {
  const row = await env.DB.prepare("SELECT theme_json FROM themes WHERE id = ? AND hidden = 0").bind(id).first();
  if (!row) return error("Theme not found", 404);
  await env.DB.prepare("UPDATE themes SET downloads = downloads + 1 WHERE id = ?").bind(id).run();
  return new Response(row.theme_json, { headers: { "content-type": "application/json; charset=utf-8" } });
}

async function getPreview(id, env) {
  const row = await env.DB.prepare("SELECT preview FROM themes WHERE id = ? AND hidden = 0").bind(id).first();
  if (!row || !row.preview) return error("No preview", 404);
  return new Response(new Uint8Array(row.preview), {
    headers: { "content-type": "image/png", "cache-control": "public, max-age=86400" },
  });
}

async function upload(request, env) {
  const body = await request.text();
  if (body.length > MAX_THEME_BYTES + MAX_PREVIEW_BYTES * 1.4 + 10_000) return error("Theme is too big (max 1.8 MB)", 413);
  let payload;
  try { payload = JSON.parse(body); } catch { return error("Invalid upload"); }
  const theme = payload.theme;
  if (!theme || typeof theme !== "object" || typeof theme.name !== "string") return error("Missing theme");
  const name = clean(theme.name, 40) || "Untitled";
  const author = clean(theme.author, 30);
  if (isOffensive(name) || isOffensive(author)) return error("Please choose a different name");

  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  const ipHash = await sha256("emu4ios-ip:" + ip);
  const since = Date.now() - 86_400_000;
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM themes WHERE ip_hash = ? AND created_at > ?")
    .bind(ipHash, since).first();
  if (recent.n >= UPLOADS_PER_DAY) return error("Upload limit reached — try again tomorrow", 429);

  const id = crypto.randomUUID();
  theme.id = id;
  theme.name = name;
  theme.author = author;
  theme.isBuiltIn = false;
  const themeJSON = JSON.stringify(theme);
  if (themeJSON.length > MAX_THEME_BYTES) return error("Theme is too big (max 1.8 MB). Try smaller GIFs or pictures.", 413);

  let preview = null;
  if (typeof payload.preview === "string") {
    try { preview = fromBase64(payload.preview); } catch { preview = null; }
    if (preview && (preview.length > MAX_PREVIEW_BYTES || preview[0] !== 0x89 || preview[1] !== 0x50)) preview = null;
  }
  const systems = Array.isArray(payload.systems) ? payload.systems.map((s) => clean(s, 8)).join(",") : "";
  await env.DB.prepare(
    "INSERT INTO themes (id, name, author, systems, theme_json, preview, size, uploader, ip_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  ).bind(id, name, author, systems, themeJSON, preview, themeJSON.length, await deviceHash(payload.device), ipHash, Date.now()).run();
  return json({ id }, 201);
}

async function like(id, request, env) {
  const { device } = await request.json().catch(() => ({}));
  if (!device) return error("Missing device");
  const dev = await deviceHash(device);
  const existing = await env.DB.prepare("SELECT 1 FROM likes WHERE theme_id = ? AND device = ?").bind(id, dev).first();
  if (existing) {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM likes WHERE theme_id = ? AND device = ?").bind(id, dev),
      env.DB.prepare("UPDATE themes SET likes = MAX(likes - 1, 0) WHERE id = ?").bind(id),
    ]);
  } else {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO likes (theme_id, device) VALUES (?, ?)").bind(id, dev),
      env.DB.prepare("UPDATE themes SET likes = likes + 1 WHERE id = ?").bind(id),
    ]);
  }
  const row = await env.DB.prepare("SELECT likes FROM themes WHERE id = ?").bind(id).first();
  return json({ liked: !existing, likes: row ? row.likes : 0 });
}

async function report(id, request, env) {
  const { device, reason } = await request.json().catch(() => ({}));
  if (!device) return error("Missing device");
  const dev = await deviceHash(device);
  const inserted = await env.DB.prepare("INSERT OR IGNORE INTO reports (theme_id, device, reason, created_at) VALUES (?, ?, ?, ?)")
    .bind(id, dev, clean(reason, 200), Date.now()).run();
  if (inserted.meta.changes > 0) {
    await env.DB.prepare("UPDATE themes SET reports = reports + 1, hidden = CASE WHEN reports + 1 >= ? THEN 1 ELSE hidden END WHERE id = ?")
      .bind(HIDE_AFTER_REPORTS, id).run();
  }
  return json({ ok: true });
}

async function remove(id, request, env) {
  const { device } = await request.json().catch(() => ({}));
  const dev = await deviceHash(device);
  const res = await env.DB.prepare("DELETE FROM themes WHERE id = ? AND uploader = ?").bind(id, dev).run();
  if (!res.meta.changes) return error("Only the person who uploaded a theme can delete it", 403);
  await env.DB.prepare("DELETE FROM likes WHERE theme_id = ?").bind(id).run();
  return json({ ok: true });
}

async function mine(request, env) {
  const url = new URL(request.url);
  const dev = await deviceHash(url.searchParams.get("device"));
  const { results } = await env.DB.prepare(`SELECT ${SUMMARY}, hidden FROM themes WHERE uploader = ? ORDER BY created_at DESC LIMIT 100`)
    .bind(dev).all();
  return json({ themes: results });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean); // ["v1","themes",id,action]
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { headers: { "access-control-allow-origin": "*", "access-control-allow-methods": "GET,POST,DELETE", "access-control-allow-headers": "content-type" } });
      }
      if (parts.length === 0) return json({ name: "Emu4ios Theme Gallery", ok: true });
      if (parts[0] !== "v1" || parts[1] !== "themes") return error("Not found", 404);
      const id = parts[2];
      const action = parts[3];
      if (!id) {
        if (request.method === "GET") return list(url, env);
        if (request.method === "POST") return upload(request, env);
      } else if (id === "mine" && request.method === "GET") {
        return mine(request, env);
      } else if (!action) {
        if (request.method === "GET") return getTheme(id, env);
        if (request.method === "DELETE") return remove(id, request, env);
      } else if (action === "preview" && request.method === "GET") {
        return getPreview(id, env);
      } else if (action === "like" && request.method === "POST") {
        return like(id, request, env);
      } else if (action === "report" && request.method === "POST") {
        return report(id, request, env);
      }
      return error("Not found", 404);
    } catch (e) {
      return error("Server error", 500);
    }
  },
};
