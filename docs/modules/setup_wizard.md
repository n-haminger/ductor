# Setup Wizard and CLI Entry

Covers `ductor` command behavior, onboarding flow, and lifecycle commands.

## Files

- `ductor_bot/__main__.py`: CLI dispatch + config helpers + `run_bot`
- `ductor_bot/cli_commands/lifecycle.py`: start/stop/restart/upgrade/uninstall logic
- `ductor_bot/cli_commands/status.py`: `ductor status` + `ductor help`
- `ductor_bot/cli_commands/service.py`: service command routing
- `ductor_bot/cli_commands/docker.py`: docker subcommands
- `ductor_bot/cli_commands/api_cmd.py`: API enable/disable commands
- `ductor_bot/cli_commands/agents.py`: sub-agent registry commands
- `ductor_bot/cli/init_wizard.py`: onboarding + smart reset

## CLI commands

- `ductor`: start bot (auto-onboarding if needed)
- `ductor onboarding` / `ductor reset`: onboarding flow (with smart reset when configured)
- `ductor status`
- `ductor stop`
- `ductor restart`
- `ductor upgrade`
- `ductor uninstall`
- `ductor service <install|status|start|stop|logs|uninstall>`
- `ductor docker <rebuild|enable|disable|mount|unmount|mounts>`
- `ductor api <enable|disable>`
- `ductor agents <list|add|remove>`
- `ductor help`

## Configuration gate

`_is_configured()` checks based on `transport` field:

- **Telegram** (default): valid non-placeholder `telegram_token` + non-empty `allowed_user_ids`
- **Matrix**: non-empty `homeserver` + non-empty `user_id`

`allowed_group_ids` controls group authorization but does not satisfy startup configuration alone.

## Onboarding flow (`run_onboarding`)

1. banner
2. provider install/auth check
3. disclaimer
4. **transport selection** (Telegram or Matrix)
5. transport-specific credentials:
   - Telegram: bot token prompt + user ID prompt
   - Matrix: homeserver URL + bot user ID + password + allowed users
6. Docker choice
7. timezone choice
8. write merged config + initialize workspace
9. optional service install

Return semantics:

- `True` when service install was completed
- `False` otherwise

Caller behavior:

- default `ductor`: onboarding if needed, then foreground start unless service install path returned `True`
- `ductor onboarding/reset`: calls `stop_bot()` first, then onboarding, then same service/foreground logic

## Lifecycle command behavior

### `stop_bot()`

Shutdown sequence:

1. stop installed service (prevents auto-respawn)
2. kill PID-file instance
3. kill remaining ductor processes
4. short lock-release wait on Windows
5. stop Docker container when enabled

### Restart

- `cmd_restart()` = `stop_bot()` + process re-exec
- restart code `42` is used for service-managed restart semantics

### Upgrade

- dev installs: no self-upgrade, show guidance
- upgradeable installs: stop -> upgrade pipeline -> verify version -> restart

### Uninstall

- stop bot/service
- optional Docker image cleanup
- remove `~/.ductor` via robust filesystem helper
- uninstall package (`pipx` or `pip`)

## Status panel

`ductor status` shows:

- running state/PID/uptime
- provider/model
- Docker state
- error count from newest `ductor*.log`
- key paths
- sub-agent status table when configured (live health if bot is running)

Note: runtime primary log file is `~/.ductor/logs/agent.log`; status error counter is currently `ductor*.log`-based.

## Docker command notes

`ductor docker ...` commands update `config.json` and/or container/image state.

- mount/unmount paths are resolved and validated
- mount list shows host path, container target, status
- restart/rebuild is required for mount flag changes to affect running container

## API command notes

`ductor api enable`:

- requires PyNaCl
- writes/updates `config.api`
- generates token when missing

`ductor api disable`:

- sets `config.api.enabled=false` (keeps token/settings)

Both require bot restart to apply.

## Service command routing

`ductor service ...` delegates to platform backends:

- Linux: systemd user service
- macOS: launchd Launch Agent
- Windows: Task Scheduler

`ductor service logs`:

- Linux: `journalctl --user -u ductor -f`
- macOS/Windows: tail from `~/.ductor/logs/agent.log` (fallback newest `*.log`)
