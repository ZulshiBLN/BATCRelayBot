"""
Pytest configuration and shared fixtures
"""

import json
import pathlib
from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture
def config_file(tmp_path):
    """Create a temporary config.json for testing"""
    config_data = {
        "bot_token": "test_token_12345",
        "guild_id": 123456789012345678,
        "voice_channel_id": 987654321098765432,
        "audio_device_name": "Voicemeeter Out MME",
        "python_path": "C:\\Python311\\python.exe",
        "voicemeeter_path": "C:\\Program Files (x86)\\VB\\Voicemeeter\\voicemeeter_x64.exe",
        "voicemeeter_process_name": "voicemeeter_x64",
        "voicemeeter_wait_seconds": 6,
        "batc_path": "",
        "batc_process_name": "",
        "batc_wait_seconds": 8,
    }
    config_file_path = tmp_path / "config.json"
    config_file_path.write_text(json.dumps(config_data), encoding="utf-8")
    return config_file_path


@pytest.fixture
def mock_discord_intents():
    """Create mock Discord intents"""
    intents = MagicMock()
    intents.default.return_value = intents
    intents.message_content = True
    return intents


@pytest.fixture
def mock_voice_client():
    """Create a mock Discord voice client"""
    vc = MagicMock()
    vc.is_connected.return_value = True
    vc.is_playing.return_value = False
    vc.channel = MagicMock()
    vc.channel.id = 987654321098765432
    vc.channel.name = "ATC Channel"
    return vc


@pytest.fixture
def mock_guild(mock_voice_client):
    """Create a mock Discord guild"""
    guild = MagicMock()
    guild.id = 123456789012345678
    guild.name = "Test Server"
    guild.voice_client = mock_voice_client

    channel = MagicMock()
    channel.id = 987654321098765432
    channel.name = "ATC Channel"
    channel.connect = MagicMock()

    guild.get_channel.return_value = channel
    return guild
