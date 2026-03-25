import { defineConfig } from "vitepress";

const repo = "https://github.com/mud-the-developer/open-ran-agent";

export default defineConfig({
  title: "Open RAN Agent",
  description:
    "Design-first documentation for an Open RAN control, operations, and deployment architecture.",
  cleanUrls: true,
  lastUpdated: true,
  ignoreDeadLinks: [/\.infographic$/],
  srcExclude: ["assets/render/**"],
  head: [
    ["link", { rel: "icon", href: "/assets/logo/open-ran-agent-16.svg", type: "image/svg+xml" }],
    ["meta", { name: "theme-color", content: "#10313d" }],
    ["meta", { property: "og:title", content: "Open RAN Agent Docs" }],
    [
      "meta",
      {
        property: "og:description",
        content:
          "Architecture, ADRs, deploy runbooks, and operator workflows for the Open RAN Agent bootstrap."
      }
    ]
  ],
  themeConfig: {
    logo: "/assets/logo/open-ran-agent-32.svg",
    siteTitle: "Open RAN Agent",
    search: {
      provider: "local"
    },
    nav: [
      { text: "Home", link: "/" },
      { text: "Architecture", link: "/architecture/" },
      { text: "ADRs", link: "/adr/" },
      { text: "Backlog", link: "/backlog/" },
      { text: "Cloudflare Pages", link: "/cloudflare-pages" }
    ],
    sidebar: {
      "/architecture/": [
        {
          text: "Architecture",
          items: [
            { text: "Guide", link: "/architecture/" },
            { text: "00. System Overview", link: "/architecture/00-system-overview" },
            { text: "01. Context And Boundaries", link: "/architecture/01-context-and-boundaries" },
            { text: "02. OTP Apps And Supervision", link: "/architecture/02-otp-apps-and-supervision" },
            { text: "03. Failure Domains", link: "/architecture/03-failure-domains" },
            { text: "04. DU-High Southbound Contract", link: "/architecture/04-du-high-southbound-contract" },
            { text: "05. ranctl Action Model", link: "/architecture/05-ranctl-action-model" },
            { text: "06. Symphony, Codex, Skills, And Ops", link: "/architecture/06-symphony-codex-skills-ops" },
            { text: "07. MVP Scope And Roadmap", link: "/architecture/07-mvp-scope-and-roadmap" },
            { text: "08. Open Questions And Risks", link: "/architecture/08-open-questions-and-risks" },
            { text: "09. OAI DU Runtime Bridge", link: "/architecture/09-oai-du-runtime-bridge" },
            { text: "10. CI And Release Bootstrap", link: "/architecture/10-ci-and-release-bootstrap" },
            { text: "11. Control State And Artifact Retention", link: "/architecture/11-control-state-and-artifact-retention" },
            { text: "12. Target Host Deployment", link: "/architecture/12-target-host-deployment" },
            { text: "13. OCUDU-Inspired Ops Profiles", link: "/architecture/13-ocudu-inspired-ops-profiles" },
            { text: "14. Debug And Evidence Workflow", link: "/architecture/14-debug-and-evidence-workflow" }
          ]
        }
      ],
      "/adr/": [
        {
          text: "ADRs",
          items: [
            { text: "Index", link: "/adr/" },
            { text: "0001. Repo Build Structure", link: "/adr/0001-repo-build-structure" },
            { text: "0002. BEAM Versus Native Boundary", link: "/adr/0002-beam-vs-native-boundary" },
            { text: "0003. Canonical FAPI IR", link: "/adr/0003-canonical-fapi-ir" },
            { text: "0004. ranctl As Single Action Entrypoint", link: "/adr/0004-ranctl-as-single-action-entrypoint" },
            { text: "0005. Ops Automation With Skills, Not MCP", link: "/adr/0005-ops-automation-with-skills-not-mcp" },
            { text: "0006. Open5GS Public Surface Compatibility Baseline", link: "/adr/0006-open5gs-public-surface-compatibility-baseline" }
          ]
        }
      ],
      "/backlog/": [
        {
          text: "Backlog",
          items: [
            { text: "Overview", link: "/backlog/" },
            { text: "Initial Tickets", link: "/backlog/initial-tickets" }
          ]
        }
      ]
    },
    outline: {
      level: [2, 3]
    },
    socialLinks: [{ icon: "github", link: repo }],
    editLink: {
      pattern: `${repo}/edit/main/docs/:path`,
      text: "Edit this page on GitHub"
    },
    footer: {
      message: "Design-first Open RAN architecture documentation.",
      copyright: "MIT Licensed"
    }
  }
});
