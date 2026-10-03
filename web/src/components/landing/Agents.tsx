import { McpMock, ToolList } from "./b-agents-ui";

export default function Agents() {
  return (
    <section id="agents" className="section">
      <div className="shell g">
        <h2 className="display display-l col-span-full lg:col-span-8">Let your agent design the banner.</h2>
        <p className="lede col-span-full !mt-0 lg:col-span-8">
          Herald ships an MCP server with 60+ tools. Local agents, <span className="nowrap">Claude Code</span>, <span className="nowrap">Codex CLI</span>, <span className="nowrap">Claude Desktop</span>, install it with one click, or with the steps in the MCP guide, and can register an app, author a template, attach a script or a Shortcut, render a preview and send a test. Cloud agents reach the same Mac through your relay, with OAuth or a device code you approve in a banner.
        </p>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-6">
          <McpMock />
        </div>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-6 lg:col-start-7">
          <h3 className="display display-m">What the agent can do</h3>
          <ToolList />
        </div>
      </div>
    </section>
  );
}
