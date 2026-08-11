[CmdletBinding()]
param(
    [string]$Version,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$projectPath = Join-Path $repositoryRoot "windows\YYReader.Windows\YYReader.Windows.csproj"
$testProjectPath = Join-Path $repositoryRoot "windows\YYReader.Windows.Tests\YYReader.Windows.Tests.csproj"
$installerScriptPath = Join-Path $repositoryRoot "windows\installer\YYReader.iss"
$releaseBuildDirectory = Join-Path $repositoryRoot "windows\YYReader.Windows\bin\Release\net8.0-windows10.0.26100.0\win-x64"
$outputDirectory = Join-Path $repositoryRoot "dist\windows"
$fullRootDirectory = Join-Path $outputDirectory "full"
$fullAppDirectory = Join-Path $fullRootDirectory "YYReader"

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionLine = Select-String -LiteralPath $projectPath -Pattern '<Version>([^<]+)</Version>' | Select-Object -First 1
    if (-not $versionLine) {
        throw "No Version property was found in $projectPath."
    }
    $Version = $versionLine.Matches[0].Groups[1].Value
}

if ($Version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') {
    throw "Version must use the 1.2.3 or 1.2.3.4 format. Current value: $Version"
}

$installerPath = Join-Path $outputDirectory "YYReader-Setup-x64-$Version.exe"
$legacyFullArchivePath = Join-Path $outputDirectory "YYReader-Windows-x64-$Version-Full.zip"
$innoCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
)
$innoCompiler = $innoCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $innoCompiler) {
    throw "Inno Setup 6 was not found. Install it from https://jrsoftware.org/isinfo.php."
}

function Remove-ReleasePath {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedTarget = [System.IO.Path]::GetFullPath($Path)
    $allowedRoot = [System.IO.Path]::GetFullPath($outputDirectory)
    if (($resolvedTarget -ne $allowedRoot) -and
        (-not $resolvedTarget.StartsWith($allowedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to clean a path outside the expected output directory: $resolvedTarget"
    }

    if (Test-Path -LiteralPath $resolvedTarget) {
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    }
}

function Copy-WinUIResources {
    param([Parameter(Mandatory)][string]$Destination)

    $resources = @(
        "YYReader.Windows.pri",
        "App.xbf",
        "MainWindow.xbf",
        "Views\AboutDialogContent.xbf",
        "Views\LibraryPage.xbf",
        "Views\ReaderPage.xbf"
    )
    foreach ($relativePath in $resources) {
        $sourcePath = Join-Path $releaseBuildDirectory $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Required WinUI runtime file was not produced: $sourcePath"
        }

        $destinationPath = Join-Path $Destination $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
}

function Assert-NoUnusedAiRuntime {
    param([Parameter(Mandatory)][string]$Directory)

    $unwantedPatterns = @("onnxruntime*.dll", "DirectML.dll", "Microsoft.Windows.AI*.dll")
    foreach ($pattern in $unwantedPatterns) {
        $match = Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter $pattern | Select-Object -First 1
        if ($match) {
            throw "Unused Windows App SDK AI/ML dependency was packaged: $($match.FullName)"
        }
    }
}

function Invoke-AppPublish {
    param(
        [Parameter(Mandatory)][bool]$SelfContained,
        [Parameter(Mandatory)][string]$Destination
    )

    $selfContainedText = $SelfContained.ToString().ToLowerInvariant()
    & dotnet clean $projectPath --configuration Release --runtime win-x64
    if ($LASTEXITCODE -ne 0) { throw "Release clean failed." }

    & dotnet build $projectPath `
        --configuration Release `
        --runtime win-x64 `
        -p:Version=$Version `
        -p:DebugType=None `
        -p:DebugSymbols=false `
        -p:WindowsAppSDKSelfContained=$selfContainedText
    if ($LASTEXITCODE -ne 0) { throw "Release build failed." }

    Remove-ReleasePath -Path $Destination
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & dotnet publish $projectPath `
        --configuration Release `
        --runtime win-x64 `
        --self-contained $selfContainedText `
        --output $Destination `
        -p:Version=$Version `
        -p:DebugType=None `
        -p:DebugSymbols=false `
        -p:WindowsAppSDKSelfContained=$selfContainedText
    if ($LASTEXITCODE -ne 0) { throw "Release publish failed." }

    Copy-WinUIResources -Destination $Destination
    Assert-NoUnusedAiRuntime -Directory $Destination
}

Push-Location $repositoryRoot
try {
    # Full.zip is no longer a release artifact; remove a stale archive from earlier builds.
    Remove-ReleasePath -Path $legacyFullArchivePath

    if (-not $SkipTests) {
        Write-Host "[1/3] Running Windows Release tests..." -ForegroundColor Cyan
        & dotnet test $testProjectPath --configuration Release
        if ($LASTEXITCODE -ne 0) { throw "Release tests failed." }
    } else {
        Write-Host "[1/3] Tests skipped." -ForegroundColor Yellow
    }

    Write-Host "[2/3] Publishing full self-contained x64 app..." -ForegroundColor Cyan
    Remove-ReleasePath -Path $fullRootDirectory
    New-Item -ItemType Directory -Path $fullAppDirectory -Force | Out-Null
    Invoke-AppPublish -SelfContained $true -Destination $fullAppDirectory
    foreach ($relativePath in @("hostfxr.dll", "hostpolicy.dll", "coreclr.dll")) {
        if (-not (Test-Path -LiteralPath (Join-Path $fullAppDirectory $relativePath))) {
            throw "Required self-contained .NET runtime file was not produced: $relativePath"
        }
    }

    Write-Host "[3/3] Compiling the full self-contained installer..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Remove-ReleasePath -Path $installerPath
    & $innoCompiler `
        "/DMyAppVersion=$Version" `
        "/DSourceDir=$fullAppDirectory" `
        "/DOutputDir=$outputDirectory" `
        $installerScriptPath
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." }
    if (-not (Test-Path -LiteralPath $installerPath)) {
        throw "The expected installer was not found: $installerPath"
    }

    $installerSizeMb = [Math]::Round((Get-Item -LiteralPath $installerPath).Length / 1MB, 1)
    Write-Host "Full self-contained installer: $installerPath ($installerSizeMb MB)" -ForegroundColor Green
    Remove-ReleasePath -Path $fullRootDirectory
} finally {
    Pop-Location
}
