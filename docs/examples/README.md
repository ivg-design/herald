# Examples

This example is a complete, runnable integration. It shows what a real app does to get its events onto Herald
well: it registers, describes what it sends, designs how it looks, and sends events. Read it end to end before you
build your own, then copy the part you need.

| Example | What it shows | Language |
|---|---|---|
| [BidBot](bidbot/README.md) | A made-up bidding app. It registers, publishes a manifest and a grid template, sends three events, adds a Shortcut button and receives a callback. | Python |

BidBot needs only Python and a running Herald. Start with its
[walkthrough](bidbot/README.md), which also shows how to run it against a [second instance of Herald](../TESTING.md#run-a-second-instance-of-herald)
so your own notifications stay untouched.

## Related

- [Send your first notification](../getting-started.md): the shortest path to a banner.
- [Clients](../../clients/README.md): the Swift, Python and Node libraries the examples use.
- [Manifests](../reference/manifests.md) and [Templates](../TEMPLATES.md): the two things every example defines.
