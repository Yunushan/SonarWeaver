# SPDX-License-Identifier: 0BSD
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('evaluation', 'production')]
    [string]$Mode = 'evaluation'
)

$ErrorActionPreference = 'Stop'
$ScriptDirectory = $PSScriptRoot
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

    if ($Mode -eq 'production') {
        if ((Get-Content -LiteralPath '.env' -Raw) -match 'postgresql\.example\.invalid') {
            throw 'Set the external SONAR_JDBC_URL in deployments/docker/.env first.'
        }
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
