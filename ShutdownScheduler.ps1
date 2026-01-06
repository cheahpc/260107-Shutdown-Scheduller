# Shutdown Scheduler - Interactive Menu with Live Countdown (Scheduled Tasks based)
# Note: Double-click StartShutdownScheduler.bat to run this UI

$ErrorActionPreference = 'Stop'

$TaskPath = "\ShutdownScheduler\"
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

    # Simplified principal - use current user without RunLevel
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    # Use simpler task name format to avoid special characters
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $name = "SS_{0}_{1}" -f $Type, $timestamp
    $desc = "Type: {0}; Created: {1:yyyy-MM-dd HH:mm:ss}" -f $Type, (Get-Date)

    Register-ScheduledTask -TaskName $name -TaskPath $TaskPath -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $desc -ErrorAction Stop | Out-Null
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
        $rem = $active.TimeRemaining
        $days = [int]$rem.Days
        $hours = [int]$rem.Hours
        $minutes = [int]$rem.Minutes
        $seconds = [int]$rem.Seconds
        
        Write-Host "Scheduled Action: $($active.Type)" -ForegroundColor Yellow
        Write-Host "ID: $($active.Name)" -ForegroundColor DarkYellow
        Write-Host "Runs At: $($active.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        
        $timeStr = @()
        if ($days -gt 0) { $timeStr += "$days day(s)" }
        if ($hours -gt 0) { $timeStr += "$hours hour(s)" }
        if ($minutes -gt 0) { $timeStr += "$minutes minute(s)" }
        if ($seconds -gt 0) { $timeStr += "$seconds second(s)" }
        if ($timeStr.Count -eq 0) { $timeStr += "less than 1 second" }
        
        Write-Host "Time Until $($active.Type): $($timeStr -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "No scheduled action detected." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Menu: [S]chedule  [A]bort  [R]efresh  [Q]uit" -ForegroundColor White
    Write-Host "Enter your choice" -ForegroundColor DarkGray
    Write-Host ""
    [Console]::Out.Flush()
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
    # Clear keyboard buffer before starting
    while ([Console]::KeyAvailable) {
        [void][Console]::ReadKey($true)
    }
    Start-Sleep -Milliseconds 100
    
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
        Write-Host "  Edit [T]ype | [D]ays | [H]ours | [M]inutes | [S]econds"
        Write-Host ""
        Write-Host "  [C]reate Schedule   [Esc] Cancel"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        [Console]::Out.Flush()

        # Drain any buffered keys before reading a fresh one
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }

        # Read a single KeyDown event using Console API (more reliable across hosts)
        $key = [Console]::ReadKey($true)
        # Echo the selected choice next to the prompt, then move to a new line
        Write-Host $key.KeyChar

        switch ($key.Key) {
            ([ConsoleKey]::D) { $days = Prompt-Int 'Days' $days }
            ([ConsoleKey]::H) { $hours = Prompt-Int 'Hours' $hours }
            ([ConsoleKey]::M) { $minutes = Prompt-Int 'Minutes' $minutes }
            ([ConsoleKey]::S) { $seconds = Prompt-Int 'Seconds' $seconds }
            ([ConsoleKey]::T) { $typeIndex = ($typeIndex + 1) % $types.Count }
            ([ConsoleKey]::C) { # C (Create)
                if ($ts.TotalSeconds -lt 1) { 
                    Write-Host ""
                    Write-Host "Please set a delay greater than 0 before creating." -ForegroundColor Red
                    Write-Host "Press any key to continue..." -ForegroundColor DarkGray
                    [void][Console]::ReadKey($true)
                    continue 
                }
                Write-Host ""
                Write-Host "Creating Schedule..." -ForegroundColor Cyan
                try {
                    # Remove existing schedules before creating new one
                    Remove-AllSchedules
                    Create-Schedule -Type $types[$typeIndex] -Delay $ts
                    Write-Host "Scheduled $($types[$typeIndex]) successfully." -ForegroundColor Green
                    Write-Host ""
                    Write-Host "Press any key to modify schedule, or wait 5 seconds to return to main menu..." -ForegroundColor Yellow

                    # Wait up to 5 seconds for keypress
                    $waited = 0
                    $keyPressed = $false
                    while ($waited -lt 5000) {
                        if ([Console]::KeyAvailable) {
                            [void][Console]::ReadKey($true)
                            $keyPressed = $true
                            break
                        }
                        Start-Sleep -Milliseconds 100
                        $waited += 100
                    }

                    if ($keyPressed) {
                        # Reload the schedule for modification
                        $existing = Get-ActiveSchedule
                        if ($null -ne $existing) {
                            $ts = $existing.TimeRemaining
                            if ($ts.TotalSeconds -gt 0) {
                                $days = [int]$ts.Days
                                $hours = [int]$ts.Hours
                                $minutes = [int]$ts.Minutes
                                $seconds = [int]$ts.Seconds
                                for ($i = 0; $i -lt $types.Count; $i++) {
                                    if ($types[$i] -eq $existing.Type) { $typeIndex = $i; break }
                                }
                            }
                        }
                        continue
                    } else {
                        return
                    }
                } catch {
                    Write-Host ""
                    Write-Host "Failed to create schedule: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "Press any key to return..." -ForegroundColor DarkGray
                    [void][Console]::ReadKey($true)
                    return
                }
            }
            ([ConsoleKey]::Escape) { return }
            default { }
        }
    }
}

function Cancel-Flow() {
    Write-Host ""
    $tasks = Get-Tasks
    if (-not $tasks -or $tasks.Count -eq 0) {
        Write-Host "Nothing to cancel." -ForegroundColor DarkGray
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return
    }
    Write-Host "The following scheduled items will be removed:" -ForegroundColor Yellow
    $tasks | ForEach-Object { Write-Host " - ID: $($_.TaskName)" }
    $ans = Read-Host "Abort schedule? (Y/N)"
    if ($ans -match '^[Yy]$') {
        Remove-AllSchedules
        Write-Host "Cancelled all scheduled items." -ForegroundColor Green
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
    }
}

# Main UI loop (static display, no auto-refresh)
while ($true) {
    Draw-MainScreen
    Write-Host "Choice: " -NoNewline
    [Console]::Out.Flush()
    $key = [Console]::ReadKey($true)
    Write-Host $key.KeyChar
    
    # Clear any remaining buffered keys
    while ([Console]::KeyAvailable) {
        [void][Console]::ReadKey($true)
    }
    
    switch ($key.Key) {
        ([ConsoleKey]::S) { Schedule-Wizard }
        ([ConsoleKey]::A) { Cancel-Flow }
        ([ConsoleKey]::R) { } # Refresh - just redraw by continuing loop
        ([ConsoleKey]::Q) { return }
        default {
            Write-Host "Unknown choice. Please enter S, A, R, or Q." -ForegroundColor Red
            Write-Host "Press any key to continue..." -ForegroundColor DarkGray
            [void][Console]::ReadKey($true)
        }
    }
}
