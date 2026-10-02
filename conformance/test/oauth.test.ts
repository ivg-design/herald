import { describe, it } from "vitest";
import { OAUTH } from "./helpers";

// TODO: OAuth conformance (discovery metadata, dynamic client registration, authorize/token, bearer use on /mcp).
// Reserved: enabled with OAUTH=1 once the relay implements it.
describe.skipIf(!OAUTH)("oauth", () => {
  it.todo("OAuth flow is not specified yet");
});
