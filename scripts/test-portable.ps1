param([Parameter(Mandatory)][string]$ArchivePath, [Parameter(Mandatory)][string]$WorkPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Process.ps1')
New-Item -ItemType Directory -Path $WorkPath -Force | Out-Null
$testRoot = Join-Path (Resolve-Path -LiteralPath $WorkPath).Path ([guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $testRoot
$executables = @(Get-ChildItem -LiteralPath $testRoot -Recurse -File -Filter 'AltQLauncher.exe')
if ($executables.Count -ne 1) { throw '便携包结构错误' }
$exe = $executables[0]
if (!(Test-Path -LiteralPath (Join-Path $exe.DirectoryName 'portable.flag'))) { throw '便携标志缺失' }
$actualConfig = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'AltQLauncher\AltQLauncher.ini'
$beforeHash = if (Test-Path -LiteralPath $actualConfig) { (Get-FileHash -LiteralPath $actualConfig).Hash } else { $null }
Invoke-ReleaseProcess -FilePath $exe.FullName -Arguments @('--check') -LogPrefix (Join-Path $testRoot 'portable') | Write-Host
if (!(Test-Path -LiteralPath (Join-Path $exe.DirectoryName 'AltQLauncher.ini'))) {
    throw '便携版未在程序旁生成个人配置'
}
$afterHash = if (Test-Path -LiteralPath $actualConfig) { (Get-FileHash -LiteralPath $actualConfig).Hash } else { $null }
if ($beforeHash -ne $afterHash) { throw '便携版改动了安装版用户配置' }
Write-Host 'PASS: 便携版直接启动使用本地配置，不改动 AppData'
