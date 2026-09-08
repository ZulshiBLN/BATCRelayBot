#Requires -Version 5.1

<#
.SYNOPSIS
Tests for picking the right VoiceMeeter bus to relay.

.DESCRIPTION
The first version recommended "the first device whose name contains
Voicemeeter and Out". ffmpeg enumerates in no useful order, so on a real
machine that landed on B3 while README step 3 had routed audio to B1 - the
bot connected, streamed the wrong bus, and the user had to correct
config.json by hand.

What the name actually means:
  B1..B3   virtual buses, meant to be captured by other software
  A1..A5   physical buses, feeding speakers and headphones
#>

BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force

    # Captured verbatim from a real machine, in the order ffmpeg returned it.
    $script:RealDevices = @(
        'External Mic (Sound BlasterX G6)',
        'Voicemeeter Out B3 (VB-Audio Voicemeeter VAIO)',
        'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)',
        'Voicemeeter Out A5 (VB-Audio Voicemeeter VAIO)',
        'Voicemeeter Out A4 (VB-Audio Voicemeeter VAIO)',
        'Headset Microphone (2- DualSense Wireless Controller)',
        'Headset Microphone (Oculus Virtual Audio Device)',
        'Microphone (Virtual Desktop Audio)',
        'Voicemeeter Out A2 (VB-Audio Voicemeeter VAIO)',
        'Voicemeeter Out A1 (VB-Audio Voicemeeter VAIO)',
        'Voicemeeter Out A3 (VB-Audio Voicemeeter VAIO)',
        'Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)'
    )
}

Describe "Get-AudioDeviceInfo" {

    It "recognises a B bus as virtual and capturable" {
        $info = Get-AudioDeviceInfo -Name 'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)'
        $info.IsVoiceMeeter | Should -BeTrue
        $info.Bus          | Should -Be 'B1'
        $info.IsVirtual    | Should -BeTrue
    }

    It "recognises an A bus as physical and never recommendable" {
        $info = Get-AudioDeviceInfo -Name 'Voicemeeter Out A1 (VB-Audio Voicemeeter VAIO)'
        $info.IsVoiceMeeter | Should -BeTrue
        $info.Bus          | Should -Be 'A1'
        $info.IsVirtual    | Should -BeFalse
        $info.Rank         | Should -BeGreaterThan 10
    }

    It "ranks B1 ahead of B2 and B3" {
        $b1 = Get-AudioDeviceInfo -Name 'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)'
        $b2 = Get-AudioDeviceInfo -Name 'Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)'
        $b3 = Get-AudioDeviceInfo -Name 'Voicemeeter Out B3 (VB-Audio Voicemeeter VAIO)'

        $b1.Rank | Should -BeLessThan $b2.Rank
        $b2.Rank | Should -BeLessThan $b3.Rank
    }

    It "treats a microphone as not a VoiceMeeter bus" {
        $info = Get-AudioDeviceInfo -Name 'External Mic (Sound BlasterX G6)'
        $info.IsVoiceMeeter | Should -BeFalse
        $info.IsVirtual     | Should -BeFalse
    }

    Context "older VoiceMeeter naming" {

        It "maps the bare Output to B1" {
            (Get-AudioDeviceInfo -Name 'VoiceMeeter Output (VB-Audio VoiceMeeter VAIO)').Bus | Should -Be 'B1'
        }

        It "maps Aux Output to B2, not to B1" {
            # 'Output' appears in this name too, so order of matching matters.
            $info = Get-AudioDeviceInfo -Name 'VoiceMeeter Aux Output (VB-Audio VoiceMeeter AUX VAIO)'
            $info.Bus       | Should -Be 'B2'
            $info.IsVirtual | Should -BeTrue
        }

        It "maps VAIO3 Output to B3" {
            (Get-AudioDeviceInfo -Name 'VoiceMeeter VAIO3 Output (VB-Audio VoiceMeeter VAIO3)').Bus | Should -Be 'B3'
        }
    }
}

Describe "Get-RankedAudioDevice" {

    It "recommends B1 from the real device list, not whatever came first" {
        # The regression: ffmpeg listed B3 second, so it used to win.
        $ranked = @(Get-RankedAudioDevice -Devices $script:RealDevices)
        $ranked[0].Name | Should -Be 'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)'
    }

    It "puts every virtual bus ahead of every physical one" {
        $ranked = @(Get-RankedAudioDevice -Devices $script:RealDevices)

        $virtualIndexes = @()
        $physicalIndexes = @()
        for ($i = 0; $i -lt $ranked.Count; $i++) {
            if ($ranked[$i].IsVirtual) { $virtualIndexes += $i } else { $physicalIndexes += $i }
        }

        ($virtualIndexes | Measure-Object -Maximum).Maximum |
            Should -BeLessThan ($physicalIndexes | Measure-Object -Minimum).Minimum
    }

    It "orders the virtual buses B1, B2, B3" {
        $ranked = @(Get-RankedAudioDevice -Devices $script:RealDevices | Where-Object { $_.IsVirtual })
        $ranked.Bus | Should -Be @('B1', 'B2', 'B3')
    }

    It "never recommends a microphone when a virtual bus exists" {
        $ranked = @(Get-RankedAudioDevice -Devices $script:RealDevices)
        $ranked[0].IsVoiceMeeter | Should -BeTrue
    }

    It "marks nothing as virtual when VoiceMeeter is absent" {
        # Without a virtual bus there must be no default at all: preselecting
        # index 0 would relay a live microphone into the voice channel.
        $noVoiceMeeter = @(
            'External Mic (Sound BlasterX G6)',
            'Headset Microphone (2- DualSense Wireless Controller)'
        )
        $ranked = @(Get-RankedAudioDevice -Devices $noVoiceMeeter)
        @($ranked | Where-Object { $_.IsVirtual }).Count | Should -Be 0
    }

    It "keeps ffmpeg's order among equally ranked devices" {
        $ranked = @(Get-RankedAudioDevice -Devices $script:RealDevices | Where-Object { -not $_.IsVoiceMeeter })
        $ranked[0].Name | Should -Be 'External Mic (Sound BlasterX G6)'
    }

    It "returns every device it was given" {
        @(Get-RankedAudioDevice -Devices $script:RealDevices).Count | Should -Be $script:RealDevices.Count
    }

    It "handles an empty list without throwing" {
        { Get-RankedAudioDevice -Devices @() } | Should -Not -Throw
    }
}

Describe "Select-AudioDevice" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Write-InstallLog { }
    }

    Context "when VoiceMeeter buses are present" {

        It "returns B1 when the user just presses Enter" {
            Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { $script:RealDevices }
            Mock -ModuleName BATCRelayBot Read-Host { "" }

            $result = Select-AudioDevice -FFmpegPath "C:\fake\ffmpeg.exe" 6>$null
            $result | Should -Be 'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)'
        }

        It "numbers only the three virtual buses, not all twelve devices" {
            # The physical buses and microphones are filtered out, so [3] is
            # the last valid choice even though ffmpeg reported twelve devices.
            Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { $script:RealDevices }
            Mock -ModuleName BATCRelayBot Read-Host { "3" }

            $result = Select-AudioDevice -FFmpegPath "C:\fake\ffmpeg.exe" 6>$null
            $result | Should -Be 'Voicemeeter Out B3 (VB-Audio Voicemeeter VAIO)'
        }

        It "never offers a microphone or an A bus" {
            # Every selectable position must resolve to a B bus. On this list
            # ffmpeg reported nine other VoiceMeeter devices and three
            # microphones; none of them may be reachable by number.
            Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { $script:RealDevices }

            foreach ($choice in 1..3) {
                Mock -ModuleName BATCRelayBot Read-Host { "$choice" }.GetNewClosure()
                $result = Select-AudioDevice -FFmpegPath "C:\fake\ffmpeg.exe" 6>$null
                $result | Should -Match 'Out B\d' -Because "position $choice must be a virtual bus"
            }
        }
    }

    Context "when no VoiceMeeter bus is present" {

        It "falls back to the full list rather than showing nothing" {
            $micsOnly = @('External Mic (Sound BlasterX G6)', 'Headset Microphone (Oculus Virtual Audio Device)')
            Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { $micsOnly }.GetNewClosure()
            Mock -ModuleName BATCRelayBot Read-Host { "1" } -ParameterFilter { $Prompt -match 'Select device' }
            Mock -ModuleName BATCRelayBot Read-Host { "y" } -ParameterFilter { $Prompt -match 'anyway' }

            $result = Select-AudioDevice -FFmpegPath "C:\fake\ffmpeg.exe" 6>$null
            $result | Should -Be 'External Mic (Sound BlasterX G6)'
        }

        It "makes the user confirm a non-virtual device instead of taking it silently" {
            $micsOnly = @('External Mic (Sound BlasterX G6)')
            Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { $micsOnly }.GetNewClosure()
            Mock -ModuleName BATCRelayBot Read-Host { "1" } -ParameterFilter { $Prompt -match 'Select device' }
            Mock -ModuleName BATCRelayBot Read-Host { "y" } -ParameterFilter { $Prompt -match 'anyway' }

            Select-AudioDevice -FFmpegPath "C:\fake\ffmpeg.exe" 6>$null | Out-Null

            Should -Invoke -ModuleName BATCRelayBot Read-Host -Times 1 -Exactly `
                -ParameterFilter { $Prompt -match 'anyway' }
        }

        It "has no Enter default when nothing is safe to preselect" {
            $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Get-AudioDevice.ps1" -Raw
            $source | Should -Match 'no safe default'
        }
    }

    Context "when ffmpeg reports nothing" {

        It "falls back to manual entry" {
            Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { @() }
            Mock -ModuleName BATCRelayBot Read-Host { "Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)" }

            $result = Select-AudioDevice -FFmpegPath "C:\fake\ffmpeg.exe" 6>$null
            $result | Should -Be 'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)'
        }

        It "returns null when the user enters nothing" {
            Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { @() }
            Mock -ModuleName BATCRelayBot Read-Host { "" }

            Select-AudioDevice -FFmpegPath "C:\fake\ffmpeg.exe" 6>$null | Should -BeNullOrEmpty
        }
    }
}
