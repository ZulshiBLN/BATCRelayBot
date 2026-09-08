# Everything Write-InstallLog writes passes through Remove-SensitiveData, so
# this is the one place that decides what can reach install.log.
#
# Until 1.4.1 it redacted tokens and nothing else. The installer wrote the real
# server and channel IDs in plain text - "Server ID (guild) accepted:" followed
# by the value - while the rule that forbids logging a token forbids logging
# those in the same sentence. Install logs travel: into bug reports,
# screenshots and support threads.
#
# Both directions matter here. A redactor that swallows timestamps, versions and
# paths makes the log useless, and a useless log gets turned off.

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psd1" -Force
}

Describe "Remove-SensitiveData" {
    Context "redacts" {
        It "a Discord bot token" {
            InModuleScope BATCRelayBot {
                $token = ('M' * 24) + '.' + ('G' * 6) + '.' + ('f' * 27)
                Remove-SensitiveData -Text "Validating $token" | Should -Not -Match ([regex]::Escape($token))
            }
        }

        It "a token behind an Authorization header" {
            InModuleScope BATCRelayBot {
                Remove-SensitiveData -Text ('Authorization: Bot ' + ('A' * 40)) |
                    Should -Match 'REDACTED-TOKEN'
            }
        }

        It "a server or channel ID" {
            InModuleScope BATCRelayBot {
                Remove-SensitiveData -Text 'Server ID (guild) accepted: 631480440548753408' |
                    Should -Be 'Server ID (guild) accepted: [REDACTED-ID]'
                Remove-SensitiveData -Text 'Voice channel ID accepted: 1535343588567683122' |
                    Should -Be 'Voice channel ID accepted: [REDACTED-ID]'
            }
        }
    }

    Context "leaves the log readable" {
        It "a timestamp" {
            InModuleScope BATCRelayBot {
                $line = 'Installation session started 2026-09-08 21:20:41'
                Remove-SensitiveData -Text $line | Should -Be $line
            }
        }

        It "a version and a build number" {
            InModuleScope BATCRelayBot {
                $line = 'BATCRelayBot 1.4.1 on PowerShell 5.1.26100.9278'
                Remove-SensitiveData -Text $line | Should -Be $line
            }
        }

        It "a filesystem path" {
            InModuleScope BATCRelayBot {
                $line = 'Python at C:\Users\x\AppData\Local\Programs\Python\Python312'
                Remove-SensitiveData -Text $line | Should -Be $line
            }
        }

        It "an ordinary number" {
            InModuleScope BATCRelayBot {
                Remove-SensitiveData -Text 'Disk space freed: 1024 MB' | Should -Be 'Disk space freed: 1024 MB'
            }
        }
    }

    # The guarantee that matters: not that one call site remembers to redact,
    # but that the log cannot receive an ID however the message was built.
    It "covers anything written through Write-InstallLog" {
        InModuleScope BATCRelayBot {
            $log = Join-Path $env:TEMP ("redaction-" + [guid]::NewGuid().ToString('N') + ".log")
            try {
                Write-InstallLog "Voice channel ID accepted: 1535343588567683122" -LogPath $log
                $written = [System.IO.File]::ReadAllText($log)
                $written | Should -Not -Match '\d{17,20}'
                $written | Should -Match 'REDACTED-ID'
            } finally { Remove-Item $log -ErrorAction SilentlyContinue }
        }
    }
}
