param([string]$ProjectPath = "")

$ErrorActionPreference = "Stop"
$sourcePath = Join-Path $PSScriptRoot "APPLY-DRIVELAB-ACHIEVEMENT-VAULT-V2.3.0-FIXED.ps1"
$runtimePath = Join-Path $PSScriptRoot ".APPLY-DRIVELAB-ACHIEVEMENT-VAULT-V2.3.0-RUNTIME.ps1"

try {
    if (!(Test-Path $sourcePath)) {
        throw "The Achievement Vault applier is missing: $sourcePath"
    }

    $source = [System.IO.File]::ReadAllText($sourcePath)
    $source = $source.Replace(
        '$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)',
        '$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)'
    )
    $source = $source.Replace(
        '$candidates = New-Object System.Collections.Generic.List[string]',
        '$candidates = [System.Collections.Generic.List[string]]::new()'
    )
    $source = $source.Replace(
        '$absent = New-Object System.Collections.Generic.List[string]',
        '$absent = [System.Collections.Generic.List[string]]::new()'
    )

    $oldRegexConstructor = @'
    $regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
'@
    $newRegexConstructor = @'
    $regex = [System.Text.RegularExpressions.Regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
'@
    $source = $source.Replace($oldRegexConstructor, $newRegexConstructor)

    [System.IO.File]::WriteAllText(
        $runtimePath,
        $source,
        [System.Text.UTF8Encoding]::new($false)
    )

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $runtimePath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -gt 0) {
        $details = $parseErrors | ForEach-Object {
            "Line $($_.Extent.StartLineNumber): $($_.Message)"
        }
        throw "PowerShell validation failed:`n$($details -join "`n")"
    }

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $runtimePath
    )
    if ($ProjectPath) {
        $arguments += @("-ProjectPath", $ProjectPath)
    }

    & powershell.exe @arguments
    exit $LASTEXITCODE
}
catch {
    Write-Host "PATCH STARTUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Remove-Item $runtimePath -Force -ErrorAction SilentlyContinue
}
