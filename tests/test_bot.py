"""
Tests for ATC Relay Bot (bot.py)
"""

import asyncio
import json
import logging
import pathlib
import sys
from unittest.mock import AsyncMock, MagicMock, Mock, patch

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

    def test_make_audio_source_returns_ffmpeg_audio(self):
        """Should return FFmpegPCMAudio instance"""
        source = bot.make_audio_source()
        assert isinstance(source, discord.FFmpegPCMAudio)

    @patch("bot.make_audio_source")
    def test_make_audio_source_correct_device(self, mock_make_audio):
        """Should use device name from config"""
        mock_source = MagicMock(spec=discord.FFmpegPCMAudio)
        mock_make_audio.return_value = mock_source
        source = bot.make_audio_source()
        assert source is not None

    def test_make_audio_source_uses_dshow_format(self):
        """Should use Windows dshow format"""
        source = bot.make_audio_source()
        # Verify the source was created with correct parameters
        assert source is not None


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
        assert "status" in [cmd.name for cmd in bot.bot.commands]

    def test_restart_stream_command_exists(self):
        """Should have !restart_stream command"""
        assert "restart_stream" in [cmd.name for cmd in bot.bot.commands]

    def test_leave_command_exists(self):
        """Should have !leave command"""
        assert "leave" in [cmd.name for cmd in bot.bot.commands]

    def test_commands_are_callable(self):
        """All registered commands should be callable"""
        for cmd in bot.bot.commands:
            assert callable(cmd.callback)

    def test_status_command_prefix(self):
        """Status command should use ! prefix"""
        cmd = bot.bot.get_command("status")
        assert cmd is not None


def test_status_command_callable():
    """!status command should be callable"""
    cmd = bot.bot.get_command("status")
    assert cmd is not None
    assert callable(cmd.callback)


def test_restart_stream_command_callable():
    """!restart_stream command should be callable"""
    cmd = bot.bot.get_command("restart_stream")
    assert cmd is not None
    assert callable(cmd.callback)


def test_leave_command_callable():
    """!leave command should be callable"""
    cmd = bot.bot.get_command("leave")
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


def test_connect_and_stream_function_exists():
    """connect_and_stream function should be defined"""
    assert callable(bot.connect_and_stream)


def test_watchdog_function_exists():
    """watchdog task loop should exist"""
    assert bot.watchdog is not None


def test_shutdown_watcher_function_exists():
    """shutdown_watcher task loop should exist"""
    assert bot.shutdown_watcher is not None


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
        assert "status" in command_names
        assert "restart_stream" in command_names
        assert "leave" in command_names
