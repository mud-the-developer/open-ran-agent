import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import process from "node:process";
import { renderToString } from "@antv/infographic/ssr";
import { chromium } from "playwright-core";

const repoRoot = process.cwd();
const chromiumPath = process.env.CHROMIUM_PATH || "/usr/bin/chromium";

const figures = [
  {
    id: "architecture-overview",
    group: "architecture overview",
    sourceRel: "docs/assets/infographics/architecture-overview.infographic",
    svgRel: "docs/assets/figures/architecture-overview.svg",
    previewRel: "output/playwright/readme-figures-svg/architecture-overview.png",
    primary: true
  },
  {
    id: "architecture-overview-lr-badge",
    group: "architecture overview",
    sourceRel: "docs/assets/infographics/variants/architecture-overview-lr-badge.infographic",
    svgRel: "docs/assets/figures/variants/architecture-overview-lr-badge.svg",
    previewRel: "output/playwright/readme-figures-svg/architecture-overview-lr-badge.png"
  },
  {
    id: "architecture-overview-sequence",
    group: "architecture overview",
    sourceRel: "docs/assets/infographics/variants/architecture-overview-sequence.infographic",
    svgRel: "docs/assets/figures/variants/architecture-overview-sequence.svg",
    previewRel: "output/playwright/readme-figures-svg/architecture-overview-sequence.png"
  },
  {
    id: "ranctl-lifecycle",
    group: "ranctl lifecycle",
    sourceRel: "docs/assets/infographics/ranctl-lifecycle.infographic",
    svgRel: "docs/assets/figures/ranctl-lifecycle.svg",
    previewRel: "output/playwright/readme-figures-svg/ranctl-lifecycle.png",
    primary: true
  },
  {
    id: "ranctl-lifecycle-lr-compact",
    group: "ranctl lifecycle",
    sourceRel: "docs/assets/infographics/variants/ranctl-lifecycle-lr-compact.infographic",
    svgRel: "docs/assets/figures/variants/ranctl-lifecycle-lr-compact.svg",
    previewRel: "output/playwright/readme-figures-svg/ranctl-lifecycle-lr-compact.png"
  },
  {
    id: "ranctl-lifecycle-sequence",
    group: "ranctl lifecycle",
    sourceRel: "docs/assets/infographics/variants/ranctl-lifecycle-sequence.infographic",
    svgRel: "docs/assets/figures/variants/ranctl-lifecycle-sequence.svg",
    previewRel: "output/playwright/readme-figures-svg/ranctl-lifecycle-sequence.png"
  },
  {
    id: "target-host-deploy",
    group: "target-host deploy",
    sourceRel: "docs/assets/infographics/target-host-deploy.infographic",
    svgRel: "docs/assets/figures/target-host-deploy.svg",
    previewRel: "output/playwright/readme-figures-svg/target-host-deploy.png",
    primary: true
  },
  {
    id: "target-host-deploy-lr-compact",
    group: "target-host deploy",
    sourceRel: "docs/assets/infographics/variants/target-host-deploy-lr-compact.infographic",
    svgRel: "docs/assets/figures/variants/target-host-deploy-lr-compact.svg",
    previewRel: "output/playwright/readme-figures-svg/target-host-deploy-lr-compact.png"
  },
  {
    id: "target-host-deploy-sequence",
    group: "target-host deploy",
    sourceRel: "docs/assets/infographics/variants/target-host-deploy-sequence.infographic",
    svgRel: "docs/assets/figures/variants/target-host-deploy-sequence.svg",
    previewRel: "output/playwright/readme-figures-svg/target-host-deploy-sequence.png"
  }
];

const galleryRel = "output/playwright/readme-figures-svg/gallery.html";
const galleryPreviewRel = "output/playwright/readme-figures-svg/gallery.png";
const themeCheckRel = "output/playwright/readme-figures-svg/theme-check.html";
const themeCheckPreviewRel = "output/playwright/readme-figures-svg/theme-check.png";

function repoPath(relativePath) {
  return path.join(repoRoot, relativePath);
}

function contentTypeFor(relativePath) {
  const ext = path.extname(relativePath).toLowerCase();

  switch (ext) {
    case ".html":
      return "text/html; charset=utf-8";
    case ".js":
      return "text/javascript; charset=utf-8";
    case ".svg":
      return "image/svg+xml";
    case ".png":
      return "image/png";
    case ".infographic":
      return "text/plain; charset=utf-8";
    case ".css":
      return "text/css; charset=utf-8";
    default:
      return "application/octet-stream";
  }
}

function startStaticServer(rootDir) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(async (request, response) => {
      try {
        const url = new URL(request.url, "http://127.0.0.1");
        const pathname = decodeURIComponent(url.pathname === "/" ? "/docs/assets/render/index.html" : url.pathname);
        const relativePath = pathname.replace(/^\/+/, "");
        const absolutePath = path.join(rootDir, relativePath);

        if (!absolutePath.startsWith(rootDir)) {
          response.writeHead(403);
          response.end("forbidden");
          return;
        }

        const body = await fs.readFile(absolutePath);
        response.writeHead(200, { "content-type": contentTypeFor(relativePath) });
        response.end(body);
      } catch (error) {
        response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
        response.end(`not found: ${error.message}`);
      }
    });

    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      resolve({
        server,
        baseUrl: `http://127.0.0.1:${address.port}`
      });
    });
  });
}

async function ensureDirectories() {
  await fs.mkdir(repoPath("docs/assets/figures"), { recursive: true });
  await fs.mkdir(repoPath("docs/assets/figures/variants"), { recursive: true });
  await fs.mkdir(repoPath("output/playwright/readme-figures-svg"), { recursive: true });
}

async function exportSvgFiles() {
  for (const figure of figures) {
    const source = await fs.readFile(repoPath(figure.sourceRel), "utf8");
    const svg = addReadmePanelBackground(await renderToString(source));

    await fs.mkdir(path.dirname(repoPath(figure.svgRel)), { recursive: true });
    await fs.writeFile(repoPath(figure.svgRel), `${svg.trim()}\n`, "utf8");
    console.log(`exported ${figure.svgRel}`);
  }
}

function addReadmePanelBackground(svg) {
  const viewBoxMatch = svg.match(/viewBox="([^"]+)"/);

  if (!viewBoxMatch) {
    return svg;
  }

  const values = viewBoxMatch[1].trim().split(/\s+/).map(Number);

  if (values.length !== 4 || values.some((value) => Number.isNaN(value))) {
    return svg;
  }

  const [x, y, width, height] = values;
  const padding = Math.max(4, Math.round(Math.min(width, height) * 0.012));
  const innerX = x + padding;
  const innerY = y + padding;
  const innerWidth = width - padding * 2;
  const innerHeight = height - padding * 2;
  const cornerRadius = Math.max(18, Math.min(30, Math.round(Math.min(width, height) * 0.04)));
  const panel = `<g id="readme-panel-background"><rect x="${innerX}" y="${innerY}" width="${innerWidth}" height="${innerHeight}" rx="${cornerRadius}" ry="${cornerRadius}" fill="#fcfcfd" stroke="#cbd5e1" stroke-width="1.25" /></g>`;

  if (svg.includes(`<g id="infographic-container">`)) {
    return svg.replace(`<g id="infographic-container">`, `${panel}<g id="infographic-container">`);
  }

  return svg.replace(/<svg\b[^>]*>/, (prefix) => `${prefix}${panel}`);
}

async function writeGalleryHtml() {
  const groups = new Map();

  for (const figure of figures) {
    const bucket = groups.get(figure.group) || [];
    bucket.push(figure);
    groups.set(figure.group, bucket);
  }

  const sections = Array.from(groups.entries())
    .map(([group, items]) => {
      const cards = items
        .map((figure) => {
          const badge = figure.primary ? `<span class="badge">README</span>` : `<span class="badge alt">variant</span>`;

          return `
            <article class="card">
              <div class="card-head">
                <h2>${figure.id}</h2>
                ${badge}
              </div>
              <div class="card-meta">
                <code>${figure.sourceRel}</code>
              </div>
              <div class="card-body">
                <img src="/${figure.svgRel}" alt="${figure.id}" />
              </div>
            </article>
          `;
        })
        .join("\n");

      return `
        <section class="group">
          <div class="group-head">
            <h1>${group}</h1>
            <p>Primary README figure plus alternate SVG variants.</p>
          </div>
          <div class="grid">
            ${cards}
          </div>
        </section>
      `;
    })
    .join("\n");

  const html = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>README Figure Gallery</title>
    <style>
      :root {
        color-scheme: light;
        --bg: #f7f3eb;
        --panel: rgba(255, 252, 247, 0.96);
        --line: rgba(148, 163, 184, 0.24);
        --ink: #0f172a;
        --muted: #475569;
        --accent: #0f766e;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        font-family: Arial, Helvetica, sans-serif;
        background:
          radial-gradient(circle at top left, rgba(15, 118, 110, 0.08), transparent 26%),
          radial-gradient(circle at top right, rgba(29, 78, 216, 0.08), transparent 22%),
          linear-gradient(180deg, #fffef8, var(--bg));
        color: var(--ink);
      }
      .shell {
        width: min(1780px, calc(100vw - 48px));
        margin: 24px auto 48px;
      }
      .hero {
        padding: 24px 28px;
        border-radius: 28px;
        background: var(--panel);
        border: 1px solid rgba(214, 211, 209, 0.85);
        box-shadow: 0 24px 72px rgba(15, 23, 42, 0.08);
      }
      .hero h1 {
        margin: 0;
        font-size: 30px;
      }
      .hero p {
        margin: 10px 0 0;
        color: var(--muted);
        font-size: 15px;
      }
      .group {
        margin-top: 28px;
      }
      .group-head h1 {
        margin: 0 0 6px;
        font-size: 22px;
      }
      .group-head p {
        margin: 0 0 16px;
        color: var(--muted);
      }
      .grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 18px;
      }
      .card {
        padding: 18px;
        border-radius: 24px;
        background: var(--panel);
        border: 1px solid rgba(214, 211, 209, 0.9);
        box-shadow: 0 18px 40px rgba(15, 23, 42, 0.06);
      }
      .card-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }
      .card-head h2 {
        margin: 0;
        font-size: 16px;
        line-height: 1.3;
      }
      .badge {
        display: inline-flex;
        align-items: center;
        padding: 6px 10px;
        border-radius: 999px;
        background: rgba(209, 250, 229, 0.92);
        color: #065f46;
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }
      .badge.alt {
        background: rgba(219, 234, 254, 0.92);
        color: #1d4ed8;
      }
      .card-meta {
        margin-top: 8px;
        color: var(--muted);
        font-size: 12px;
      }
      .card-meta code {
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      }
      .card-body {
        margin-top: 14px;
        padding: 10px;
        border-radius: 18px;
        background: linear-gradient(180deg, rgba(255, 255, 255, 0.96), rgba(248, 250, 252, 0.9));
        border: 1px solid var(--line);
      }
      .card-body img {
        display: block;
        width: 100%;
        height: auto;
      }
    </style>
  </head>
  <body>
    <main class="shell">
      <section class="hero">
        <h1>README SVG figure gallery</h1>
        <p>Rendered with AntV Infographic SSR, then checked in a real browser before README selection.</p>
      </section>
      ${sections}
    </main>
  </body>
</html>
`;

  await fs.writeFile(repoPath(galleryRel), html, "utf8");
}

async function writeThemeCheckHtml() {
  const cards = figures
    .filter((figure) => figure.primary)
    .map((figure) => {
      return `
        <article class="theme-card">
          <div class="theme-head">
            <h2>${figure.id}</h2>
            <code>${figure.svgRel}</code>
          </div>
          <div class="theme-grid">
            <section class="surface light">
              <span class="surface-label">light surface</span>
              <img src="/${figure.svgRel}" alt="${figure.id} light preview" />
            </section>
            <section class="surface dark">
              <span class="surface-label">dark surface</span>
              <img src="/${figure.svgRel}" alt="${figure.id} dark preview" />
            </section>
          </div>
        </article>
      `;
    })
    .join("\n");

  const html = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>README Figure Theme Check</title>
    <style>
      :root {
        --ink: #0f172a;
        --muted: #475569;
        --line: rgba(148, 163, 184, 0.24);
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        font-family: Arial, Helvetica, sans-serif;
        background: linear-gradient(180deg, #fffef8, #f5efe4);
        color: var(--ink);
      }
      .shell {
        width: min(1800px, calc(100vw - 48px));
        margin: 24px auto 48px;
      }
      .hero {
        padding: 22px 28px;
        border-radius: 26px;
        background: rgba(255, 252, 247, 0.96);
        border: 1px solid rgba(214, 211, 209, 0.88);
        box-shadow: 0 20px 60px rgba(15, 23, 42, 0.08);
      }
      .hero h1 {
        margin: 0;
        font-size: 28px;
      }
      .hero p {
        margin: 10px 0 0;
        color: var(--muted);
      }
      .theme-card {
        margin-top: 22px;
        padding: 18px;
        border-radius: 24px;
        background: rgba(255, 252, 247, 0.96);
        border: 1px solid rgba(214, 211, 209, 0.88);
        box-shadow: 0 16px 48px rgba(15, 23, 42, 0.06);
      }
      .theme-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        margin-bottom: 14px;
      }
      .theme-head h2 {
        margin: 0;
        font-size: 18px;
      }
      .theme-head code {
        color: var(--muted);
        font-size: 12px;
      }
      .theme-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 16px;
      }
      .surface {
        padding: 16px;
        border-radius: 20px;
        border: 1px solid var(--line);
      }
      .surface.light {
        background: #ffffff;
      }
      .surface.dark {
        background: #0f172a;
      }
      .surface-label {
        display: inline-flex;
        margin-bottom: 10px;
        padding: 6px 10px;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.88);
        color: #334155;
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .surface.dark .surface-label {
        background: rgba(15, 23, 42, 0.82);
        color: #e2e8f0;
        border: 1px solid rgba(148, 163, 184, 0.28);
      }
      .surface img {
        display: block;
        width: 100%;
        height: auto;
      }
    </style>
  </head>
  <body>
    <main class="shell">
      <section class="hero">
        <h1>README figure theme check</h1>
        <p>Each primary SVG is checked on both light and dark surfaces after export.</p>
      </section>
      ${cards}
    </main>
  </body>
</html>
`;

  await fs.writeFile(repoPath(themeCheckRel), html, "utf8");
}

async function waitForImages(page, selector) {
  await page.waitForFunction((cssSelector) => {
    const images = Array.from(document.querySelectorAll(cssSelector));
    return images.length > 0 && images.every((img) => img.complete && img.naturalWidth > 0);
  }, selector, { timeout: 60_000 });
}

async function renderPreviewPngs(baseUrl) {
  const browser = await chromium.launch({
    executablePath: chromiumPath,
    headless: true
  });

  try {
    const page = await browser.newPage({
      viewport: {
        width: 1800,
        height: 1280
      },
      deviceScaleFactor: 1
    });

    for (const figure of figures) {
      const svgUrl = `${baseUrl}/${figure.svgRel}`;
      const html = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <style>
      body {
        margin: 0;
        padding: 28px;
        background:
          radial-gradient(circle at top left, rgba(15, 118, 110, 0.08), transparent 26%),
          linear-gradient(180deg, #fffef8, #f6f1e8);
        font-family: Arial, Helvetica, sans-serif;
      }
      .frame {
        width: 1500px;
        margin: 0 auto;
        padding: 22px 22px 18px;
        border-radius: 26px;
        background: rgba(255, 252, 247, 0.96);
        border: 1px solid rgba(214, 211, 209, 0.88);
        box-shadow: 0 20px 60px rgba(15, 23, 42, 0.08);
      }
      .title {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 14px;
      }
      .title h1 {
        margin: 0;
        font-size: 18px;
      }
      .title span {
        color: #475569;
        font-size: 12px;
      }
      .canvas {
        padding: 16px;
        border-radius: 20px;
        background: linear-gradient(180deg, rgba(255, 255, 255, 0.96), rgba(248, 250, 252, 0.92));
        border: 1px solid rgba(148, 163, 184, 0.22);
      }
      img {
        display: block;
        width: 100%;
        height: auto;
      }
    </style>
  </head>
  <body>
    <section class="frame">
      <div class="title">
        <h1>${figure.id}</h1>
        <span>${figure.primary ? "README primary" : "alternate variant"}</span>
      </div>
      <div class="canvas">
        <img src="${svgUrl}" alt="${figure.id}" />
      </div>
    </section>
  </body>
</html>`;

      await page.setContent(html, { waitUntil: "load" });
      await waitForImages(page, "img");
      await page.locator(".frame").screenshot({ path: repoPath(figure.previewRel) });
      console.log(`previewed ${figure.previewRel}`);
    }

    await page.goto(`${baseUrl}/${galleryRel}`, { waitUntil: "networkidle" });
    await waitForImages(page, "img");
    await page.screenshot({ path: repoPath(galleryPreviewRel), fullPage: true });
    console.log(`previewed ${galleryPreviewRel}`);

    await page.goto(`${baseUrl}/${themeCheckRel}`, { waitUntil: "networkidle" });
    await waitForImages(page, "img");
    await page.screenshot({ path: repoPath(themeCheckPreviewRel), fullPage: true });
    console.log(`previewed ${themeCheckPreviewRel}`);
  } finally {
    await browser.close();
  }
}

await ensureDirectories();
await exportSvgFiles();
await writeGalleryHtml();
await writeThemeCheckHtml();

const { server, baseUrl } = await startStaticServer(repoRoot);

try {
  await renderPreviewPngs(baseUrl);
} finally {
  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) reject(error);
      else resolve();
    });
  });
}
