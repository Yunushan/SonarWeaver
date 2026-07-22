# SPDX-License-Identifier: 0BSD
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('doctor', 'install', 'status', 'verify', 'version', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Target,

    [switch]$UpgradeApproved,
    [switch]$BackupVerified,

    [uri]$Url,
    [string]$MonitoringPasscodeFile,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$WindowsInstaller = Join-Path $Root 'deployments\native\windows\Install-SonarQube.ps1'
$DockerBootstrap = Join-Path $Root 'deployments\docker\Bootstrap.ps1'
$ProductionVerifier = Join-Path $Root 'deployments\Verify-Production.ps1'

function Show-SonarWeaverHelp {
    @'
SonarWeaver - multi-platform SonarQube deployment toolkit

Usage:
  .\bin\sonarweaver.ps1 doctor windows
  .\bin\sonarweaver.ps1 install windows [PowerShell options]
  .\bin\sonarweaver.ps1 install docker [evaluation|production] [Docker options]
  .\bin\sonarweaver.ps1 status windows|docker [evaluation|production]
  .\bin\sonarweaver.ps1 verify -Url https://sonarqube.example -MonitoringPasscodeFile C:\secure\monitoring-passcode
  .\bin\sonarweaver.ps1 version

Use WSL or a POSIX administration host for the RKE2/K3s installer.
'@ | Write-Output
}

switch ($Command) {
    'help' { Show-SonarWeaverHelp; return }
    'version' {
        $lockPath = Join-Path $Root 'config\versions.env'
        $values = @{}
        Get-Content -LiteralPath $lockPath | ForEach-Object {
            if ($_ -match '^(?<key>[A-Z0-9_]+)="(?<value>[^"]+)"$') {
                $values[$Matches.key] = $Matches.value
            }
        }
        Write-Output "SonarWeaver $($values.SONARWEAVER_VERSION)"
        Write-Output "Community Build $($values.SONARQUBE_COMMUNITY_VERSION); Helm chart $($values.SONARQUBE_HELM_CHART_VERSION)"
        return
    }
    'doctor' {
        if ($Target -eq 'windows') {
            & $WindowsInstaller -Evaluation -DryRun @RemainingArguments
        } elseif ($Target -eq 'docker') {
            if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
                throw 'Docker Desktop or Docker Engine is required.'
            }
            & docker info *> $null
            if ($LASTEXITCODE -ne 0) { throw 'Docker Engine is not reachable.' }
            & docker compose version *> $null
            if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 is required.' }
            Push-Location (Join-Path $Root 'deployments\docker')
            try {
                & docker compose --env-file .env.example -f compose.yaml -f compose.local.yaml config --quiet
                if ($LASTEXITCODE -ne 0) { throw 'Docker Compose validation failed.' }
            } finally {
                Pop-Location
            }
            Write-Output 'Docker checks passed.'
        } else {
            throw 'PowerShell doctor supports windows and docker. Use WSL/POSIX for RKE2 or K3s.'
        }
    }
    'install' {
        if ($Target -eq 'windows') {
            & $WindowsInstaller @RemainingArguments
        } elseif ($Target -eq 'docker') {
            $mode = 'evaluation'
            $dockerArguments = @($RemainingArguments)
            if ($dockerArguments.Count -gt 0 -and $dockerArguments[0] -in @('evaluation', 'production')) {
                $mode = $dockerArguments[0]
                if ($dockerArguments.Count -gt 1) {
                    $dockerArguments = $dockerArguments[1..($dockerArguments.Count - 1)]
                } else {
                    $dockerArguments = @()
                }
            }
            $forwardUpgradeApproved = $UpgradeApproved
            $forwardBackupVerified = $BackupVerified
            foreach ($argument in $dockerArguments) {
                switch ($argument) {
                    '-UpgradeApproved' { $forwardUpgradeApproved = $true }
                    '-BackupVerified' { $forwardBackupVerified = $true }
                    default { throw "Unsupported Docker option: $argument" }
                }
            }
            $dockerParameters = @{
                Mode = $mode
                UpgradeApproved = $forwardUpgradeApproved
                BackupVerified = $forwardBackupVerified
            }
            & $DockerBootstrap @dockerParameters
        } else {
            throw 'PowerShell install supports windows and docker. Use WSL/POSIX for RKE2 or K3s.'
        }
    }
    'status' {
        if ($Target -eq 'windows') {
            Get-ScheduledTask -TaskName 'SonarWeaver-SonarQube' | Get-ScheduledTaskInfo
        } elseif ($Target -eq 'docker') {
            $mode = if ($RemainingArguments.Count -gt 0) { $RemainingArguments[0] } else { 'evaluation' }
            if ($mode -notin @('evaluation', 'production')) {
                throw 'Docker status mode must be evaluation or production.'
            }
            if ($RemainingArguments.Count -gt 1) {
                throw 'PowerShell Docker status does not accept additional Compose arguments.'
            }
            Push-Location (Join-Path $Root 'deployments\docker')
            try {
                if ($mode -eq 'evaluation') {
                    & docker compose --env-file .env -f compose.yaml -f compose.local.yaml ps
                } else {
                    & docker compose --env-file .env -f compose.yaml ps
                }
            } finally { Pop-Location }
        } else {
            throw 'PowerShell status supports windows and docker.'
        }
    }
    'verify' {
        if (-not $Url) { throw 'PowerShell verification requires -Url https://sonarqube.example.' }
        if (-not $MonitoringPasscodeFile) { throw 'PowerShell verification requires -MonitoringPasscodeFile PATH.' }
        & $ProductionVerifier -Url $Url -MonitoringPasscodeFile $MonitoringPasscodeFile
    }
}
