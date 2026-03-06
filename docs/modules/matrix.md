# matrix/

Matrix/Element transport layer (`matrix-nio`): message handling, streaming, buttons, formatting, credentials.

Alternative to the Telegram transport — selected via `config.transport = "matrix"`.

## Files

- `matrix/bot.py`: `MatrixBot` class implementing `BotProtocol`; message ingestion, command routing, authorization, streaming
- `matrix/transport.py`: `MatrixTransport` adapter for `MessageBus`; maps envelopes to Matrix room messages
- `matrix/sender.py`: message formatting and sending; Markdown→HTML, file upload, message splitting
- `matrix/credentials.py`: login flow (saved credentials → config token → password login)
- `matrix/id_map.py`: bidirectional `room_id` ↔ `int` mapping (deterministic SHA256)
- `matrix/buttons.py`: reaction-based button replacement; emoji digits + numbered text fallback
- `matrix/formatting.py`: Markdown → Matrix HTML conversion
- `matrix/typing.py`: typing indicator context manager
- `matrix/streaming.py`: `MatrixStreamEditor` for `m.replace`-based streaming (unused; kept for reference)
- `matrix/startup.py`: Matrix-specific startup (orchestrator, observers, restart sentinel)

## Streaming

Matrix uses **segment-based streaming**: text is buffered and flushed as separate messages at tool/system boundaries.

- `_on_delta()`: accumulates text into buffer
- `_on_tool()`: flushes buffer as message, sends `**[TOOL: name]**` tag, re-sets typing indicator
- `_on_system()`: flushes buffer, sends `*[STATUS]*` tag (THINKING, COMPACTING, etc.), re-sets typing indicator
- Final segment gets button extraction via `ButtonTracker`

Typing indicator is re-set after each sent message because Matrix clears it on `room_send`.

## Buttons

Matrix lacks inline keyboards. Workaround:

- Emoji digit reactions (1️⃣–🔟) on selector messages
- Numbered text list as visual fallback
- Text input matching (`1`, `2`, etc.) for clients without reaction support
- One active button set per room

## Authorization

- **Room-level**: `allowed_rooms` filter (empty = all rooms)
- **User-level**: `allowed_users` filter (empty = all users)
- **Group mention-only**: in multi-user rooms, bot responds only to @mentions or replies to its own messages
- Auto-join allowed rooms on invite; reject + leave unauthorized rooms

## Command routing

Same command set as Telegram, with `!` or `/` prefix:

- Transport-level: `!stop`, `!stop_all`, `!restart`, `!new`, `!help`, `!info`, `!session`, `!showfiles`, `!agent_commands`
- Orchestrator-routed: `!status`, `!model`, `!memory`, `!cron`, `!sessions`, `!tasks`, `!agents`

## Configuration

```toml
# pyproject.toml
[project.optional-dependencies]
matrix = ["matrix-nio>=0.25.0"]
```

```json
{
  "transport": "matrix",
  "matrix": {
    "homeserver": "https://matrix.example.com",
    "user_id": "@bot:matrix.example.com",
    "password": "...",
    "allowed_rooms": [],
    "allowed_users": ["@user:matrix.example.com"],
    "store_path": "matrix_store"
  }
}
```

Credentials are persisted in `matrix_store/credentials.json` (mode 0o600) after first login.
