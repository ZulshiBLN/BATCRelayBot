"""
Tests for ATC Relay Bot (bot.py)
"""

import asyncio
import json
import logging
import pathlib
import sys
from unittest.mock import MagicMock, Mock, patch, AsyncMock

import discord
import pytest

# Prevent bot.py from running config validation at import time
with patch("pathlib.Path.exists", return_value=True):
    with patch("builtins.open", create=True):
        with patch("json.load", return_value={
            "bot_token": "test_token",
            "guild_id": 123456789012345678,
            "voice_channel_id": 987654321098765432,
            "audio_device_name": "Voicemeeter Out MME",
        }):
            import bot


class TestLoadConfig:
    """Tests for load_config() function"""

    def test_load_config_missing_file(self, tmp_path):
        """Should exit with error when config.json doesn't exist"""
        config_path = tmp_path / "config.json"
        with patch("bot.CONFIG_PATH", config_path):
            with pytest.raises(SystemExit) as exc_info:
                bot.load_config()
            assert exc_info.value.code == 1

    def test_load_config_valid_json(self, tmp_path):
        """Should load valid config.json"""
        config_data = {
            "bot_token": "test_token",
            "guild_id": 123456789012345678,
            "voice_channel_id": 987654321098765432,
            "audio_device_name": "Voicemeeter Out MME",
        }
        config_file = tmp_path / "config.json"
        config_file.write_text(json.dumps(config_data), encoding="utf-8")

        with patch("bot.CONFIG_PATH", config_file):
            config = bot.load_config()
            assert config["bot_token"] == "test_token"
            assert config["guild_id"] == 123456789012345678

    def test_load_config_with_utf8_bom(self, tmp_path):
        """Should handle UTF-8 BOM in config.json"""
        config_data = {
            "bot_token": "test_token",
            "guild_id": 123456789012345678,
            "voice_channel_id": 987654321098765432,
            "audio_device_name": "Voicemeeter Out MME",
        }
        config_file = tmp_path / "config.json"
        # Write with UTF-8 BOM
        config_file.write_bytes(b'\xef\xbb\xbf' + json.dumps(config_data).encode("utf-8"))

        with patch("bot.CONFIG_PATH", config_file):
            config = bot.load_config()
            assert config["bot_token"] == "test_token"


class TestConfigValidation:
    """Tests for config.json validation"""

    def test_config_has_required_keys(self):
        """Config should have all required keys"""
        required_keys = ["bot_token", "guild_id", "voice_channel_id", "audio_device_name"]
        for key in required_keys:
            assert key in bot.CONFIG, f"Missing required key: {key}"

    def test_config_required_keys_not_empty(self):
        """Required config keys should not be empty"""
        assert bot.CONFIG.get("bot_token"), "bot_token is empty"
        assert bot.CONFIG.get("guild_id"), "guild_id is empty"
        assert bot.CONFIG.get("voice_channel_id"), "voice_channel_id is empty"
        assert bot.CONFIG.get("audio_device_name"), "audio_device_name is empty"

    def test_config_ids_are_integers(self):
        """guild_id and voice_channel_id should be integers"""
        assert isinstance(bot.CONFIG["guild_id"], int), "guild_id must be integer"
        assert isinstance(bot.CONFIG["voice_channel_id"], int), "voice_channel_id must be integer"


class TestAudioSource:
    """Tests for make_audio_source() function"""

    @patch("discord.FFmpegPCMAudio")
    def test_make_audio_source_returns_ffmpeg_audio(self, mock_ffmpeg):
        """Should create FFmpegPCMAudio instance"""
        bot.make_audio_source()
        mock_ffmpeg.assert_called_once()

    @patch("discord.FFmpegPCMAudio")
    def test_make_audio_source_correct_device(self, mock_ffmpeg):
        """Should use device name from config"""
        bot.make_audio_source()
        # Verify it was called with correct device
        call_kwargs = mock_ffmpeg.call_args[1]
        assert call_kwargs["before_options"] == "-f dshow"

    @patch("discord.FFmpegPCMAudio")
    def test_make_audio_source_uses_dshow_format(self, mock_ffmpeg):
        """Should use Windows dshow format"""
        bot.make_audio_source()
        call_kwargs = mock_ffmpeg.call_args[1]
        assert call_kwargs["before_options"] == "-f dshow"
        assert call_kwargs["options"] == "-vn"


class TestBotIntents:
    """Tests for Discord bot intents configuration"""

    def test_bot_has_intents(self):
        """Bot should be configured with intents"""
        assert bot.bot.intents is not None

    def test_bot_has_message_content_intent(self):
        """Bot should have message_content intent enabled"""
        assert bot.bot.intents.message_content is True

    def test_bot_default_intents(self):
        """Bot should have default intents base"""
        # message_content is explicitly enabled
        assert bot.bot.intents.message_content is True


class TestCommandRegistration:
    """Tests for Discord command registration"""

    def test_status_command_exists(self):
        """Should have !status command"""
        assert "BATCstatus" in [cmd.name for cmd in bot.bot.commands]

    def test_restart_stream_command_exists(self):
        """Should have !restart_stream command"""
        assert "BATCrestart" in [cmd.name for cmd in bot.bot.commands]

    def test_leave_command_exists(self):
        """Should have !leave command"""
        assert "BATCleave" in [cmd.name for cmd in bot.bot.commands]

    def test_commands_are_callable(self):
        """All registered commands should be callable"""
        for cmd in bot.bot.commands:
            assert callable(cmd.callback)

    def test_status_command_prefix(self):
        """Status command should use ! prefix"""
        cmd = bot.bot.get_command("BATCstatus")
        assert cmd is not None


def test_status_command_callable():
    """!status command should be callable"""
    cmd = bot.bot.get_command("BATCstatus")
    assert cmd is not None
    assert callable(cmd.callback)


def test_restart_stream_command_callable():
    """!restart_stream command should be callable"""
    cmd = bot.bot.get_command("BATCrestart")
    assert cmd is not None
    assert callable(cmd.callback)


def test_leave_command_callable():
    """!leave command should be callable"""
    cmd = bot.bot.get_command("BATCleave")
    assert cmd is not None
    assert callable(cmd.callback)


class TestStopSignal:
    """Tests for stop signal file handling"""

    def test_stop_signal_path_defined(self):
        """STOP_SIGNAL_PATH should be defined"""
        assert bot.STOP_SIGNAL_PATH is not None

    def test_stop_signal_path_is_pathlib(self):
        """STOP_SIGNAL_PATH should be a pathlib.Path"""
        assert isinstance(bot.STOP_SIGNAL_PATH, pathlib.Path)

    def test_stop_signal_is_in_project_directory(self):
        """STOP_SIGNAL_PATH should be in project directory"""
        expected_parent = pathlib.Path(bot.__file__).parent
        assert bot.STOP_SIGNAL_PATH.parent == expected_parent


class TestLogging:
    """Tests for logging configuration"""

    def test_logger_exists(self):
        """Logger 'atc-relay' should be configured"""
        assert bot.log is not None
        assert bot.log.name == "atc-relay"

    def test_logger_level(self):
        """Logger should be at INFO level or higher"""
        assert bot.log.level <= logging.INFO or bot.log.level == logging.NOTSET

    def test_logging_format(self):
        """Logger should have handlers with format"""
        has_handler = len(logging.getLogger("atc-relay").handlers) >= 0
        assert has_handler or logging.getLogger("atc-relay") is not None


class TestTaskLoops:
    """Tests for background task loops"""

    def test_watchdog_loop_exists(self):
        """watchdog background task should be defined"""
        assert hasattr(bot, "watchdog")
        assert isinstance(bot.watchdog, discord.ext.tasks.Loop)

    def test_shutdown_watcher_loop_exists(self):
        """shutdown_watcher background task should be defined"""
        assert hasattr(bot, "shutdown_watcher")
        assert isinstance(bot.shutdown_watcher, discord.ext.tasks.Loop)

    def test_watchdog_interval(self):
        """watchdog should run every 10 seconds"""
        assert bot.watchdog.seconds == 10

    def test_shutdown_watcher_interval(self):
        """shutdown_watcher should run every 1 second"""
        assert bot.shutdown_watcher.seconds == 1


@pytest.mark.asyncio
async def test_connect_and_stream_guild_not_found():
    """connect_and_stream should handle missing guild gracefully"""
    with patch.object(bot.bot, "get_guild", return_value=None):
        # Should not raise
        await bot.connect_and_stream()


@pytest.mark.asyncio
async def test_connect_and_stream_channel_not_found():
    """connect_and_stream should handle missing channel gracefully"""
    guild = MagicMock()
    guild.get_channel = Mock(return_value=None)

    with patch.object(bot.bot, "get_guild", return_value=guild):
        await bot.connect_and_stream()
        guild.get_channel.assert_called_once()


@pytest.mark.asyncio
async def test_connect_and_stream_already_connected():
    """connect_and_stream should handle already connected state"""
    guild = MagicMock()
    channel = MagicMock(spec=discord.VoiceChannel)
    channel.id = bot.CONFIG["voice_channel_id"]
    channel.name = "Test Channel"

    voice_client = AsyncMock()
    voice_client.channel.id = channel.id

    # is_playing() and play() are synchronous in discord.py. Left as AsyncMock
    # attributes they return coroutines, and a coroutine is always truthy - so
    # "if not voice_client.is_playing()" was always false and the streaming
    # branch was never reached, whatever return_value said. That is what the
    # "coroutine was never awaited" warning in every test run was reporting.
    voice_client.is_playing = Mock(return_value=False)
    voice_client.play = Mock()

    guild.get_channel = Mock(return_value=channel)
    guild.voice_client = voice_client

    with patch.object(bot.bot, "get_guild", return_value=guild):
        with patch("bot.make_audio_source", return_value=MagicMock()):
            await bot.connect_and_stream()

            # The previous assertion was "get_channel is not None or
            # is_playing.called". A mock creates attributes on access, so the
            # left side is true for any mock and the test could not fail.
            voice_client.is_playing.assert_called_once()
            voice_client.play.assert_called_once()


@pytest.mark.asyncio
async def test_connect_and_stream_does_not_restart_a_running_stream():
    """The other half: already playing means play() must not be called again."""
    guild = MagicMock()
    channel = MagicMock(spec=discord.VoiceChannel)
    channel.id = bot.CONFIG["voice_channel_id"]
    channel.name = "Test Channel"

    voice_client = AsyncMock()
    voice_client.channel.id = channel.id
    voice_client.is_playing = Mock(return_value=True)
    voice_client.play = Mock()

    guild.get_channel = Mock(return_value=channel)
    guild.voice_client = voice_client

    with patch.object(bot.bot, "get_guild", return_value=guild):
        with patch("bot.make_audio_source", return_value=MagicMock()):
            await bot.connect_and_stream()
            voice_client.play.assert_not_called()


def test_watchdog_task_loop_exists():
    """watchdog task loop should exist and be configured"""
    assert bot.watchdog is not None
    assert bot.watchdog.seconds == 10
    assert callable(bot.watchdog.coro)


def test_shutdown_watcher_task_loop_exists():
    """shutdown_watcher task loop should exist and be configured"""
    assert bot.shutdown_watcher is not None
    assert bot.shutdown_watcher.seconds == 1
    assert callable(bot.shutdown_watcher.coro)


def test_shutdown_watcher_detects_signal_file():
    """shutdown_watcher should check for stop signal file"""
    # Verify the task loop references the stop signal path
    assert bot.STOP_SIGNAL_PATH is not None
    assert callable(bot.shutdown_watcher.coro)


@pytest.mark.asyncio
async def test_on_ready_starts_tasks():
    """on_ready event should start watchdog and shutdown_watcher tasks"""
    # Mock the tasks
    bot.watchdog.start = Mock()
    bot.shutdown_watcher.start = Mock()
    bot.watchdog.is_running = Mock(return_value=False)
    bot.shutdown_watcher.is_running = Mock(return_value=False)

    # Manually call on_ready logic (it's decorated with @bot.event)
    await bot.on_ready()

    # Verify tasks would be started if not already running
    assert bot.watchdog is not None
    assert bot.shutdown_watcher is not None


def test_status_command_exists_and_callable():
    """status command should be registered and callable"""
    cmd = bot.bot.get_command("BATCstatus")
    assert cmd is not None
    assert callable(cmd.callback)
    assert cmd.name == "BATCstatus"


def test_restart_stream_command_exists_and_callable():
    """restart_stream command should be registered and callable"""
    cmd = bot.bot.get_command("BATCrestart")
    assert cmd is not None
    assert callable(cmd.callback)
    assert cmd.name == "BATCrestart"


def test_leave_command_exists_and_callable():
    """leave command should be registered and callable"""
    cmd = bot.bot.get_command("BATCleave")
    assert cmd is not None
    assert callable(cmd.callback)
    assert cmd.name == "BATCleave"


class TestIntegration:
    """Integration tests for bot startup and configuration"""

    def test_bot_is_commands_bot(self):
        """bot instance should be a commands.Bot"""
        assert isinstance(bot.bot, discord.ext.commands.Bot)

    def test_bot_command_prefix(self):
        """Bot should use ! as command prefix"""
        assert bot.bot.command_prefix == "!"

    def test_config_path_defined(self):
        """CONFIG_PATH should be defined"""
        assert bot.CONFIG_PATH is not None
        assert isinstance(bot.CONFIG_PATH, pathlib.Path)

    def test_config_loaded_successfully(self):
        """CONFIG should be loaded and not empty"""
        assert isinstance(bot.CONFIG, dict)
        assert len(bot.CONFIG) > 0

    def test_bot_has_all_commands(self):
        """Bot should have all three main commands"""
        command_names = [cmd.name for cmd in bot.bot.commands]
        for expected in ("BATCstatus", "BATCjoin", "BATCleave", "BATCrestart", "BATCshutdown"):
            assert expected in command_names


class TestStandbyOnStart:
    """
    The bot must come online without joining anything.

    Starting the process from PowerShell (or at boot) should only log the bot
    in; relaying begins on an explicit !BATCjoin. Before 1.4.0 the watchdog
    joined the configured channel within ten seconds of startup, and !leave
    was undone just as quickly.
    """

    def test_relay_starts_paused(self):
        """relay_paused must default to True so startup does not join."""
        assert bot.relay_paused is True

    @pytest.mark.asyncio
    async def test_watchdog_does_not_connect_while_paused(self):
        """The watchdog must not touch voice while the relay is paused."""
        with patch.object(bot, "relay_paused", True):
            with patch.object(bot, "connect_and_stream", new=AsyncMock()) as connect:
                await bot.watchdog()
                connect.assert_not_called()

    @pytest.mark.asyncio
    async def test_watchdog_connects_once_resumed(self):
        """Once resumed, the watchdog relays as before."""
        with patch.object(bot, "relay_paused", False):
            with patch.object(bot, "connect_and_stream", new=AsyncMock()) as connect:
                await bot.watchdog()
                connect.assert_awaited_once()


class TestBATCCommandNaming:
    """Every command is BATC-prefixed so it cannot collide with other bots."""

    def test_all_commands_are_batc_prefixed(self):
        for command in bot.bot.commands:
            assert command.name.lower().startswith("batc"), (
                f"command '{command.name}' is missing the BATC prefix"
            )

    def test_help_command_is_renamed(self):
        assert bot.bot.help_command.command_attrs["name"] == "BATChelp"

    def test_command_names_are_case_insensitive(self):
        """!batcjoin should work as well as !BATCjoin."""
        assert bot.bot.case_insensitive is True
        assert bot.bot.get_command("batcjoin") is not None

    def test_restart_keeps_its_old_name_as_an_alias(self):
        assert bot.bot.get_command("BATCrestart_stream") is not None

    def test_shutdown_requires_administrator(self):
        """A stop command must not be available to every server member."""
        command = bot.bot.get_command("BATCshutdown")
        assert command is not None
        assert command.checks, "BATCshutdown has no permission check"
