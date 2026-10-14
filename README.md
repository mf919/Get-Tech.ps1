# Get-Tech.ps1

![Version](https://img.shields.io/badge/release-v1.0.1-blue) [![License: MIT](https://img.shields.io/badge/license-MIT-green)](#license)
 
© 2026 Mike Frazier

Simple automation of essential Windows and Lenovo/HP/Dell updates on refurbished devices.

## Usecases

Updating a gold image on a bare-metal system before cloning to a fleet of the same model, or easing the updating process for large quantities of unsimilar devices.

## Before you begin

- Connect an AC adapter with the device's listed wattage
- Connect Ethernet, directly or through an adapter (USB-C recommended)
- For laptops, install a battery (for best results, charged to >25% capacity)
- Install Windows 11
- For Dell devices, install Dell Command | Update Windows Universal Application
- Check WiFi access point is on and reachable

## Usage

1. Set WiFi credentials in the `ADD THE WIFI` portion of the script
2. Place `.bat` launcher and customized script in `C:\Users\Public\Downloads\Get-Tech\`
3. Double-click `Launcher.bat`, accept the UAC prompt.
4. Continue working on a different device/project while the script works (approx. 10-20m runtime).

> [!NOTE]
> For new users: Launcher is only included for convenience, use your preferred launch method. It only needs to run as admin in PowerShell 5.1 or newer.

Once you're confident in the consistency of its output, you can disable the verbose logging by commenting out the `$VerbosePreference` line.

## Post-run procedure

1. Confirm the Get-Tech task was automatically deleted in Task Scheduler (if present but not running, reboot and let it finish)
2. Run updates manually once from Settings and LCV/DCU/HPSA to allow the Settings app to update its cache and for Windows to attach the last round of drivers
3. Restart and apply updates (<kbd>Win</kbd> + <kbd>X</kbd>, <kbd>U</kbd>, <kbd>A</kbd>)
4. Use Device Manager to ensure drivers were properly assigned by Windows
5. For gold images, run image integrity tools on the source host before capturing to reduce downstream corruption

## Known issues

- There's no integrity or availability check for `wuauserv.exe` before running PSWU. If it's unavailable, it will just fail. If I can find an efficient way to add this in the future, I will.
- PowerShell modules can fail if they encounter malformed update information. This is beyond my control and typically remedied by the reboot-and-update cycle built into the script.

## License

Get-Tech.ps1 a generic MIT license. Launcher.bat is public domain.

## TO-DO

- Add automatic sleep and apply-and-restart
- More testing
