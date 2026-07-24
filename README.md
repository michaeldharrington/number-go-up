# Number go up

![Click count](https://img.shields.io/endpoint?url=https%3A%2F%2Fglobal-click-counter.mdharr.workers.dev%2Fshield&style=for-the-badge)

A macOS menu bar app with one counter, shared by everyone running it. You
click. Number go up. That's the app.

The count lives in your menu bar (`8.4M`-style). Open the dropdown for the
full total, the Click button, your lifetime contribution, a countdown to
your next click, and a 24-hour sparkline.

## Install

1. Download `GlobalClick.zip` from [Releases](../../releases)
2. Unzip, drag **GlobalClick.app** to Applications, launch
3. Click

No accounts, no login. The app stashes an anonymous UUID in your Keychain,
and that's the only thing that knows who you are.

Requires macOS 14+.

## How it works

```
/client   SwiftUI MenuBarExtra app — no dependencies
/server   Cloudflare Worker + Durable Object + KV
```

- A single Durable Object (`idFromName("global")`) holds the one true
  total. There's exactly one instance worldwide, so increments serialize
  without locks. An hourly alarm snapshots the total into a rolling
  24-point history for the sparkline.
- KV handles per-user state: rate limiting (1 click/hour per client, 5/hour
  per IP, and IPs are stored only as SHA-256 hashes) plus lifetime click
  counts. The Durable Object never sees who clicked.
- The client polls every 60s (10s while the menu is open), pauses during
  sleep, and updates optimistically on click. If the server says 429, it
  snaps back and shows a countdown.

### API

All endpoints except `/history` require `X-Client-Id: <uuid>`.

| Endpoint | Returns |
|---|---|
| `GET /count` | `{ total, yourClicks, nextClickAt }` — `nextClickAt` is null when you can click now |
| `POST /click` | Same shape; `429 { error, nextClickAt }` when rate-limited |
| `GET /history` | `{ history: [{ ts, total }] }` — last 24 hourly snapshots |
| `GET /shield` | [shields.io endpoint-badge](https://shields.io/badges/endpoint-badge) JSON — powers the badge above, no header needed |

## Development

### Server

```bash
cd server
npm install
npm test        # Vitest (rate limiting + Durable Object)
npm run dev     # local server at http://localhost:8787 — KV/DO simulated, no account needed
```

Smoke test:

```bash
ID=$(uuidgen | tr A-Z a-z)
curl -H "X-Client-Id: $ID" http://localhost:8787/count
curl -X POST -H "X-Client-Id: $ID" http://localhost:8787/click
```

Deploy (free Cloudflare plan works):

```bash
npx wrangler login
npx wrangler kv namespace create RATE_LIMIT
# paste the returned id into wrangler.toml (REPLACE_WITH_KV_NAMESPACE_ID)
npx wrangler deploy
```

### Client

```bash
cd client
./make-app.sh          # debug-ish local build → GlobalClick.app
open GlobalClick.app
```

The server URL is one constant in
[`client/Sources/GlobalClick/AppConfig.swift`](client/Sources/GlobalClick/AppConfig.swift)
— `http://localhost:8787` for local dev, your `workers.dev` URL for
production. Rebuild after changing it.

`swift run` works for quick iteration, but notifications need the real
`.app` bundle and you'll get a Dock icon.

### Releasing

`client/make-release.sh` builds a universal binary, signs it with your
Developer ID, notarizes it with `notarytool`, staples the ticket, and
drops `dist/GlobalClick.zip` ready for a GitHub Release. One-time
credential setup is documented at the top of the script.

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./make-release.sh
```

## License

[MIT](LICENSE)
