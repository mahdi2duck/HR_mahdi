-- Create proxies table for the proxy farm
CREATE TABLE IF NOT EXISTS proxies (
  id            BIGINT PRIMARY KEY,
  tunnel_url    TEXT UNIQUE NOT NULL,
  proxy_url     TEXT NOT NULL,
  runner_ip     TEXT,
  status        TEXT DEFAULT 'active' CHECK (status IN ('active', 'dead', 'stale')),
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_proxies_status ON proxies(status);
CREATE INDEX IF NOT EXISTS idx_proxies_created ON proxies(created_at DESC);

-- Enable RLS (locked down â€” only service role can write)
ALTER TABLE proxies ENABLE ROW LEVEL SECURITY;

-- Service role can do everything
CREATE POLICY "Service role full access" ON proxies
  FOR ALL
  USING (auth.role() = 'service_role');

-- Anyone can read (for your apps)
CREATE POLICY "Public read access" ON proxies
  FOR SELECT
  USING (true);
