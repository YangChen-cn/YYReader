[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$separator = [System.IO.Path]::DirectorySeparatorChar

function Remove-GeneratedPath {
    param([Parameter(Mandatory)][string]$RelativePath)

    $target = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $RelativePath))
    if (($target -eq $repositoryRoot) -or
        (-not $target.StartsWith($repositoryRoot + $separator, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to remove a path outside the repository: $target"
    }

    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
        Write-Host "Removed $RelativePath"
    }
}

$generatedPaths = @(
    ".codex\dotnet-sdk",
    ".codex\windows-sdk",
    ".codex\environments",
    "windows\YYReader.Windows\bin",
    "windows\YYReader.Windows\obj",
    "windows\YYReader.Windows.Core\bin",
    "windows\YYReader.Windows.Core\obj",
    "windows\YYReader.Windows.Tests\bin",
    "windows\YYReader.Windows.Tests\obj",
    "dist\windows\publish",
    "dist\windows\publish-online-v120",
    "dist\windows\publish-framework-dependent",
    "dist\windows\full"
)

foreach ($relativePath in $generatedPaths) {
    Remove-GeneratedPath -RelativePath $relativePath
}

Write-Host "Local generated files cleaned. Release installers in dist\windows are preserved."
