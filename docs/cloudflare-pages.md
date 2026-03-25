# Cloudflare Pages Deployment

<div class="doc-kicker">Docs Site Operations</div>

This repo now ships a static docs site built from `docs/` with VitePress and targeted at Cloudflare Pages.

## Recommended operating model

Use **Cloudflare Pages Git integration** for deployment and keep **GitHub Actions** limited to docs validation.

That split keeps the setup simple:

- Cloudflare Pages owns production deploys and preview URLs
- GitHub Actions verifies that the site still builds cleanly
- no Cloudflare API token is required in GitHub just to keep the docs healthy

This repo now includes a docs-only workflow at [`.github/workflows/docs-site.yml`](https://github.com/mud-the-developer/open-ran-agent/blob/main/.github/workflows/docs-site.yml) that runs `npm ci` and `npm run docs:build`, then uploads the generated static site as a CI artifact.

## Local development

```bash
npm install
npm run docs:dev
```

The development server runs at `http://127.0.0.1:4173`.

## Production build

```bash
npm run docs:build
```

The generated static output lands in `docs/.vitepress/dist`.

## Local static preview

```bash
npm run docs:preview
```

## Cloudflare Pages configuration

This repo includes a `wrangler.toml` configured for Pages:

```toml
name = "open-ran-agent-docs"
compatibility_date = "2026-03-25"
pages_build_output_dir = "./docs/.vitepress/dist"
```

### Git-integrated Pages project

Use these values in the Cloudflare dashboard:

- **Framework preset:** None
- **Build command:** `npm ci && npm run docs:build`
- **Build output directory:** `docs/.vitepress/dist`
- **Production branch:** `main`
- **Root directory:** repository root

Recommended **Build watch paths** for this repo:

- `docs/**`
- `package.json`
- `package-lock.json`
- `wrangler.toml`

This keeps unrelated umbrella runtime work from triggering a Pages rebuild when the docs site itself has not changed.

### Direct Upload with Wrangler

Use this as a fallback or for one-off preview pushes. It is not the recommended steady-state path for this repo.

After building locally:

```bash
npx wrangler pages project create
npx wrangler pages deploy docs/.vitepress/dist
```

## Suggested deployment model

Use Git integration for the steady state, keep `wrangler pages deploy` around for preview pushes or one-off direct uploads, and let GitHub Actions stay on build verification plus artifact upload only.

## GitHub Actions behavior

The docs workflow triggers only when docs-site inputs change:

- `docs/**`
- `package.json`
- `package-lock.json`
- `wrangler.toml`

On every matching push to `main` and every matching pull request, it will:

1. install dependencies with `npm ci`
2. build the site with `npm run docs:build`
3. upload `docs/.vitepress/dist` as a CI artifact

## What this site includes

- home page and documentation hub
- architecture guide and ADR index
- backlog surface
- existing SVG figures and logo assets
- local search through VitePress
