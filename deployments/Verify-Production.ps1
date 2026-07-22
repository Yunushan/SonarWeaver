# SPDX-License-Identifier: 0BSD
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [uri]$Url,
    [Parameter(Mandatory = $true)]
    [string]$MonitoringPasscodeFile
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($Url.Scheme -ne 'https') { throw 'Production verification requires an https:// URL.' }
if (-not (Test-Path -LiteralPath $MonitoringPasscodeFile -PathType Leaf)) {
    throw "Monitoring passcode file does not exist: $MonitoringPasscodeFile"
}

$passcode = [IO.File]::ReadAllText($MonitoringPasscodeFile)
if ([string]::IsNullOrEmpty($passcode)) { throw 'Monitoring passcode file is empty.' }
if ($passcode.Contains("`r") -or $passcode.Contains("`n")) {
    throw 'Monitoring passcode must not contain line endings; create it without a trailing newline.'
}

$baseUrl = $Url.AbsoluteUri.TrimEnd('/')
$headers = @{ 'X-Sonar-Passcode' = $passcode }
$status = Invoke-RestMethod -Uri "$baseUrl/api/system/status" -Method Get -TimeoutSec 30
if ($status.status -ne 'UP') { throw "SonarQube system status is not UP: $($status.status)" }

$metrics = Invoke-WebRequest -Uri "$baseUrl/api/monitoring/metrics" -Method Get `
    -Headers $headers -TimeoutSec 30 -UseBasicParsing
if ([string]::IsNullOrWhiteSpace($metrics.Content)) {
    throw 'Monitoring endpoint returned an empty response.'
}

Write-Output 'Production HTTPS, health, and monitoring checks passed.'
