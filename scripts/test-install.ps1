param([Parameter(Mandatory)][string]$SetupPath, [Parameter(Mandatory)][string]$WorkPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Process.ps1')
New-Item -ItemType Directory -Path $WorkPath -Force | Out-Null
$testRoot = Join-Path (Resolve-Path -LiteralPath $WorkPath).Path ([guid]::NewGuid().ToString('N'))
$installDir = Join-Path $testRoot 'app with spaces'
$profileDir = Join-Path $testRoot 'profile'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$actualConfig = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'AltQLauncher\AltQLauncher.ini'
$actualHash = if (Test-Path -LiteralPath $actualConfig) { (Get-FileHash -LiteralPath $actualConfig).Hash } else { $null }
$registration = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher'
$registrationExisted = Test-Path -LiteralPath $registration
Invoke-ReleaseProcess -FilePath $SetupPath -RawArguments "/S /TESTMODE /D=$installDir" `
    -LogPrefix (Join-Path $testRoot 'install') | Write-Host
$exe = Join-Path $installDir 'AltQLauncher.exe'
if (!(Test-Path -LiteralPath $exe) -or !(Test-Path -LiteralPath (Join-Path $installDir '.test-install'))) {
    throw '隔离安装未生成预期文件'
}
Write-Host 'PASS: 安装包可安装到含空格的隔离目录'
Invoke-ReleaseProcess -FilePath $exe -Arguments @('--check', '--data-dir', $profileDir) `
    -LogPrefix (Join-Path $testRoot 'check') | Write-Host
$config = Join-Path $profileDir 'AltQLauncher.ini'
[System.IO.File]::AppendAllText($config, "`n; upgrade-preservation-check`n", [System.Text.UTF8Encoding]::new($false))
$beforeHash = (Get-FileHash -LiteralPath $config).Hash
Invoke-ReleaseProcess -FilePath $SetupPath -RawArguments "/S /TESTMODE /D=$installDir" `
    -LogPrefix (Join-Path $testRoot 'upgrade') | Write-Host
Invoke-ReleaseProcess -FilePath $exe -Arguments @('--check', '--data-dir', $profileDir) `
    -LogPrefix (Join-Path $testRoot 'upgrade-check') | Write-Host
if ((Get-FileHash -LiteralPath $config).Hash -ne $beforeHash) { throw '升级覆盖了用户配置' }
Write-Host 'PASS: 重复安装及首次启动均保留已有配置'
Invoke-ReleaseProcess -FilePath (Join-Path $installDir 'Uninstall.exe') -Arguments @('/S') `
    -LogPrefix (Join-Path $testRoot 'uninstall') | Write-Host
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while ((Test-Path -LiteralPath $exe) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
if (Test-Path -LiteralPath $exe) { throw '卸载后主程序仍存在' }
if ((Get-FileHash -LiteralPath $config).Hash -ne $beforeHash) { throw '卸载删除或修改了用户配置' }
Write-Host 'PASS: 卸载删除主程序并保留用户配置'
$afterActualHash = if (Test-Path -LiteralPath $actualConfig) { (Get-FileHash -LiteralPath $actualConfig).Hash } else { $null }
if ($actualHash -ne $afterActualHash -or (Test-Path -LiteralPath $registration) -ne $registrationExisted) {
    throw '隔离安装测试影响了实际用户配置或安装注册'
}
Write-Host 'PASS: 验证模式未改动实际 AppData 配置或安装注册'
