import { Infographic } from "https://esm.sh/@antv/infographic@0.2.16";

const figures = [
  "architecture-overview",
  "ranctl-lifecycle",
  "target-host-deploy"
];

const params = new URLSearchParams(window.location.search);
const figure = figures.includes(params.get("figure")) ? params.get("figure") : figures[0];
const sourcePath = `../infographics/${figure}.infographic`;

const nav = document.getElementById("figure-nav");
const sourcePathNode = document.getElementById("source-path");
const statusNode = document.getElementById("status");
const container = document.getElementById("container");

for (const name of figures) {
  const link = document.createElement("a");
  link.href = `?figure=${name}`;
  link.textContent = name;
  if (name === figure) link.className = "active";
  nav.appendChild(link);
}

sourcePathNode.textContent = sourcePath;

async function main() {
  const response = await fetch(sourcePath);

  if (!response.ok) {
    throw new Error(`failed to fetch ${sourcePath}`);
  }

  const source = await response.text();

  const infographic = new Infographic({
    container,
    width: "100%",
    height: "100%",
    editable: false
  });

  await infographic.render(source);

  window.__infographicFigure = figure;
  window.__infographicSourcePath = sourcePath;
  window.__infographicSource = source;
  window.__infographicRendered = true;

  document.body.dataset.rendered = "true";
  statusNode.textContent = "rendered";
}

main().catch((error) => {
  console.error(error);
  document.body.dataset.rendered = "error";
  statusNode.textContent = `error: ${error.message}`;
});
