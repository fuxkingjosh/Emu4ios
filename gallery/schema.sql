CREATE TABLE IF NOT EXISTS themes (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, author TEXT NOT NULL DEFAULT '', systems TEXT NOT NULL DEFAULT '',
  theme_json TEXT NOT NULL, preview BLOB, size INTEGER NOT NULL,
  likes INTEGER NOT NULL DEFAULT 0, downloads INTEGER NOT NULL DEFAULT 0, reports INTEGER NOT NULL DEFAULT 0,
  hidden INTEGER NOT NULL DEFAULT 0, uploader TEXT NOT NULL, ip_hash TEXT NOT NULL, created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS themes_new ON themes(hidden, created_at DESC);
CREATE INDEX IF NOT EXISTS themes_popular ON themes(hidden, likes DESC, downloads DESC);
CREATE INDEX IF NOT EXISTS themes_ip ON themes(ip_hash, created_at);
CREATE TABLE IF NOT EXISTS likes (theme_id TEXT NOT NULL, device TEXT NOT NULL, PRIMARY KEY (theme_id, device));
CREATE TABLE IF NOT EXISTS reports (theme_id TEXT NOT NULL, device TEXT NOT NULL, reason TEXT, created_at INTEGER NOT NULL, PRIMARY KEY (theme_id, device));
