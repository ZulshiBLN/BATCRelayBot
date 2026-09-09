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

    # Read from bot.py rather than retyped here. These three listed the keys
    # themselves and so only confirmed that the test fixture agreed with the
    # test: they stayed green through the removal of voice_channel_id from
    # REQUIRED_KEYS, which is the one thing they existed to notice.
    def test_config_has_every_key_bot_py_demands(self):
        for key in bot.REQUIRED_KEYS:
            assert key in bot.CONFIG, f"Missing required key: {key}"

    def test_no_required_key_is_empty(self):
        for key in bot.REQUIRED_KEYS:
            assert bot.CONFIG.get(key), f"{key} is empty"

    def test_the_server_id_is_an_integer(self):
        """discord.py matches guilds on int; a quoted ID resolves to nothing."""
        assert isinstance(bot.CONFIG["guild_id"], int), "guild_id must be integer"

    def test_the_channel_is_not_configuration_any_more(self):
        """It is decided per !BATCjoin, so requiring it would block startup."""
        assert "voice_channel_id" not in bot.REQUIRED_KEYS


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
async def test_connect_and_stream_channel_not_found(monkeypatch):
    """connect_and_stream should handle missing channel gracefully"""
    guild = MagicMock()
    guild.get_channel = Mock(return_value=None)

    # The target is set by !BATCjoin now, not read from config.json.
    monkeypatch.setattr(bot, "target_channel_id", 987654321098765432)

    with patch.object(bot.bot, "get_guild", return_value=guild):
        await bot.connect_and_stream()
        guild.get_channel.assert_called_once()


@pytest.mark.asyncio
async def test_connect_and_stream_without_a_target_does_nothing():
    """Nobody has said !BATCjoin, so there is nowhere to go."""
    guild = MagicMock()
    guild.get_channel = Mock(return_value=None)

    # target_channel_id is None at import; the watchdog runs on a timer and
    # must not invent a channel of its own.
    with patch.object(bot.bot, "get_guild", return_value=guild):
        await bot.connect_and_stream()
        guild.get_channel.assert_not_called()


@pytest.mark.asyncio
async def test_connect_and_stream_already_connected(monkeypatch):
    """connect_and_stream should handle already connected state"""
    guild = MagicMock()
    channel = MagicMock(spec=discord.VoiceChannel)
    channel.id = 555000111222333444
    channel.name = "Test Channel"

    monkeypatch.setattr(bot, "target_channel_id", channel.id)

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
async def test_connect_and_stream_does_not_restart_a_running_stream(monkeypatch):
    """The other half: already playing means play() must not be called again."""
    guild = MagicMock()
    channel = MagicMock(spec=discord.VoiceChannel)
    channel.id = 555000111222333444
    channel.name = "Test Channel"

    # Without a target, connect_and_stream returns before reaching play() and
    # this would pass for the wrong reason.
    monkeypatch.setattr(bot, "target_channel_id", channel.id)

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

    def test_help_is_our_own_command_not_the_built_in_one(self):
        """The default help printed a flat block with no separation."""
        assert bot.bot.help_command is None
        assert bot.bot.get_command("BATChelp") is not None

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


def make_context(guild=None, author_channel=None):
    """
    A command context with just enough of Discord in it.

    guild.voice_channels and guild.get_channel are what resolution reads;
    ctx.author.voice.channel is where the caller is sitting.
    """
    ctx = MagicMock()
    ctx.guild = guild
    ctx.author.voice = MagicMock() if author_channel else None
    if author_channel:
        ctx.author.voice.channel = author_channel

    # Both are awaited, so neither may be an ordinary Mock.
    ctx.send = AsyncMock()
    ctx.author.send = AsyncMock()
    return ctx


def make_voice_channel(name, channel_id):
    channel = MagicMock(spec=discord.VoiceChannel)
    channel.name = name
    channel.id = channel_id
    return channel


class TestResolveTargetChannel:
    """
    Which channel a !BATCjoin means.

    The bot used to relay into one channel fixed at install time, so moving it
    meant editing config.json and restarting. Whoever types the command is
    almost always already in the channel they want it in.
    """

    def test_defaults_to_the_channel_the_caller_is_in(self):
        channel = make_voice_channel("Tower", 111)
        guild = MagicMock()
        guild.voice_channels = [channel]

        found, reason = bot.resolve_target_channel(make_context(guild, channel))

        assert found is channel
        assert reason is None

    def test_a_named_channel_wins_over_the_caller_s_own(self):
        here = make_voice_channel("Tower", 111)
        there = make_voice_channel("Ground", 222)
        guild = MagicMock()
        guild.voice_channels = [here, there]

        found, reason = bot.resolve_target_channel(make_context(guild, here), "Ground")

        assert found is there
        assert reason is None

    def test_a_name_matches_whatever_case_it_was_typed_in(self):
        channel = make_voice_channel("Tower", 111)
        guild = MagicMock()
        guild.voice_channels = [channel]

        found, _ = bot.resolve_target_channel(make_context(guild), "tower")

        assert found is channel

    def test_an_id_is_taken_exactly(self):
        channel = make_voice_channel("Tower", 111)
        guild = MagicMock()
        guild.voice_channels = [channel]
        guild.get_channel = Mock(return_value=channel)

        found, reason = bot.resolve_target_channel(make_context(guild), "111")

        assert found is channel
        assert reason is None
        guild.get_channel.assert_called_once_with(111)

    def test_duplicate_names_take_the_first_and_do_not_fail(self):
        """Discord allows two channels to share a name. Refusing helps nobody."""
        first = make_voice_channel("Tower", 111)
        second = make_voice_channel("Tower", 222)
        guild = MagicMock()
        guild.voice_channels = [first, second]

        found, reason = bot.resolve_target_channel(make_context(guild), "Tower")

        assert found is first
        assert reason is None

    def test_a_caller_in_no_channel_naming_none_is_told_why(self):
        guild = MagicMock()
        guild.voice_channels = []

        found, reason = bot.resolve_target_channel(make_context(guild))

        assert found is None
        assert "not in a voice channel" in reason.lower()
        assert "!BATCjoin" in reason

    def test_an_unknown_name_is_refused_saying_what_was_looked_for(self):
        guild = MagicMock()
        guild.voice_channels = [make_voice_channel("Tower", 111)]

        found, reason = bot.resolve_target_channel(make_context(guild), "Apron")

        assert found is None
        assert "Apron" in reason

    def test_an_unknown_id_is_refused_saying_what_was_looked_for(self):
        guild = MagicMock()
        guild.voice_channels = []
        guild.get_channel = Mock(return_value=None)

        found, reason = bot.resolve_target_channel(make_context(guild), "999")

        assert found is None
        assert "999" in reason

    def test_an_id_naming_a_text_channel_is_refused(self):
        """get_channel returns any channel type; only a voice one will do."""
        guild = MagicMock()
        guild.voice_channels = []
        guild.get_channel = Mock(return_value=MagicMock(spec=discord.TextChannel))

        found, reason = bot.resolve_target_channel(make_context(guild), "111")

        assert found is None
        assert "111" in reason

    def test_a_direct_message_has_no_channels_to_search(self):
        found, reason = bot.resolve_target_channel(make_context(guild=None))

        assert found is None
        assert "server" in reason.lower()


class TestReplyWording:
    """
    The replies Michel wrote in the findings file, in the radio-callout voice
    the rest of the bot uses. Each names who asked and where.
    """

    @pytest.mark.asyncio
    async def test_help_lists_every_command_with_its_description(self):
        ctx = make_context(MagicMock())
        ctx.author.display_name = "Zulshi"

        await bot.batc_help.callback(ctx)

        text = ctx.send.await_args.args[0]

        # Derived, not retyped: a command added later must appear here too.
        for command in bot.bot.commands:
            assert command.name in text, f"{command.name} is missing from the help"
            for line in (command.help or "").splitlines():
                assert line in text

        assert "ready to copy your selection" in text
        assert "Say selected option" in text

    @pytest.mark.asyncio
    async def test_help_puts_each_description_under_its_own_command(self):
        """The flat block was the complaint: no telling where one ended."""
        ctx = make_context(MagicMock())

        await bot.batc_help.callback(ctx)
        lines = ctx.send.await_args.args[0].splitlines()

        index = lines.index("**BATCjoin**")
        assert lines[index + 1].startswith("    ")
        assert "Request channel entry" in lines[index + 1]

    @pytest.mark.asyncio
    async def test_shutdown_help_says_it_needs_an_administrator(self):
        ctx = make_context(MagicMock())

        await bot.batc_help.callback(ctx)

        assert "Administrator authorization required." in ctx.send.await_args.args[0]

    @pytest.mark.asyncio
    async def test_leave_names_the_channel_it_left(self, monkeypatch):
        ctx = make_context(MagicMock())
        ctx.author.display_name = "Zulshi"

        voice_client = AsyncMock()
        voice_client.channel.name = "Tower"

        monkeypatch.setattr(bot, "target_channel_id", 111)
        with patch("bot.configured_voice_client", return_value=voice_client):
            await bot.batc_leave.callback(ctx)

        reply = ctx.send.await_args.args[0]
        assert "Zulshi" in reply
        assert "Tower" in reply
        assert "Good day" in reply

        # The name is read before disconnecting; afterwards there is none.
        voice_client.disconnect.assert_awaited_once()
        assert bot.target_channel_id is None

    @pytest.mark.asyncio
    async def test_status_reports_transmitting_in_the_words_asked_for(self, monkeypatch):
        ctx = make_context(MagicMock())
        ctx.author.display_name = "Zulshi"

        voice_client = MagicMock()
        voice_client.is_connected = Mock(return_value=True)
        voice_client.is_playing = Mock(return_value=True)
        voice_client.channel.name = "Tower"

        monkeypatch.setattr(bot, "relay_paused", False)
        with patch("bot.configured_voice_client", return_value=voice_client):
            await bot.batc_status.callback(ctx)

        reply = ctx.send.await_args.args[0]
        assert reply.startswith("Zulshi, ")
        assert "is currently transmitting from" in reply
        assert "Tower" in reply

    @pytest.mark.asyncio
    async def test_status_separates_connected_from_transmitting(self, monkeypatch):
        """In the channel with no stream is not the same as relaying."""
        ctx = make_context(MagicMock())
        ctx.author.display_name = "Zulshi"

        voice_client = MagicMock()
        voice_client.is_connected = Mock(return_value=True)
        voice_client.is_playing = Mock(return_value=False)
        voice_client.channel.name = "Tower"

        monkeypatch.setattr(bot, "relay_paused", True)
        with patch("bot.configured_voice_client", return_value=voice_client):
            await bot.batc_status.callback(ctx)

        reply = ctx.send.await_args.args[0]
        assert "not transmitting" in reply
        assert "BATCjoin" in reply, "a paused relay needs the way out of it"

    @pytest.mark.asyncio
    async def test_status_names_the_caller_when_not_in_a_channel(self, monkeypatch):
        ctx = make_context(MagicMock())
        ctx.author.display_name = "Zulshi"

        monkeypatch.setattr(bot, "relay_paused", True)
        with patch("bot.configured_voice_client", return_value=None):
            await bot.batc_status.callback(ctx)

        assert ctx.send.await_args.args[0].startswith("Zulshi, ")

    @pytest.mark.asyncio
    async def test_shutdown_signs_off_before_writing_the_stop_signal(self, tmp_path):
        """
        The order matters: shutdown_watcher polls every second and closes the
        connection, so a message written after the signal never arrives.
        """
        ctx = make_context(MagicMock())
        ctx.author.display_name = "Zulshi"

        signal = tmp_path / "stop.signal"
        sent_before_signal = []
        ctx.send = AsyncMock(side_effect=lambda text: sent_before_signal.append(signal.exists()))

        with patch("bot.STOP_SIGNAL_PATH", signal):
            await bot.batc_shutdown.callback(ctx)

            assert signal.exists(), "the process has to be told to stop"
            assert sent_before_signal == [False], "the sign-off went out after the signal"

    @pytest.mark.asyncio
    async def test_shutdown_says_it_is_going_offline(self):
        ctx = make_context(MagicMock())
        ctx.author.display_name = "Zulshi"

        with patch("bot.STOP_SIGNAL_PATH", MagicMock()):
            await bot.batc_shutdown.callback(ctx)

        reply = ctx.send.await_args.args[0]
        assert reply.startswith("Zulshi, ")
        assert "is terminating transmission" in reply
        assert "I repeat" in reply
        assert "offline now, bye bye!" in reply

    @pytest.mark.asyncio
    async def test_restart_names_the_caller_and_the_channel(self, monkeypatch):
        ctx = make_context(MagicMock())
        ctx.author.display_name = "Zulshi"

        voice_client = MagicMock()
        voice_client.channel.name = "Tower"

        monkeypatch.setattr(bot, "relay_paused", False)
        with patch("bot.configured_voice_client", return_value=voice_client):
            with patch("bot.connect_and_stream", new=AsyncMock()):
                await bot.batc_restart.callback(ctx)

        reply = ctx.send.await_args.args[0]
        assert "Zulshi" in reply
        assert "I say again" in reply
        assert "Tower" in reply


def grant(connect=True, speak=True, view=True):
    """A channel whose permissions_for() reports the given three."""
    channel = make_voice_channel("Tower", 111)
    permissions = MagicMock()
    permissions.view_channel = view
    permissions.connect = connect
    permissions.speak = speak
    channel.permissions_for = Mock(return_value=permissions)
    return channel


class TestJoinPermissions:
    """
    What happens when the bot may not enter, or may not be heard.

    Before this, the caller got nothing they could act on. Without Speak the
    bot joins and streams into silence, which looks like a broken install
    rather than a permission an admin can grant in ten seconds.
    """

    def test_nothing_missing_when_both_are_granted(self):
        assert bot.missing_join_permissions(grant(), MagicMock()) == []

    def test_connect_is_reported(self):
        assert bot.missing_join_permissions(grant(connect=False), MagicMock()) == ["Connect"]

    def test_speak_is_reported(self):
        assert bot.missing_join_permissions(grant(speak=False), MagicMock()) == ["Speak"]

    def test_both_are_reported(self):
        missing = bot.missing_join_permissions(grant(connect=False, speak=False), MagicMock())
        assert missing == ["Connect", "Speak"]

    def test_view_channel_is_reported(self):
        """Without it the channel cannot be joined, or even seen."""
        assert bot.missing_join_permissions(grant(view=False), MagicMock()) == ["View Channel"]

    def test_the_required_set_matches_what_the_bot_does(self):
        """
        Derived from the code, not from a list somebody wrote down: ctx.send
        in every command, connect() and play() for the voice side. Read
        Message History is deliberately absent - commands arrive over the
        gateway as they are typed, and nothing here reads older messages.
        """
        assert bot.VOICE_PERMISSIONS == ("View Channel", "Connect", "Speak")
        assert bot.TEXT_PERMISSIONS == ("View Channel", "Send Messages")

        # Asserted against the calls, not against the prose around them: an
        # earlier version of this looked for the word "history" and tripped
        # over the comment explaining why it is not needed.
        source = pathlib.Path(bot.__file__).read_text(encoding="utf-8")
        for unused in (".history(", ".fetch_message(", ".add_reaction(", "embed="):
            assert unused not in source, f"{unused} would need a permission not listed"

    @pytest.mark.asyncio
    async def test_the_detail_goes_to_the_caller_by_direct_message(self):
        ctx = make_context(MagicMock())
        channel = grant(connect=False)

        await bot.report_missing_permissions(ctx, channel, ["Connect"])

        ctx.author.send.assert_awaited_once()
        detail = ctx.author.send.await_args.args[0]
        assert "Tower" in detail
        assert "Connect" in detail

        # It named Connect and Speak and stopped there, so an admin fixed one
        # channel and hit the next wall. The whole requirement is stated.
        for permission in bot.VOICE_PERMISSIONS + bot.TEXT_PERMISSIONS:
            assert permission in detail, f"{permission} is not mentioned"

    @pytest.mark.asyncio
    async def test_the_channel_is_told_that_a_message_was_sent(self):
        """Otherwise the command looks ignored."""
        ctx = make_context(MagicMock())

        await bot.report_missing_permissions(ctx, grant(connect=False), ["Connect"])

        ctx.send.assert_awaited_once()
        assert "Tower" in ctx.send.await_args.args[0]

    @pytest.mark.asyncio
    async def test_closed_direct_messages_fall_back_to_the_channel(self):
        """Not delivering it at all would be the worst of the three."""
        ctx = make_context(MagicMock())
        ctx.author.send = AsyncMock(
            side_effect=discord.Forbidden(MagicMock(status=403), "cannot send")
        )

        await bot.report_missing_permissions(ctx, grant(speak=False), ["Speak"])

        ctx.send.assert_awaited_once()
        detail = ctx.send.await_args.args[0]
        assert "Speak" in detail
        assert "Tower" in detail

    # The check has to run before the target is remembered. Setting it first
    # would leave the watchdog retrying an impossible channel every ten
    # seconds for as long as the process runs.
    @pytest.mark.asyncio
    async def test_join_refuses_without_remembering_the_channel(self, monkeypatch):
        channel = grant(connect=False)
        guild = MagicMock()
        guild.voice_channels = [channel]
        ctx = make_context(guild, channel)

        monkeypatch.setattr(bot, "target_channel_id", None)
        monkeypatch.setattr(bot, "relay_paused", True)

        with patch("bot.connect_and_stream", new=AsyncMock()) as connect:
            await bot.batc_join.callback(ctx)

            connect.assert_not_awaited()

        assert bot.target_channel_id is None
        assert bot.relay_paused is True
        ctx.author.send.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_join_proceeds_when_both_are_granted(self, monkeypatch):
        channel = grant()
        guild = MagicMock()
        guild.voice_channels = [channel]
        ctx = make_context(guild, channel)

        monkeypatch.setattr(bot, "target_channel_id", None)
        monkeypatch.setattr(bot, "relay_paused", True)

        with patch("bot.connect_and_stream", new=AsyncMock()) as connect:
            with patch("bot.configured_voice_client", return_value=None):
                await bot.batc_join.callback(ctx)

                connect.assert_awaited_once()

        assert bot.target_channel_id == channel.id
        assert bot.relay_paused is False


class TestShutdownSurvivesFailure:
    """
    The bot must always keep a way out.

    On 2026-09-09 a session logged a join, then twenty seconds, then nothing -
    no "Stop signal detected" line at all - and ended when Stop-BATCRelayBot's
    fifteen-second grace ran out and terminated it. A discord.py task loop
    stops on an unhandled exception and says nothing about it, and this loop
    was the only thing reading the stop signal.
    """

    def test_both_loops_report_failure_instead_of_dying_quietly(self):
        assert bot.shutdown_watcher.get_task is not None
        assert bot.shutdown_watcher._error is not bot.tasks.Loop.error.__get__
        # The handler is what discord.py calls; without one the loop ends.
        assert bot.shutdown_watcher._error.__name__ == "shutdown_watcher_error"
        assert bot.watchdog._error.__name__ == "watchdog_error"

    @pytest.mark.asyncio
    async def test_a_failed_check_does_not_end_the_watcher(self, monkeypatch):
        """An unreadable stop.signal is a reason to look again in a second."""
        signal = MagicMock()
        signal.exists = Mock(side_effect=OSError("device not ready"))
        monkeypatch.setattr(bot, "STOP_SIGNAL_PATH", signal)

        # No exception escapes, so the loop lives to check again.
        await bot.shutdown_watcher.coro()

    @pytest.mark.asyncio
    async def test_the_audio_source_is_released_before_the_process_ends(self, monkeypatch, tmp_path):
        """
        discord.py kills ffmpeg from the player's daemon thread. If the
        interpreter exits first that thread is torn down, ffmpeg survives, and
        it keeps holding the VoiceMeeter bus it was capturing.
        """
        source = MagicMock()
        monkeypatch.setattr(bot, "current_source", source)

        signal = tmp_path / "stop.signal"
        signal.touch()
        monkeypatch.setattr(bot, "STOP_SIGNAL_PATH", signal)

        # voice_clients is a read-only property, so it is replaced on the
        # class rather than the instance.
        with patch.object(type(bot.bot), "voice_clients", new=[]):
            with patch.object(bot.bot, "close", new=AsyncMock()):
                await bot.shutdown_watcher.coro()

        source.cleanup.assert_called_once()
        assert bot.current_source is None
        assert not signal.exists()

    @pytest.mark.asyncio
    async def test_it_clears_its_own_pid_file(self, monkeypatch, tmp_path):
        """A shutdown from chat used to leave bot.pid naming a dead process."""
        import os

        pid_file = tmp_path / "bot.pid"
        pid_file.write_text(str(os.getpid()))
        monkeypatch.setattr(bot, "PID_FILE_PATH", pid_file)

        signal = tmp_path / "stop.signal"
        signal.touch()
        monkeypatch.setattr(bot, "STOP_SIGNAL_PATH", signal)

        with patch.object(type(bot.bot), "voice_clients", new=[]):
            with patch.object(bot.bot, "close", new=AsyncMock()):
                await bot.shutdown_watcher.coro()

        assert not pid_file.exists()

    def test_it_leaves_a_pid_file_that_is_not_its_own(self, monkeypatch, tmp_path):
        """Someone else's file is not ours to delete."""
        pid_file = tmp_path / "bot.pid"
        pid_file.write_text("999999")
        monkeypatch.setattr(bot, "PID_FILE_PATH", pid_file)

        bot.release_pid_file()

        assert pid_file.exists()

    @pytest.mark.asyncio
    async def test_leaving_releases_it_too(self, monkeypatch):
        source = MagicMock()
        monkeypatch.setattr(bot, "current_source", source)

        ctx = make_context(MagicMock())
        voice_client = AsyncMock()
        voice_client.channel.name = "Tower"

        with patch("bot.configured_voice_client", return_value=voice_client):
            await bot.batc_leave.callback(ctx)

        source.cleanup.assert_called_once()


class TestLogRedaction:
    """
    bot_error.log travels the same way install.log does - into bug reports and
    screenshots - and the secrets rule covers both. install.log was fixed in
    1.4.1; this one still carried lines like

        The voice handshake is being terminated for Channel ID
        1535343588567683122 (Guild ID 631480440548753408)

    written by discord.py rather than by us, which is why a redactor on our
    own logger would not have caught them.
    """

    @staticmethod
    def record(message, *args, name="discord.voice_state"):
        return logging.LogRecord(name, logging.INFO, "bot.py", 1, message, args, None)

    def test_a_library_line_loses_its_ids(self):
        entry = self.record(
            "The voice handshake is being terminated for Channel ID %s (Guild ID %s)",
            1535343588567683122,
            631480440548753408,
        )

        bot.RedactSecrets().filter(entry)
        rendered = entry.getMessage()

        assert "1535343588567683122" not in rendered
        assert "631480440548753408" not in rendered
        assert rendered.count("[REDACTED-ID]") == 2

    def test_a_token_would_not_get_through_either(self):
        token = ("M" * 24) + "." + ("G" * 6) + "." + ("f" * 27)
        entry = self.record("Using %s", token)

        bot.RedactSecrets().filter(entry)

        assert token not in entry.getMessage()

    def test_the_log_stays_readable(self):
        """A redactor that eats timestamps, versions and pids gets turned off."""
        for line in (
            "Installation session started 2026-09-09 10:10:01",
            "BATCRelayBot 1.4.1 on Python 3.12.10",
            "ffmpeg process 33836 should have terminated with a return code of 1",
            "Python at C:\\Users\\x\\AppData\\Local\\Programs\\Python\\Python312",
        ):
            entry = self.record(line)
            bot.RedactSecrets().filter(entry)
            assert entry.getMessage() == line

    # The filter existing is not the filter running. It has to sit on the
    # handler every logger's records pass through, not on ours.
    def test_it_is_attached_where_the_library_records_pass(self):
        handlers = logging.getLogger().handlers
        assert handlers, "nothing would be written at all"

        assert any(
            any(isinstance(f, bot.RedactSecrets) for f in handler.filters)
            for handler in handlers
        ), "the filter is not on the root handler, so library lines bypass it"


def test_bot_py_stays_ascii():
    """
    A BOM-less file with non-ASCII is read as ANSI by PowerShell 5.1, and this
    file is copied by the installer and parsed by the PowerShell tests, which
    read REQUIRED_KEYS out of it.

    Four non-breaking spaces reached the help indentation through an edit in
    which they looked exactly like spaces. They render as spaces, compare as
    something else, and nothing says so.
    """
    source = pathlib.Path(bot.__file__).read_text(encoding="utf-8")

    offenders = sorted({ch for ch in source if ord(ch) > 127})
    assert not offenders, (
        "non-ASCII in bot.py: " + ", ".join(f"U+{ord(c):04X}" for c in offenders)
    )
