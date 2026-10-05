---
name: herald-notifications
description: Notify the owner's Mac through Herald and read their replies, when the user asks to be notified, asked a question, or told when work is done.
---

Use the connected Herald MCP tools: `send_notification`, `get_receipt`, `wait_for_reply` and `herald_status`. They reach the owner's Mac through the owner's own relay. Text and presentation fields only (title, body, speak, persistent, priority, group and the rest of the tool schema); the relay refuses buttons, commands, callbacks and scripts.

Give every logical notification a stable `notificationId` and reuse it on retry, so a retry never shows a second banner. Set `expectReply: true` when you need an answer. A `received` receipt means the relay has it; `displayed` means a banner was shown; `spoken` that speech finished; `suppressed` (with a reason) that the owner's quiet hours or mute held it back. Do not report a notification as seen until the receipt says `displayed`, and do not report a reply until `get_receipt` or `wait_for_reply` returns one. A voice reply has `transcript` (made on the Mac, may be imperfect) and `audioUrl`.

The connection is durable. It was approved once on the owner's Mac and works until they revoke it there. Tokens do not expire and are never replaced; never ask the owner to reconnect because of time, a retry or a refresh.

The reply event is `notification.reply` (MCP Events, protocol 2026-07-28). It fires once when the owner first answers a notification this connection sent. Its data is `{notificationId, id, kind}`: ids only, so read the answer with `get_receipt`. Subscribe only through the host-supported MCP Events connection using the callback URL the host issues; never invent a personal callback URL. The owner's approval of this connection already authorises the subscription: nothing more is needed from them, and the subscription does not lapse. A 2xx from the callback service is receipt, not proof that this conversation woke. Do not claim automatic wake until an actual reply has woken a run.

If `herald_status` shows the Mac offline, notifications queue on the relay for a day and are delivered when it returns; say so instead of retrying in a loop.
