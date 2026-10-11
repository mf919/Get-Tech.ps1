# Get-Tech.ps1
v1.0.1 release - (C) 2026 Mike Frazier - MIT License

Simple automation of essential Windows and Lenovo/HP/Dell updates on refurbished devices.

## Usecases:
Updating a gold image on a baremetal system before cloning to a fleet of the same model, or easing the updating process for a large quantities of unsimilar devices.

## Before you begin:

- Connect AC adapter & Ethernet
- Install battery (for best results, charged to >25% capacity)
- Install Windows 11
- For Dell devices, install Dell Command | Update Windows Universal Application
- Check wifi access point is on and reachable
- Set wifi credentials in the ADD THE WIFI portion of the script
- Place .bat launcher and customized script in C:\Users\Public\Downloads\Get-Tech\

## Usage
- Double-click Launcher.bat, accept the UAC prompt
- Continue working on a different device/project while the script works (approx. 10-20 runtime)

## Post-run procedure:
- Confirm updates were completed by checking the Get-Tech task was automatically deleted in Task Scheduler
- Run updates manually once from Settings and LCV/DCU/HPSA to allow the Settings app to update its cache and for Windows to attach the last round of drivers
- Restart and apply updates (Win + X, U, A)
- Use Device Manager to ensure drivers were assigned
- For gold images, run image integrity tools on the source host before capturing to reduce downstream corruption

## TODO
- Rewrite Readme.md
- Add automatic sleep and apply-and-restart
- More testing
