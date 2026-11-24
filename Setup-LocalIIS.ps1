<#
.SYNOPSIS
    Once per PC: sets up iSupportArchiveV2 in your PC's IIS at http://localhost:88/iSupportArchiveV2, like the other apps. Run it from
    this folder in PowerShell as Administrator. Safe to run again: it adds what's missing and keeps the saved
    connections unless you type the password again.

.DESCRIPTION
    - app pool    iSupportArchiveV2: No Managed Code (.NET 10 runs through the ASP.NET Core module), its own built-in identity,
                  no idle shutdown or timed recycle
    - application /iSupportArchiveV2 under the site on port 88, running from bin\LocalIIS (each Debug build publishes the app
                  there), Windows sign-in on, anonymous off
    - folders     the app pool may read bin\LocalIIS and write obj\IISShadowCopy (where IIS runs a copy of the app,
                  so building isn't blocked by locked files)
    - connections on the app pool, never in the app's files, all as WebAppsUser like on the servers:
                  Default -> iSupport_Archive on sql1 (read only), IntranetSecurity on devdb1, CommonData on sql1

    Needs the .NET 10 Hosting Bundle installed on this PC (it adds the ASP.NET Core module to IIS).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Setup-LocalIIS.ps1
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [int]$Port = 88,
    [string]$Login = 'WebAppsUser',
    [Security.SecureString]$Password
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
$project = Join-Path $PSScriptRoot "$app.csproj"
$path = Join-Path $PSScriptRoot 'bin\LocalIIS'
$shadow = Join-Path $PSScriptRoot 'obj\IISShadowCopy'
$apphost = 'MACHINE/WEBROOT/APPHOST'

# The site on port 88
$site = Get-Website | Where-Object { $_.bindings.Collection | Where-Object { $_.protocol -eq 'http' -and $_.bindingInformation -match ":$Port`:" } } | Select-Object -First 1
if (-not $site) { throw "No IIS site has an http binding on port $Port. Sites: $((Get-Website).Name -join ', '). Use -Port." }
$module = Get-WebGlobalModule | Where-Object Name -eq 'AspNetCoreModuleV2'
if (-not $module) {
    throw "The .NET 10 Hosting Bundle isn't installed (no AspNetCoreModuleV2 in IIS). Install it from https://dotnet.microsoft.com/download/dotnet/10.0 (ASP.NET Core Runtime > Hosting Bundle), then run this again."
}

# A first build, so IIS has something to run
if (-not (Test-Path (Join-Path $path "$app.dll"))) {
    Write-Host 'Building the app (Debug) into bin\LocalIIS...'
    dotnet build $project -c Debug --nologo -v q
    if ($LASTEXITCODE -ne 0) { throw 'The build failed; fix it and run this again.' }
}
New-Item -ItemType Directory -Force -Path $shadow | Out-Null

# App pool
if (-not (Test-Path "IIS:\AppPools\$app")) { New-WebAppPool -Name $app | Out-Null; Write-Host "Created app pool $app" }
Set-ItemProperty "IIS:\AppPools\$app" -Name managedRuntimeVersion -Value ''
Set-ItemProperty "IIS:\AppPools\$app" -Name processModel.loadUserProfile -Value $true
# Keep the app running (a stop drops open pages' connections): no idle shutdown, no timed recycle
Set-ItemProperty "IIS:\AppPools\$app" -Name processModel.idleTimeout -Value ([TimeSpan]::Zero)
Set-ItemProperty "IIS:\AppPools\$app" -Name recycling.periodicRestart.time -Value ([TimeSpan]::Zero)

# Application
$existing = Get-WebApplication -Site $site.Name -Name $app
if (-not $existing) {
    New-WebApplication -Site $site.Name -Name $app -PhysicalPath $path -ApplicationPool $app | Out-Null
    Write-Host "Created application /$app in '$($site.Name)'"
}
elseif ($existing.PhysicalPath -ne $path -or $existing.applicationPool -ne $app) {
    Set-ItemProperty "IIS:\Sites\$($site.Name)\$app" -Name physicalPath -Value $path
    Set-ItemProperty "IIS:\Sites\$($site.Name)\$app" -Name applicationPool -Value $app
    Write-Host "Pointed /$app at $path, app pool $app"
}

# Windows sign-in only
Set-WebConfigurationProperty -PSPath $apphost -Location "$($site.Name)/$app" -Filter system.webServer/security/authentication/windowsAuthentication -Name enabled -Value $true
Set-WebConfigurationProperty -PSPath $apphost -Location "$($site.Name)/$app" -Filter system.webServer/security/authentication/anonymousAuthentication -Name enabled -Value $false

# Folder permissions for the app pool's identity
$identity = "IIS AppPool\$app"
icacls $PSScriptRoot /grant "${identity}:(OI)(CI)RX" /C /Q | Out-Null
icacls $shadow /grant "${identity}:(OI)(CI)M" /C /Q | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Couldn't give $identity access to $shadow." }

# Connections, as app pool environment variables (read by the app as configuration: "__" stands for ":")
$variables = "system.applicationHost/applicationPools/add[@name='$app']/environmentVariables"
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

$saved = $null -ne (Get-PoolVariable 'ConnectionStrings__Default')
if (-not $Password) {
    $prompt = "$Login password (it will not show)"
    if ($saved) { $prompt += '; Enter keeps the saved connections' }
    $Password = Read-Host $prompt -AsSecureString
}
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }

if ($plain) {
    function New-ConnectionString([string]$server, [string]$database) {
        # the builder quotes the password properly, whatever characters it has
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
        $builder['Data Source'] = $server
        $builder['Initial Catalog'] = $database
        $builder['User ID'] = $Login
        $builder['Password'] = $plain
        $builder.ToString() + ';TrustServerCertificate=true'
    }
    # the archive itself: there's no staging copy, and the app only ever reads it
    Set-PoolVariable 'ConnectionStrings__Default' (New-ConnectionString 'sql1' 'iSupport_Archive')
    Set-PoolVariable 'ConnectionStrings__IntranetSecurity' (New-ConnectionString 'devdb1' 'IntranetSecurity')
    Set-PoolVariable 'ConnectionStrings__CommonData' (New-ConnectionString 'sql1' 'CommonData')
    Write-Host "Saved the Default, IntranetSecurity and CommonData connections ($Login) on the app pool."
}
elseif (-not $saved) {
    Write-Warning "No password given, so no connections were saved: the app can't reach its databases. Run this again to add them."
}

Restart-WebAppPool -Name $app
Write-Host ""
Write-Host "$app is set up: http://localhost:$Port/$app" -ForegroundColor Green
Write-Host "Build in Visual Studio (or dotnet build), then refresh the page."
