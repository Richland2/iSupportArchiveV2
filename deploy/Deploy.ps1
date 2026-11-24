<#
.SYNOPSIS
    Publishes iSupportArchiveV2 and copies it to webapp01, staging by default. Run from the app's folder on a developer PC.

.DESCRIPTION
    Builds a Release copy, takes the site offline for the copy (app_offline.htm, which IIS shows while it's there
    and which stops the app so its files can be replaced), mirrors the files (anything on the server that isn't
    part of the app is removed, except the logs folder), then brings it back. The server must have been set up with
    Setup-IIS.ps1 first. Production asks you to confirm.

.EXAMPLE
    .\deploy\Deploy.ps1
    .\deploy\Deploy.ps1 -Target Production
#>
[CmdletBinding()]
param(
    [ValidateSet('Staging', 'Production')][string]$Target = 'Staging',
    [string]$Server = 'webapp01',
    # where the app's folders are, as seen from this PC
    [string]$Root = "\\$Server\d$\WebApplications"
)
$ErrorActionPreference = 'Stop'

$app = 'iSupportArchiveV2'
$name = if ($Target -eq 'Staging') { "${app}Staging" } else { $app }
$destination = Join-Path $Root "$app\$name"
$project = Join-Path $PSScriptRoot "..\$app.csproj"
$output = Join-Path $PSScriptRoot "..\bin\deploy\$Target"

if (-not (Test-Path $destination)) {
    throw "$destination isn't there. Set the app up on the server first: deploy\Setup-IIS.ps1 -Target $Target (on $Server, as Administrator)."
}
if ($Target -eq 'Production') {
    $answer = Read-Host "Deploy to PRODUCTION ($destination)? Type the app name, $app, to go ahead"
    if ($answer -ne $app) { Write-Host 'Not deployed.'; return }
}

if (Test-Path $output) { Remove-Item $output -Recurse -Force }
dotnet publish $project -c Release -o $output
if ($LASTEXITCODE -ne 0) { throw 'The publish failed; nothing was copied.' }

$offline = Join-Path $destination 'app_offline.htm'
Set-Content -Path $offline -Encoding utf8 -Value '<!DOCTYPE html><html><head><title>Updating</title></head><body style="font-family:sans-serif"><h2>This site is being updated.</h2><p>Please try again in a minute.</p></body></html>'
try {
    Start-Sleep -Seconds 3   # let the app stop and release its files
    robocopy $output $destination /MIR /XF app_offline.htm /XD logs /R:10 /W:3 /NFL /NDL /NJH /NP
    if ($LASTEXITCODE -ge 8) { throw "Copying failed (robocopy code $LASTEXITCODE); the site stays offline until this is fixed and run again." }
    $global:LASTEXITCODE = 0
    Remove-Item $offline
}
catch {
    Write-Warning "The site is still showing 'being updated' ($offline)."
    throw
}
Write-Host "Deployed to ${name}: http://$Server/$name"
