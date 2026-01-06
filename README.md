# Shutdown Scheduler (Batch + PowerShell)

Double-click `StartShutdownScheduler.bat` to launch an interactive scheduler that:
- Detects scheduled actions created by this tool and shows: Type, ID (task name), Run Time, and Time Until action (days/hours/minutes/seconds).
- Lets you schedule Shutdown/Restart/Logoff/Sleep/Hibernate using days/hours/minutes/seconds.
- Lets you abort existing schedules made by this tool.

Notes:
- The BAT auto-elevates to admin when needed to register tasks. The window stays open so you can see messages.
- Uses Windows Scheduled Tasks under `\ShutdownScheduler` and only manages tasks it creates.
- Sleep/Hibernate depend on system power settings being enabled.

## Main Menu
Displayed info (when a schedule exists):
- Scheduled Action, ID, Runs At, and Time Until action.

Keys (press directly, no Enter):
- `S`: Schedule (open wizard)
- `A`: Abort (remove all schedules created by this tool)
- `R`: Refresh (re-read current schedule/status)
- `Q`: Quit

The prompt shows `Choice:` and echoes your key (e.g., `Choice: S`).

## Schedule Wizard
- If a schedule exists, its values load for modification (type and remaining D/H/M/S).
- Options (press a key):
   - `T`: Change shutdown type (cycles)
   - `D`/`H`/`M`/`S`: Edit days/hours/minutes/seconds
      - Blank (Enter) resets that unit to 0
      - `c` cancels editing that unit (keeps current)
   - `C`: Create schedule (replaces any existing schedule)
   - `Esc`: Cancel and return to main menu

On create:
- Shows `Creating Schedule...` then `Scheduled <Type> successfully.`
- Then: `Press any key to modify schedule, or wait 5 seconds to return to main menu...`
   - Press any key: stays in the wizard, reloads current schedule values
   - Wait 5 seconds: returns to main menu

## Abort Flow
- Lists each task as `ID: <TaskName>` and asks: `Abort schedule? (Y/N)`
- Press `Y` to delete all tasks created by this tool; any other key cancels.
- Messages use "Press any key to continue..." where applicable.

## Troubleshooting
- If schedule creation fails with permissions, run the BAT as Administrator.
- If Sleep/Hibernate do nothing, enable those power states in Windows settings/firmware.
