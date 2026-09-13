"""
Tests for the BeyondATC transcript reaching Discord: the feed the loop
drains, the message format, the loop itself, and the !BATCtext command with
its join and leave wiring. The parser and tailer are in test_batc_log.py.
"""

import logging
import pathlib
import tempfile
from unittest.mock import AsyncMock, MagicMock, patch

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

from tests.test_batc_log import exchange


def transmission(text, sim_time="Friday 19:10", com1="121.755"):
    return bot.Transmission(sim_time, com1, text)


class TestTranscriptFeed:
    """Tailer and parser together, the unit the loop drains."""

    def test_yields_the_controllers_lines_as_they_are_appended(self, tmp_path):
        log = tmp_path / "Player.log"
        log.write_text("", encoding="utf-8")
        feed = bot.TranscriptFeed(log)
        feed.poll()
        with log.open("a", encoding="utf-8") as f:
            f.write("\n".join(exchange()) + "\n")
        assert [t.text for t in feed.poll()] == ["Swiss 874, taxi to holding point A1."]

    def test_forgets_learned_voices_when_the_file_is_replaced(self, tmp_path):
        # Voice ids are handed out per session. Yesterday's controller id can
        # be today's copilot, so a new file means a new parser.
        log = tmp_path / "Player.log"
        log.write_text("first session\n" * 100, encoding="utf-8")
        feed = bot.TranscriptFeed(log)
        feed.poll()
        with log.open("a", encoding="utf-8") as f:
            f.write("\n".join(exchange(controller_voice="500")) + "\n")
        assert len(feed.poll()) == 1

        # New session, and voice 500 speaks without ever following a script.
        log.write_text("\n".join(exchange(controller_voice="500")[1:]) + "\n", encoding="utf-8")
        assert feed.poll() == []


class TestFormat:

    def test_clock_frequency_and_text(self):
        assert bot.format_transmission(transmission("Swiss 874, climb FL100.")) == (
            "**19:10** · 121.755 · Swiss 874, climb FL100."
        )

    def test_text_alone_when_no_player_state_preceded_it(self):
        assert bot.format_transmission(transmission("Swiss 874, climb FL100.", None, None)) == (
            "Swiss 874, climb FL100."
        )

class TestFitLines:
    """How many lines go onto a page before it is full."""

    def test_takes_what_fits_and_returns_the_rest(self):
        text, rest = bot.fit_lines("", ["a" * 900, "b" * 900, "c" * 900])
        assert text == "a" * 900 + "\n" + "b" * 900
        assert rest == ["c" * 900]

    def test_appends_to_existing_text_with_a_newline(self):
        text, rest = bot.fit_lines("first", ["second"])
        assert text == "first\nsecond"
        assert rest == []

    def test_the_boundary_is_inclusive(self):
        # 1999 + newline + 0 characters would be 2000: a one-character line
        # does not fit, an empty page takes exactly 2000.
        text, rest = bot.fit_lines("x" * 1999, ["y"])
        assert (text, rest) == ("x" * 1999, ["y"])
        text, rest = bot.fit_lines("x" * 1998, ["y"])
        assert (text, rest) == ("x" * 1998 + "\ny", [])

    def test_a_line_longer_than_a_page_is_cut_rather_than_stuck(self):
        # Otherwise nothing ever fits and the loop spins on it for ever.
        text, rest = bot.fit_lines("", ["z" * 2500])
        assert len(text) == 2000
        assert rest == []


def new_message(message_id=1):
    message = MagicMock()
    message.id = message_id
    message.edit = AsyncMock()
    return message


def relay_setup(monkeypatch, transmissions, enabled=True, channel_id=42, channel="default", record_dir=None):
    feed = MagicMock()
    feed.poll.return_value = transmissions
    if channel == "default":
        channel = MagicMock()
        channel.id = channel_id
        ids = iter(range(1000, 2000))
        channel.send = AsyncMock(side_effect=lambda content: new_message(next(ids)))
    monkeypatch.setattr(bot, "transcript_feed", feed)
    monkeypatch.setattr(bot, "text_enabled", enabled)
    monkeypatch.setattr(bot, "text_channel_id", channel_id)
    monkeypatch.setattr(bot, "current_page", None)
    monkeypatch.setattr(bot, "pending_lines", [])
    record_dir = record_dir or pathlib.Path(tempfile.mkdtemp())
    monkeypatch.setattr(bot, "session_record", bot.SessionRecord(record_dir / "transcript-session.json"))
    monkeypatch.setattr(bot.bot, "get_channel", MagicMock(return_value=channel))
    return feed, channel


class TestTranscriptRelayLoop:

    def test_loop_exists_and_runs_every_second(self):
        assert isinstance(bot.transcript_relay, discord.ext.tasks.Loop)
        assert bot.transcript_relay.seconds == 1

    @pytest.mark.asyncio
    async def test_on_ready_starts_it(self):
        bot.watchdog.start = MagicMock()
        bot.shutdown_watcher.start = MagicMock()
        bot.transcript_relay.start = MagicMock()
        bot.watchdog.is_running = MagicMock(return_value=True)
        bot.shutdown_watcher.is_running = MagicMock(return_value=True)
        bot.transcript_relay.is_running = MagicMock(return_value=False)
        await bot.on_ready()
        bot.transcript_relay.start.assert_called_once()

    @pytest.mark.asyncio
    async def test_drains_the_file_but_posts_nothing_while_off(self, monkeypatch):
        # Draining keeps the parser learning voices, and stops a backlog from
        # being dumped the moment someone switches the feed on.
        feed, channel = relay_setup(monkeypatch, [transmission("Swiss 874, climb FL100.")], enabled=False)

        await bot.transcript_relay()

        feed.poll.assert_called_once()
        channel.send.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_posts_what_arrived_as_one_message(self, monkeypatch):
        _, channel = relay_setup(monkeypatch, [
            transmission("Swiss 874, climb FL100."),
            transmission("Swiss 874, contact Swiss Radar 133.905.", "Friday 19:11"),
        ])

        await bot.transcript_relay()

        channel.send.assert_awaited_once_with(
            "**19:10** · 121.755 · Swiss 874, climb FL100.\n"
            "**19:11** · 121.755 · Swiss 874, contact Swiss Radar 133.905."
        )

    @pytest.mark.asyncio
    async def test_nothing_new_sends_nothing(self, monkeypatch):
        _, channel = relay_setup(monkeypatch, [])

        await bot.transcript_relay()

        channel.send.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_a_refused_send_switches_the_feed_off_and_says_so_once(self, monkeypatch, caplog):
        # Otherwise the loop fails every second for as long as the process
        # runs, and the log fills with the same line.
        _, channel = relay_setup(monkeypatch, [transmission("Swiss 874, climb FL100.")])
        channel.send = AsyncMock(side_effect=discord.Forbidden(MagicMock(status=403), "Missing Access"))

        with caplog.at_level(logging.WARNING):
            await bot.transcript_relay()

        assert bot.text_enabled is False
        assert any("Send Messages" in r.getMessage() for r in caplog.records)

    @pytest.mark.asyncio
    async def test_a_channel_that_is_gone_does_not_raise(self, monkeypatch):
        relay_setup(monkeypatch, [transmission("Swiss 874, climb FL100.")], channel=None)

        await bot.transcript_relay()


class TestPages:
    """
    One message, edited as lines arrive; a new one only when the next line
    would not fit. Michel chose this over a message per line: a flight is
    one page, two or three at most, instead of thirty messages.
    """

    @pytest.mark.asyncio
    async def test_a_later_line_is_appended_by_editing_not_by_a_new_message(self, monkeypatch):
        feed, channel = relay_setup(monkeypatch, [transmission("Swiss 874, climb FL100.")])
        await bot.transcript_relay()
        page = bot.current_page.message

        feed.poll.return_value = [transmission("Swiss 874, contact Swiss Radar 133.905.", "Friday 19:11")]
        await bot.transcript_relay()

        channel.send.assert_awaited_once()
        page.edit.assert_awaited_once_with(
            content="**19:10** · 121.755 · Swiss 874, climb FL100.\n"
                    "**19:11** · 121.755 · Swiss 874, contact Swiss Radar 133.905."
        )

    @pytest.mark.asyncio
    async def test_a_new_page_starts_only_when_the_line_would_not_fit(self, monkeypatch):
        long = transmission("x" * 1950, None, None)
        feed, channel = relay_setup(monkeypatch, [long])
        await bot.transcript_relay()
        first = bot.current_page.message

        # 1950 + newline + 49 = 2000: fits, so an edit.
        feed.poll.return_value = [transmission("y" * 49, None, None)]
        await bot.transcript_relay()
        first.edit.assert_awaited_once()
        assert channel.send.await_count == 1

        # One more character does not, so a second page.
        feed.poll.return_value = [transmission("z", None, None)]
        await bot.transcript_relay()
        assert channel.send.await_count == 2
        assert channel.send.await_args.args[0] == "z"
        assert len(bot.session_record.load()[1]) == 2

    @pytest.mark.asyncio
    async def test_a_failed_edit_keeps_the_line_for_the_next_poll(self, monkeypatch, caplog):
        feed, channel = relay_setup(monkeypatch, [transmission("Swiss 874, climb FL100.")])
        await bot.transcript_relay()
        page = bot.current_page.message
        page.edit = AsyncMock(side_effect=[
            discord.HTTPException(MagicMock(status=502), "Bad Gateway"),
            None,
        ])

        feed.poll.return_value = [transmission("Swiss 874, descend FL090.", "Friday 19:11")]
        with caplog.at_level(logging.WARNING):
            await bot.transcript_relay()
        assert bot.pending_lines == ["**19:11** · 121.755 · Swiss 874, descend FL090."]
        assert sum("ATC text" in r.getMessage() for r in caplog.records) == 1

        feed.poll.return_value = []
        await bot.transcript_relay()
        assert bot.pending_lines == []
        assert page.edit.await_count == 2
        assert page.edit.await_args.kwargs["content"].endswith("Swiss 874, descend FL090.")

    @pytest.mark.asyncio
    async def test_a_page_someone_deleted_is_replaced_by_a_new_one(self, monkeypatch):
        feed, channel = relay_setup(monkeypatch, [transmission("Swiss 874, climb FL100.")])
        await bot.transcript_relay()
        page = bot.current_page.message
        page.edit = AsyncMock(side_effect=discord.NotFound(MagicMock(status=404), "Unknown Message"))

        feed.poll.return_value = [transmission("Swiss 874, descend FL090.", "Friday 19:11")]
        await bot.transcript_relay()       # the edit 404s; the line stays pending
        feed.poll.return_value = []
        await bot.transcript_relay()       # next poll: a new page carries it

        assert channel.send.await_count == 2
        assert bot.current_page.message is not page
        assert bot.pending_lines == []

    @pytest.mark.asyncio
    async def test_switching_text_off_drops_what_was_pending_and_on_continues_the_page(self, monkeypatch):
        feed, channel = relay_setup(monkeypatch, [transmission("Swiss 874, climb FL100.")])
        await bot.transcript_relay()
        page = bot.current_page.message
        monkeypatch.setattr(bot, "pending_lines", ["stale"])

        ctx = make_text_context()
        await bot.batc_text.callback(ctx)      # off
        assert bot.pending_lines == []
        await bot.batc_text.callback(ctx)      # on again

        feed.poll.return_value = [transmission("Swiss 874, descend FL090.", "Friday 19:11")]
        await bot.transcript_relay()
        page.edit.assert_awaited_once()
        assert channel.send.await_count == 1

    @pytest.mark.asyncio
    async def test_join_starts_a_fresh_page(self, monkeypatch):
        monkeypatch.setattr(bot, "current_page", bot.TranscriptPage(new_message(), "old"))
        monkeypatch.setattr(bot, "pending_lines", ["old line"])
        monkeypatch.setattr(bot, "session_record", bot.SessionRecord(pathlib.Path(tempfile.mkdtemp()) / "r.json"))
        monkeypatch.setattr(bot.bot, "get_partial_messageable", MagicMock())
        monkeypatch.setattr(bot, "target_channel_id", None)
        monkeypatch.setattr(bot, "relay_paused", True)
        monkeypatch.setattr(bot, "text_channel_id", None)
        monkeypatch.setattr(bot, "text_enabled", False)
        voice = MagicMock(spec=discord.VoiceChannel)
        voice.name = "Tower"
        voice.id = 111
        voice.permissions_for.return_value = discord.Permissions.all()
        guild = MagicMock()
        guild.voice_channels = [voice]
        ctx = make_text_context()
        ctx.guild = guild
        ctx.author.voice = MagicMock()
        ctx.author.voice.channel = voice
        ctx.author.send = AsyncMock()

        with patch("bot.connect_and_stream", new=AsyncMock()):
            with patch("bot.configured_voice_client", return_value=None):
                await bot.batc_join.callback(ctx)

        assert bot.current_page is None
        assert bot.pending_lines == []


def make_text_context(channel_id=42, channel_name="tower-chat"):
    ctx = MagicMock()
    ctx.channel.id = channel_id
    ctx.channel.name = channel_name
    ctx.author.display_name = "Michel"
    ctx.send = AsyncMock()
    return ctx


class TestBATCtext:

    def test_command_exists(self):
        assert bot.bot.get_command("BATCtext") is not None

    @pytest.mark.asyncio
    async def test_without_a_join_it_stays_off_and_says_why(self, monkeypatch):
        monkeypatch.setattr(bot, "text_channel_id", None)
        monkeypatch.setattr(bot, "text_enabled", False)
        ctx = make_text_context()

        await bot.batc_text.callback(ctx)

        assert bot.text_enabled is False
        assert "BATCjoin" in ctx.send.await_args.args[0]

    @pytest.mark.asyncio
    async def test_toggles_on_and_names_the_channel(self, monkeypatch):
        monkeypatch.setattr(bot, "text_channel_id", 42)
        monkeypatch.setattr(bot, "text_enabled", False)
        ctx = make_text_context()

        await bot.batc_text.callback(ctx)

        assert bot.text_enabled is True
        reply = ctx.send.await_args.args[0]
        assert "on" in reply.lower()
        assert "tower-chat" in reply

    @pytest.mark.asyncio
    async def test_toggles_off_again(self, monkeypatch):
        monkeypatch.setattr(bot, "text_channel_id", 42)
        monkeypatch.setattr(bot, "text_enabled", True)
        ctx = make_text_context()

        await bot.batc_text.callback(ctx)

        assert bot.text_enabled is False
        assert "off" in ctx.send.await_args.args[0].lower()


class TestJoinAndLeaveCarryTheTextChannel:

    @pytest.mark.asyncio
    async def test_join_remembers_the_channel_it_was_typed_in_and_starts_off(self, monkeypatch):
        voice = MagicMock(spec=discord.VoiceChannel)
        voice.name = "Tower"
        voice.id = 111
        voice.permissions_for.return_value = discord.Permissions.all()
        guild = MagicMock()
        guild.voice_channels = [voice]
        ctx = make_text_context(channel_id=42)
        ctx.guild = guild
        ctx.author.voice = MagicMock()
        ctx.author.voice.channel = voice
        ctx.author.send = AsyncMock()

        monkeypatch.setattr(bot, "target_channel_id", None)
        monkeypatch.setattr(bot, "relay_paused", True)
        monkeypatch.setattr(bot, "text_channel_id", None)
        monkeypatch.setattr(bot, "text_enabled", True)

        with patch("bot.connect_and_stream", new=AsyncMock()):
            with patch("bot.configured_voice_client", return_value=None):
                await bot.batc_join.callback(ctx)

        assert bot.text_channel_id == 42
        assert bot.text_enabled is False

    @pytest.mark.asyncio
    async def test_leave_forgets_the_channel_and_switches_off(self, monkeypatch):
        monkeypatch.setattr(bot, "relay_paused", False)
        monkeypatch.setattr(bot, "target_channel_id", 111)
        monkeypatch.setattr(bot, "text_channel_id", 42)
        monkeypatch.setattr(bot, "text_enabled", True)
        ctx = make_text_context()

        with patch("bot.configured_voice_client", return_value=None):
            await bot.batc_leave.callback(ctx)

        assert bot.text_channel_id is None
        assert bot.text_enabled is False


# --- Phase 2: the record, and the pages leaving with the bot -------------------

import os
import stat


class TestSessionRecord:

    def test_remembers_pages_and_the_channel(self, tmp_path):
        record = bot.SessionRecord(tmp_path / "transcript-session.json")
        assert record.load() == (None, [])
        record.add(42, 1001)
        record.add(42, 1002)
        assert record.load() == (42, [1001, 1002])

    def test_a_new_channel_starts_a_new_list(self, tmp_path):
        record = bot.SessionRecord(tmp_path / "r.json")
        record.add(42, 1001)
        record.add(43, 2001)
        assert record.load() == (43, [2001])

    def test_clear_removes_the_file(self, tmp_path):
        record = bot.SessionRecord(tmp_path / "r.json")
        record.add(42, 1001)
        record.clear()
        assert not (tmp_path / "r.json").exists()
        assert record.load() == (None, [])

    def test_never_holds_more_than_the_cap(self, tmp_path):
        record = bot.SessionRecord(tmp_path / "r.json")
        for i in range(bot.SESSION_RECORD_CAP + 25):
            record.add(42, i)
        _, ids = record.load()
        assert len(ids) == bot.SESSION_RECORD_CAP
        assert ids[0] == 25 and ids[-1] == bot.SESSION_RECORD_CAP + 24

    def test_a_corrupt_file_reads_as_empty(self, tmp_path):
        path = tmp_path / "r.json"
        path.write_text("{not json", encoding="utf-8")
        assert bot.SessionRecord(path).load() == (None, [])

    @pytest.mark.skipif(os.name != "nt", reason="the Hidden attribute is a Windows thing")
    def test_the_file_is_hidden(self, tmp_path):
        record = bot.SessionRecord(tmp_path / "r.json")
        record.add(42, 1001)
        attributes = os.stat(tmp_path / "r.json").st_file_attributes
        assert attributes & stat.FILE_ATTRIBUTE_HIDDEN

    @pytest.mark.skipif(os.name != "nt", reason="the Hidden attribute is a Windows thing")
    def test_a_hidden_file_can_still_be_rewritten(self, tmp_path):
        record = bot.SessionRecord(tmp_path / "r.json")
        record.add(42, 1001)
        record.add(42, 1002)
        assert record.load() == (42, [1001, 1002])


def deletion_setup(monkeypatch, tmp_path, ids=(1001, 1002, 1003), channel_id=42, failing=None):
    """
    A record with pages in it, and a bot whose partial messages record what
    was deleted. `failing` maps a message id to the exception its delete
    raises.
    """
    record = bot.SessionRecord(tmp_path / "r.json")
    for i in ids:
        record.add(channel_id, i)
    monkeypatch.setattr(bot, "session_record", record)

    deleted = []
    order = []
    failing = failing or {}

    def partial(message_id):
        order.append("delete")
        pm = MagicMock()
        pm.id = message_id
        if message_id in failing:
            pm.delete = AsyncMock(side_effect=failing[message_id])
        else:
            async def delete():
                deleted.append(message_id)
            pm.delete = AsyncMock(side_effect=delete)
        return pm

    messageable = MagicMock()
    messageable.get_partial_message = MagicMock(side_effect=partial)
    monkeypatch.setattr(bot.bot, "get_partial_messageable", MagicMock(return_value=messageable))
    return record, deleted, order


def not_found():
    return discord.NotFound(MagicMock(status=404), "Unknown Message")


def bad_gateway():
    return discord.HTTPException(MagicMock(status=502), "Bad Gateway")


class TestDeleteSessionPages:

    @pytest.mark.asyncio
    async def test_deletes_every_recorded_page_and_clears_the_record(self, monkeypatch, tmp_path):
        record, deleted, _ = deletion_setup(monkeypatch, tmp_path)

        count = await bot.delete_session_pages()

        assert deleted == [1001, 1002, 1003]
        assert count == 3
        assert record.load() == (None, [])
        bot.bot.get_partial_messageable.assert_called_once_with(42)

    @pytest.mark.asyncio
    async def test_a_page_already_gone_is_skipped_and_dropped(self, monkeypatch, tmp_path):
        record, deleted, _ = deletion_setup(monkeypatch, tmp_path, failing={1002: not_found()})

        await bot.delete_session_pages()

        assert deleted == [1001, 1003]
        assert record.load() == (None, [])

    @pytest.mark.asyncio
    async def test_a_page_that_will_not_delete_stays_in_the_record(self, monkeypatch, tmp_path):
        record, deleted, _ = deletion_setup(monkeypatch, tmp_path, failing={1002: bad_gateway()})

        await bot.delete_session_pages()

        assert deleted == [1001, 1003]
        assert record.load() == (42, [1002])

    @pytest.mark.asyncio
    async def test_an_empty_record_touches_discord_not_at_all(self, monkeypatch, tmp_path):
        deletion_setup(monkeypatch, tmp_path, ids=())
        assert await bot.delete_session_pages() == 0
        bot.bot.get_partial_messageable.assert_not_called()


class TestPagesLeaveWithTheBot:

    @pytest.mark.asyncio
    async def test_leave_deletes_the_pages_before_it_replies(self, monkeypatch, tmp_path):
        record, deleted, order = deletion_setup(monkeypatch, tmp_path)
        monkeypatch.setattr(bot, "relay_paused", False)
        monkeypatch.setattr(bot, "target_channel_id", 111)
        monkeypatch.setattr(bot, "text_channel_id", 42)
        monkeypatch.setattr(bot, "text_enabled", True)
        monkeypatch.setattr(bot, "current_page", None)
        monkeypatch.setattr(bot, "pending_lines", [])
        ctx = make_text_context()
        ctx.send = AsyncMock(side_effect=lambda *a, **k: order.append("reply"))

        with patch("bot.configured_voice_client", return_value=None):
            await bot.batc_leave.callback(ctx)

        assert order == ["delete", "delete", "delete", "reply"]
        assert record.load() == (None, [])

    @pytest.mark.asyncio
    async def test_shutdown_deletes_the_pages_before_closing(self, monkeypatch, tmp_path):
        record, deleted, order = deletion_setup(monkeypatch, tmp_path)
        signal = tmp_path / "stop.signal"
        signal.touch()
        monkeypatch.setattr(bot, "STOP_SIGNAL_PATH", signal)
        monkeypatch.setattr(bot, "current_source", None)

        async def close():
            order.append("close")

        with patch.object(type(bot.bot), "voice_clients", new=[]):
            with patch.object(bot.bot, "close", new=AsyncMock(side_effect=close)):
                await bot.shutdown_watcher.coro()

        assert order == ["delete", "delete", "delete", "close"]
        assert record.load() == (None, [])

    @pytest.mark.asyncio
    async def test_shutdown_still_closes_when_deleting_blows_up(self, monkeypatch, tmp_path):
        deletion_setup(monkeypatch, tmp_path)
        signal = tmp_path / "stop.signal"
        signal.touch()
        monkeypatch.setattr(bot, "STOP_SIGNAL_PATH", signal)
        monkeypatch.setattr(bot, "current_source", None)
        monkeypatch.setattr(bot.bot, "get_partial_messageable", MagicMock(side_effect=RuntimeError("no gateway")))

        with patch.object(type(bot.bot), "voice_clients", new=[]):
            with patch.object(bot.bot, "close", new=AsyncMock()) as close:
                await bot.shutdown_watcher.coro()

        close.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_login_cleans_up_what_a_killed_bot_left_behind(self, monkeypatch, tmp_path):
        record, deleted, _ = deletion_setup(monkeypatch, tmp_path)
        for loop in (bot.watchdog, bot.shutdown_watcher, bot.transcript_relay):
            loop.start = MagicMock()
            loop.is_running = MagicMock(return_value=True)

        await bot.on_ready()

        assert deleted == [1001, 1002, 1003]
        assert record.load() == (None, [])

    @pytest.mark.asyncio
    async def test_a_new_page_is_recorded_when_it_is_posted(self, monkeypatch, tmp_path):
        feed, channel = relay_setup(monkeypatch, [transmission("Swiss 874, climb FL100.")], record_dir=tmp_path)

        await bot.transcript_relay()

        channel_id, ids = bot.session_record.load()
        assert channel_id == 42
        assert ids == [bot.current_page.message.id]
