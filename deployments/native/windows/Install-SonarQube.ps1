# SPDX-License-Identifier: 0BSD
#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingPlainTextForPassword',
    '',
    Justification = 'JdbcPasswordFile is a filesystem path; the password is never accepted as a command-line value.'
)]
[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallRoot = "$env:ProgramData\SonarWeaver",
    [string]$JdbcUrl,
    [string]$JdbcUser,
    [string]$JdbcPasswordFile,
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$Sha256,
    [switch]$Evaluation,
    [switch]$NoStart,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$TaskName = 'SonarWeaver-SonarQube'
$SigningKey = '679F1EE92B19609DE816FDE81DB198F93525EC1A'
$SigningKeyServer = 'hkps://keyserver.ubuntu.com'

function Show-Log {
    param([string]$Message)
    Write-Information "[sonarweaver] $Message" -InformationAction Continue
}

function Get-LockedVersion {
    $lockPath = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent) 'config\versions.env'
    $line = Get-Content -LiteralPath $lockPath | Where-Object { $_ -match '^SONARQUBE_COMMUNITY_VERSION=' } | Select-Object -First 1
    if (-not $line) { throw 'Could not read SONARQUBE_COMMUNITY_VERSION from config/versions.env.' }
    return (($line -split '=', 2)[1]).Trim('"')
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this system installation from an elevated PowerShell session.'
    }
}

function Get-JavaInfo {
    $java = Get-Command java.exe -ErrorAction Stop
    $versionText = (& $java.Source -version 2>&1 | Out-String)
    if ($versionText -notmatch 'version\s+"(?<major>\d+)') {
        throw "Could not parse Java version from: $versionText"
    }
    $major = [int]$Matches.major
    if ($major -notin @(21, 25)) {
        throw "Java $major is unsupported; install a current JDK 21 or 25 CPU release."
    }
    return [pscustomobject]@{ Path = $java.Source; Major = $major }
}

function Invoke-ArchiveVerification {
    param(
        [string]$Archive,
        [string]$Signature,
        [string]$ExpectedSha256,
        [string]$TemporaryRoot
    )

    if ($ExpectedSha256) {
        $actual = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
        if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
            throw 'SonarQube archive SHA-256 mismatch.'
        }
        Show-Log 'Archive SHA-256 verified.'
        return
    }

    $gpg = Get-Command gpg.exe -ErrorAction SilentlyContinue
    if (-not $gpg) {
        throw 'GnuPG is required for default signature verification. Install gpg or pass -Sha256 from a trusted source.'
    }

    $gpgHome = Join-Path $TemporaryRoot 'gnupg'
    New-Item -ItemType Directory -Path $gpgHome | Out-Null
    & $gpg.Source --batch --homedir $gpgHome --keyserver $SigningKeyServer --recv-keys $SigningKey | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve the pinned SonarSource signing key.' }

    $fingerprintLines = & $gpg.Source --batch --homedir $gpgHome --with-colons --fingerprint $SigningKey
    $fingerprint = $fingerprintLines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1
    if (-not $fingerprint -or (($fingerprint -split ':')[9]) -ne $SigningKey) {
        throw 'Unexpected SonarSource signing-key fingerprint.'
    }
    & $gpg.Source --batch --homedir $gpgHome --verify $Signature $Archive | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'SonarQube archive signature verification failed.' }
    Show-Log "Archive signature verified with SonarSource key $SigningKey."
}

if (-not $Version) { $Version = Get-LockedVersion }
if ($Version -notmatch '^[0-9A-Za-z._-]+$') { throw "Invalid version: $Version" }
if (-not [Environment]::Is64BitOperatingSystem) { throw 'SonarQube requires 64-bit Windows.' }
$javaInfo = Get-JavaInfo
Show-Log "Java $($javaInfo.Major) is supported."

if ($Evaluation) {
    if ($JdbcUrl -or $JdbcUser -or $JdbcPasswordFile) {
        throw 'Do not combine -Evaluation with JDBC options.'
    }
    Write-Warning 'Embedded H2 is for evaluation only and must not hold production data.'
} else {
    if (-not $JdbcUrl) { throw 'Production mode requires -JdbcUrl.' }
    if (-not $JdbcUser) { throw 'Production mode requires -JdbcUser.' }
    if (-not $JdbcPasswordFile) { throw 'Production mode requires -JdbcPasswordFile.' }
    if (-not (Test-Path -LiteralPath $JdbcPasswordFile -PathType Leaf)) {
        throw "Cannot read JDBC password file: $JdbcPasswordFile"
    }
    if ((Get-Item -LiteralPath $JdbcPasswordFile).Length -eq 0) {
        throw 'JDBC password file is empty.'
    }
}

$versionDir = Join-Path $InstallRoot "versions\$Version"
$dataDir = Join-Path $InstallRoot 'data'
$logsDir = Join-Path $InstallRoot 'logs'
$tempDir = Join-Path $InstallRoot 'temp'
$configDir = Join-Path $InstallRoot 'config'
$passwordTarget = Join-Path $configDir 'jdbc-password'
$wrapperPath = Join-Path $InstallRoot 'sonarweaver-start.cmd'

Show-Log "Plan: install SonarQube $Version into $versionDir"
Show-Log "Plan: register startup task $TaskName as Local Service"
if ($DryRun) {
    Show-Log 'Dry run complete; no changes made.'
    return
}
Test-Administrator

@($InstallRoot, (Join-Path $InstallRoot 'versions'), $dataDir, $logsDir, $tempDir, $configDir) |
    ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }

$newInstall = $false
if (-not (Test-Path -LiteralPath $versionDir -PathType Container)) {
    $newInstall = $true
    $workDir = Join-Path ([IO.Path]::GetTempPath()) ("sonarweaver-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $workDir | Out-Null
    try {
        $archive = Join-Path $workDir "sonarqube-$Version.zip"
        $signature = "$archive.asc"
        $baseUrl = "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-$Version.zip"
        Show-Log "Downloading SonarQube $Version from SonarSource."
        Invoke-WebRequest -Uri $baseUrl -OutFile $archive -UseBasicParsing
        if (-not $Sha256) {
            Invoke-WebRequest -Uri "$baseUrl.asc" -OutFile $signature -UseBasicParsing
        }
        Invoke-ArchiveVerification -Archive $archive -Signature $signature -ExpectedSha256 $Sha256 -TemporaryRoot $workDir
        $extractRoot = Join-Path $workDir 'extracted'
        Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot
        $extracted = Join-Path $extractRoot "sonarqube-$Version"
        if (-not (Test-Path -LiteralPath $extracted -PathType Container)) {
            throw 'Unexpected archive layout.'
        }
        Move-Item -LiteralPath $extracted -Destination $versionDir
    } finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
} elseif (-not (Test-Path -LiteralPath (Join-Path $versionDir "lib\sonar-application-$Version.jar"))) {
    throw "Existing version directory is incomplete: $versionDir"
} else {
    Show-Log "Version $Version is already present; reusing it."
}

$propertiesPath = Join-Path $versionDir 'conf\sonar.properties'
if (-not $newInstall -and
    (-not (Test-Path -LiteralPath $propertiesPath) -or
     (Get-Content -LiteralPath $propertiesPath -TotalCount 1) -notmatch '^# Managed by SonarWeaver\.$')) {
    throw 'Refusing to overwrite an unmanaged sonar.properties in an existing installation.'
}
$properties = @(
    '# Managed by SonarWeaver.'
    "sonar.path.data=$dataDir"
    "sonar.path.logs=$logsDir"
    "sonar.path.temp=$tempDir"
    'sonar.web.host=127.0.0.1'
    'sonar.web.port=9000'
)
if (-not $Evaluation) {
    $properties += "sonar.jdbc.url=$JdbcUrl"
    $properties += "sonar.jdbc.username=$JdbcUser"
}
[IO.File]::WriteAllLines(
    $propertiesPath,
    [string[]]$properties,
    [Text.UTF8Encoding]::new($false)
)

if (-not $Evaluation) {
    Copy-Item -LiteralPath $JdbcPasswordFile -Destination $passwordTarget -Force
} else {
    Remove-Item -LiteralPath $passwordTarget -Force -ErrorAction SilentlyContinue
}

$launcherPath = Join-Path $versionDir 'bin\windows-x86-64\StartSonar.bat'
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw 'The supported Windows StartSonar.bat launcher is missing from the archive.'
}
$javaDirectory = Split-Path -Parent $javaInfo.Path
$wrapper = @(
    '@echo off'
    'setlocal'
    "set `"PATH=$javaDirectory;%PATH%`""
)
if (-not $Evaluation) {
    $wrapper += "set /p SONAR_JDBC_PASSWORD=<`"$passwordTarget`""
}
$wrapper += "call `"$launcherPath`""
$wrapper | Set-Content -LiteralPath $wrapperPath -Encoding ASCII

# Local Service, Local System, and Administrators SIDs are language-independent.
& icacls.exe $InstallRoot /inheritance:r /grant:r `
    '*S-1-5-19:(OI)(CI)M' `
    '*S-1-5-18:(OI)(CI)F' `
    '*S-1-5-32-544:(OI)(CI)F' /T | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not secure $InstallRoot." }
if (-not $Evaluation) {
    & icacls.exe $passwordTarget /inheritance:r /grant:r `
        '*S-1-5-19:R' '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not secure the JDBC password file.' }
}

$taskArgument = '/d /s /c ""{0}""' -f $wrapperPath
$action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument $taskArgument
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\LOCAL SERVICE' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

if (-not $NoStart) {
    Start-ScheduledTask -TaskName $TaskName
    Show-Log "SonarQube is starting. Logs: $logsDir"
} else {
    Show-Log "Installed without starting. Start with: Start-ScheduledTask -TaskName '$TaskName'"
}
Show-Log 'After startup, open http://127.0.0.1:9000 and immediately change admin/admin.'
