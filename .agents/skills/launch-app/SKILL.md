---
name: launch-app
description: Launch the Open RAN Agent dashboard or docs UI for runtime validation.
---

# Launch App

Prefer the runtime dashboard for app-touching changes:

```bash
mix deps.get
bin/ran-dashboard
```

Expected runtime signals:
- UI root: `http://127.0.0.1:4050/`
- Health probe: `http://127.0.0.1:4050/api/health`
- Snapshot JSON: `http://127.0.0.1:4050/api/dashboard`

Notes:
- `bin/ran-dashboard` auto-compiles the umbrella apps when sources changed.
- Default bind is `127.0.0.1:4050`.
- Use this path when validating changes under `apps/`, `bin/`, deploy flows, or the dashboard UX.

If the change is docs-site only, use the docs server instead:

```bash
npm ci --ignore-scripts
npm run docs:dev
```

Docs runtime signals:
- Docs UI: `http://127.0.0.1:4173/`
- Production-style validation: `npm run docs:build`
