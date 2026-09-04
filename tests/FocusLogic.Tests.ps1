<#
    Pester-Tests (v5+) fuer src/FocusLogic.psm1.
    Ausfuehren:  Invoke-Pester .\tests\FocusLogic.Tests.ps1
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../src/FocusLogic.psm1" -Force
}

Describe 'Test-ShouldSwitchWindow' {
    BeforeAll { $script:t0 = [datetime]::UtcNow }

    It 'gleiches Fenster -> false' {
        Test-ShouldSwitchWindow 100 100 $script:t0 $script:t0.AddMilliseconds(500) 120 $false | Should -BeFalse
    }
    It 'Entprellung noch nicht abgelaufen -> false' {
        Test-ShouldSwitchWindow 100 200 $script:t0 $script:t0.AddMilliseconds(50) 120 $false | Should -BeFalse
    }
    It 'anderes Fenster, Entprellung abgelaufen -> true' {
        Test-ShouldSwitchWindow 100 200 $script:t0 $script:t0.AddMilliseconds(200) 120 $false | Should -BeTrue
    }
    It 'Maustaste gedrueckt -> false (kein Wechsel beim Ziehen/Markieren)' {
        Test-ShouldSwitchWindow 100 200 $script:t0 $script:t0.AddMilliseconds(500) 120 $true | Should -BeFalse
    }
    It 'ungueltiges Handle (0) -> false' {
        Test-ShouldSwitchWindow 100 0 $script:t0 $script:t0.AddMilliseconds(500) 120 $false | Should -BeFalse
    }
}

Describe 'Test-IsFocusableWindow' {
    It 'Desktop (WorkerW) -> false' {
        Test-IsFocusableWindow 'WorkerW' 'explorer' $true @() | Should -BeFalse
    }
    It 'Taskleiste (Shell_TrayWnd) -> false' {
        Test-IsFocusableWindow 'Shell_TrayWnd' 'explorer' $true @() | Should -BeFalse
    }
    It 'unsichtbares Fenster -> false' {
        Test-IsFocusableWindow 'Chrome_WidgetWin_1' 'chrome' $false @() | Should -BeFalse
    }
    It 'ausgeschlossener Prozess -> false' {
        Test-IsFocusableWindow 'SomeClass' 'game' $true @('game') | Should -BeFalse
    }
    It 'ausgeschlossener Prozess mit .exe-Schreibweise -> false' {
        Test-IsFocusableWindow 'SomeClass' 'game.exe' $true @('game') | Should -BeFalse
    }
    It 'normales sichtbares Fenster -> true' {
        Test-IsFocusableWindow 'Chrome_WidgetWin_1' 'chrome' $true @() | Should -BeTrue
    }
}
