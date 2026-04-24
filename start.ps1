# Trust PSGallery and ensure NuGet provider is available
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# =====================================================================
# COLLECT ALL INPUTS UPFRONT
# Tech enters everything here before imaging begins - then walks away
# =====================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  OSDCloud Imaging Setup" -ForegroundColor Cyan
Write-Host "  Enter all details before imaging begins" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# itadmin password
$itAdminPassSecure = Read-Host "Set password for itadmin account" -AsSecureString
$itAdminPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($itAdminPassSecure))

# New user Okta username
do {
    $NewUser = Read-Host "`nCustomer's Okta username (e.g. GChilla)"
    if ($NewUser -match "[@&!$*'\s]") {
        Write-Host "No domain, spaces or special characters. Use Okta username only." -ForegroundColor Yellow
    }
} while ($NewUser -match "[@&!$*'\s]")

$NewFullName = Read-Host "Customer's full name (e.g. Ghostface Chilla)"

# User password
$PassChoice = $null
while ($PassChoice -notin @('1','2')) {
    $PassChoice = Read-Host "`n1 = custom temporary password  /  2 = default password (P@ssw0rd)"
}

if ($PassChoice -eq '1') {
    $UserPassSecure = Read-Host "Temporary password for $NewUser" -AsSecureString
    $UserPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($UserPassSecure))
} else {
    $UserPass = 'P@ssw0rd'
}

# Force password reset
$ResetChoice = Read-Host "`nForce password reset on first logon? (yes/no)"
$ForceReset  = $ResetChoice -eq 'yes'
$ForceResetLine = if ($ForceReset) { "net user `"$NewUser`" /logonpasswordchg:yes" } else { '' }

Write-Host "`nAll inputs collected. Starting imaging - you can walk away." -ForegroundColor Green

# =====================================================================
# INSTALL OSD MODULE
# =====================================================================
$MaxAttempts = 5
$Attempt     = 0
while (-not (Get-Module -ListAvailable -Name OSD)) {
    $Attempt++
    Write-Host "Installing OSD module (attempt $Attempt of $MaxAttempts)..."
    Install-Module OSD -Force -SkipPublisherCheck -ErrorAction SilentlyContinue
    if ($Attempt -ge $MaxAttempts) {
        Write-Host "ERROR: OSD module failed to install after $MaxAttempts attempts." -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Seconds 5
}

Import-Module OSD -Force
Write-Host "OSD module loaded." -ForegroundColor Green

# =====================================================================
# IMAGE THE DEVICE
# =====================================================================
$Params = @{
    OSVersion  = 'Windows 11'
    OSBuild    = '24H2'
    OSEdition  = 'Enterprise'
    OSLanguage = 'en-us'
    OSLicense  = 'Volume'
    ZTI        = $true
}

Start-OSDCloud @Params

# =====================================================================
# POST-IMAGING: Write AutoCreateUser.ps1 and unattend.xml to new OS
# =====================================================================

# Write AutoCreateUser.ps1 with pre-collected user data baked in
$SetupScriptsDir = 'C:\Windows\Setup\Scripts\SetupComplete'
if (-not (Test-Path $SetupScriptsDir)) { New-Item -Path $SetupScriptsDir -ItemType Directory -Force | Out-Null }

$AutoCreateScript = @"
`$Username = '$NewUser'
`$FullName  = '$NewFullName'
`$Password  = ConvertTo-SecureString '$UserPass' -AsPlainText -Force

New-LocalUser -Name `$Username -Password `$Password -FullName `$FullName -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group Administrators -Member `$Username -ErrorAction SilentlyContinue
$ForceResetLine

# Self-delete then log off itadmin to land on login screen
Remove-Item -Path `$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
Start-Process 'logoff.exe'
"@

Set-Content -Path "$SetupScriptsDir\AutoCreateUser.ps1" -Value $AutoCreateScript -Encoding UTF8
Write-Host "AutoCreateUser.ps1 written." -ForegroundColor Green

# Write unattend.xml to skip OOBE, create itadmin, auto-logon once to trigger AutoCreateUser.ps1
$PantherPath = 'C:\Windows\Panther'
if (-not (Test-Path $PantherPath)) { New-Item -Path $PantherPath -ItemType Directory -Force | Out-Null }

$UnattendXML = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>*</ComputerName>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>3</ProtectYourPC>
                <SkipMachineOOBE>true</SkipMachineOOBE>
                <SkipUserOOBE>true</SkipUserOOBE>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Password>
                            <Value>$itAdminPass</Value>
                            <PlainText>true</PlainText>
                        </Password>
                        <DisplayName>itadmin</DisplayName>
                        <Group>Administrators</Group>
                        <Name>itadmin</Name>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <AutoLogon>
                <Password>
                    <Value>$itAdminPass</Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <LogonCount>1</LogonCount>
                <Username>itadmin</Username>
            </AutoLogon>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <CommandLine>PowerShell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Windows\Setup\Scripts\SetupComplete\AutoCreateUser.ps1"</CommandLine>
                    <Description>Create User Account</Description>
                    <Order>1</Order>
                    <RequiresUserInput>false</RequiresUserInput>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
"@

Set-Content -Path "$PantherPath\unattend.xml" -Value $UnattendXML -Encoding UTF8
Write-Host "unattend.xml written - OOBE will be skipped on first boot." -ForegroundColor Green

# =====================================================================
# COUNTDOWN RESTART
# =====================================================================
$Countdown = 30
Write-Host "`nImaging complete. Restarting in $Countdown seconds..." -ForegroundColor Green
for ($i = $Countdown; $i -gt 0; $i--) {
    Write-Host "  Restarting in $i seconds...  " -ForegroundColor Yellow -NoNewline
    Write-Host "`r" -NoNewline
    Start-Sleep -Seconds 1
}
Restart-Computer -Force
