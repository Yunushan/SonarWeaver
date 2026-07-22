# SPDX-License-Identifier: 0BSD
#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    '',
    Justification = 'The test temporarily defines a Docker command mock and restores prior state.'
)]
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'deployments\native\windows\Install-SonarQube.ps1'
$content = Get-Content -LiteralPath $installer -Raw
$dockerBootstrap = Join-Path $root 'deployments\docker\Bootstrap.ps1'
$dockerContent = Get-Content -LiteralPath $dockerBootstrap -Raw
$wrapper = Join-Path $root 'bin\sonarweaver.ps1'
$wrapperContent = Get-Content -LiteralPath $wrapper -Raw
$productionVerifier = Join-Path $root 'deployments\Verify-Production.ps1'
$verifierContent = Get-Content -LiteralPath $productionVerifier -Raw

$requiredControls = @(
    '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12',
    "[ValidatePattern('^[A-Fa-f0-9]{64}$')]",
    "`$SigningKey = '679F1EE92B19609DE816FDE81DB198F93525EC1A'",
    'Get-FileHash -LiteralPath $Archive -Algorithm SHA256',
    '& $gpg.Source --batch --homedir $gpgHome --verify $Signature $Archive',
    "New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\LOCAL SERVICE'",
    'Copy-Item -LiteralPath $JdbcPasswordFile -Destination $passwordTarget -Force',
    '& icacls.exe $passwordTarget /inheritance:r'
)

foreach ($control in $requiredControls) {
    if (-not $content.Contains($control)) {
        throw "Windows installer is missing required security control: $control"
    }
}

$requiredDockerControls = @(
    '[switch]$UpgradeApproved',
    '[switch]$BackupVerified',
    '& docker compose --env-file .env -f compose.yaml ps -q sonarqube',
    '& docker inspect --format ''{{.Config.Image}}'' $runningContainer',
    'Complete the approved upgrade runbook and restore verification',
    '& icacls.exe $Path /inheritance:r'
)

foreach ($control in $requiredDockerControls) {
    if (-not $dockerContent.Contains($control)) {
        throw "Windows Docker bootstrap is missing required security control: $control"
    }
}

foreach ($control in (
    "if (`$Url.Scheme -ne 'https')",
    "'X-Sonar-Passcode' = `$passcode",
    'Invoke-RestMethod -Uri "$baseUrl/api/system/status"',
    'Invoke-WebRequest -Uri "$baseUrl/api/monitoring/metrics"'
)) {
    if (-not $verifierContent.Contains($control)) {
        throw "PowerShell production verifier is missing required security control: $control"
    }
}

if (-not $wrapperContent.Contains('& $DockerBootstrap @dockerParameters')) {
    throw 'Windows command wrapper must forward Docker production safety options.'
}
foreach ($control in ('[switch]$UpgradeApproved', '[switch]$BackupVerified', "'-UpgradeApproved' { `$forwardUpgradeApproved = `$true }", "'-BackupVerified' { `$forwardBackupVerified = `$true }")) {
    if (-not $wrapperContent.Contains($control)) {
        throw "Windows command wrapper is missing Docker safety option forwarding: $control"
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("sonarweaver-wrapper-test-{0}" -f [guid]::NewGuid())
try {
    $testBin = Join-Path $testRoot 'bin'
    $testDocker = Join-Path $testRoot 'deployments\docker'
    New-Item -ItemType Directory -Path $testBin, $testDocker -Force | Out-Null
    Copy-Item -LiteralPath $wrapper -Destination (Join-Path $testBin 'sonarweaver.ps1')
    @'
param(
    [string]$Mode,
    [switch]$UpgradeApproved,
    [switch]$BackupVerified,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$UnexpectedArguments
)
Write-Output "$Mode|$UpgradeApproved|$BackupVerified|$($UnexpectedArguments -join ',')"
'@ | Set-Content -LiteralPath (Join-Path $testDocker 'Bootstrap.ps1') -Encoding ASCII
    @'
param(
    [uri]$Url,
    [string]$MonitoringPasscodeFile
)
Write-Output "$Url|$MonitoringPasscodeFile"
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'deployments\Verify-Production.ps1') -Encoding ASCII

    $forwarded = & (Join-Path $testBin 'sonarweaver.ps1') install docker production -UpgradeApproved -BackupVerified
    if ($forwarded -notcontains 'production|True|True|') {
        throw "Windows command wrapper did not forward Docker safety options: $forwarded"
    }

    $verification = & (Join-Path $testBin 'sonarweaver.ps1') verify `
        -Url 'https://sonarqube.example' -MonitoringPasscodeFile 'C:\secure\monitoring-passcode'
    if ($verification -notcontains 'https://sonarqube.example/|C:\secure\monitoring-passcode') {
        throw "Windows command wrapper did not forward production verification inputs: $verification"
    }

    $previousDockerFunction = Get-Item -Path Function:\global:docker -ErrorAction SilentlyContinue
    try {
        function global:docker {
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$DockerArguments
            )
            $global:sonarweaverDockerStatusCall = $DockerArguments -join ' '
        }

        $global:sonarweaverDockerStatusCall = ''
        $null = & (Join-Path $testBin 'sonarweaver.ps1') status docker production
        if ($global:sonarweaverDockerStatusCall -ne 'compose --env-file .env -f compose.yaml ps') {
            throw "Windows production Docker status used the wrong Compose model: $global:sonarweaverDockerStatusCall"
        }

        $global:sonarweaverDockerStatusCall = ''
        $null = & (Join-Path $testBin 'sonarweaver.ps1') status docker evaluation
        if ($global:sonarweaverDockerStatusCall -ne 'compose --env-file .env -f compose.yaml -f compose.local.yaml ps') {
            throw "Windows evaluation Docker status used the wrong Compose model: $global:sonarweaverDockerStatusCall"
        }
    } finally {
        if ($previousDockerFunction) {
            Set-Item -Path Function:\global:docker -Value $previousDockerFunction.ScriptBlock
        } else {
            Remove-Item -Path Function:\global:docker -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name sonarweaverDockerStatusCall -Scope Global -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Windows deployment security invariants passed.'
