"""Tests for the transport registry."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from ductor_bot.transport_registry import create_bot


class TestTransportRegistry:
    def test_unknown_transport_raises(self) -> None:
        config = MagicMock()
        config.transport = "discord"
        with pytest.raises(ValueError, match="Unknown transport.*discord"):
            create_bot(config)

    def test_telegram_transport(self) -> None:
        config = MagicMock()
        config.transport = "telegram"
        fake_bot = MagicMock()
        with patch("ductor_bot.bot.app.TelegramBot", return_value=fake_bot):
            bot = create_bot(config, agent_name="test")
        assert bot is fake_bot

    def test_matrix_transport(self) -> None:
        config = MagicMock()
        config.transport = "matrix"
        fake_bot = MagicMock()
        with patch("ductor_bot.matrix.bot.MatrixBot", return_value=fake_bot):
            bot = create_bot(config, agent_name="test")
        assert bot is fake_bot
