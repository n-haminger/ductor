"""Tests for cli/base.py: sudo_wrap and wrap_command helpers."""

from __future__ import annotations

from ductor_bot.cli.base import CLIConfig, docker_wrap, sudo_wrap, wrap_command


class TestSudoWrap:
    """Test sudo_wrap() command wrapping."""

    def test_no_linux_user_passthrough(self) -> None:
        cmd = ["claude", "-p", "hello"]
        cfg = CLIConfig(working_dir="/workspace")
        result_cmd, cwd = sudo_wrap(cmd, cfg)
        assert result_cmd == cmd
        assert cwd == "/workspace"

    def test_wraps_with_sudo(self) -> None:
        cmd = ["claude", "-p", "hello"]
        cfg = CLIConfig(linux_user="ductor-codex", working_dir="/workspace")
        result_cmd, cwd = sudo_wrap(cmd, cfg)
        assert result_cmd[0] == "sudo"
        assert "-Hnu" in result_cmd
        assert "ductor-codex" in result_cmd
        assert "--" in result_cmd
        # Original command preserved after -- (binary may be resolved to global path)
        sep = result_cmd.index("--")
        assert result_cmd[sep + 2 :] == cmd[1:]
        assert cwd == "/workspace"

    def test_preserves_ductor_env_vars(self) -> None:
        cmd = ["claude"]
        cfg = CLIConfig(linux_user="ductor-test", working_dir="/workspace")
        result_cmd, _ = sudo_wrap(cmd, cfg)
        # Find the --preserve-env flag
        preserve = [a for a in result_cmd if a.startswith("--preserve-env=")]
        assert len(preserve) == 1
        preserved_vars = preserve[0].split("=", 1)[1]
        for var in ("DUCTOR_HOME", "DUCTOR_AGENT_NAME", "PATH"):
            assert var in preserved_vars

    def test_extra_env_keys_preserved(self) -> None:
        cmd = ["gemini"]
        cfg = CLIConfig(linux_user="ductor-test", working_dir="/workspace")
        result_cmd, _ = sudo_wrap(cmd, cfg, extra_env={"CUSTOM_KEY": "val"})
        preserve = [a for a in result_cmd if a.startswith("--preserve-env=")]
        preserved_vars = preserve[0].split("=", 1)[1]
        assert "CUSTOM_KEY" in preserved_vars

    def test_non_interactive_flag(self) -> None:
        cmd = ["claude"]
        cfg = CLIConfig(linux_user="ductor-test", working_dir="/workspace")
        result_cmd, _ = sudo_wrap(cmd, cfg)
        # -Hnu means set HOME + non-interactive + user
        assert "-Hnu" in result_cmd

    def test_home_not_preserved(self) -> None:
        """HOME must not be in --preserve-env so sudo -H sets the target user's HOME."""
        cmd = ["claude"]
        cfg = CLIConfig(linux_user="ductor-test", working_dir="/workspace")
        result_cmd, _ = sudo_wrap(cmd, cfg)
        preserve = [a for a in result_cmd if a.startswith("--preserve-env=")]
        preserved_vars = preserve[0].split("=", 1)[1].split(",")
        assert "HOME" not in preserved_vars


class TestWrapCommand:
    """Test wrap_command() dispatch logic."""

    def test_no_isolation_passthrough(self) -> None:
        cmd = ["claude", "-p", "hello"]
        cfg = CLIConfig(working_dir="/workspace")
        result_cmd, cwd = wrap_command(cmd, cfg)
        assert result_cmd == cmd
        assert cwd == "/workspace"

    def test_docker_takes_precedence(self) -> None:
        cmd = ["claude", "-p", "hello"]
        cfg = CLIConfig(
            docker_container="sandbox",
            linux_user="ductor-test",
            working_dir="/workspace",
            chat_id=1,
        )
        result_cmd, cwd = wrap_command(cmd, cfg)
        assert result_cmd[0] == "docker"
        assert cwd is None

    def test_sudo_when_no_docker(self) -> None:
        cmd = ["claude", "-p", "hello"]
        cfg = CLIConfig(
            linux_user="ductor-codex",
            working_dir="/workspace",
        )
        result_cmd, cwd = wrap_command(cmd, cfg)
        assert result_cmd[0] == "sudo"
        assert cwd == "/workspace"

    def test_interactive_forwarded_to_docker(self) -> None:
        cmd = ["gemini"]
        cfg = CLIConfig(
            docker_container="sandbox",
            working_dir="/workspace",
            chat_id=1,
        )
        result_cmd, _ = wrap_command(cmd, cfg, interactive=True)
        assert "-i" in result_cmd

    def test_extra_env_forwarded(self) -> None:
        cmd = ["gemini"]
        cfg = CLIConfig(
            docker_container="sandbox",
            working_dir="/workspace",
            chat_id=1,
        )
        result_cmd, _ = wrap_command(cmd, cfg, extra_env={"FOO": "bar"})
        assert "FOO=bar" in result_cmd
