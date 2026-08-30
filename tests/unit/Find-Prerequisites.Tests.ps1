BeforeAll {
    # Import module
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

Describe "Find-Python" {
    It "Returns hashtable with Required keys" {
        $result = Find-Python
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain "Found"
        $result.Keys | Should -Contain "Path"
        $result.Keys | Should -Contain "Version"
        $result.Keys | Should -Contain "Method"
    }

    It "Found should be boolean" {
        $result = Find-Python
        $result.Found | Should -BeOfType [bool]
    }

    It "If Found=true, Path should not be null" {
        $result = Find-Python
        if ($result.Found) {
            $result.Path | Should -Not -BeNullOrEmpty
        }
    }

    It "If Found=false, Path should be null" {
        # This depends on actual system state, just verify structure
        $result = Find-Python
        if (-not $result.Found) {
            $result.Path | Should -BeNullOrEmpty
        }
    }
}

Describe "Find-FFmpeg" {
    It "Returns hashtable with Required keys" {
        $result = Find-FFmpeg
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain "Found"
        $result.Keys | Should -Contain "Path"
        $result.Keys | Should -Contain "Version"
        $result.Keys | Should -Contain "Method"
    }

    It "Found should be boolean" {
        $result = Find-FFmpeg
        $result.Found | Should -BeOfType [bool]
    }
}

Describe "Find-VoiceMeeter" {
    It "Returns hashtable with Required keys" {
        $result = Find-VoiceMeeter
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain "Found"
        $result.Keys | Should -Contain "Path"
        $result.Keys | Should -Contain "Version"
        $result.Keys | Should -Contain "Method"
    }

    It "Found should be boolean" {
        $result = Find-VoiceMeeter
        $result.Found | Should -BeOfType [bool]
    }

    It "Returns correct structure for missing VoiceMeeter" {
        # If VoiceMeeter not installed, should still return valid hashtable
        $result = Find-VoiceMeeter
        $result.Found | Should -BeOfType [bool]
        # If not found, all values should be null or empty
        if (-not $result.Found) {
            $result.Path | Should -BeNullOrEmpty
        }
    }
}

Describe "Find-BeyondATC" {
    It "Returns hashtable with Required keys" {
        $result = Find-BeyondATC
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain "Found"
        $result.Keys | Should -Contain "Path"
        $result.Keys | Should -Contain "Version"
        $result.Keys | Should -Contain "Method"
    }

    It "Found should be boolean" {
        $result = Find-BeyondATC
        $result.Found | Should -BeOfType [bool]
    }

    It "BeyondATC is optional - always returns valid structure" {
        $result = Find-BeyondATC
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe "Prerequisites Detection Integration" {
    It "Can call all functions without error" {
        { Find-Python } | Should -Not -Throw
        { Find-FFmpeg } | Should -Not -Throw
        { Find-VoiceMeeter } | Should -Not -Throw
        { Find-BeyondATC } | Should -Not -Throw
    }

    It "All functions return consistent structure" {
        $results = @(
            (Find-Python),
            (Find-FFmpeg),
            (Find-VoiceMeeter),
            (Find-BeyondATC)
        )
        foreach ($result in $results) {
            $result.Found | Should -BeOfType [bool]
            $result.Keys | Should -Contain "Found"
            $result.Keys | Should -Contain "Path"
            $result.Keys | Should -Contain "Version"
            $result.Keys | Should -Contain "Method"
        }
    }
}
