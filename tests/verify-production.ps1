# SPDX-License-Identifier: 0BSD
#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    '',
    Justification = 'The test temporarily shadows HTTP cmdlets and removes the mocks in finally.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidOverwritingBuiltInCmdlets',
    '',
    Justification = 'The test temporarily shadows HTTP cmdlets and removes the mocks in finally.'
)]
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $root 'deployments\Verify-Production.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("sonarweaver-verify-test-{0}" -f [guid]::NewGuid())
$passcodeFile = Join-Path $testRoot 'monitoring-passcode'

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    [IO.File]::WriteAllText($passcodeFile, 'monitoring-passcode', [Text.Encoding]::ASCII)

    function global:Invoke-RestMethod {
        param([uri]$Uri)
        if ($Uri.AbsolutePath -ne '/api/system/status') { throw "Unexpected health URI: $Uri" }
        [pscustomobject]@{ status = 'UP' }
    }
    function global:Invoke-WebRequest {
        param([uri]$Uri, [hashtable]$Headers)
        if ($Uri.AbsolutePath -ne '/api/monitoring/metrics') { throw "Unexpected metrics URI: $Uri" }
        if ($Headers['X-Sonar-Passcode'] -ne 'monitoring-passcode') { throw 'Monitoring passcode was not sent as a request header.' }
        [pscustomobject]@{ Content = '# HELP sonarweaver_test 1' }
    }

    & $verifier -Url 'https://sonarqube.example' -MonitoringPasscodeFile $passcodeFile | Out-Null

    try {
        & $verifier -Url 'http://sonarqube.example' -MonitoringPasscodeFile $passcodeFile | Out-Null
        throw 'Production verifier unexpectedly accepted an HTTP URL.'
    } catch {
        if ($_.Exception.Message -notmatch 'https') { throw }
    }

    [IO.File]::WriteAllText($passcodeFile, "monitoring-passcode`n", [Text.Encoding]::ASCII)
    try {
        & $verifier -Url 'https://sonarqube.example' -MonitoringPasscodeFile $passcodeFile | Out-Null
        throw 'Production verifier unexpectedly accepted a passcode line ending.'
    } catch {
        if ($_.Exception.Message -notmatch 'line endings') { throw }
    }
} finally {
    Remove-Item -Path Function:\global:Invoke-RestMethod -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\global:Invoke-WebRequest -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'PowerShell production verifier tests passed.'
