# Trust PSGallery and ensure NuGet provider is available
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install OSD module with retry loop
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

$Params = @{
    OSVersion  = 'Windows 11'
    OSBuild    = '24H2'
    OSEdition  = 'Enterprise'
    OSLanguage = 'en-us'
    OSLicense  = 'Volume'
    ZTI        = $true
}

Start-OSDCloud @Params

# Countdown restart
$Countdown = 30
Write-Host "`nImaging complete. Restarting in $Countdown seconds..." -ForegroundColor Green
for ($i = $Countdown; $i -gt 0; $i--) {
    Write-Host "  Restarting in $i seconds...  " -ForegroundColor Yellow -NoNewline
    Write-Host "`r" -NoNewline
    Start-Sleep -Seconds 1
}
Restart-Computer -Force
