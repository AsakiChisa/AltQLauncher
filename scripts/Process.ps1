function Invoke-ReleaseProcess {
    param([string]$FilePath, [string[]]$Arguments, [string]$LogPrefix, [string]$RawArguments)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($RawArguments) {
        $startInfo.Arguments = $RawArguments
    } else {
        foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (!$process.Start()) { throw "无法启动：$FilePath" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(60000)) {
        $process.Kill($true)
        throw "进程超过 60 秒未结束：$FilePath"
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($LogPrefix) {
        [System.IO.File]::WriteAllText($LogPrefix + '.stdout.log', $stdout, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($LogPrefix + '.stderr.log', $stderr, [System.Text.UTF8Encoding]::new($false))
    }
    if ($process.ExitCode -ne 0) {
        throw "进程失败（$($process.ExitCode)）：$FilePath`n$stdout`n$stderr"
    }
    if ($stderr.Trim()) { Write-Host $stderr.Trim() }
    return $stdout
}
