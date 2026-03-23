import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { chromium } from "playwright-core";

const repoRoot = process.cwd();
const baseUrl = process.env.README_FIGURE_BASE_URL || "http://127.0.0.1:4173/docs/assets/render/index.html";
const chromiumPath = process.env.CHROMIUM_PATH || "/usr/bin/chromium";

const figures = [
  {
    name: "architecture-overview",
    screenshotPath: path.join(repoRoot, "output/playwright/readme-figures/architecture-overview.png"),
    finalPath: path.join(repoRoot, "docs/assets/figures/architecture-overview.png")
  },
  {
    name: "ranctl-lifecycle",
    screenshotPath: path.join(repoRoot, "output/playwright/readme-figures/ranctl-lifecycle.png"),
    finalPath: path.join(repoRoot, "docs/assets/figures/ranctl-lifecycle.png")
  },
  {
    name: "target-host-deploy",
    screenshotPath: path.join(repoRoot, "output/playwright/readme-figures/target-host-deploy.png"),
    finalPath: path.join(repoRoot, "docs/assets/figures/target-host-deploy.png")
  }
];

await fs.mkdir(path.join(repoRoot, "output/playwright/readme-figures"), { recursive: true });

const browser = await chromium.launch({
  executablePath: chromiumPath,
  headless: true
});

try {
  const page = await browser.newPage({
    viewport: {
      width: 1600,
      height: 1100
    },
    deviceScaleFactor: 1
  });

  for (const figure of figures) {
    const url = `${baseUrl}?figure=${figure.name}`;
    console.log(`rendering ${figure.name}`);
    await page.goto(url, { waitUntil: "networkidle" });
    await page.waitForFunction(() => window.__infographicRendered === true, null, {
      timeout: 60_000
    });

    const svgLocator = page.locator("#container svg");

    await svgLocator.waitFor({ state: "visible", timeout: 60_000 });

    await page.screenshot({ path: figure.screenshotPath, fullPage: true });
    await svgLocator.screenshot({ path: figure.finalPath });
  }
} finally {
  await browser.close();
}
