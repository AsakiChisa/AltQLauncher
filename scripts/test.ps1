param([Parameter(Mandatory)][string]$AutoHotkeyPath, [Parameter(Mandatory)][string]$WorkPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Path $WorkPath -Force | Out-Null
$WorkPath = (Resolve-Path -LiteralPath $WorkPath).Path
. (Join-Path $PSScriptRoot 'Process.ps1')
Invoke-ReleaseProcess -FilePath $AutoHotkeyPath -Arguments @('/ErrorStdOut=UTF-8',
    (Join-Path $repoRoot 'tests\Core.test.ahk'), '--library', $WorkPath) `
    -LogPrefix (Join-Path $WorkPath 'core') | Write-Host
