// The docs tree from the brief, mapped to the repo's Markdown. `file` is relative to content/ and mirrors
// the repo layout. `slice` takes only the named headings (and everything beneath them); "intro" is the text
// before the first heading. Nothing is retyped: every page is cut from the repo's own Markdown.

export interface DocEntry {
  slug: string;
  title: string;
  file: string;
  slice?: string[];
  description?: string; // overrides the first-paragraph description
  note?: string; // shown under the title when a page is a cut of a larger file
}
export interface DocGroup {
  id: string;
  title: string;
  items: DocEntry[];
}

const R = "docs/reference";
const C = "docs/reference/components";

export const DOC_TREE: DocGroup[] = [
  {
    id: "getting-started",
    title: "Getting started",
    items: [
      { slug: "install", title: "Install", file: "docs/install.md" },
      { slug: "first-notification", title: "Send your first notification", file: "docs/getting-started.md" },
      { slug: "integrate", title: "Integrate Herald into your app", file: "docs/integrate.md" },
      { slug: "agent-quickstart", title: "Connect an AI agent", file: "docs/AGENT-QUICKSTART.md" },
      { slug: "app", title: "The Herald app", file: "docs/APP.md" },
    ],
  },
  {
    id: "guides",
    title: "Guides",
    items: [
      { slug: "design-a-banner", title: "Design a banner", file: "docs/AUTHORING.md" },
      { slug: "templates", title: "Templates", file: "docs/TEMPLATES.md" },
      { slug: "actions", title: "Two-way notifications", file: "docs/ACTIONS.md" },
      { slug: "voice", title: "Make Herald speak", file: "docs/VOICE.md" },
      { slug: "mcp", title: "Agents and MCP", file: "docs/MCP.md" },
      { slug: "testing", title: "Testing", file: "docs/TESTING.md" },
    ],
  },
  {
    id: "cloud",
    title: "Cloud relay",
    items: [
      { slug: "setup", title: "Set up the relay", file: "docs/CLOUD.md" },
      { slug: "how-it-works", title: "How the relay works", file: "docs/cloud/how-it-works.md" },
      { slug: "connect-agent", title: "Connect an agent with a key", file: "docs/cloud/connect-agent.md" },
      { slug: "connect-chatgpt", title: "Connect ChatGPT", file: "docs/cloud/connect-chatgpt.md" },
      { slug: "connect-dot", title: "Connect an OpenAI dot", file: "docs/cloud/connect-dot.md" },
      { slug: "device-flow", title: "Agents without a browser", file: "docs/cloud/device-flow.md" },
      { slug: "reply-events", title: "Reply events and dots", file: "docs/cloud/reply-events.md" },
      { slug: "custom-domain", title: "Custom domain", file: "docs/cloud/custom-domain.md" },
      { slug: "operating", title: "Operate the relay", file: "docs/cloud/operating.md" },
    ],
  },
  {
    id: "concepts",
    title: "Concepts",
    items: [
      { slug: "banners", title: "How banners behave", file: `${R}/banners.md` },
      { slug: "manifests", title: "Manifests", file: `${R}/manifests.md` },
      { slug: "grid-and-layout", title: "Grid & layout", file: `${R}/grid-and-layout.md` },
      { slug: "bindings", title: "Bindings & tokens", file: `${R}/bindings.md` },
      { slug: "actions", title: "Actions", file: `${R}/actions.md` },
      { slug: "stacking", title: "Stacking", file: `${R}/stacking.md` },
      { slug: "quiet-hours", title: "Quiet hours", file: `${R}/quiet-hours.md` },
      { slug: "voice", title: "Voice", file: `${R}/voice.md` },
    ],
  },
  {
    id: "components",
    title: "Components",
    items: [
      { slug: "overview", title: "What every component shares", file: `${C}/README.md` },
      { slug: "text", title: "Text", file: `${C}/text.md` },
      { slug: "image", title: "Image", file: `${C}/image.md` },
      { slug: "issuer-icon", title: "Issuer icon", file: `${C}/issuerIcon.md` },
      { slug: "timestamp", title: "Timestamp", file: `${C}/timestamp.md` },
      { slug: "button", title: "Button", file: `${C}/button.md` },
      { slug: "actions", title: "Actions row", file: `${C}/actions.md` },
      { slug: "icon-button", title: "Icon button", file: `${C}/iconButton.md` },
      { slug: "badge", title: "Badge", file: `${C}/badge.md` },
      { slug: "stack-badge", title: "Stack badge", file: `${C}/stackBadge.md` },
      { slug: "progress", title: "Progress", file: `${C}/progress.md` },
      { slug: "rive", title: "Rive animation", file: `${C}/rive.md` },
      { slug: "spacer", title: "Spacer", file: `${C}/spacer.md` },
    ],
  },
  {
    id: "rive",
    title: "Rive",
    items: [
      { slug: "preparing", title: "Preparing a .riv", file: `${R}/rive.md`, slice: ["intro", "What Herald does with a Rive file", "Preparing the file in the Rive editor"] },
      { slug: "assets", title: "Getting a file into Herald", file: `${R}/rive.md`, slice: ["Where the files live", "Getting a file into Herald"] },
      { slug: "artboards", title: "Using it in a template", file: `${R}/rive.md`, slice: ["Referencing a file from a template", "Sizing and fit"] },
      { slug: "inputs", title: "Inputs: hover, click, values", file: `${R}/rive.md`, slice: ["Inputs and how fields drive them", "Worked example: a bell that rings on new mail"] },
      { slug: "bundles", title: "Bundles", file: `${R}/rive.md`, slice: ["Packaging with a template (`.heraldtemplate`)"] },
      { slug: "troubleshooting", title: "Testing & troubleshooting", file: `${R}/rive.md`, slice: ["Testing without a window", "When the file is missing or broken", "Troubleshooting"] },
    ],
  },
  {
    id: "sf-symbols",
    title: "SF Symbols",
    items: [
      { slug: "choosing", title: "Choosing a symbol", file: `${R}/symbols.md`, slice: ["intro", "Where a symbol can go", "The `symbol` value", "In the Designer"] },
      { slug: "rendering-modes", title: "Rendering modes & colours", file: `${R}/symbols.md`, slice: ["Examples by rendering mode", "Examples by component", "Precedence"] },
      { slug: "effects", title: "Effects & triggers", file: `${R}/symbols.md`, slice: ["Effects", "Examples by effect", "Common mistakes"] },
    ],
  },
  {
    id: "api",
    title: "HTTP API",
    items: [
      { slug: "overview", title: "Overview", file: `${R}/api/README.md` },
      { slug: "notifications", title: "Notifications", file: `${R}/api/notifications.md` },
      { slug: "apps", title: "Apps", file: `${R}/api/apps.md` },
      { slug: "templates", title: "Templates", file: `${R}/api/templates.md` },
      { slug: "manifests", title: "Manifests", file: `${R}/api/manifests.md` },
      { slug: "assets", title: "Assets", file: `${R}/api/assets.md` },
      { slug: "history", title: "History", file: `${R}/api/history.md` },
      { slug: "replies", title: "Replies & callbacks", file: `${R}/api/replies.md` },
      { slug: "stacks", title: "Stacks", file: `${R}/api/stacks.md` },
      { slug: "settings", title: "Settings & quiet hours", file: `${R}/api/settings.md` },
      { slug: "setup", title: "Voice & MCP setup", file: `${R}/api/setup.md` },
      { slug: "relay", title: "Cloud relay (local)", file: `${R}/api/relay.md` },
      { slug: "diagnostics", title: "Diagnostics", file: `${R}/api/diagnostics.md` },
    ],
  },
  {
    id: "mcp",
    title: "MCP tools",
    items: [
      { slug: "overview", title: "Overview", file: `${R}/mcp/README.md` },
      { slug: "notifications", title: "Notifications", file: `${R}/mcp/notifications.md` },
      { slug: "templates", title: "Templates & assets", file: `${R}/mcp/templates.md` },
      { slug: "apps-and-settings", title: "Apps, settings & history", file: `${R}/mcp/apps-and-settings.md` },
      { slug: "relay", title: "Cloud relay", file: `${R}/mcp/relay.md` },
    ],
  },
  {
    id: "relay-api",
    title: "Relay API",
    items: [
      { slug: "overview", title: "Overview and authentication", file: `${R}/relay/README.md` },
      { slug: "agent", title: "Agent endpoints", file: `${R}/relay/agent.md` },
      { slug: "mcp", title: "MCP endpoint", file: `${R}/relay/mcp.md` },
      { slug: "events", title: "Reply events", file: `${R}/relay/events.md` },
      { slug: "oauth", title: "OAuth", file: `${R}/relay/oauth.md` },
      { slug: "device-flow", title: "Device flow", file: `${R}/relay/device-flow.md` },
      { slug: "pairing-and-devices", title: "Pairing and devices", file: `${R}/relay/pairing-and-devices.md` },
      { slug: "device-side", title: "Device-side endpoints", file: `${R}/relay/device-side.md` },
      { slug: "limits-and-errors", title: "Limits and errors", file: `${R}/relay/limits-and-errors.md` },
    ],
  },
  {
    id: "reference",
    title: "Reference",
    items: [
      { slug: "cli", title: "herald CLI", file: `${R}/cli.md` },
      { slug: "swift-client", title: "HeraldClient (Swift)", file: "clients/README.md", slice: ["intro", "Swift"] },
      { slug: "clients", title: "Python & Node clients", file: "clients/README.md", slice: ["Python", "Node", "Registering a manifest"] },
      { slug: "parity", title: "What you can do where", file: `${R}/parity.md` },
      { slug: "glossary", title: "Glossary", file: `${R}/glossary.md` },
    ],
  },
  {
    id: "examples",
    title: "Examples",
    items: [
      { slug: "bidbot", title: "BidBot", file: "docs/examples/bidbot/README.md" },
    ],
  },
  {
    id: "help",
    title: "Help",
    items: [
      { slug: "troubleshooting", title: "Troubleshooting", file: "docs/troubleshooting.md" },
      { slug: "report-an-issue", title: "Report an issue", file: "" },
    ],
  },
];

/** Old docs URLs, kept working: [from, to]. The landing page, the README and outside links point at these. */
export const DOC_REDIRECTS: [string, string][] = [
  ["/docs/concepts/templates", "/docs/guides/templates"],
  ["/docs/concepts/empty-cells", "/docs/guides/templates#collapse-semantics"],
  ["/docs/concepts/cloud-relay", "/docs/cloud/setup"],
  ["/docs/getting-started/glossary", "/docs/reference/glossary"],
  ["/docs/reference/http-api", "/docs/api/overview"],
  ["/docs/reference/mcp-tools", "/docs/mcp/overview"],
  ["/docs/reference/template-bundles", "/docs/api/templates#move-templates-between-macs"],
  ["/docs/reference/config-files", "/docs/api/settings"],
  ["/docs/reference/cloud-relay-api", "/docs/cloud/connect-agent"],
  ["/docs/reference/relay-endpoints", "/docs/api/relay"],
  ["/docs/rive/sizing", "/docs/rive/artboards"],
  ["/docs/sf-symbols/weights-scales", "/docs/sf-symbols/rendering-modes"],
  ["/docs/sf-symbols/variable-value", "/docs/sf-symbols/choosing"],
  ["/docs/more/authoring", "/docs/guides/design-a-banner"],
  ["/docs/more/bindings", "/docs/concepts/bindings"],
  ["/docs/more/actions-reference", "/docs/concepts/actions"],
  ["/docs/more/parity", "/docs/reference/parity"],
  ["/docs/more/mcp-guide", "/docs/guides/mcp"],
  ["/docs/more/voice-guide", "/docs/guides/voice"],
  ["/docs/more/api-overview", "/docs/api/overview"],
  ["/docs/more/reference-index", "/docs"],
  ["/docs/more/examples-index", "/docs/examples/bidbot"],
  ["/docs/examples/webwatcher", "/docs/examples/bidbot"],
  ["/docs/reference/relay-api", "/docs/relay-api/overview"],
  ["/docs/more/testing", "/docs/guides/testing"],
];

export const ISSUE_URL = "https://github.com/ivg-design/herald/issues/new";
