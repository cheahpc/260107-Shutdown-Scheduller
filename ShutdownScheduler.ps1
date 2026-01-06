# Shutdown Scheduler - Interactive Menu with Live Countdown (Scheduled Tasks based)
# Note: Double-click StartShutdownScheduler.bat to run this UI

$ErrorActionPreference = 'Stop'

$TaskPath = "\\ShutdownScheduler\\"
$Title = "Shutdown Scheduler"

function Set-WindowTitle {
    try { $Host.UI.RawUI.WindowTitle = $Title } catch {}
}

function Format-TimeSpan([TimeSpan]$ts) {
    if ($ts -lt [TimeSpan]::Zero) { return "00:00:00" }
    $days = [int]$ts.Days
    $hh = [int]$ts.Hours
    $mm = [int]$ts.Minutes
    $ss = [int]$ts.Seconds
    if ($days -gt 0) {
        return "{0}d {1:00}:{2:00}:{3:00}" -f $days, $hh, $mm, $ss
    } else {
        return "{0:00}:{1:00}:{2:00}" -f $hh, $mm, $ss
    }
}

function Get-Tasks() {
    try {
        $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction Stop
        return $tasks
    } catch {
        return @()
    }
}

function Get-ActiveSchedule() {
    $tasks = Get-Tasks
    if (-not $tasks -or $tasks.Count -eq 0) { return $null }

    $now = Get-Date
    $entries = foreach ($t in $tasks) {
        try {
            $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $TaskPath -ErrorAction Stop
            if ($info.NextRunTime -gt $now) {
                $type = $null
                if ($t.Description -match 'Type:\s*([A-Za-z]+)') { $type = $matches[1] }
                if (-not $type) {
                    # Fall back to name parsing SS_<Type>_yyyyMMdd_HHmmss
                    if ($t.TaskName -match '^SS_([A-Za-z]+)_') { $type = $matches[1] }
                }
                [pscustomobject]@{
                    Name = $t.TaskName
                    Type = $type
                    NextRunTime = $info.NextRunTime
                    TimeRemaining = ($info.NextRunTime - $now)
                }
            }
        } catch {}
    }

    $entries | Sort-Object NextRunTime | Select-Object -First 1
}

function Remove-AllSchedules() {
    $tasks = Get-Tasks
    foreach ($t in $tasks) {
        try { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $TaskPath -Confirm:$false | Out-Null } catch {}
    }
}

function New-ActionForType($type) {
    switch ($type) {
        'Shutdown' { return New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '-s -t 0 -f' }
        'Restart'  { return New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '-r -t 0 -f' }
        'Logoff'   { return New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '-l' }
        'Hibernate' { return New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '/h' }
        'Sleep'     { return New-ScheduledTaskAction -Execute 'rundll32.exe' -Argument 'powrprof.dll,SetSuspendState Sleep' }
        default { throw "Unknown shutdown type: $type" }
    }
}

function Create-Schedule([string]$Type, [TimeSpan]$Delay) {
    if ($Delay.TotalSeconds -lt 1) { throw "Delay must be at least 1 second." }
    $target = (Get-Date).Add($Delay)

    $action = New-ActionForType $Type
    $trigger = New-ScheduledTaskTrigger -Once -At $target

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromHours(1))

    $name = 'SS_{0}_{1:yyyyMMdd_HHmmss}' -f $Type, $target
    $desc = 'Type: {0}; Created: {1:yyyy-MM-dd HH:mm:ss}' -f $Type, (Get-Date)

    try {
        Register-ScheduledTask -TaskName $name -TaskPath $TaskPath -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $desc | Out-Null
    } catch {
        throw "Failed to register scheduled task. Try running as Administrator. Error: $($_.Exception.Message)"
    }
}

function Draw-MainScreen() {
    Clear-Host
    Set-WindowTitle

    $now = Get-Date
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    Write-Host "Now: $($now.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host ""

    $active = Get-ActiveSchedule
    if ($null -ne $active) {
        Write-Host "Scheduled: $($active.Type)" -ForegroundColor Yellow
        Write-Host "Runs At: $($active.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    } else {
        Write-Host "No scheduled action detected." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Menu: [S]chedule  [A]bort  [Q]uit" -ForegroundColor White
    Write-Host "Enter your choice and press Enter." -ForegroundColor DarkGray
}

function Prompt-Int($label, [int]$current) {
    while ($true) {
        $input = Read-Host "$label ($current) - 'c' to cancel, blank to reset to 0"
        if ([string]::IsNullOrWhiteSpace($input)) { return 0 }
        if ($input -match '^(?i:c)$') { return $current }
        $n = $null
        if ([int]::TryParse($input, [ref]$n)) {
            if ($n -ge 0) { return $n }
        }
        Write-Host "Please enter a non-negative integer, 'c' to cancel, or blank to reset." -ForegroundColor Red
    }
}

function Schedule-Wizard() {
    $days = 0; $hours = 0; $minutes = 0; $seconds = 0
    $types = @('Shutdown','Restart','Logoff','Sleep','Hibernate')
    $typeIndex = 0

    # Load existing schedule if present
    $existing = Get-ActiveSchedule
    if ($null -ne $existing) {
        $ts = $existing.TimeRemaining
        if ($ts.TotalSeconds -gt 0) {
            $days = [int]$ts.Days
            $hours = [int]$ts.Hours
            $minutes = [int]$ts.Minutes
            $seconds = [int]$ts.Seconds
            # Find type index
            for ($i = 0; $i -lt $types.Count; $i++) {
                if ($types[$i] -eq $existing.Type) { $typeIndex = $i; break }
            }
        }
    }

    while ($true) {
        Clear-Host
        Set-WindowTitle
        $ts = [TimeSpan]::FromDays($days) + [TimeSpan]::FromHours($hours) + [TimeSpan]::FromMinutes($minutes) + [TimeSpan]::FromSeconds($seconds)
        $target = (Get-Date).Add($ts)
        Write-Host "=== Schedule Wizard ===" -ForegroundColor Cyan
        Write-Host "Type: $($types[$typeIndex])" -ForegroundColor Yellow
        Write-Host "Days: $days  Hours: $hours  Minutes: $minutes  Seconds: $seconds"
        Write-Host "Total: $(Format-TimeSpan $ts)"
        Write-Host "Will run at: $($target.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor White
        Write-Host "  Edit [D]ays   Edit [H]ours   Edit [M]inutes   Edit [S]econds"
        Write-Host "  Edit [T]ype   [C]reate Schedule   Esc) Cancel"
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyUp')
        switch ($key.VirtualKeyCode) {
            68 { $days = Prompt-Int 'Days' $days }      # D
            72 { $hours = Prompt-Int 'Hours' $hours }   # H
            77 { $minutes = Prompt-Int 'Minutes' $minutes } # M
            83 { $seconds = Prompt-Int 'Seconds' $seconds } # S
            84 { $typeIndex = ($typeIndex + 1) % $types.Count } # T
            67 { # C (Create)
                if ($ts.TotalSeconds -lt 1) { Write-Host "Please set a delay greater than 0 before creating." -ForegroundColor Red; Start-Sleep 1; continue }
                try {
                    # Remove existing schedules before creating new one
                    Remove-AllSchedules
                    Create-Schedule -Type $types[$typeIndex] -Delay $ts
                    Write-Host "Scheduled $($types[$typeIndex]) successfully." -ForegroundColor Green
                    Start-Sleep 1
                    return
                } catch {
                    Write-Host $_.Exception.Message -ForegroundColor Red
                    Write-Host "Press any key to return..." -ForegroundColor DarkGray
                    [void][Console]::ReadKey($true)
                    return
                }
            }
            27 { return } # Esc
            default { }
        }
    }
}

function Cancel-Flow() {
    Clear-Host
    Set-WindowTitle
    $tasks = Get-Tasks
    if (-not $tasks -or $tasks.Count -eq 0) {
        Write-Host "Nothing to cancel." -ForegroundColor DarkGray
        Start-Sleep 1
        return
    }
    Write-Host "The following scheduled items will be removed:" -ForegroundColor Yellow
    $tasks | ForEach-Object { Write-Host " - $($_.TaskName)" }
    $ans = Read-Host "Type YES to confirm"
    if ($ans -eq 'YES') {
        Remove-AllSchedules
        Write-Host "Cancelled all scheduled items." -ForegroundColor Green
        Start-Sleep 1
    }
}

# Main UI loop (static display, no auto-refresh)
while ($true) {
    Draw-MainScreen
    $choice = Read-Host "Choice (S/A/Q)"
    switch ($choice.ToUpperInvariant()) {
        'S' { Schedule-Wizard }
        'A' { Cancel-Flow }
        'Q' { break }
        default {
            Write-Host "Unknown choice. Please enter S, A, or Q." -ForegroundColor Red
            Start-Sleep 1
        }
    }
}
