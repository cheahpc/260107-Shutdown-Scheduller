# Shutdown Scheduler (Batch + PowerShell)

Double-click `StartShutdownScheduler.bat` to launch an interactive scheduler that:
- Detects scheduled actions created by this tool and shows them in an ordered table with Type, ID (task name), Run Time, and Time Until action (days/hours/minutes/seconds).
- Lets you create new schedules (Shutdown/Restart/Logoff/Sleep/Hibernate) using days/hours/minutes/seconds.
- Lets you modify an existing schedule by selecting its number from the list.
- Lets you abort all schedules or abort a specific schedule.

Notes:
- The BAT auto-elevates to admin when needed to register tasks. The window stays open so you can see messages.
- Uses Windows Scheduled Tasks under `\ShutdownScheduler` and only manages tasks it creates.
- Sleep/Hibernate depend on system power settings being enabled.

## Main Menu

Displayed info: 
- Ordered table of all detected schedules (Type, ID, Runs At, Time Until). A loading message appears while schedules are being detected, then the menu refreshes with the latest data.

Keys (press directly, no Enter):
- `N`: New schedule
- `M`: Modify an existing schedule by choosing its list number
- `A`: Abort (abort all or abort a specific schedule number)
- `R`: Refresh (re-read current schedules/status)
- `Q`: Quit

The prompt shows `Choice:` and echoes your key (e.g., `Choice: S`).

## Schedule Wizard

- When launched from `New` it starts blank. When launched from `Modify`, it preloads the selected schedule's type and remaining D/H/M/S.
- Options (press a key):
  - `T`: Change shutdown type (cycles)
  - `D`/`H`/`M`/`S`: Edit days/hours/minutes/seconds
    - Blank (Enter) resets that unit to 0
    - `c` cancels editing that unit (keeps current)
  - `C`: Create schedule (saves a new scheduled task; in Modify it replaces the chosen one)
  - `Esc`: Cancel and return to main menu

On create:
- Shows `Creating Schedule...` then `Scheduled <Type> successfully.`
- Prompts: `Press any key to return to the menu...`

## Abort Flow

- Choose `A` on the main menu.
- Enter `A` to abort all schedules, or enter a specific list number to abort that one schedule. Press Enter to cancel.
- Messages use "Press any key to continue..." where applicable.

## Troubleshooting

- If schedule creation fails with permissions, run the BAT as Administrator.
- If Sleep/Hibernate do nothing, enable those power states in Windows settings/firmware.
