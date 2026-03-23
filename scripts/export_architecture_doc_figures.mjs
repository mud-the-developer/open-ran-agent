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
    id: "00-system-overview",
    sourceRel: "docs/assets/infographics/architecture/00-system-overview.infographic",
    svgRel: "docs/assets/figures/architecture/00-system-overview.svg",
    previewRel: "output/playwright/doc-figures-architecture/00-system-overview.png"
  },
  {
    id: "01-context-and-boundaries",
    sourceRel: "docs/assets/infographics/architecture/01-context-and-boundaries.infographic",
    svgRel: "docs/assets/figures/architecture/01-context-and-boundaries.svg",
    previewRel: "output/playwright/doc-figures-architecture/01-context-and-boundaries.png"
  },
  {
    id: "02-otp-apps-and-supervision",
    sourceRel: "docs/assets/infographics/architecture/02-otp-apps-and-supervision.infographic",
    svgRel: "docs/assets/figures/architecture/02-otp-apps-and-supervision.svg",
    previewRel: "output/playwright/doc-figures-architecture/02-otp-apps-and-supervision.png"
  },
  {
    id: "03-failure-domains",
    sourceRel: "docs/assets/infographics/architecture/03-failure-domains.infographic",
    svgRel: "docs/assets/figures/architecture/03-failure-domains.svg",
    previewRel: "output/playwright/doc-figures-architecture/03-failure-domains.png"
  },
  {
    id: "04-du-high-southbound-contract",
    sourceRel: "docs/assets/infographics/architecture/04-du-high-southbound-contract.infographic",
    svgRel: "docs/assets/figures/architecture/04-du-high-southbound-contract.svg",
    previewRel: "output/playwright/doc-figures-architecture/04-du-high-southbound-contract.png"
  },
  {
    id: "06-ops-flow",
    sourceRel: "docs/assets/infographics/architecture/06-ops-flow.infographic",
    svgRel: "docs/assets/figures/architecture/06-ops-flow.svg",
    previewRel: "output/playwright/doc-figures-architecture/06-ops-flow.png"
  },
  {
    id: "06-backend-switch-and-rollback",
    sourceRel: "docs/assets/infographics/architecture/06-backend-switch-and-rollback.infographic",
    svgRel: "docs/assets/figures/architecture/06-backend-switch-and-rollback.svg",
    previewRel: "output/playwright/doc-figures-architecture/06-backend-switch-and-rollback.png"
  }
];

const galleryRel = "output/playwright/doc-figures-architecture/gallery.html";
const galleryPreviewRel = "output/playwright/doc-figures-architecture/gallery.png";

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

function addPanelBackground(svg) {
  const viewBoxMatch = svg.match(/viewBox="([^"]+)"/);

  if (!viewBoxMatch) return svg;

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
  const panel = `<g id="doc-panel-background"><rect x="${innerX}" y="${innerY}" width="${innerWidth}" height="${innerHeight}" rx="${cornerRadius}" ry="${cornerRadius}" fill="#fcfcfd" stroke="#cbd5e1" stroke-width="1.25" /></g>`;

  if (svg.includes(`<g id="infographic-container">`)) {
    return svg.replace(`<g id="infographic-container">`, `${panel}<g id="infographic-container">`);
  }

  return svg.replace(/<svg\b[^>]*>/, (prefix) => `${prefix}${panel}`);
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
  await fs.mkdir(repoPath("docs/assets/figures/architecture"), { recursive: true });
  await fs.mkdir(repoPath("output/playwright/doc-figures-architecture"), { recursive: true });
}

async function exportSvgFiles() {
  for (const figure of figures) {
    const source = await fs.readFile(repoPath(figure.sourceRel), "utf8");
    const svg = addPanelBackground(await renderToString(source));

    await fs.writeFile(repoPath(figure.svgRel), `${svg.trim()}\n`, "utf8");
    console.log(`exported ${figure.svgRel}`);
  }
}

async function writeGalleryHtml() {
  const cards = figures.map((figure) => `
    <article class="card">
      <div class="card-head">
        <h2>${figure.id}</h2>
        <code>${figure.sourceRel}</code>
      </div>
      <div class="card-body">
        <img src="/${figure.svgRel}" alt="${figure.id}" />
      </div>
    </article>
  `).join("\n");

  const html = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Architecture Doc Figure Gallery</title>
    <style>
      :root {
        --bg: #f7f3eb;
        --panel: rgba(255, 252, 247, 0.96);
        --line: rgba(148, 163, 184, 0.24);
        --ink: #0f172a;
        --muted: #475569;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        font-family: Arial, Helvetica, sans-serif;
        background:
          radial-gradient(circle at top left, rgba(15, 118, 110, 0.08), transparent 26%),
          linear-gradient(180deg, #fffef8, var(--bg));
        color: var(--ink);
      }
      .shell {
        width: min(1800px, calc(100vw - 48px));
        margin: 24px auto 48px;
      }
      .hero {
        padding: 22px 28px;
        border-radius: 26px;
        background: var(--panel);
        border: 1px solid rgba(214, 211, 209, 0.88);
        box-shadow: 0 20px 60px rgba(15, 23, 42, 0.08);
      }
      .hero h1 { margin: 0; font-size: 28px; }
      .hero p { margin: 10px 0 0; color: var(--muted); }
      .grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 18px;
        margin-top: 22px;
      }
      .card {
        padding: 18px;
        border-radius: 24px;
        background: var(--panel);
        border: 1px solid rgba(214, 211, 209, 0.9);
        box-shadow: 0 16px 48px rgba(15, 23, 42, 0.06);
      }
      .card-head h2 { margin: 0; font-size: 17px; }
      .card-head code { color: var(--muted); font-size: 12px; }
      .card-body {
        margin-top: 12px;
        padding: 12px;
        border-radius: 18px;
        background: linear-gradient(180deg, rgba(255, 255, 255, 0.96), rgba(248, 250, 252, 0.92));
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
        <h1>Architecture doc figure gallery</h1>
        <p>ASCII diagrams replaced with SVG figures rendered from local AntV infographic sources.</p>
      </section>
      <section class="grid">
        ${cards}
      </section>
    </main>
  </body>
</html>`;

  await fs.writeFile(repoPath(galleryRel), html, "utf8");
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
      const html = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <style>
      body {
        margin: 0;
        padding: 28px;
        background: linear-gradient(180deg, #fffef8, #f6f1e8);
        font-family: Arial, Helvetica, sans-serif;
      }
      .frame {
        width: 1500px;
        margin: 0 auto;
        padding: 22px 22px 18px;
        border-radius: 26px;
        background: rgba(255, 252, 247, 0.96);
        border: 1px solid rgba(214, 211, 209, 0.88);
      }
      h1 {
        margin: 0 0 12px;
        font-size: 18px;
      }
      .canvas {
        padding: 14px;
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
      <h1>${figure.id}</h1>
      <div class="canvas">
        <img src="${baseUrl}/${figure.svgRel}" alt="${figure.id}" />
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
  } finally {
    await browser.close();
  }
}

await ensureDirectories();
await exportSvgFiles();
await writeGalleryHtml();

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
