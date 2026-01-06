# Shutdown Scheduler (Batch + PowerShell)

Double-click `StartShutdownScheduler.bat` to launch an interactive menu that:
- Shows detected scheduled actions created by this tool (type and run time)
- Lets you schedule a shutdown/restart/logoff/sleep/hibernate after days/hours/minutes/seconds
- Lets you cancel all scheduled actions created by this tool

Notes:
- The BAT auto-elevates to admin when needed to create tasks.
- This tool uses Windows Scheduled Tasks under the folder `\ShutdownScheduler`. It detects and manages tasks it created.
- Sleep/Hibernate availability depends on your system power settings.

## Usage
1. Double-click `StartShutdownScheduler.bat` (it will prompt for admin if required).
2. Press `S` to schedule. In the wizard:
   - If a schedule exists, it will be loaded for modification.
   - Use `D/H/M/S` to edit units (blank/Enter=reset to 0, type 'c' to cancel and keep current value).
   - Press `T` to cycle through shutdown types.
   - Press `C` to create the schedule (replaces any existing schedule).
   - Press `Esc` to cancel and return to main menu.
3. Press `A` (on the main menu) to abort/remove all scheduled items created by this tool.
4. Press `Q` to quit the UI.
