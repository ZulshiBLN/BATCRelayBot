"""
ATC Relay Bot
-------------
Joins a Discord voice channel and live-streams the audio signal from a
Windows recording device (e.g. "VoiceMeeter Output") into that channel.
Intended as an automated replacement for the manual "second browser
account" trick used to bring BATC/BeyondATC radio traffic into Discord.

Starting this process only brings the bot online in Discord - it stands by
without joining anything. Relaying begins on an explicit !BATCjoin, so having
the bot start with Windows does not put it in a voice channel.

Chat commands (all prefixed with BATC so they cannot collide with other bots
in the same server; command names are case-insensitive):

  !BATCjoin      join a channel and start relaying - yours by default,
                 or !BATCjoin <name or id> for a particular one
  !BATCleave     leave and stay out until !BATCjoin
  !BATCstatus    connection and stream state
  !BATCrestart   restart the stream without leaving
  !BATCtext      toggle ATC text - what the controller says, as it is said,
                 posted in the channel !BATCjoin was typed in (off by default)
  !BATCshutdown  stop this process (Administrator only)
  !BATChelp      list the commands

Requirements:
  - Python 3.10+
  - pip install -r requirements.txt
  - ffmpeg.exe, either on PATH or given as ffmpeg_path in config.json
  - A Discord bot token (see README.md)
  - The exact device name of your VoiceMeeter output as seen by ffmpeg
    (Install-BATCRelayBot picks it from a list)

Configuration: config.json (see config.example.json)
"""

import asyncio
import json
import logging
import os
import pathlib
import re
import sys

import discord
from discord.ext import commands, tasks

# A Discord snowflake: 17 to 20 digits, not part of a longer number and not
# part of a version or a path. The same shape Remove-SensitiveData redacts
# from install.log, because it is the same rule.
SNOWFLAKE_PATTERN = re.compile(r"(?<![\d.\\/])\d{17,20}(?![\d.])")

# A bot token, in case one ever reaches a message. Nothing here logs one, but
# a library or a traceback might.
TOKEN_PATTERN = re.compile(r"\b[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{20,}\b")


class RedactSecrets(logging.Filter):
    """
    Keeps Discord IDs out of the log, whoever wrote them.

    discord.py logs lines like "The voice handshake is being terminated for
    Channel ID 1535343588567683122 (Guild ID 631480440548753408)", which is
    exactly what the secrets rule forbids - and bot_error.log travels into bug
    reports and screenshots the same way install.log does. That one was fixed
    in 1.4.1; this log was not looked at.

    Attached to the handler rather than to a logger: every library's records
    propagate to the root handler, and a filter on our own logger would only
    ever see our own lines.

    It does not reach into exception tracebacks. An ID in a traceback frame
    would still get through.
    """

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()

        redacted = TOKEN_PATTERN.sub("[REDACTED-TOKEN]", message)
        redacted = SNOWFLAKE_PATTERN.sub("[REDACTED-ID]", redacted)

        if redacted != message:
            # The arguments are already folded in, so they must not be
            # applied a second time when the record is formatted.
            record.msg = redacted
            record.args = ()

        return True


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

for _handler in logging.getLogger().handlers:
    _handler.addFilter(RedactSecrets())

log = logging.getLogger("atc-relay")

CONFIG_PATH = pathlib.Path(__file__).parent / "config.json"
STOP_SIGNAL_PATH = pathlib.Path(__file__).parent / "stop.signal"
PID_FILE_PATH = pathlib.Path(__file__).parent / "bot.pid"


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        log.error(
            "config.json is missing. Copy config.example.json to config.json "
            "and fill in your values."
        )
        sys.exit(1)
    # utf-8-sig instead of utf-8: tolerates a UTF-8 BOM if present
    # (e.g. when config.json was created with Notepad or PowerShell Set-Content)
    with open(CONFIG_PATH, "r", encoding="utf-8-sig") as f:
        return json.load(f)


CONFIG = load_config()

# voice_channel_id is deliberately absent. The channel is decided per
# !BATCjoin, so an installation that still carries the field simply keeps an
# unused key rather than needing a migration.
REQUIRED_KEYS = ["bot_token", "guild_id", "audio_device_name"]
for key in REQUIRED_KEYS:
    if not CONFIG.get(key):
        log.error("Field '%s' is missing or empty in config.json", key)
        sys.exit(1)

# --- BeyondATC transcript ----------------------------------------------------
#
# BeyondATC has no API and no transcript file, but Unity writes Player.log as
# the game runs, and every transmission involving the player lands there as
# one block:
#
#   [LocalVoiceInput] sid=173 ls=1.258 | "Swiss eight seven four, taxi ..."
#   [LocalVoicePhonemes] sid=173 | "..."
#   ------------------------------
#   [PlayerState] Friday 19:10, lat: ..., com1: 121.755(On), ...
#   [Instruction] Swiss 874, taxi to holding point A1, runway 28, via N, F, INNER, A.
#   ------------------------------
#
# [Instruction] is the clean text; [PlayerState] beside it carries the sim
# clock and COM1. The log never says who is speaking, and readbacks by the
# copilot look exactly like the controller's lines. What does tell them
# apart: a [ControllerScript] line precedes each exchange with the player, and
# the first [LocalVoiceInput] after it is always the controller. Voices seen
# there are controllers; a block whose last voice is one of them is ATC.
# Checked against a full flight, LSZH-EDDS with a go-around: 29 posted, 33
# skipped, none wrong. What the player says himself is a
# [Speech Transcription] block and never an [Instruction].

VOICE_ID_PATTERN = re.compile(r"^\[LocalVoiceInput\] sid=(\d+)")
PLAYER_STATE_PATTERN = re.compile(
    r"^\[PlayerState\] (?P<sim_time>[A-Za-z]+ \d\d:\d\d),.*?com1: (?P<com1>[\d.]+)"
)


class Transmission:
    """One thing ATC said to the player, with the sim clock and frequency."""

    __slots__ = ("sim_time", "com1", "text")

    def __init__(self, sim_time, com1, text):
        self.sim_time = sim_time
        self.com1 = com1
        self.text = text


class InstructionParser:
    """
    Feed it Player.log lines; it returns a Transmission for each controller
    line and None for everything else. Learns which voices are controllers as
    it goes, so it needs the lines in order and from the start of a session
    - which is what tailing a live file gives it.
    """

    def __init__(self):
        self._controller_voices = set()
        self._next_voice_is_controller = False
        self._last_voice = None
        self._sim_time = None
        self._com1 = None

    def feed(self, line):
        line = line.rstrip("\r\n")

        if line.startswith("[ControllerScript]"):
            self._next_voice_is_controller = True
            return None

        voice = VOICE_ID_PATTERN.match(line)
        if voice:
            self._last_voice = voice.group(1)
            if self._next_voice_is_controller:
                self._controller_voices.add(self._last_voice)
                self._next_voice_is_controller = False
            return None

        state = PLAYER_STATE_PATTERN.match(line)
        if state:
            self._sim_time = state.group("sim_time")
            self._com1 = state.group("com1")
            return None

        if line.startswith("[Instruction] "):
            # Consumed either way: an [Instruction] with no voice of its own
            # must not inherit the previous speaker.
            voice, self._last_voice = self._last_voice, None
            if voice in self._controller_voices:
                return Transmission(self._sim_time, self._com1, line[len("[Instruction] "):])

        return None


class LogTailer:
    """
    Follows a file that another process is writing, returning whole new lines
    on each call. Starts at the end: a bot started mid-flight must not replay
    the flight. A file that shrinks has been replaced - BeyondATC rotates
    Player.log on launch - and is read from the beginning.
    """

    def __init__(self, path):
        self.path = pathlib.Path(path)
        self._offset = None
        self._partial = b""
        # Set when the file was replaced, for whoever keeps state per file.
        self.restarted = False

    def read_new_lines(self):
        try:
            size = self.path.stat().st_size
        except OSError:
            # Not installed, not running yet, or rotating this very moment.
            return []

        if self._offset is None:
            # First sight of the file: nothing in it was said while anyone
            # was listening.
            self._offset = size
            return []

        if size < self._offset:
            # A new file - all of it is new.
            self._offset = 0
            self._partial = b""
            self.restarted = True

        if size == self._offset:
            return []

        with open(self.path, "rb") as f:
            f.seek(self._offset)
            data = f.read()
            self._offset = f.tell()

        # Unity writes UTF-8 without BOM; phoneme lines carry IPA and a read
        # may cut one in half, so bytes are split first and decoded per line.
        pieces = (self._partial + data).split(b"\n")
        self._partial = pieces.pop()
        return [piece.decode("utf-8", errors="replace").rstrip("\r") for piece in pieces]


class TranscriptFeed:
    """
    The tailer and the parser together: poll() returns what ATC has said
    since the last call. A replaced file gets a fresh parser - voice ids are
    handed out per session, and yesterday's controller can be today's copilot.
    """

    def __init__(self, path):
        self._tailer = LogTailer(path)
        self._parser = InstructionParser()

    def poll(self):
        lines = self._tailer.read_new_lines()
        if self._tailer.restarted:
            self._parser = InstructionParser()
            self._tailer.restarted = False
        found = []
        for line in lines:
            transmission = self._parser.feed(line)
            if transmission is not None:
                found.append(transmission)
        return found


def batc_log_path():
    """
    Where BeyondATC writes Player.log. Unity fixes the location from company
    and product name, so it is derived rather than asked for; batc_log_path in
    config.json overrides it for the rare case.
    """
    configured = CONFIG.get("batc_log_path")
    if configured:
        return pathlib.Path(configured)
    return (
        pathlib.Path.home()
        / "AppData" / "LocalLow" / "Skirmish Mode Games, Inc" / "BeyondATC" / "Player.log"
    )


def format_transmission(transmission):
    """
    `**19:10** . 121.755 . Swiss 874, climb FL100.` with a middle dot as the
    separator - clock and frequency from the [PlayerState] line, or the text
    alone when there was none. The dot is escaped because this file has to
    stay ASCII; see test_bot_py_stays_ascii.
    """
    if transmission.sim_time and transmission.com1:
        clock = transmission.sim_time.split()[-1]
        return f"**{clock}** \u00b7 {transmission.com1} \u00b7 {transmission.text}"
    return transmission.text


DISCORD_MESSAGE_LIMIT = 2000


def messages_from(lines):
    """Joins lines into as few messages as fit under Discord's limit."""
    messages = []
    current = ""
    for line in lines:
        candidate = line if not current else current + "\n" + line
        if current and len(candidate) > DISCORD_MESSAGE_LIMIT:
            messages.append(current)
            current = line
        else:
            current = candidate
    if current:
        messages.append(current)
    return messages


intents = discord.Intents.default()
intents.message_content = True  # only needed if you want the text commands below

# Every command carries a BATC prefix so this bot cannot collide with other
# bots in the same server, and case_insensitive lets !batcjoin work too.
#
# The built-in help is switched off in favour of BATChelp below. The default
# one printed a flat block in which it was not clear where one command ended
# and the next began.
bot = commands.Bot(
    command_prefix="!",
    intents=intents,
    case_insensitive=True,
    help_command=None,
)


def station_name():
    """
    What the bot calls itself in replies.

    bot.user is None until the connection is up, and every reply here is sent
    afterwards - but a test may call these functions without a connection, and
    "None is now transmitting" would be a poor way to find that out.
    """
    return bot.user.display_name if bot.user else "BATCRelayBot"


def make_audio_source() -> discord.FFmpegPCMAudio:
    """
    Builds a live audio source from the configured Windows recording device.
    -f dshow + audio="<device name>" is the Windows-specific ffmpeg syntax
    for reading a recording device as a continuous stream.
    """
    device = CONFIG["audio_device_name"]
    before_options = "-f dshow"
    # Use the ffmpeg the installer actually found. Without this discord.py
    # falls back to plain "ffmpeg" and needs it on PATH, which is not the case
    # for a manual extraction to e.g. C:\ffmpeg.
    executable = CONFIG.get("ffmpeg_path") or "ffmpeg"
    if executable != "ffmpeg" and not pathlib.Path(executable).exists():
        log.warning("ffmpeg_path %s does not exist, falling back to PATH", executable)
        executable = "ffmpeg"
    # -re not needed (this is a live input, not a file replay, so it's
    # already real-time)
    return discord.FFmpegPCMAudio(
        source=f"audio={device}",
        executable=executable,
        before_options=before_options,
        options="-vn",
    )


def configured_voice_client():
    """
    The voice client for the configured guild.

    State is read from that guild rather than from wherever a command was
    typed - otherwise running a command in a second server reports the wrong
    state. The guild is still configuration; the channel is not.
    """
    guild = bot.get_guild(CONFIG["guild_id"])
    return guild.voice_client if guild else None


# Where the bot is going. Decided by !BATCjoin rather than at install time, and
# kept here because the watchdog reconnects to it every ten seconds - it has to
# outlive the command that set it. None means nobody has asked yet.
target_channel_id = None

# The ffmpeg process behind the stream, kept so it can be ended deliberately.
#
# discord.py kills it from the audio player's thread, which is a daemon
# thread: if the interpreter exits first, that thread is torn down before its
# cleanup runs and ffmpeg keeps holding the recording device. An orphan on a
# VoiceMeeter bus is not a tidiness problem - it takes the machine's audio
# with it until somebody kills the process by hand.
current_source = None


def release_pid_file():
    """
    Removes bot.pid, but only when it names this process.

    Stop-BATCRelayBot removes it; a shutdown from chat left it behind naming a
    process that had exited. Nothing treats it as the authority any more -
    that is what the process list is for - but a file stating something untrue
    is still something somebody will eventually read.

    The identity check matters: two installations have their own directories,
    but a file that has been rewritten by someone else is not ours to delete.
    """
    try:
        if PID_FILE_PATH.read_text().strip() == str(os.getpid()):
            PID_FILE_PATH.unlink()
    except OSError:
        pass


def release_audio_source():
    """Ends the ffmpeg process now, rather than hoping a thread gets to it."""
    global current_source

    source = current_source
    current_source = None
    if source is None:
        return

    try:
        source.cleanup()
        log.info("Audio source released.")
    except Exception:
        log.exception("Could not release the audio source")


def resolve_target_channel(ctx, argument=""):
    """
    Works out which voice channel a !BATCjoin means.

    In order: the channel named in the argument, otherwise the one the caller
    is sitting in. Whoever types the command is almost always already there.

    Returns (channel, reason) with exactly one of them set, so the caller can
    say why nothing happened instead of failing silently.
    """
    guild = getattr(ctx, "guild", None)
    if guild is None:
        return None, "That only works in a server, not in a direct message."

    wanted = (argument or "").strip()

    if wanted:
        # An ID is exact. A name is not: Discord lets two channels share one,
        # so the first match wins and the reply names what it joined.
        if wanted.isdigit():
            channel = guild.get_channel(int(wanted))
            if isinstance(channel, discord.VoiceChannel):
                return channel, None
            return None, f"No voice channel with the ID {wanted} on this server."

        matches = [c for c in guild.voice_channels if c.name.lower() == wanted.lower()]
        if not matches:
            # A channel the bot may not see is not in its cache at all, so it
            # is indistinguishable from one that does not exist. Say both.
            return None, (
                f'No voice channel called "{wanted}" on this server - or I have '
                f"no View Channel permission on it."
            )
        return matches[0], None

    voice = getattr(ctx.author, "voice", None)
    channel = getattr(voice, "channel", None)
    if channel is not None:
        return channel, None

    return None, (
        "You are not in a voice channel. Join one and say `!BATCjoin` again, "
        "or name it: `!BATCjoin <name or id>`."
    )


# What the bot needs, derived from what it actually does rather than from a
# list somebody once wrote down.
#
#   View Channel   it cannot join, or even see, a channel hidden from it
#   Connect        channel.connect()
#   Speak          voice_client.play()
#
#   View Channel   a command in a channel it cannot see never reaches it
#   Send Messages  every command answers with ctx.send()
#
# Read Message History is not among them. Commands arrive over the gateway as
# they are typed; history is for reading messages from before, which nothing
# here does. Sending a direct message needs no server permission at all - only
# that the recipient accepts them.
#
# Not a permission but required all the same: the Message Content intent in
# the developer portal. Without it the text of a message never reaches the bot
# and no prefix command works.
VOICE_PERMISSIONS = ("View Channel", "Connect", "Speak")
TEXT_PERMISSIONS = ("View Channel", "Send Messages")


def missing_join_permissions(channel, member):
    """
    Which of the permissions needed to relay are missing on a voice channel.

    View Channel gets it listed, Connect gets the bot in, Speak lets it be
    heard. Without Speak it joins and streams into silence, which looks like a
    broken installation rather than a permission a server admin can grant in
    ten seconds.
    """
    permissions = channel.permissions_for(member)

    missing = []
    if not permissions.view_channel:
        missing.append("View Channel")
    if not permissions.connect:
        missing.append("Connect")
    if not permissions.speak:
        missing.append("Speak")
    return missing


async def report_missing_permissions(ctx, channel, missing):
    """
    Tells the caller what is missing where, by direct message.

    The detail goes to the person who asked rather than into the channel:
    they are the one who can pass it to an admin, and a permissions lecture
    in a busy channel helps nobody. The channel gets one line saying a
    message was sent, so the command does not look ignored.

    If their direct messages are closed, the detail goes to the channel
    instead - failing to deliver it at all would be the worst of the three.
    """
    names = " and ".join(missing)
    detail = (
        f"I could not enter **{channel.name}**.\n"
        f"Missing on that channel: **{names}**.\n"
        f"\n"
        f"What I need, in full:\n"
        f"  on a voice channel I should join - {', '.join(VOICE_PERMISSIONS)}\n"
        f"  on the text channel you type in - {', '.join(TEXT_PERMISSIONS)}\n"
        f"\n"
        f"A server admin can grant {'them' if len(missing) > 1 else 'it'} under "
        f"Channel Settings > Permissions, for my role. Then say `!BATCjoin` again."
    )

    try:
        await ctx.author.send(detail)
    except discord.Forbidden:
        await ctx.send(detail)
        return

    await ctx.send(
        f"Cannot enter **{channel.name}** - I have sent you the details."
    )


async def connect_and_stream():
    guild = bot.get_guild(CONFIG["guild_id"])
    if guild is None:
        log.error("Guild %s not found - is the bot on that server?", CONFIG["guild_id"])
        return

    if target_channel_id is None:
        log.error("No target channel - !BATCjoin decides where the bot goes")
        return

    channel = guild.get_channel(target_channel_id)
    if channel is None or not isinstance(channel, discord.VoiceChannel):
        log.error("Voice channel %s not found", target_channel_id)
        return

    voice_client = guild.voice_client

    if voice_client is None:
        voice_client = await channel.connect(reconnect=True)
        log.info("Connected to voice channel: %s", channel.name)
    elif voice_client.channel.id != channel.id:
        await voice_client.move_to(channel)
        log.info("Moved to voice channel: %s", channel.name)

    if not voice_client.is_playing():
        global current_source
        source = make_audio_source()
        current_source = source
        voice_client.play(source, after=lambda e: log.warning("Stream ended: %s", e))
        log.info("Audio stream started (device: %s)", CONFIG["audio_device_name"])


# Starts paused on purpose: launching the bot from PowerShell only brings it
# online in Discord, it does not join a voice channel. Joining is an explicit
# !BATCjoin, so starting the bot at boot does not put it in the channel.
#
# !BATCleave sets this again. Without it the watchdog below would undo the
# leave within ten seconds, which left no way to get the bot out from chat.
relay_paused = True


# Where ATC's lines go: the text channel !BATCjoin was typed in, which the bot
# can already send to because it answered the command there. Off after every
# join; !BATCtext switches it on, and !BATCleave clears both.
text_channel_id = None
text_enabled = False
transcript_feed = TranscriptFeed(batc_log_path())


@tasks.loop(seconds=1)
async def transcript_relay():
    """
    Drains Player.log every second and posts what ATC said. The file is
    drained even while the feed is off: the parser keeps learning voices, and
    switching the feed on must not dump a backlog into the channel.
    """
    global text_enabled
    transmissions = transcript_feed.poll()
    if not transmissions or not text_enabled or text_channel_id is None:
        return

    channel = bot.get_channel(text_channel_id)
    if channel is None:
        return

    try:
        for message in messages_from([format_transmission(t) for t in transmissions]):
            await channel.send(message)
    except discord.Forbidden:
        # Once, and off - not every second for as long as the process runs.
        text_enabled = False
        log.warning(
            "Cannot post ATC text in #%s - the bot needs Send Messages there. "
            "Text is off until the next !BATCtext.",
            getattr(channel, "name", text_channel_id),
        )


@transcript_relay.error
async def transcript_relay_error(error: Exception):
    log.exception("transcript_relay failed, restarting it", exc_info=error)
    transcript_relay.restart()


@tasks.loop(seconds=10)
async def watchdog():
    """
    Periodically checks whether the bot is still connected and streaming,
    and (re)connects / restarts the stream if needed (e.g. after a
    connection drop).
    """
    if relay_paused:
        return
    try:
        await connect_and_stream()
    except Exception:
        log.exception("Error in watchdog cycle")


@tasks.loop(seconds=1)
async def shutdown_watcher():
    """
    Checks every second whether a stop.signal file has been created, by
    either Stop-BATCRelayBot or !BATCshutdown. If so: leave the voice channel
    cleanly, close the bot connection, and exit the process instead of just
    being force-killed.

    The whole body is guarded. A discord.py task loop that raises an unhandled
    exception stops, and stops quietly - after which nothing can end this
    process gracefully any more: !BATCshutdown writes a signal nobody reads,
    Stop-BATCRelayBot waits fifteen seconds and terminates the process, and
    ffmpeg is orphaned holding the recording device. The log from 2026-09-09
    shows exactly that shape: a join, then twenty seconds, then nothing, with
    no "Stop signal detected" line anywhere.
    """
    try:
        if not STOP_SIGNAL_PATH.exists():
            return
    except OSError:
        log.exception("Could not check for the stop signal")
        return

    log.info("Stop signal detected, leaving voice channel and shutting down...")
    shutdown_watcher.stop()
    if watchdog.is_running():
        watchdog.stop()

    for vc in list(bot.voice_clients):
        try:
            await vc.disconnect(force=True)
            log.info("Left voice channel cleanly.")
        except Exception:
            log.exception("Error while leaving the voice channel")

    # Not left to disconnect(). It ends the player thread, which is a daemon
    # thread, and the ffmpeg process is only killed by that thread's finally.
    # If the interpreter exits first the thread is torn down and ffmpeg
    # survives, holding the dshow capture of the VoiceMeeter bus.
    release_audio_source()

    try:
        STOP_SIGNAL_PATH.unlink()
    except OSError:
        pass

    release_pid_file()

    await bot.close()


@shutdown_watcher.error
async def shutdown_watcher_error(error: Exception):
    """
    A loop that dies silently takes the only graceful exit with it.

    discord.py stops a task loop on an unhandled exception and says nothing
    unless a handler like this one exists. Restarting it is right: the failure
    is far more likely to be transient - a file lock on stop.signal - than a
    reason to give up the ability to shut down at all.
    """
    log.exception("shutdown_watcher failed, restarting it", exc_info=error)
    shutdown_watcher.restart()


@watchdog.error
async def watchdog_error(error: Exception):
    log.exception("watchdog failed, restarting it", exc_info=error)
    watchdog.restart()


@bot.event
async def on_ready():
    log.info("Logged in as %s", bot.user)
    log.info("Standing by - use !BATCjoin in Discord to join the voice channel.")
    if not watchdog.is_running():
        watchdog.start()
    if not shutdown_watcher.is_running():
        shutdown_watcher.start()
    if not transcript_relay.is_running():
        transcript_relay.start()


@bot.command(name="BATCstatus", help="Request current station status.")
async def batc_status(ctx: commands.Context):
    """Show whether the bot is connected and streaming."""
    who = ctx.author.display_name
    station = station_name()

    vc = configured_voice_client()

    if vc and vc.is_connected():
        if vc.is_playing():
            message = f"{who}, {station} is currently transmitting from **{vc.channel.name}**."
        else:
            message = f"{who}, {station} is in **{vc.channel.name}** but not transmitting."

        # Paused means the watchdog will not restart the stream on its own, so
        # the way out of it is worth naming here.
        if relay_paused:
            message += " Say BATCjoin to resume."

        await ctx.send(message)
    elif relay_paused:
        await ctx.send(f"{who}, {station} is standing by. Say BATCjoin for channel entry.")
    else:
        await ctx.send(f"{who}, {station} is off the air, reconnecting shortly.")


@bot.command(
    name="BATCjoin",
    help="Request channel entry and commence transmissions.",
)
async def batc_join(ctx: commands.Context, *, channel_name: str = ""):
    """Join a voice channel and start relaying. Defaults to the caller's."""
    global relay_paused, target_channel_id, text_channel_id, text_enabled

    channel, reason = resolve_target_channel(ctx, channel_name)
    if channel is None:
        await ctx.send(reason)
        return

    # Before the target is remembered and the relay unpaused. Setting them
    # first would leave the watchdog retrying a channel the bot may not enter,
    # every ten seconds, for as long as the process runs.
    missing = missing_join_permissions(channel, ctx.guild.me)
    if missing:
        log.warning("Cannot join %s - missing %s", channel.name, ", ".join(missing))
        await report_missing_permissions(ctx, channel, missing)
        return

    target_channel_id = channel.id
    relay_paused = False

    # The transcript goes where this command was typed, and stays off until
    # someone asks for it - a text feed nobody wanted is noise in a shared
    # channel.
    text_channel_id = ctx.channel.id
    text_enabled = False

    try:
        await connect_and_stream()
    except Exception:
        log.exception("!BATCjoin failed")
        await ctx.send("Could not join the voice channel - see the bot log for details.")
        return

    vc = configured_voice_client()
    if vc and vc.is_connected():
        await ctx.send(
            f"{ctx.author.display_name}, {station_name()} is now transmitting "
            f"from **{vc.channel.name}**."
        )
    else:
        await ctx.send(f"Could not join **{channel.name}**.")


@bot.command(
    name="BATCleave",
    help="Request termination of transmissions and vacate the channel.",
)
async def batc_leave(ctx: commands.Context):
    """Leave the channel and stay out until !BATCjoin."""
    global relay_paused, target_channel_id, text_channel_id, text_enabled
    relay_paused = True

    # Cleared too: the next !BATCjoin decides where the bot goes, and leaving
    # a stale target here would let the watchdog pull it back on its own.
    target_channel_id = None
    text_channel_id = None
    text_enabled = False

    vc = configured_voice_client()
    if vc:
        # Read before disconnecting: afterwards there is no channel to name.
        left = vc.channel.name
        await vc.disconnect()
        release_audio_source()
        await ctx.send(
            f"{ctx.author.display_name}, contact {station_name()} again in "
            f"**{left}**. Good day."
        )
    else:
        await ctx.send("Wasn't connected. Standing by - `!BATCjoin` to resume.")


@bot.command(
    name="BATCrestart",
    aliases=["BATCrestart_stream"],
    help="Request transmission restart.",
)
async def batc_restart(ctx: commands.Context):
    """Restart the audio stream without leaving the channel."""
    if relay_paused:
        await ctx.send("The relay is paused. Use `!BATCjoin` first.")
        return

    vc = configured_voice_client()
    if vc:
        vc.stop()
    await connect_and_stream()

    vc = configured_voice_client()
    where = f" **{vc.channel.name}**" if vc and vc.channel else ""
    await ctx.send(f"{ctx.author.display_name}, I say again, cleared to land{where}.")


@bot.command(
    name="BATCtext",
    help="Toggle ATC text - what the controller says, posted in the channel BATCjoin was called from.",
)
async def batc_text(ctx: commands.Context):
    """Switch the transcript on or off. One command, so it is a toggle."""
    global text_enabled
    who = ctx.author.display_name
    station = station_name()

    if text_channel_id is None:
        await ctx.send(f"{who}, {station} is standing by. Say BATCjoin first, then BATCtext.")
        return

    text_enabled = not text_enabled
    if text_enabled:
        where = getattr(bot.get_channel(text_channel_id), "name", None) or ctx.channel.name
        await ctx.send(f"{who}, ATC text is on. Read you in **{where}**.")
    else:
        await ctx.send(f"{who}, ATC text is off. Radio only.")


@bot.command(
    name="BATCshutdown",
    help="Request station shutdown.\nAdministrator authorization required.",
)
@commands.has_permissions(administrator=True)
async def batc_shutdown(ctx: commands.Context):
    """Stop the bot process entirely (Administrator only)."""
    # Writes the same stop.signal that Stop-BATCRelayBot uses, so the shutdown
    # path is the one already exercised elsewhere: leave the channel cleanly,
    # close the connection, exit the process. Exists because a bot started in
    # the background and orphaned from its PID file was otherwise unreachable.
    #
    # Sent before the signal, not after: the watcher checks every second and
    # closes the connection, and a message written after that never arrives.
    station = station_name()
    await ctx.send(
        f"{ctx.author.display_name}, {station} is terminating transmission. "
        f"I repeat {station} is offline now, bye bye!"
    )

    # Logged without naming who asked - the secrets rule covers user
    # identities. What matters here is that the command ran at all: the log of
    # 2026-09-09 showed neither this line nor the watcher's, which is what
    # made it impossible to tell whether the signal was written or ignored.
    log.info("Shutdown requested from chat, writing the stop signal")
    STOP_SIGNAL_PATH.touch()


@bot.command(name="BATChelp", help="Request available services.")
async def batc_help(ctx: commands.Context):
    """
    Lists the commands, each with its own description underneath it.

    Built from the registered commands rather than from a list written out
    here, so a command added later cannot be left out of its own help - and
    each description lives on the command it describes, in one place.
    """
    lines = [
        f"{ctx.author.display_name}, {station_name()} ready to copy your selection.",
        "Available options follow:",
        "",
    ]

    for command in sorted(bot.commands, key=lambda c: c.name.lower()):
        lines.append(f"**{command.name}**")
        for line in (command.help or "").splitlines():
            lines.append(f"    {line}")
        lines.append("")

    lines.append("Say selected option.")
    await ctx.send("\n".join(lines))


@batc_shutdown.error
async def batc_shutdown_error(ctx: commands.Context, error):
    if isinstance(error, commands.MissingPermissions):
        await ctx.send("`!BATCshutdown` requires the Administrator permission.")
    else:
        raise error


if __name__ == "__main__":
    bot.run(CONFIG["bot_token"], log_handler=None)
