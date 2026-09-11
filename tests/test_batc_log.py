"""
Tests for the BeyondATC transcript: the parser that picks the controller's
transmissions out of Player.log, and the tailer that follows the file.

The fixture is the log of a real flight, LSZH to EDDS with a go-around on
2026-09-11, cut to the lines after the flight information block and without
the three traffic-only tags. Every line the parser reads is present and
unchanged. The expected transmissions were checked by hand against the flight
before this test existed - they are the truth the parser is measured against,
not something derived from it.
"""

import pathlib
from unittest.mock import patch

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


FIXTURE = pathlib.Path(__file__).parent / "fixtures" / "player-log-lszh-edds.txt"

# What ATC said to the player over the whole flight, in order - and nothing
# the copilot read back, nothing the player asked. 29 of the file's 62
# [Instruction] lines. Repeats ("report ready for descent" twice) are real:
# the controller said it twice.
EXPECTED = [
    ("Friday 18:43", "121.930", "Swiss 874, Zurich Delivery, information S current, cleared to Stuttgart via the DEGE2Y departure, runway 28, climb to 7000 feet, squawk 1000."),
    ("Friday 18:43", "121.930", "Swiss 874, readback correct. Contact ground 121.755 when ready for push or start."),
    ("Friday 19:04", "121.755", "Swiss 874, Zurich Apron, pushback approved. Face west."),
    ("Friday 19:10", "121.755", "Swiss 874, taxi to holding point A1, runway 28, via N, F, INNER, A."),
    ("Friday 19:19", "121.755", "Swiss 874, contact Zurich Tower 118.1."),
    ("Friday 19:20", "118.100", "Swiss 874, Zurich Tower, wind variable, 1 knots, runway 28, cleared for takeoff."),
    ("Friday 19:22", "118.100", "Swiss 874, contact Zurich Departure 125.955."),
    ("Friday 19:23", "125.955", "Swiss 874, Zurich Departure, identified, climb FL100."),
    ("Friday 19:25", "125.955", "Swiss 874, contact Swiss Radar 133.905, bye bye."),
    ("Friday 19:26", "133.905", "Swiss 874, Swiss Radar, good evening, identified, climb FL190."),
    ("Friday 19:29", "133.905", "Swiss 874, contact Swiss Radar 128.05, have a good evening."),
    ("Friday 19:29", "128.050", "Swiss 874, Swiss Radar, identified."),
    ("Friday 19:30", "128.050", "Swiss 874, cleared REUT5A arrival, runway 25."),
    ("Friday 19:30", "128.050", "Swiss 874, cleared REUT5A arrival, runway 25."),
    ("Friday 19:31", "128.050", "Swiss 874, contact Swiss Radar 133.905."),
    ("Friday 19:31", "133.905", "Swiss 874, Swiss Radar, identified."),
    ("Friday 19:35", "133.905", "Swiss 874, report ready for descent."),
    ("Friday 19:35", "133.905", "Swiss 874, report ready for descent."),
    ("Friday 19:35", "133.905", "Swiss 874, Swiss Radar?"),
    ("Friday 19:37", "133.905", "Swiss 874, descend to FL090."),
    ("Friday 19:42", "133.905", "Swiss 874, contact Stuttgart Director 119.85."),
    ("Friday 19:42", "119.850", "Swiss 874 Stuttgart Director, QNH 1023 expect the ILS approach runway 25 with the REU1W transition."),
    ("Friday 19:43", "119.850", "Swiss 874, descend via STAR to FL090."),
    ("Friday 19:44", "119.850", "Swiss 874, cleared direct REUTL, cross REUTL at or above FL090, cleared ILS approach runway 25."),
    ("Friday 19:53", "119.850", "Swiss 874, contact Stuttgart Tower 118.805."),
    ("Friday 19:53", "118.805", "Swiss 874, Stuttgart Tower, wind 270 degrees, 1 knots, runway 25 cleared to land."),
    ("Friday 19:58", "118.805", "Swiss 874, roger. Fly the published missed approach procedure, climb 5,000."),
    ("Friday 19:58", "118.805", "Swiss 874, contact Stuttgart Director 119.85."),
    ("Friday 19:58", "119.850", "Swiss 874, welcome back. Continue."),
]


def parse_all(lines):
    parser = bot.InstructionParser()
    out = []
    for line in lines:
        t = parser.feed(line)
        if t is not None:
            out.append((t.sim_time, t.com1, t.text))
    return out


# One exchange in the shape the log always has: the controller's line, then
# the copilot's readback. Voice 500 is the controller because it is the first
# to speak after the script; 600 is the copilot.
def exchange(controller_voice="500", copilot_voice="600"):
    return [
        "[ControllerScript] AICommunicationSystem.TaxiToRunwayInstructionScript",
        f'[LocalVoiceInput] sid={controller_voice} ls=1.0 | "Swiss eight seven four, taxi to holding point alpha one."',
        f'[LocalVoicePhonemes] sid={controller_voice} | "..."',
        "------------------------------",
        "[PlayerState] Friday 19:10, lat: 47.4525, lon: 8.5589, alt: 1408, hdg: 275, spd: 0, gs: 0, lastFix: , currFix: ZH541, inVector: False, com1: 121.755(On), com2: 121.500(On), transponder: 2000(On)",
        "[Instruction] Swiss 874, taxi to holding point A1.",
        "------------------------------",
        f'[LocalVoiceInput] sid={copilot_voice} ls=1.1 | "Taxi to holding point alpha one, swiss eight seven four."',
        f'[LocalVoicePhonemes] sid={copilot_voice} | "..."',
        "------------------------------",
        "[PlayerState] Friday 19:10, lat: 47.4525, lon: 8.5589, alt: 1408, hdg: 275, spd: 0, gs: 0, lastFix: , currFix: ZH541, inVector: False, com1: 121.755(On), com2: 121.500(On), transponder: 2000(On)",
        "[Instruction] Taxi to holding point A1, Swiss 874.",
        "------------------------------",
    ]


class TestInstructionParser:

    def test_the_whole_flight_yields_exactly_what_atc_said(self):
        lines = FIXTURE.read_text(encoding="utf-8").splitlines()
        assert parse_all(lines) == EXPECTED

    def test_the_controllers_line_is_posted_and_the_readback_is_not(self):
        assert parse_all(exchange()) == [
            ("Friday 19:10", "121.755", "Swiss 874, taxi to holding point A1."),
        ]

    def test_a_voice_that_never_followed_a_script_is_not_posted(self):
        # Same block without the [ControllerScript] line: nobody has been
        # identified as a controller, so nothing may be posted.
        assert parse_all(exchange()[1:]) == []

    def test_a_learned_voice_stays_learned_without_a_new_script(self):
        # A controller repeats itself or calls the player without a new
        # script - the flight had both. Second block, same voice, no script.
        lines = exchange() + exchange()[1:]
        assert [t for _, _, t in parse_all(lines)] == [
            "Swiss 874, taxi to holding point A1.",
            "Swiss 874, taxi to holding point A1.",
        ]

    def test_what_the_player_says_is_never_a_transmission(self):
        lines = exchange()[:1] + [
            "------------------------------",
            "[Speech Transcription] Raw: swiss eight seven four request taxi",
            "[Speech Transcription] AI Processed: Swiss 874 request taxi.",
            "[Speech Transcription] Table Fallback: swiss 874 request taxi",
            "------------------------------",
        ]
        assert parse_all(lines) == []

    def test_an_instruction_with_no_voice_before_it_is_not_posted(self):
        # The voice is consumed by the [Instruction] it belongs to. A second
        # [Instruction] with no new [LocalVoiceInput] in front has no speaker
        # and must not inherit the controller's.
        lines = exchange()[:7] + [
            "[PlayerState] Friday 19:10, lat: 0, lon: 0, alt: 0, hdg: 0, spd: 0, gs: 0, lastFix: , currFix: , inVector: False, com1: 121.755(On), com2: 121.500(On), transponder: 2000(On)",
            "[Instruction] Swiss 874, taxi to holding point A1.",
        ]
        assert len(parse_all(lines)) == 1

    def test_a_line_between_the_voice_and_its_block_does_not_matter(self):
        # Four of 69 blocks in the first flight had an engine line here.
        lines = exchange()
        lines.insert(3, "Look rotation viewing vector is zero")
        assert len(parse_all(lines)) == 1

    def test_lines_keep_their_windows_line_endings_out_of_the_text(self):
        lines = [line + "\r\n" for line in exchange()]
        assert parse_all(lines)[0][2] == "Swiss 874, taxi to holding point A1."


class TestLogTailer:

    def test_starts_at_the_end_so_nothing_old_is_replayed(self, tmp_path):
        log = tmp_path / "Player.log"
        log.write_text("old line 1\nold line 2\n", encoding="utf-8")
        tailer = bot.LogTailer(log)
        assert tailer.read_new_lines() == []

    def test_returns_what_was_appended_since_the_last_read(self, tmp_path):
        log = tmp_path / "Player.log"
        log.write_text("old\n", encoding="utf-8")
        tailer = bot.LogTailer(log)
        tailer.read_new_lines()
        with log.open("a", encoding="utf-8") as f:
            f.write("[Instruction] one\r\n[Instruction] two\r\n")
        assert tailer.read_new_lines() == ["[Instruction] one", "[Instruction] two"]
        assert tailer.read_new_lines() == []

    def test_holds_a_partial_line_until_its_newline_arrives(self, tmp_path):
        log = tmp_path / "Player.log"
        log.write_text("", encoding="utf-8")
        tailer = bot.LogTailer(log)
        tailer.read_new_lines()
        with log.open("a", encoding="utf-8") as f:
            f.write("[Instruction] Swiss 874, cli")
        assert tailer.read_new_lines() == []
        with log.open("a", encoding="utf-8") as f:
            f.write("mb FL100.\n")
        assert tailer.read_new_lines() == ["[Instruction] Swiss 874, climb FL100."]

    def test_reads_from_the_start_when_the_file_has_been_replaced(self, tmp_path):
        # BeyondATC rotates Player.log on launch. The new file is shorter than
        # the offset the tailer held, and everything in it is new.
        log = tmp_path / "Player.log"
        log.write_text("a long first session\n" * 50, encoding="utf-8")
        tailer = bot.LogTailer(log)
        tailer.read_new_lines()
        log.write_text("boot\n[Instruction] first of the new session\n", encoding="utf-8")
        assert tailer.read_new_lines() == ["boot", "[Instruction] first of the new session"]

    def test_a_missing_file_yields_nothing_and_no_error(self, tmp_path):
        tailer = bot.LogTailer(tmp_path / "Player.log")
        assert tailer.read_new_lines() == []

    def test_a_file_that_appears_later_is_picked_up_from_its_end(self, tmp_path):
        # The bot may start before BeyondATC. When the file appears, what is
        # already in it is boot noise from before anyone was listening.
        log = tmp_path / "Player.log"
        tailer = bot.LogTailer(log)
        tailer.read_new_lines()
        log.write_text("boot noise\n", encoding="utf-8")
        assert tailer.read_new_lines() == []
        with log.open("a", encoding="utf-8") as f:
            f.write("[Instruction] live\n")
        assert tailer.read_new_lines() == ["[Instruction] live"]

    def test_bytes_that_are_not_utf8_do_not_stop_the_stream(self, tmp_path):
        log = tmp_path / "Player.log"
        log.write_bytes(b"")
        tailer = bot.LogTailer(log)
        tailer.read_new_lines()
        with log.open("ab") as f:
            f.write(b"[LocalVoicePhonemes] sid=1 | \"\xff\xfe\"\n[Instruction] fine\n")
        lines = tailer.read_new_lines()
        assert lines[-1] == "[Instruction] fine"


def test_the_log_path_is_derived_from_the_user_profile_unless_configured():
    with patch.dict(bot.CONFIG, {}, clear=False):
        bot.CONFIG.pop("batc_log_path", None)
        derived = bot.batc_log_path()
    assert derived.name == "Player.log"
    assert "BeyondATC" in derived.parts
    assert "LocalLow" in derived.parts

    with patch.dict(bot.CONFIG, {"batc_log_path": r"D:\elsewhere\Player.log"}):
        assert bot.batc_log_path() == pathlib.Path(r"D:\elsewhere\Player.log")
