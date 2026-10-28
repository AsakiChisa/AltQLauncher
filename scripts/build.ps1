param(
    [string]$ToolsPath,
    [string]$BuildPath,
    [string]$DistPath,
    [switch]$SkipTests
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path $PSScriptRoot -Parent
if (!$ToolsPath) { $ToolsPath = Join-Path $repoRoot '.tools' }
if (!$BuildPath) { $BuildPath = Join-Path $repoRoot 'build' }
if (!$DistPath) { $DistPath = Join-Path $repoRoot 'dist' }
foreach ($directory in @($ToolsPath, $BuildPath, $DistPath)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$ToolsPath = (Resolve-Path -LiteralPath $ToolsPath).Path
$BuildPath = (Resolve-Path -LiteralPath $BuildPath).Path
$DistPath = (Resolve-Path -LiteralPath $DistPath).Path
. (Join-Path $PSScriptRoot 'Process.ps1')

function Get-VerifiedToolArchive {
    param([string]$Name, $Tool, [string]$CachePath, [string]$DiagnosticsPath)
    $archive = Join-Path $CachePath $Tool.file
    $downloadLog = Join-Path $DiagnosticsPath 'downloads.stdout.log'
    if ((Test-Path -LiteralPath $archive) -and
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -eq $Tool.sha256) {
        return $archive
    }
    # 地区镜像或跳转页可能返回 HTTP 200；每次只接受锁定 SHA256 的内容。
    $urls = @($Tool.url)
    if ($Tool.PSObject.Properties.Name -contains 'fallback_urls') { $urls += @($Tool.fallback_urls) }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    $sequence = 0
    foreach ($url in $urls) {
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            $sequence++
            $temporary = $archive + '.download-' + [guid]::NewGuid().ToString('N')
            $description = "$Name attempt=$sequence url=$url"
            Write-Host "下载并校验官方工具：$description"
            Add-Content -LiteralPath $downloadLog -Value $description -Encoding utf8
            try {
                if ($curl) {
                    Invoke-ReleaseProcess -FilePath $curl.Source -Arguments @('--location', '--fail', '--silent',
                        '--show-error', '--connect-timeout', '10', '--max-time', '30', '--output', $temporary, $url) `
                        -LogPrefix (Join-Path $DiagnosticsPath "download-$Name-$sequence") | Out-Null
                } else {
                    Invoke-WebRequest -Uri $url -OutFile $temporary -TimeoutSec 30 -MaximumRedirection 10
                }
                $actual = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
                if ($actual -ne $Tool.sha256) {
                    $bytes = (Get-Item -LiteralPath $temporary).Length
                    throw "SHA256 mismatch expected=$($Tool.sha256) actual=$actual bytes=$bytes"
                }
                # 验证成功后才替换缓存，不会解压错误文件或降低校验要求。
                Move-Item -LiteralPath $temporary -Destination $archive -Force
                Add-Content -LiteralPath $downloadLog -Value "$Name verified SHA256=$actual" -Encoding utf8
                return $archive
            } catch {
                $failureMessage = $_.Exception.Message
                Add-Content -LiteralPath $downloadLog -Value "$description failed: $failureMessage" -Encoding utf8
                Write-Warning "本次下载未通过校验，将重试或切换官方镜像：$failureMessage"
            } finally {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
            }
        }
    }
    throw "无法获取通过校验的 $Name；已尝试所有官方地址，详情见 $downloadLog。"
}

$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION 必须为 x.y.z' }
$source = Join-Path $repoRoot 'src\AltQLauncher.ahk'
if (![System.IO.File]::ReadAllText($source).Contains(";@Ahk2Exe-SetVersion $version")) {
    throw 'VERSION 与源码的 Ahk2Exe 版本标记不一致'
}
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tools.lock.json') -Raw | ConvertFrom-Json
foreach ($property in $lock.PSObject.Properties) {
    $tool = $property.Value
    $archive = Get-VerifiedToolArchive -Name $property.Name -Tool $tool -CachePath $ToolsPath -DiagnosticsPath $BuildPath
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $ToolsPath $tool.folder) -Force
}
$runtime = Join-Path $ToolsPath 'AutoHotkey\AutoHotkey64.exe'
$compiler = Join-Path $ToolsPath 'Ahk2Exe\Ahk2Exe.exe'
$nsis = Join-Path $ToolsPath 'NSIS\nsis-3.13\makensis.exe'
foreach ($required in @($runtime, $compiler, $nsis)) {
    if (!(Test-Path -LiteralPath $required)) { throw "缺少工具：$required" }
}
if (!$SkipTests) {
    & (Join-Path $PSScriptRoot 'test.ps1') -AutoHotkeyPath $runtime -WorkPath (Join-Path $BuildPath 'tests')
}
$packageRoot = Join-Path $BuildPath ('package-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $packageRoot 'stage'
foreach ($folder in @('', 'source', 'licenses', 'third-party-source')) {
    New-Item -ItemType Directory -Path (Join-Path $stage $folder) -Force | Out-Null
}
$compiled = Join-Path $stage 'AltQLauncher.exe'
Write-Host "编译 AltQLauncher $version x64"
Invoke-ReleaseProcess -FilePath $compiler -Arguments @('/in', $source, '/out', $compiled,
    '/base', $runtime, '/ahk', $runtime, '/compress', '0', '/cp', '65001', '/silent', 'verbose') `
    -LogPrefix (Join-Path $BuildPath 'compile') | Write-Host
if (!(Test-Path -LiteralPath $compiled)) { throw '编译未产生 EXE' }
$sourceArchive = Join-Path $repoRoot 'vendor\AutoHotkey-v2.0.31-source.zip'
if ((Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash -ne 'C002AD1CFC7ACB44AE3A55A721AE4975A90312FB001D7E4E42CF382EFEB26E60') {
    throw '随附 AutoHotkey 源码归档校验失败'
}
Copy-Item -LiteralPath $source -Destination (Join-Path $stage 'source\AltQLauncher.ahk') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\AltQLauncher.default.ini') -Destination (Join-Path $stage 'AltQLauncher.default.ini') -Force
foreach ($document in @('README.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $document) -Destination (Join-Path $stage $document) -Force
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'licenses\AutoHotkey-GPL-2.0-and-PCRE.txt') -Destination (Join-Path $stage 'licenses') -Force
Copy-Item -LiteralPath $sourceArchive -Destination (Join-Path $stage 'third-party-source') -Force
$setup = Join-Path $DistPath "AltQLauncher-$version-Setup-x64.exe"
Invoke-ReleaseProcess -FilePath $nsis -Arguments @('/V3', "/DAPP_VERSION=$version", "/DSTAGE_DIR=$stage",
    "/DOUT_FILE=$setup", (Join-Path $repoRoot 'installer\AltQLauncher.nsi')) `
    -LogPrefix (Join-Path $BuildPath 'installer') | Write-Host
$portable = Join-Path $packageRoot 'AltQLauncher-Portable'
New-Item -ItemType Directory -Path $portable -Force | Out-Null
Get-ChildItem -LiteralPath $stage | Copy-Item -Destination $portable -Recurse -Force
[System.IO.File]::WriteAllText((Join-Path $portable 'portable.flag'), '', [System.Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $portable -DestinationPath (Join-Path $DistPath "AltQLauncher-$version-Portable-x64.zip") -Force
$sourceFiles = @('src\AltQLauncher.ahk', 'src\AltQLauncher.default.ini', 'installer\AltQLauncher.nsi',
    'tests\Core.test.ahk', '.github\workflows\build.yml',
    'scripts\build.ps1', 'scripts\Process.ps1', 'scripts\test.ps1', 'scripts\test-install.ps1',
    'scripts\test-portable.ps1', 'scripts\tools.lock.json',
    'licenses\AutoHotkey-GPL-2.0-and-PCRE.txt', 'vendor\AutoHotkey-v2.0.31-source.zip',
    'README.md', 'CHANGELOG.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'VERSION', '.gitignore', '.gitattributes')
$sourceStage = Join-Path $packageRoot 'source-package'
foreach ($relativePath in $sourceFiles) {
    $targetPath = Join-Path $sourceStage $relativePath
    New-Item -ItemType Directory -Path (Split-Path $targetPath -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot $relativePath) -Destination $targetPath
}
Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $sourceStage -Force | ForEach-Object { $_.FullName }) `
    -DestinationPath (Join-Path $DistPath "AltQLauncher-$version-Source.zip") -Force
if (!$SkipTests) {
    & (Join-Path $PSScriptRoot 'test-portable.ps1') `
        -ArchivePath (Join-Path $DistPath "AltQLauncher-$version-Portable-x64.zip") `
        -WorkPath (Join-Path $BuildPath 'portable-test')
    & (Join-Path $PSScriptRoot 'test-install.ps1') -SetupPath $setup -WorkPath (Join-Path $BuildPath 'install-test')
}
$artifacts = @(Get-ChildItem -LiteralPath $DistPath -File | Where-Object { $_.Name -like "AltQLauncher-$version-*" })
$checksums = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($artifact.Name)"
}
[System.IO.File]::WriteAllText((Join-Path $DistPath 'SHA256SUMS.txt'), ($checksums -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "构建完成：$DistPath"
