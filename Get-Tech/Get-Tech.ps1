#Requires -RunAsAdministrator

# Get-Tech.ps1 - v1.0.1 release - (C) 2026 Mike Frazier - MIT License
#
# Description: Simple automation of essential Windows and Lenovo/HP/Dell updates on refurbished devices.
# Usecases: Updating a gold image on a baremetal system before cloning to a fleet of the same model, or  easing the updating process for a large quantities of unsimilar devices.
#
# Before you begin:
# Connect AC adapter & ethernet
# Install battery (for best results, charged to >25% capacity)
# Install Windows 11
# For Dell devices, install Dell Command | Update Windows Universal Application
# Check wifi acccess point is on and reachable
# Set wifi credentials in the ADD THE WIFI portion of the script
# Place .bat launcher and customized script in C:\Users\Public\Downloads\Get-Tech\
#
# Post-run procedure:
# Confirm updates were completed by looking for the Get-Tech task in Task Scheduler
# Run updates manually once from Settings and LCV/DCU/HPSA to allow the Settings app to update its cache and for Windows to attach the last round of drivers
# Restart and apply updates (Win + X, U, A)
# Use Device Manager to ensure drivers were assigned
# For gold images, run image integrity tools on the source host before capturing to reduce downstream corruption


# Determine current phase by counting this script's logs:
$logDir = "C:\Users\Public\Downloads\Get-Tech\logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$phase = @(Get-ChildItem -Path $logDir -Filter "script-log-*.txt" -File -ErrorAction SilentlyContinue).Count

# If the expected schtask unregister fails during phase 3, purge schtask & clear modified settings, then force stop
if ($phase -eq 4) { 
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsExpedited /t REG_DWORD /d 0 /f # Turn off Get Me Up To Date
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    powercfg /change standby-timeout-ac 10  # Set sleep timeout when plugged in
    powercfg /change monitor-timeout-ac 10  # Set display timeout when plugged in
    powercfg /change standby-timeout-dc 5   # Set sleep timeout on battery
    powercfg /change monitor-timeout-dc 5   # Set display timeout on battery
    exit }

# Prevent sleep from interrupting updates
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-dc 0



### ADD THE WIFI ###

if ($phase -eq 0) {
# Set the SSID and PW for your network
$profilefile="Guest_Wifi.xml"
$SSID="Guest Wifi"
$PW="guestwifipassword"

# Convert SSID to raw Hex for the WLANProfile
$SSIDHEX=($SSID.ToCharArray() |foreach-object {'{0:X}' -f ([int]$_)}) -join''

# Create the WiFi profile XML
$xmlfile="<?xml version=""1.0""?>
<WLANProfile xmlns=""http://www.microsoft.com/networking/WLAN/profile/v1"">
    <name>$SSID</name>
    <SSIDConfig>
        <SSID>
            <hex>$SSIDHEX</hex>
            <name>$SSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$PW</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"
# Generate the file then pass it to NetSH
$XMLFILE > ($profilefile)
netsh wlan add profile filename="$($profilefile)"
netsh wlan show profiles $SSID key=clear
netsh wlan connect name=$SSID }

# Start logging
Start-Transcript -Path "$logDir\script-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

# Set all other commands to verbose
$VerbosePreference = "Continue"

# Schedule a startup task as system so it can run without logon
$taskName = "Get-Tech"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null }



### DETECT MANUFACTURER ###
# Reads the baseboard manufacturer field with a regex then declares $vendor based on the contents
$vendor = switch -Regex ((Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer) {
    "Dell"       { "DELL" }
    "HP|Hewlett" { "HP" }
    "Lenovo"     { "LENOVO" }
    default      { "Unknown" } }



### KICK THE STACK ###

if ($phase -eq 0) {
# Rebuild the Windows Time Service registration
net start w32time  # Start service
Start-Sleep 3      # Wait 3 secs to avoid errors
net stop w32time   # Stop service
w32tm /unregister  # Unregister
w32tm /register    # Re-register
net start w32time  # Start service

# Make service stack components automatic (in case they aren't) and align them
Set-Service -Name w32time -StartupType Automatic       # Windows Time Service
Set-Service -Name wuauserv -StartupType Automatic      # Windows Update Automatic Updating service
Set-Service -Name cryptSvc -StartupType Automatic      # Cryptographic Service
Set-Service -Name BITS -StartupType Automatic          # Background Intelligent Transfer Service
Set-Service -Name TrustedInstaller -StartupType Manual 

# Set Windows Update's "Get Me Up to Date" setting
# In theory, if an unexpected hang happens when installing updates, windows will automatically reboot to apply updates, continuing our process
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsExpedited /t REG_DWORD /d 1 /f }

# Wake up Windows Update Service Stack by using W32Time to sync with NTP, with a slight wait to prevent errors
# W32Time only completes the desired sync if run twice
do { Start-Sleep -Seconds 3
     w32tm /resync /force } until ($LASTEXITCODE -eq 0)
do { Start-Sleep -Seconds 3
     w32tm /resync /force } until ($LASTEXITCODE -eq 0)

# Pause until DNS can find Windows Update
# If this hangs indefinitely despite good connections and DNS being up, reimage
do { Start-Sleep -Seconds 5 } until (Resolve-DNSname -Name "download.windowsupdate.com" -ErrorAction Continue) #Find Windows Update
do { Start-Sleep -Seconds 5 } until (Resolve-DNSname -Name "cdn.powershellgallery.com" -ErrorAction Continue)  #Find PowerShell Gallery

# In the event of a broken PSWindowsUpdate installation, this will get the majority of our drivers
usoclient /scaninstallwait



### INSTALL MISSING TRUSTS & SOFTWARE ###

if ($phase -eq 0) {
# Trust PSGallery and update NuGet and PowerShellGet
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false 
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

# Install PSWU if it's not already installed
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers }

# For Dell, checks DCU-CLI is preinstalled because even silent installation is slow
    if ($vendor -like "DELL" -and -not (Test-Path "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe")) {
    winget install Dell.CommandUpdate.Universal --silent --accept-source-agreements --accept-package-agreements }

# For HP, install Image Assistant
    if ($vendor -like "HP") {
    winget install hp.imageassistant }

# For Lenovo, install LSUClient
    if ($vendor -like "LENOVO" -and -not (Get-Module -ListAvailable -Name LSUClient)) {
    Install-Module -Name LSUClient -Force -Confirm:$false -Scope AllUsers } }



### FIRMWARE ###

# Select vendor-specific updater and ArgList based on baseboard vendor
function Invoke-FirmwareUpdate { switch ($vendor) {

    "DELL"    { Start-Process -FilePath "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe" `
               -ArgumentList "/applyupdates -updatetype=bios,firmware,driver,application -reboot=disable -autoSuspendBitLocker=enable" `
               -Wait
                break }

    "HP"      { Start-Process -FilePath "C:\SWSetup\HPImageAssistant\HPImageAssistant.exe" `
               -ArgumentList "/Operation:Analyze /Action:Install /Category:All,Accessories /Selection:All /Silent" `
               -Wait
                break }
                   
    "LENOVO"  { Import-Module LSUClient
               $updates = Get-LSUpdate | Where-Object { $_.Installer.Unattended }
               $updates | Save-LSUpdate
               $updates | Install-LSUpdate
                break }

    "Unknown" { Write-Verbose "Unsupported vendor - skipping."
                break }
                    
     # If you get the Unexpected Error while working in controlled environments, you may need to reimage, flash bios, both, or recycle the device.
     default   { Write-Verbose "Unexpected Error - skipping." } } }

# Bust $profilefile ghost if it exists - fails with a benign error if it doesn't
# For some reason this became necessary during testing, and only consistently worked in this exact step in the process
if ($phase -eq 0) { Remove-Item -Path "C:\Users\Public\Downloads\Get-Tech\$profilefile" -Force }



### Update Routine ###

## Run updates for the current phase, then reboot and continue
Import-Module PSWindowsUpdate -Force

# Get updates, 
switch ($phase) {
    0 { Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -NotTitle KB -IgnoreReboot               # Drivers only, no OS updates
        Invoke-FirmwareUpdate                                                                           # Vendor-served drivers and firmware updates
        Invoke-FirmwareUpdate }
    1 { Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -NotTitle KB -IgnoreReboot
        Invoke-FirmwareUpdate
        Invoke-FirmwareUpdate }
    2 { Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -NotTitle KB -IgnoreReboot
        Invoke-FirmwareUpdate
        Invoke-FirmwareUpdate }
    3 { Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -NotTitle Preview -IgnoreReboot          # OS Updates, excluding Previews
        Invoke-FirmwareUpdate
        Invoke-FirmwareUpdate
        reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsExpedited /t REG_DWORD /d 0 /f # Turn off Get Me Up To Date
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } }  # Remove Scheduled Task

# All-phase reset-and-stop routine, uses typical windows power settings
powercfg /change standby-timeout-ac 10
powercfg /change monitor-timeout-ac 10
powercfg /change standby-timeout-dc 5
powercfg /change monitor-timeout-dc 5
Stop-Transcript
shutdown /f /r /t 0
