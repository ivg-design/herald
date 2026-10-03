import { McpMock, ToolList } from "./b-agents-ui";

export default function Agents() {
  return (
    <section id="agents" className="section section-dark">
      <div className="shell">
        <p className="eyebrow">For agents</p>
        <h2 className="display max-w-[18ch] text-[clamp(40px,6vw,72px)]">Let your agent design the banner.</h2>
        <p className="lede !max-w-[68ch]">
          Herald ships an MCP server with 60+ tools. Local agents, Claude Code, Codex, Claude Desktop, install it with one click, or with the steps in the MCP guide, and can register an app, author a template, attach a script or a Shortcut, render a preview and send a test. Cloud agents reach the same Mac through your relay, with OAuth or a device code you approve in a banner.
        </p>
        <div className="mt-12 grid gap-10 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] md:gap-14 lg:grid-cols-[minmax(0,540px)_1fr]">
          <McpMock />
          <div>
            <h3 className="m-0 text-[20px] font-medium">What the agent can do</h3>
            <ToolList />
          </div>
        </div>
      </div>
    </section>
  );
}
