# SPDX-License-Identifier: 0BSD
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('evaluation', 'production')]
    [string]$Mode = 'evaluation',
    [switch]$UpgradeApproved,
    [switch]$BackupVerified
)

$ErrorActionPreference = 'Stop'
$ScriptDirectory = $PSScriptRoot

function Set-DockerSecretAcl {
    param([string]$Path)

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $Path /inheritance:r /grant:r `
        "*$currentSid`:(R)" `
        '*S-1-5-18:(F)' `
        '*S-1-5-32-544:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not secure the Docker JDBC password file.' }
}

function Confirm-ProductionUpgrade {
    $envContent = Get-Content -LiteralPath '.env' -Raw
    $desiredMatch = [regex]::Match($envContent, '(?m)^SONARQUBE_IMAGE=([^\r\n]+)$')
    if (-not $desiredMatch.Success) { throw 'SONARQUBE_IMAGE is missing from deployments/docker/.env.' }
    $desiredImage = $desiredMatch.Groups[1].Value

    $runningContainer = [string](& docker compose --env-file .env -f compose.yaml ps -q sonarqube 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine whether SonarQube is already running.' }
    if (-not $runningContainer) { return }

    $runningImage = [string](& docker inspect --format '{{.Config.Image}}' $runningContainer 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $runningImage) {
        throw 'Could not determine the running SonarQube image; inspect it before an upgrade.'
    }

    if ($runningImage -ne $desiredImage) {
        if (-not ($UpgradeApproved -and $BackupVerified)) {
            throw 'The requested image differs from the running SonarQube image. Complete the approved upgrade runbook and restore verification, then re-run with -UpgradeApproved -BackupVerified.'
        }
        Write-Output '[sonarweaver] Upgrade acknowledgement accepted for the changed SonarQube image.'
    }
}

Push-Location $ScriptDirectory
try {
    if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
        throw 'Docker Desktop or Docker Engine is required.'
    }
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Engine is not reachable.' }
    & docker compose version *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 is required.' }

    if (-not (Test-Path -LiteralPath '.env')) {
        Copy-Item -LiteralPath '.env.example' -Destination '.env'
        Write-Output 'Created deployments/docker/.env from the example.'
    }
    New-Item -ItemType Directory -Path 'secrets' -Force | Out-Null
    $secretPath = Join-Path $ScriptDirectory 'secrets\jdbc_password'
    if (-not (Test-Path -LiteralPath $secretPath) -or (Get-Item -LiteralPath $secretPath).Length -eq 0) {
        $bytes = New-Object byte[] 36
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        [IO.File]::WriteAllText($secretPath, [Convert]::ToBase64String($bytes), [Text.Encoding]::ASCII)
        Write-Output 'Created a random database password in deployments/docker/secrets/.'
    }
    $secretBytes = [IO.File]::ReadAllBytes($secretPath)
    if ($secretBytes -contains 10 -or $secretBytes -contains 13) {
        throw 'secrets/jdbc_password must not contain line endings; create it without a trailing newline.'
    }
    Set-DockerSecretAcl -Path $secretPath

    if ($Mode -eq 'production') {
        if ((Get-Content -LiteralPath '.env' -Raw) -match 'postgresql\.example\.invalid') {
            throw 'Set the external SONAR_JDBC_URL in deployments/docker/.env first.'
        }
        Confirm-ProductionUpgrade
        & docker compose --env-file .env -f compose.yaml config --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Docker Compose validation failed.' }
        & docker compose --env-file .env -f compose.yaml up -d
    } else {
        & docker compose --env-file .env -f compose.yaml -f compose.local.yaml config --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Docker Compose validation failed.' }
        & docker compose --env-file .env -f compose.yaml -f compose.local.yaml up -d
    }
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose startup failed.' }
    Write-Output 'SonarQube is starting. Open http://127.0.0.1:9000 and immediately change admin/admin.'
} finally {
    Pop-Location
}
