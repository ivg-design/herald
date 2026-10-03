import SectionHead from "./SectionHead";
import { McpMock, ToolList } from "./b-agents-ui";

export default function Agents() {
  return (
    <section id="agents" className="section">
      <div className="shell g">
        <SectionHead
          title="Let your agent design the banner."
          titleCols="lg:col-span-10"
          ledeCols="lg:col-span-9"
          lede={
            <>
              Herald ships an MCP server with 60+ tools. Local agents, <span className="nowrap">Claude Code</span>, <span className="nowrap">Codex CLI</span>, <span className="nowrap">Claude Desktop</span>, install it with one click, or with the steps in the MCP guide, and can register an app, author a template, attach a script or a Shortcut, render a preview and send a test. Cloud agents reach the same Mac through your relay, with OAuth or a device code you approve in a banner.
            </>
          }
        />
        <div className="col-span-full min-w-0 lg:col-span-6">
          <h3 className="display display-m m-0">Install it in your agent</h3>
          <McpMock />
        </div>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-6 lg:col-start-7 lg:mt-0">
          <h3 className="display display-m m-0">What the agent can do</h3>
          <ToolList />
        </div>
      </div>
    </section>
  );
}
