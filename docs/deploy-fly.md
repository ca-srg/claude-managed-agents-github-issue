# Deploying to Fly.io

This guide walks through hosting `github-issue-agent` on Fly.io.

> **App name caveat.** Fly.io blocks any app name containing the substring
> `github` (anti-phishing filter), so the bundled `fly.toml` uses
> `gh-issue-agent`. Pick whatever you like, just avoid `github`.

> **Ingress note.** The committed `fly.toml` does NOT contain
> `[http_service]`, `[[services]]`, or `[[services.ports]]`, so the app is
> not registered with the Fly proxy and `<app>.fly.dev` will not route to
> it. To expose the server publicly you must either (a) add an
> `[http_service]` block to `fly.toml` and redeploy, or (b) front the
> machine with your own ingress (reverse proxy / VPN / etc.) on the Fly
> private network.

```
[ User Browser ]
    │  (your chosen ingress: http_service / private network / external proxy)
    ▼
[ Fly Machine (nrt) ]
  ├─ bun run index.ts          (Hono SSR + run queue + SSE)
  └─ /data volume → SQLite + agent state
```

The repo ships these supporting files:

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage build: deps → Tailwind CSS → runtime |
| `scripts/start.sh` | Spawns `bun`, sets up state symlink, propagates signals |
| `fly.toml` | Single-machine config, `/data` volume, TCP healthcheck |
| `.dockerignore` | Strips local state and tests from build context |

## Prerequisites

- A Fly.io account + `flyctl` installed (`brew install flyctl` / curl install)
- Anthropic API key, GitHub PAT (`repo` for classic; `contents:read`,
  `issues:write`, `pull_requests:write` for fine-grained)

## 1. Create the Fly app

```bash
# from repo root
fly apps create gh-issue-agent --org personal

# 1 GB volume in the same region
fly volumes create data --size 1 --region nrt --app gh-issue-agent
```

If you prefer `fly launch`, be aware that it rewrites `fly.toml` and may
inject an `[http_service]` block. Review the diff before committing.

## 2. Set Fly secrets

```bash
fly secrets set --app gh-issue-agent \
  ANTHROPIC_API_KEY='sk-ant-...' \
  GITHUB_TOKEN='ghp_...'
```

## 3. Deploy

```bash
fly deploy --app gh-issue-agent
```

Watch the logs for `Listening on http://0.0.0.0:3000`:

```bash
fly logs --app gh-issue-agent
```

## 4. Day-to-day operations

```bash
# Tail logs
fly logs --app gh-issue-agent

# SSH into the running machine
fly ssh console --app gh-issue-agent

# Check disk usage (volume is mounted at /data)
fly ssh console --app gh-issue-agent -C 'df -h /data'

# Backup the SQLite db locally
fly ssh sftp get /data/dashboard.db ./dashboard.db.bak --app gh-issue-agent

# Re-deploy after code changes
fly deploy --app gh-issue-agent
```

## Troubleshooting

- **App responds with 502**
  → The machine crashed. Inspect with
    `fly ssh console --app gh-issue-agent` and `pgrep -fa bun`. If the
    process is gone, `fly machine restart`.

- **Run lock complaint after a crash**
  → `fly ssh console --app gh-issue-agent -C 'rm /data/agent-state/run.lock.lock'`.

- **`HOST` is `127.0.0.1`**
  → Something overrode `HOST`. Inside the container it must be `0.0.0.0`
    so external ingress can reach the server.

## Cost notes

- `shared-cpu-1x` 1 GB machine in `nrt` is roughly **$5 / month** if running
  24/7. The Fly free allowance covers up to 3 such VMs.
- `data` volume: $0.15 / GB-month.
- Anthropic billing dwarfs hosting cost (~$0.08 per session-hour at the time
  of writing). See `README.md`.
