"""
ATC Relay Bot
-------------
Joins a Discord voice channel and live-streams the audio signal from a
Windows recording device (e.g. "VoiceMeeter Output") into that channel.
Intended as an automated replacement for the manual "second browser
account" trick used to bring BATC/BeyondATC radio traffic into Discord.

Requirements:
  - Python 3.10+
  - pip install -r requirements.txt
  - ffmpeg.exe must be on PATH (https://ffmpeg.org/download.html)
  - A Discord bot token (see README.md)
  - The exact device name of your VoiceMeeter output as seen by ffmpeg
    (see README.md, "Find audio device" step)

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

REQUIRED_KEYS = ["bot_token", "guild_id", "voice_channel_id", "audio_device_name"]
for key in REQUIRED_KEYS:
    if not CONFIG.get(key):
        log.error("Field '%s' is missing or empty in config.json", key)
        sys.exit(1)

intents = discord.Intents.default()
intents.message_content = True  # only needed if you want the text commands below

bot = commands.Bot(command_prefix="!", intents=intents)


def make_audio_source() -> discord.FFmpegPCMAudio:
    """
    Builds a live audio source from the configured Windows recording device.
    -f dshow + audio="<device name>" is the Windows-specific ffmpeg syntax
    for reading a recording device as a continuous stream.
    """
    device = CONFIG["audio_device_name"]
    before_options = "-f dshow"
    # -re not needed (this is a live input, not a file replay, so it's
    # already real-time)
    return discord.FFmpegPCMAudio(
        source=f"audio={device}",
        before_options=before_options,
        options="-vn",
    )


async def connect_and_stream():
    guild = bot.get_guild(CONFIG["guild_id"])
    if guild is None:
        log.error("Guild %s not found - is the bot on that server?", CONFIG["guild_id"])
        return

    channel = guild.get_channel(CONFIG["voice_channel_id"])
    if channel is None or not isinstance(channel, discord.VoiceChannel):
        log.error("Voice channel %s not found", CONFIG["voice_channel_id"])
        return

    voice_client = guild.voice_client

    if voice_client is None:
        voice_client = await channel.connect(reconnect=True)
        log.info("Connected to voice channel: %s", channel.name)
    elif voice_client.channel.id != channel.id:
        await voice_client.move_to(channel)
        log.info("Moved to voice channel: %s", channel.name)

    if not voice_client.is_playing():
        source = make_audio_source()
        voice_client.play(source, after=lambda e: log.warning("Stream ended: %s", e))
        log.info("Audio stream started (device: %s)", CONFIG["audio_device_name"])


@tasks.loop(seconds=10)
async def watchdog():
    """
    Periodically checks whether the bot is still connected and streaming,
    and (re)connects / restarts the stream if needed (e.g. after a
    connection drop).
    """
    try:
        await connect_and_stream()
    except Exception:
        log.exception("Error in watchdog cycle")


@tasks.loop(seconds=1)
async def shutdown_watcher():
    """
    Checks every second whether a stop.signal file has been created (by
    stop_bot.ps1). If so: leave the voice channel cleanly, close the bot
    connection, and exit the process instead of just being force-killed.
    """
    if not STOP_SIGNAL_PATH.exists():
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

    try:
        STOP_SIGNAL_PATH.unlink()
    except FileNotFoundError:
        pass

    await bot.close()


@bot.event
async def on_ready():
    log.info("Logged in as %s", bot.user)
    if not watchdog.is_running():
        watchdog.start()
    if not shutdown_watcher.is_running():
        shutdown_watcher.start()


@bot.command(name="status")
async def status(ctx: commands.Context):
    vc = ctx.guild.voice_client if ctx.guild else None
    if vc and vc.is_connected():
        state = "streaming" if vc.is_playing() else "connected, but no active stream"
        await ctx.send(f"Connected to **{vc.channel.name}** - {state}.")
    else:
        await ctx.send("Not connected to a voice channel.")


@bot.command(name="restart_stream")
async def restart_stream(ctx: commands.Context):
    vc = ctx.guild.voice_client if ctx.guild else None
    if vc:
        vc.stop()
    await connect_and_stream()
    await ctx.send("Stream restarted.")


@bot.command(name="leave")
async def leave(ctx: commands.Context):
    vc = ctx.guild.voice_client if ctx.guild else None
    if vc:
        await vc.disconnect()
        await ctx.send("Left the voice channel.")
    else:
        await ctx.send("Wasn't connected to begin with.")


if __name__ == "__main__":
    bot.run(CONFIG["bot_token"], log_handler=None)
