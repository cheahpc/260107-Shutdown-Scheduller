# Shutdown Scheduler - Interactive Menu with Live Countdown (Scheduled Tasks based)
# Note: Double-click StartShutdownScheduler.bat to run this UI

$ErrorActionPreference = 'Stop'

$TaskPath = "\ShutdownScheduler\"
$Title = "Shutdown Scheduler"

# Error handling wrapper to show errors before exit
trap {
    Write-Host ""
    Write-Host "FATAL ERROR:" -ForegroundColor Red
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack trace:" -ForegroundColor Yellow
    Write-Host "$($_.ScriptStackTrace)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    [void][Console]::ReadKey($true)
    exit 1
}

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

function Get-ScheduleEntries() {
    $tasks = Get-Tasks
    if ($null -eq $tasks -or @($tasks).Count -eq 0) { return @() }

    $now = Get-Date
    $entries = foreach ($t in $tasks) {
        try {
            $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $TaskPath -ErrorAction Stop
            $next = $info.NextRunTime
            # Skip if NextRunTime is null, empty, or MinValue (task disabled or broken)
            if ($null -eq $next -or $next -eq [datetime]::MinValue) { continue }

            $type = $null
            if ($t.Description -match 'Type:\s*([A-Za-z]+)') { $type = $matches[1] }
            if (-not $type -and $t.TaskName -match '^SS_([A-Za-z]+)_') { $type = $matches[1] }
            if (-not $type) { $type = 'Unknown' }

            [pscustomobject]@{
                Name = $t.TaskName
                Type = $type
                NextRunTime = $next
                TimeRemaining = ($next - $now)
            }
        } catch {}
    }

    $entries | Where-Object { $_ -ne $null } | Sort-Object NextRunTime
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
    $entries = Get-ScheduleEntries
    if ($null -eq $entries -or @($entries).Count -eq 0) { return $null }
    $entries | Sort-Object NextRunTime | Select-Object -First 1
}

function Remove-AllSchedules() {
    $tasks = Get-Tasks
    foreach ($t in $tasks) {
        try { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $TaskPath -Confirm:$false | Out-Null } catch {}
    }
}

function Remove-ScheduleByName([string]$TaskName) {
    if ([string]::IsNullOrWhiteSpace($TaskName)) { return }
    try {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false | Out-Null
    } catch {}
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
    param(
        [array]$Schedules
    )

    Clear-Host
    Set-WindowTitle

    $now = Get-Date
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    Write-Host "Now: $($now.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host ""

    if ($null -eq $Schedules -or @($Schedules).Count -eq 0) {
        Write-Host "No scheduled actions detected." -ForegroundColor DarkGray
    } else {
        Write-Host "Detected schedules (ordered by run time):" -ForegroundColor Yellow
        Write-Host "Idx  Type        ID                             Runs At             Time Until"
        Write-Host "---  ----------  ----------------------------  -------------------  ----------------"
        $idx = 1
        foreach ($s in $Schedules) {
            $until = Format-TimeSpan $s.TimeRemaining
            $line = "{0,3}  {1,-10}  {2,-28}  {3,-19}  {4}" -f $idx, $s.Type, $s.Name, $s.NextRunTime.ToString('yyyy-MM-dd HH:mm'), $until
            Write-Host $line
            $idx++
        }
    }

    Write-Host ""
    Write-Host "Menu: [N]ew  [M]odify  [A]bort  [R]efresh  [Q]uit" -ForegroundColor White
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

function Schedule-Wizard([pscustomobject]$ExistingSchedule, [string]$ReplaceTaskName) {
    # Clear keyboard buffer before starting
    while ([Console]::KeyAvailable) {
        [void][Console]::ReadKey($true)
    }
    Start-Sleep -Milliseconds 100
    
    $days = 0; $hours = 0; $minutes = 0; $seconds = 0
    $types = @('Shutdown','Restart','Logoff','Sleep','Hibernate')
    $typeIndex = 0

    if ($null -ne $ExistingSchedule) {
        $ts = $ExistingSchedule.TimeRemaining
        if ($ts.TotalSeconds -lt 1) { $ts = [TimeSpan]::FromSeconds(1) }
        $days = [int]$ts.Days
        $hours = [int]$ts.Hours
        $minutes = [int]$ts.Minutes
        $seconds = [int]$ts.Seconds
        for ($i = 0; $i -lt $types.Count; $i++) {
            if ($types[$i] -eq $ExistingSchedule.Type) { $typeIndex = $i; break }
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
            ([ConsoleKey]::C) {
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
                    Create-Schedule -Type $types[$typeIndex] -Delay $ts
                    if ($ReplaceTaskName) { Remove-ScheduleByName -TaskName $ReplaceTaskName }
                    Write-Host "Scheduled $($types[$typeIndex]) successfully." -ForegroundColor Green
                    Write-Host "Press any key to return to the menu..." -ForegroundColor Yellow
                    [void][Console]::ReadKey($true)
                    return
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

function Abort-Flow($Schedules) {
    Write-Host ""
    if ($null -eq $Schedules -or @($Schedules).Count -eq 0) {
        Write-Host "Nothing to abort." -ForegroundColor DarkGray
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return
    }

    Write-Host "Abort options:" -ForegroundColor Yellow
    Write-Host "  [A] Abort all" -ForegroundColor White
    Write-Host "  Enter a number to abort a specific schedule" -ForegroundColor White
    $choice = Read-Host "Choice (A/number/Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($choice)) { return }

    if ($choice -match '^(?i:a)$') {
        Remove-AllSchedules
        Write-Host "Cancelled all scheduled items." -ForegroundColor Green
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return
    }

    $n = $null
    if (-not [int]::TryParse($choice, [ref]$n)) {
        Write-Host "Invalid choice." -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return
    }

    if ($n -lt 1 -or $n -gt @($Schedules).Count) {
        Write-Host "Number out of range." -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return
    }

    $target = $Schedules[$n - 1]
    Remove-ScheduleByName -TaskName $target.Name
    Write-Host "Cancelled schedule: $($target.Name)" -ForegroundColor Green
    Write-Host "Press any key to continue..." -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

function Modify-Flow($Schedules) {
    Write-Host ""
    if ($null -eq $Schedules -or @($Schedules).Count -eq 0) {
        Write-Host "Nothing to modify." -ForegroundColor DarkGray
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return
    }

    $choice = Read-Host "Enter the schedule number to modify (blank to cancel)"
    if ([string]::IsNullOrWhiteSpace($choice)) { return }
    $n = $null
    if (-not [int]::TryParse($choice, [ref]$n)) {
        Write-Host "Please enter a valid number." -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return
    }
    if ($n -lt 1 -or $n -gt @($Schedules).Count) {
        Write-Host "Number out of range." -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return
    }

    $target = $Schedules[$n - 1]
    Schedule-Wizard -ExistingSchedule $target -ReplaceTaskName $target.Name
}

function Load-SchedulesWithMessage() {
    Clear-Host
    Set-WindowTitle
    Write-Host "Detecting schedules..." -ForegroundColor Cyan
    [Console]::Out.Flush()
    try {
        Get-ScheduleEntries
    } catch {
        Write-Host ""
        Write-Host "ERROR while detecting schedules:" -ForegroundColor Red
        Write-Host "$($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Press any key to continue..." -ForegroundColor Yellow
        [void][Console]::ReadKey($true)
        return @()
    }
}

# Main UI loop (static display, no auto-refresh)
while ($true) {
    $schedules = Load-SchedulesWithMessage
    Draw-MainScreen -Schedules $schedules
    Write-Host "Choice: " -NoNewline
    [Console]::Out.Flush()
    $key = [Console]::ReadKey($true)
    Write-Host $key.KeyChar
    
    # Clear any remaining buffered keys
    while ([Console]::KeyAvailable) {
        [void][Console]::ReadKey($true)
    }
    
    switch ($key.Key) {
        ([ConsoleKey]::N) { Schedule-Wizard }
        ([ConsoleKey]::M) { Modify-Flow -Schedules $schedules }
        ([ConsoleKey]::A) { Abort-Flow -Schedules $schedules }
        ([ConsoleKey]::R) { } # Refresh - reloads on next loop
        ([ConsoleKey]::Q) { return }
        default {
            Write-Host "Unknown choice. Please enter N, M, A, R, or Q." -ForegroundColor Red
            Write-Host "Press any key to continue..." -ForegroundColor DarkGray
            [void][Console]::ReadKey($true)
        }
    }
}
