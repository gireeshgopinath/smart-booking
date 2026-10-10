# Shared T01 verification helpers. Dot-sourcing defines functions only.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function T01-SafePath([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Absolute relative path rejected.' }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $full = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
    if (-not $full.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escapes owned root.' }
    $cursor = $full
    while ($cursor.Length -ge $rootPath.Length) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse point rejected.' }
        if ($cursor -eq $rootPath) { break }
        $cursor = Split-Path -Parent $cursor
    }
    return $full
}

function T01-HashText([string]$Value) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function T01-Source([string]$Root) {
    $files = [Collections.Generic.List[object]]::new()
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($Root)
    while ($queue.Count) {
        foreach ($item in @(Get-ChildItem -LiteralPath $queue.Dequeue() -Force)) {
            $relative = $item.FullName.Substring($Root.Length + 1).Replace('\','/')
            $generated = $relative -eq '.t01-neg-exits.json' -or $relative -match '(^|/)(target|build|dist|node_modules|\.tools|\.git)(/|$)|^docs/(execution/(runs|prepared|packets)|verification)/'
            if ($relative -eq 'docs/verification/VERIFICATION_MATRIX.md') { $generated = $false }
            if ($generated) { continue }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('Source reparse point: ' + $relative) }
            if ($item.PSIsContainer) {
                if ($item.Name -notin @('.git','.tools','.m2','.gradle','node_modules','target','build','dist','.venv','venv','__pycache__')) { $queue.Enqueue($item.FullName) }
                continue
            }
            if ($relative -match '(?i)(^|/)(\.env($|\.)|credentials?([./]|$)|secrets?([./]|$)|id_rsa|id_ed25519|[^/]+\.(pem|key|pfx|p12|jks|keystore)$)' -and $relative -notmatch '(?i)\.env\.(example|sample|template)$') { continue }
            $files.Add([ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant();bytes=$item.Length})
        }
    }
    $sorted = @($files | Sort-Object { $_.path })
    $basis = ($sorted | ForEach-Object { $_.path + ':' + $_.sha256 }) -join "`n"
    return [pscustomobject]@{revision=('no-git-sha256:' + (T01-HashText $basis));files=$sorted}
}

function T01-Start([string]$Name, [string[]]$OwnedNames, [string]$Root) {
    $source = T01-Source $Root
    $id = $Name + '-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
    $run = T01-SafePath $Root ('docs/verification/T01/verification-runs/' + $id)
    if (Test-Path -LiteralPath $run) { throw 'Run directory already exists.' }
    [void][IO.Directory]::CreateDirectory($run)
    $independent = T01-SafePath $Root 'docs/verification/T01/independent'
    [void][IO.Directory]::CreateDirectory($independent)
    foreach ($name in $OwnedNames) {
        $old = T01-SafePath $independent $name
        if (Test-Path -LiteralPath $old) {
            $prior = T01-SafePath $run 'prior'
            [void][IO.Directory]::CreateDirectory($prior)
            Copy-Item -LiteralPath $old -Destination (T01-SafePath $prior $name)
            Remove-Item -LiteralPath $old
        }
    }
    return [pscustomobject]@{root=$Root;name=$Name;runId=$id;run=$run;independent=$independent;startedAtUtc=[DateTime]::UtcNow.ToString('o');source=$source}
}

function T01-Write($Context, [string]$Name, $Data, [int]$ExitCode) {
    $payload = [ordered]@{schemaVersion=1;taskId='T01';runId=$Context.runId;startedAtUtc=$Context.startedAtUtc;finishedAtUtc=[DateTime]::UtcNow.ToString('o');command=('pwsh -NoProfile -File scripts/verify/verify-T01' + $(if ($Context.name -eq 'build') { '' } else { '-' + $Context.name }) + '.ps1');exitCode=$ExitCode;sourceFingerprint=$Context.source.revision;environment=[ordered]@{powershell=$PSVersionTable.PSVersion.ToString();os=[Runtime.InteropServices.RuntimeInformation]::OSDescription;workspace=$Context.root};data=$Data}
    $text = ($payload | ConvertTo-Json -Depth 50) + "`n"
    foreach ($dir in @($Context.run,$Context.independent)) { [IO.File]::WriteAllText((T01-SafePath $dir $Name),$text,[Text.UTF8Encoding]::new($false)) }
}

function T01-AssertUnchanged($Context) {
    if ((T01-Source $Context.root).revision -cne $Context.source.revision) { throw 'Source changed during verification.' }
}

function T01-Sanitize([string]$Text) {
    return $Text -replace '(?i)(Bearer\s+)[^\s]+','$1[REDACTED]' -replace '(https?://)[^\s/@]+:[^\s/@]+@','$1[REDACTED]@' -replace '(?i)((?:password|api[_-]?key|access[_-]?token|capability)\s*[=:]\s*)[^\s,;]+','$1[REDACTED]'
}

function T01-Process([string]$Executable, [string[]]$Arguments, [string]$Directory, [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 180) {
    $started = [DateTime]::UtcNow.ToString('o')
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.WorkingDirectory=$Directory
    if ($Executable -match '\.cmd$') {
        foreach ($value in @($Executable) + $Arguments) { if ($value -match '["\r\n&|<>^%!]') { throw 'Unsafe command argument rejected.' } }
        $info.FileName = (Get-Command cmd.exe -ErrorAction Stop).Source
        $quoted = (@($Executable) + $Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $info.Arguments = '/d /s /c "' + $quoted + '"'
    } else {
        $info.FileName=$Executable
        foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    }
    foreach ($key in @('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS','MAVEN_OPTS','MAVEN_ARGS','MVNW_REPOURL','MVNW_USERNAME','MVNW_PASSWORD','MAVEN_HOME','M2_HOME')) { [void]$info.Environment.Remove($key) }
    foreach ($entry in $Environment.GetEnumerator()) { $info.Environment[$entry.Key]=[string]$entry.Value }
    $process = [Diagnostics.Process]::new(); $process.StartInfo=$info
    try {
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $output=T01-Sanitize ($stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
        return [pscustomobject]@{executable=$Executable;arguments=$Arguments;directory=$Directory;startedAtUtc=$started;finishedAtUtc=[DateTime]::UtcNow.ToString('o');exitCode=$process.ExitCode;timedOut=$timedOut;output=$output}
    } finally { $process.Dispose() }
}

function T01-Fetch([string]$Url, [string]$Destination) {
    $start=[DateTime]::UtcNow.ToString('o')
    $client=[Net.Http.HttpClient]::new(); $client.Timeout=[TimeSpan]::FromSeconds(20)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Booking-T01-verification/1.0')
    try {
        $response=$client.GetAsync($Url).GetAwaiter().GetResult()
        try {
            if (-not $response.IsSuccessStatusCode) { return [pscustomobject]@{url=$Url;startedAtUtc=$start;finishedAtUtc=[DateTime]::UtcNow.ToString('o');statusCode=[int]$response.StatusCode;ok=$false;bytes=0;sha256=$null;error='HTTP_FAILURE';path=$null} }
            $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            [IO.File]::WriteAllBytes($Destination,$bytes)
            return [pscustomobject]@{url=$Url;startedAtUtc=$start;finishedAtUtc=[DateTime]::UtcNow.ToString('o');statusCode=[int]$response.StatusCode;ok=$true;bytes=$bytes.Length;sha256=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant();error=$null;path=$Destination}
        } finally { $response.Dispose() }
    } catch { return [pscustomobject]@{url=$Url;startedAtUtc=$start;finishedAtUtc=[DateTime]::UtcNow.ToString('o');statusCode=$null;ok=$false;bytes=0;sha256=$null;errorType=$_.Exception.GetType().FullName;error=(T01-Sanitize $_.Exception.Message);path=$null} } finally { $client.Dispose() }
}
