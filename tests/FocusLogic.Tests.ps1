<#
    Pester-Tests (v5+) fuer src/FocusLogic.psm1.
    Ausfuehren:  Invoke-Pester .\tests\FocusLogic.Tests.ps1
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../src/FocusLogic.psm1" -Force
}

Describe 'Get-MonitorIndexForPoint' {
    BeforeAll {
        $script:mons = @(
            [pscustomobject]@{ Left = 0;     Top = 0; Right = 1920; Bottom = 1080 }
            [pscustomobject]@{ Left = -1920; Top = 0; Right = 0;    Bottom = 1080 }
        )
    }

    It 'findet den Hauptmonitor' {
        Get-MonitorIndexForPoint 100 100 $script:mons | Should -Be 0
    }
    It 'findet den linken Monitor bei negativem X' {
        Get-MonitorIndexForPoint -50 100 $script:mons | Should -Be 1
    }
    It 'linke/obere Kante gehoert zum Monitor' {
        Get-MonitorIndexForPoint 0 0 $script:mons | Should -Be 0
    }
    It 'rechte Kante ist exklusiv' {
        Get-MonitorIndexForPoint 1920 100 $script:mons | Should -Be -1
    }
    It 'Punkt ausserhalb aller Monitore -> -1' {
        Get-MonitorIndexForPoint 5000 5000 $script:mons | Should -Be -1
    }
}

Describe 'Test-ShouldSwitch' {
    BeforeAll { $script:t0 = [datetime]::UtcNow }

    It 'gleicher Index -> false' {
        Test-ShouldSwitch 0 0 $script:t0 $script:t0.AddMilliseconds(500) 120 | Should -BeFalse
    }
    It 'Entprellung noch nicht abgelaufen -> false' {
        Test-ShouldSwitch 0 1 $script:t0 $script:t0.AddMilliseconds(50) 120 | Should -BeFalse
    }
    It 'Entprellung abgelaufen -> true' {
        Test-ShouldSwitch 0 1 $script:t0 $script:t0.AddMilliseconds(200) 120 | Should -BeTrue
    }
    It 'ungueltiger aktueller Index -> false' {
        Test-ShouldSwitch 0 -1 $script:t0 $script:t0.AddMilliseconds(200) 120 | Should -BeFalse
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
