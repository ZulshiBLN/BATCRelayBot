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
import pathlib
import sys

import discord
from discord.ext import commands, tasks

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("atc-relay")

CONFIG_PATH = pathlib.Path(__file__).parent / "config.json"
STOP_SIGNAL_PATH = pathlib.Path(__file__).parent / "stop.signal"


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
            return None, f'No voice channel called "{wanted}" on this server.'
        return matches[0], None

    voice = getattr(ctx.author, "voice", None)
    channel = getattr(voice, "channel", None)
    if channel is not None:
        return channel, None

    return None, (
        "You are not in a voice channel. Join one and say `!BATCjoin` again, "
        "or name it: `!BATCjoin <name or id>`."
    )


def missing_join_permissions(channel, member):
    """
    Which of the two permissions needed to relay are missing on a channel.

    Connect gets the bot in, Speak lets it be heard. Without Speak it joins
    and streams into silence, which looks like a broken installation rather
    than a permission a server admin can grant in ten seconds.
    """
    permissions = channel.permissions_for(member)

    missing = []
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
    global relay_paused, target_channel_id

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
    global relay_paused, target_channel_id
    relay_paused = True

    # Cleared too: the next !BATCjoin decides where the bot goes, and leaving
    # a stale target here would let the watchdog pull it back on its own.
    target_channel_id = None

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
