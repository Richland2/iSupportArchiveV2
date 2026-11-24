<#
.SYNOPSIS
    Sets up iSupportArchiveV2 (or iSupportArchiveV2Staging) in IIS on webapp01. Run once per environment, on the server, in PowerShell
    as Administrator. Safe to run again: it adds what's missing and keeps each connection string unless you type a
    new one.

.DESCRIPTION
    Following webapp01's pattern (EMS / EMSStaging, 1TWO1 / 1TWO1Staging):
      - folder      D:\WebApplications\iSupportArchiveV2\iSupportArchiveV2 (or ...\iSupportArchiveV2Staging)
      - app pool    iSupportArchiveV2 (or iSupportArchiveV2Staging): No Managed Code (.NET 10 runs through the ASP.NET Core module),
                    its own built-in identity, user profile loaded so sign-in tokens survive restarts, no idle
                    shutdown, recycled daily at 3 AM
      - application /iSupportArchiveV2 (or /iSupportArchiveV2Staging) under the site, Windows sign-in on, anonymous off
      - settings    on the app pool, never in the app's files (a deploy replaces those): the connection strings,
                    the scheduled-job key, and ASPNETCORE_ENVIRONMENT=Staging for staging

.EXAMPLE
    .\Setup-IIS.ps1 -Target Staging
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Staging', 'Production')][string]$Target,
    [string]$SiteName = 'Default Web Site',
    [string]$Root = 'D:\WebApplications'
)
$ErrorActionPreference = 'Stop'

# IIS's PowerShell tools only work in 64-bit PowerShell. "Windows PowerShell (x86)" is 32-bit: stop and say what to do
# (restarting in 64-bit from here can't read the keyboard, so the password prompt would hang).
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Host 'This is 32-bit PowerShell ("Windows PowerShell (x86)"), which can''t change IIS.' -ForegroundColor Yellow
    Write-Host 'Open "Windows PowerShell" (without x86) as Administrator from the Start menu, and run the same command there.'
    exit 1
}
Import-Module WebAdministration

$app = 'iSupportArchiveV2'
$name = if ($Target -eq 'Staging') { "${app}Staging" } else { $app }
$path = Join-Path $Root "$app\$name"
$apphost = 'MACHINE/WEBROOT/APPHOST'

if (-not (Test-Path "IIS:\Sites\$SiteName")) {
    throw "There's no IIS site named '$SiteName'. Sites: $((Get-ChildItem IIS:\Sites).Name -join ', '). Use -SiteName."
}
$module = Get-WebGlobalModule | Where-Object Name -eq 'AspNetCoreModuleV2'
if (-not $module) { throw "The ASP.NET Core Hosting Bundle isn't installed (no AspNetCoreModuleV2 in IIS)." }

# Folder
if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null; Write-Host "Created $path" }

# App pool
if (-not (Test-Path "IIS:\AppPools\$name")) { New-WebAppPool -Name $name | Out-Null; Write-Host "Created app pool $name" }
Set-ItemProperty "IIS:\AppPools\$name" -Name managedRuntimeVersion -Value ''
Set-ItemProperty "IIS:\AppPools\$name" -Name processModel.loadUserProfile -Value $true
# Keep the app running: a stop or recycle drops every open page's connection ("Rejoining the server..."). No idle
# shutdown (IIS's default stops it after 20 quiet minutes), and the regular recycle at 3 AM instead of every 29 hours.
Set-ItemProperty "IIS:\AppPools\$name" -Name processModel.idleTimeout -Value ([TimeSpan]::Zero)
Set-ItemProperty "IIS:\AppPools\$name" -Name recycling.periodicRestart.time -Value ([TimeSpan]::Zero)
Clear-ItemProperty "IIS:\AppPools\$name" -Name recycling.periodicRestart.schedule
Set-ItemProperty "IIS:\AppPools\$name" -Name recycling.periodicRestart.schedule -Value @{ value = '03:00:00' }

# Application
$existing = Get-WebApplication -Site $SiteName -Name $name
if (-not $existing) {
    New-WebApplication -Site $SiteName -Name $name -PhysicalPath $path -ApplicationPool $name | Out-Null
    Write-Host "Created application /$name"
}
elseif ($existing.PhysicalPath -ne $path -or $existing.applicationPool -ne $name) {
    Write-Warning "/$name already exists with folder $($existing.PhysicalPath) and app pool $($existing.applicationPool); left as it is."
}

# Windows sign-in only
Set-WebConfigurationProperty -PSPath $apphost -Location "$SiteName/$name" -Filter system.webServer/security/authentication/windowsAuthentication -Name enabled -Value $true
Set-WebConfigurationProperty -PSPath $apphost -Location "$SiteName/$name" -Filter system.webServer/security/authentication/anonymousAuthentication -Name enabled -Value $false

# App pool settings (environment variables, read by the app as configuration: "__" stands for ":")
$variables = "system.applicationHost/applicationPools/add[@name='$name']/environmentVariables"
function Get-PoolVariable([string]$variable) {
    (Get-WebConfigurationProperty -PSPath $apphost -Filter $variables -Name collection |
        Where-Object name -eq $variable).value
}
function Set-PoolVariable([string]$variable, [string]$value) {
    if ($null -ne (Get-PoolVariable $variable)) {
        Remove-WebConfigurationProperty -PSPath $apphost -Filter $variables -Name collection -AtElement @{ name = $variable }
    }
    Add-WebConfigurationProperty -PSPath $apphost -Filter $variables -Name collection -Value @{ name = $variable; value = $value }
}
function Remove-PoolVariable([string]$variable) {
    if ($null -ne (Get-PoolVariable $variable)) {
        Remove-WebConfigurationProperty -PSPath $apphost -Filter $variables -Name collection -AtElement @{ name = $variable }
    }
}

if ($Target -eq 'Staging') { Set-PoolVariable 'ASPNETCORE_ENVIRONMENT' 'Staging' } else { Remove-PoolVariable 'ASPNETCORE_ENVIRONMENT' }

$connections = [ordered]@{
    Default          = 'iSupport_Archive on sql1, the archived tickets (read only; staging uses it too)'
    IntranetSecurity = 'IntranetSecurity (the app has no roles there, but sign-in looks)'
    CommonData       = 'CommonData, which keeps students out'
}
foreach ($connection in $connections.GetEnumerator()) {
    $variable = "ConnectionStrings__$($connection.Key)"
    $current = Get-PoolVariable $variable
    $prompt = "Connection string for $($connection.Key), $($connection.Value)"
    $prompt += if ($null -ne $current) { ' (Enter keeps the current one)' } else { ' (Enter skips it)' }
    $value = Read-Host $prompt
    if ($value) { Set-PoolVariable $variable $value }
}

if ($null -eq (Get-PoolVariable 'R2__Jobs__Key')) {
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $key = [Convert]::ToBase64String($bytes).Replace('+', '-').Replace('/', '_')
    Set-PoolVariable 'R2__Jobs__Key' $key
    Write-Host "Set a new scheduled-job key. A scheduled task on this server runs a job with:"
    Write-Host "  powershell -NoProfile -Command `"Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri 'http://localhost/$name/jobs/example?key=$key'`""
}

Restart-WebAppPool -Name $name
Write-Host ""
Write-Host "$name is set up: $path, app pool $name, http://$env:COMPUTERNAME/$name"
Write-Host "Next: deploy from a developer PC with deploy\Deploy.ps1 -Target $Target"
