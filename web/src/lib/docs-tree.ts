// The docs tree from the brief, mapped to the repo's Markdown. `file` is relative to content/ and mirrors
// the repo layout. `slice` takes only the named headings (and everything beneath them); "intro" is the text
// before the first heading. Nothing is retyped: every page is cut from the repo's own Markdown.

export interface DocEntry {
  slug: string;
  title: string;
  file: string;
  slice?: string[];
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
      { slug: "install", title: "Install", file: "README.md", slice: ["Install"] },
      { slug: "first-notification", title: "Send your first notification", file: "README.md", slice: ["API"] },
      { slug: "agent-quickstart", title: "Agent quickstart", file: "docs/AGENT-QUICKSTART.md" },
      { slug: "glossary", title: "Glossary", file: `${R}/glossary.md` },
    ],
  },
  {
    id: "concepts",
    title: "Concepts",
    items: [
      { slug: "manifests", title: "Manifests", file: `${R}/manifests.md` },
      { slug: "grid-and-layout", title: "Grid & layout", file: `${R}/grid-and-layout.md` },
      { slug: "templates", title: "Templates", file: "docs/TEMPLATES.md" },
      { slug: "empty-cells", title: "Empty cells & collapsing", file: "docs/TEMPLATES.md", slice: ["Collapse semantics"] },
      { slug: "actions", title: "Actions (two-way)", file: "docs/ACTIONS.md" },
      { slug: "stacking", title: "Stacking & grouping", file: `${R}/stacking.md` },
      { slug: "quiet-hours", title: "Quiet hours", file: `${R}/quiet-hours.md` },
      { slug: "voice", title: "Voice", file: `${R}/voice.md` },
      {
        slug: "cloud-relay",
        title: "Cloud relay",
        file: "docs/CLOUD.md",
        slice: ["intro", "Set up your relay (Enable relay)", "Security model", "Free plan budget and per-device limits", "Operating the relay", "Troubleshooting"],
      },
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
      { slug: "actions", title: "Actions", file: `${C}/actions.md` },
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
      { slug: "artboards", title: "Artboards & state machines", file: `${R}/rive.md`, slice: ["Referencing a file from a template"] },
      { slug: "inputs", title: "Inputs: hover, click, values", file: `${R}/rive.md`, slice: ["Inputs and how fields drive them", "Worked example: a bell that rings on new mail"] },
      { slug: "assets", title: "Uploading assets", file: `${R}/rive.md`, slice: ["Where the files live", "Getting a file into Herald"] },
      { slug: "sizing", title: "Sizing & fit", file: `${R}/rive.md`, slice: ["Sizing and fit"] },
      { slug: "bundles", title: "Bundles", file: `${R}/rive.md`, slice: ["Packaging with a template (`.heraldtemplate`)"] },
      { slug: "troubleshooting", title: "Troubleshooting", file: `${R}/rive.md`, slice: ["When the file is missing or broken", "Testing without a window", "Troubleshooting"] },
    ],
  },
  {
    id: "sf-symbols",
    title: "SF Symbols",
    items: [
      { slug: "choosing", title: "Choosing a symbol", file: `${R}/symbols.md`, slice: ["intro", "Where a symbol can go", "The `symbol` value"] },
      { slug: "weights-scales", title: "Weights & scales", file: `${R}/symbols.md`, slice: ["Examples by component", "Precedence"] },
      { slug: "rendering-modes", title: "Rendering modes & colours", file: `${R}/symbols.md`, slice: ["Examples by rendering mode"] },
      { slug: "variable-value", title: "Variable value", file: `${R}/symbols.md`, slice: ["In the Designer", "Common mistakes"] },
      { slug: "effects", title: "Effects & triggers", file: `${R}/symbols.md`, slice: ["Effects", "Examples by effect"] },
    ],
  },
  {
    id: "reference",
    title: "Reference",
    items: [
      { slug: "http-api", title: "HTTP API", file: `${R}/api.md` },
      { slug: "cli", title: "herald CLI", file: `${R}/cli.md` },
      { slug: "mcp-tools", title: "MCP tools", file: `${R}/mcp-tools.md` },
      { slug: "swift-client", title: "HeraldClient (Swift)", file: "clients/README.md", slice: ["Swift"] },
      { slug: "clients", title: "Python & Node clients", file: "clients/README.md", slice: ["Python", "Node", "Registering a manifest (1.1)"] },
      { slug: "template-bundles", title: "Template bundles", file: `${R}/api.md`, slice: ["Template bundles"], note: "From the HTTP API reference." },
      { slug: "config-files", title: "config & files", file: `${R}/api.md`, slice: ["Settings", "Per-app settings", "Assets"], note: "From the HTTP API reference." },
      {
        slug: "cloud-relay-api",
        title: "Cloud relay API",
        file: "docs/CLOUD.md",
        slice: ["Connect a cloud agent", "Connect ChatGPT (OAuth)", "No browser? Use the device flow", "What the agent can do", "Replying to the agent"],
      },
      { slug: "relay-endpoints", title: "Relay endpoints", file: `${R}/api.md`, slice: ["Cloud relay"], note: "From the HTTP API reference." },
    ],
  },
  {
    id: "examples",
    title: "Examples",
    items: [
      { slug: "bidbot", title: "bidbot", file: "docs/examples/bidbot/README.md" },
      { slug: "webwatcher", title: "WebWatcher", file: "README.md", slice: ["WebWatcher integration"] },
    ],
  },
  {
    id: "help",
    title: "Help",
    items: [
      { slug: "troubleshooting", title: "Troubleshooting", file: "README.md", slice: ["Troubleshooting"] },
      { slug: "report-an-issue", title: "Report an issue", file: "" },
    ],
  },
  {
    id: "more",
    title: "More guides",
    items: [
      { slug: "authoring", title: "Authoring guide", file: "docs/AUTHORING.md" },
      { slug: "bindings", title: "Bindings and tokens", file: `${R}/bindings.md` },
      { slug: "actions-reference", title: "Actions reference", file: `${R}/actions.md` },
      { slug: "parity", title: "Designer vs API parity", file: `${R}/parity.md` },
      { slug: "mcp-guide", title: "MCP server guide", file: "docs/MCP.md" },
      { slug: "voice-guide", title: "Voice guide", file: "docs/VOICE.md" },
      { slug: "api-overview", title: "API overview (1.1)", file: "docs/API.md" },
      { slug: "reference-index", title: "Reference index", file: `${R}/README.md` },
      { slug: "examples-index", title: "Examples index", file: "docs/examples/README.md" },
      { slug: "testing", title: "Testing Herald", file: "docs/TESTING.md" },
    ],
  },
];

export const ISSUE_URL = "https://github.com/ivg-design/herald/issues/new";
