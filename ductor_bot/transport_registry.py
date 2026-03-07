"""Transport registry: centralizes bot creation for all transports.

Instead of scattering ``if config.transport == "matrix"`` checks across
the codebase, all transport-specific logic is registered here.
Adding a new transport (e.g. Discord, Slack) requires only adding an
entry to ``_TRANSPORT_FACTORIES``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ductor_bot.bot.protocol import BotProtocol
    from ductor_bot.config import AgentConfig


def create_bot(config: AgentConfig, *, agent_name: str = "main") -> BotProtocol:
    """Create the transport-specific bot for *config*.

    Raises ``ValueError`` for unknown transport types.
    """
    factory = _TRANSPORT_FACTORIES.get(config.transport)
    if factory is None:
        msg = f"Unknown transport: {config.transport!r}. Supported: {list(_TRANSPORT_FACTORIES)}"
        raise ValueError(msg)
    return factory(config, agent_name=agent_name)


def _create_telegram(config: AgentConfig, *, agent_name: str) -> BotProtocol:
    from ductor_bot.bot.app import TelegramBot

    return TelegramBot(config, agent_name=agent_name)


def _create_matrix(config: AgentConfig, *, agent_name: str) -> BotProtocol:
    from ductor_bot.matrix.bot import MatrixBot

    return MatrixBot(config, agent_name=agent_name)


_TRANSPORT_FACTORIES: dict[str, object] = {
    "telegram": _create_telegram,
    "matrix": _create_matrix,
}
