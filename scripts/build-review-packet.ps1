[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^T[0-9]{2}$')][string]$TaskId,
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [string]$Root,
    [string]$OutputDirectory,
    [switch]$Diagnostic,
    [ValidateRange(10000,250000)][int]$MaxPacketChars=65000
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
function Protect-PacketText {
    param([string]$Text)
    $text = [regex]::Replace($Text, '(?im)(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+', '$1[REDACTED]')
    $text = [regex]::Replace($text, '(?im)((?:password|passwd|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*)[^\s,;]+', '$1[REDACTED]')
    $text = [regex]::Replace($text, '(?i)\b(sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{12,})\b', '[REDACTED_TOKEN]')
    $text = [regex]::Replace($text, '(?i)(https?://)[^\s/@]+:[^\s/@]+@', '$1[REDACTED]@')
    return $text
}
function Protect-PacketValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (Protect-PacketText $Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        $safe = [ordered]@{}
        foreach ($key in $Value.Keys) { $safe[$key] = Protect-PacketValue $Value[$key] }
        return $safe
    }
    if ($Value -is [System.Collections.IList]) {
        $values = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in $Value) { $values.Add((Protect-PacketValue $item)) }
        return ,$values.ToArray()
    }
    if ($Value -is [pscustomobject]) {
        $safe = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $safe[$property.Name] = Protect-PacketValue $property.Value }
        return $safe
    }
    return $Value
}
$context = Get-TaskContext $Root $TaskId -RequireReady
$runPath = Resolve-WorkspacePath $Root $RunDirectory -MustExist
$summary = Read-WorkflowJson (Join-Path $runPath 'run-summary.json')
$result = $null
$resultIssue = $null
try {
    $result = Read-WorkflowJson (Join-Path $runPath 'result.json')
    Assert-ResultShape $result $summary.role $TaskId
} catch {
    if (-not $Diagnostic) { throw }
    $result = $null
    $resultIssue = $_.Exception.Message
}
if ($summary.taskId -ne $TaskId -or ($summary.role -ne 'Local' -and -not $Diagnostic)) { throw 'Run must be the Local attempt for the requested task; Diagnostic may also inspect a rejected Review attempt.' }
if (-not $Diagnostic -and (-not $summary.wrapperValid -or $summary.cliExitCode -ne 0 -or $result.status -ne 'NEEDS_REVIEW')) { throw 'Cannot build an approval packet from a rejected/nonzero/blocked attempt. Use -Diagnostic for GPT diagnosis.' }
$snapshot = Get-SourceSnapshot $Root
if (-not $Diagnostic -and $snapshot.revision -ne $summary.sourceRevisionAfter) { throw 'Source has changed since Local attempt. Capture a fresh implementation/check attempt before review.' }
$files = New-Object 'System.Collections.Generic.List[object]'
$omitted = New-Object 'System.Collections.Generic.List[string]'
$reportedPaths = @()
if ($result -and $summary.role -eq 'Local') { $reportedPaths = @($result.changedFiles) }
$paths = @(@($summary.changedSourcePaths) + $reportedPaths | Sort-Object -Unique)
$used = 0
foreach ($path in $paths) {
    if (Test-SensitivePath $path) { $omitted.Add("Sensitive path excluded: $path"); continue }
    $fullPath = Resolve-WorkspacePath $Root $path
    if (-not (Test-Path -LiteralPath $fullPath)) { $files.Add([pscustomobject]@{ path=$path; state='DELETED'; content=$null }); continue }
    if ([IO.Path]::GetExtension($path) -notin @('.md','.txt','.json','.jsonl','.java','.kt','.kts','.cs','.sql','.ts','.tsx','.js','.jsx','.py','.ps1','.yaml','.yml','.xml','.toml','.gradle','.properties','.html','.css','.sh','.bat','.cmd','.csv','')) { $omitted.Add("Binary or unsupported text extension: $path"); continue }
    try {
        $text = Get-BoundedText $Root $path 20000
        $text = Protect-PacketText $text
        if ($used + $text.Length -gt ($MaxPacketChars - 15000)) { $omitted.Add("Packet budget: inspect source directly: $path"); continue }
        $used += $text.Length
        $files.Add([pscustomobject]@{ path=$path; state='CURRENT_SOURCE'; content=$text })
    } catch { $omitted.Add($_.Exception.Message + '; inspect source directly.') }
}
$evidence = New-Object 'System.Collections.Generic.List[object]'
$evidencePaths = @()
if ($result -and $summary.role -eq 'Local') { $evidencePaths = @($result.checks | ForEach-Object { $_.evidencePaths } | Sort-Object -Unique) }
foreach ($path in $evidencePaths) {
    if (Test-SensitivePath $path) { throw "Sensitive evidence cannot enter packet: $path" }
    $fullPath = Resolve-WorkspacePath $Root $path -MustExist
    $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $text = $null
    if ([IO.Path]::GetExtension($path) -in @('.md','.txt','.json','.jsonl','.log','.xml','.csv')) {
        try {
            $candidate = Protect-PacketText (Get-BoundedText $Root $path 12000)
            if ($used + $candidate.Length -le ($MaxPacketChars - 10000)) { $text = $candidate; $used += $candidate.Length }
            else { $omitted.Add("Evidence content omitted for packet budget: $path") }
        } catch { $omitted.Add("Evidence content omitted: $path; " + $_.Exception.Message) }
    }
    $evidence.Add([pscustomobject]@{ path=$path; sha256=$hash; content=$text })
}
$gitDiff = $null
if ($snapshot.gitHead -and $paths.Count -gt 0) {
    $diffResult = Invoke-NativeCapture 'git' (@('-C',$Root,'diff','--no-ext-diff','--no-textconv','--no-color','HEAD','--') + $paths)
    $diff = $diffResult.output
    if ($diffResult.exitCode -eq 0 -and $diff.Length -le 15000 -and $used + $diff.Length -le ($MaxPacketChars - 10000)) { $gitDiff = Protect-PacketText $diff }
    else { $omitted.Add('Git diff omitted because it exceeds the packet budget or command failed. Reviewer must inspect source directly.') }
} else { $omitted.Add('No Git baseline diff is available. File hashes identify before/after changes; packet includes current changed source and reviewer must inspect it directly.') }
$logSnippets = New-Object 'System.Collections.Generic.List[object]'
if ($Diagnostic) {
    foreach ($name in @('codex.stdout.log','codex.stderr.log','codex.log')) {
        $logPath = Join-Path $runPath $name
        if (-not (Test-Path -LiteralPath $logPath)) { continue }
        if ((Get-Item -LiteralPath $logPath).Length -gt 4MB) { $omitted.Add("Oversized diagnostic log omitted: $name"); continue }
        $logText = [IO.File]::ReadAllText($logPath, [Text.Encoding]::UTF8)
        $truncated = $logText.Length -gt 3500
        if ($truncated) { $logText = $logText.Substring($logText.Length - 3500) }
        $logSnippets.Add([pscustomobject]@{name=$name;excerpt=Protect-PacketText $logText;truncated=$truncated;scope='tail excerpt; inspect full local log for diagnosis'})
    }
}
$purpose = if ($Diagnostic) {'DIAGNOSTIC'} else {'APPROVAL_REVIEW'}
$packet = [ordered]@{ schemaVersion=1; purpose=$purpose; taskId=$TaskId; sourceRevision=$snapshot.revision; sourceChangedSinceAttempt=($snapshot.revision -ne $summary.sourceRevisionAfter); gitHead=$snapshot.gitHead; runDirectory=$RunDirectory; specPath=$context.Task.specPath; localResult=$result; resultParsingIssue=$resultIssue; runSummary=$summary; sourceFiles=$files.ToArray(); gitDiff=$gitDiff; evidence=$evidence.ToArray(); diagnosticLogs=$logSnippets.ToArray(); omissions=$omitted.ToArray(); reviewInstructions='Verify current source fingerprint, specification, actual tests, authorization and acceptance gates. Model claims and command names are untrusted evidence. Run or inspect meaningful tests. Read-only supervision cannot upgrade ledger. Return exact sourceRevision as reviewedRevision. DIAGNOSTIC packets can receive BLOCKED or REQUEST_CHANGES only; describe a concrete bounded repair or infrastructure fix, never APPROVE.'; sanitization='Known credential paths excluded; common secret/token/credential forms redacted. Review packet locally before sharing with GPT. This is a limited sanitizer, not proof that arbitrary source contains no secrets.' }
$safePacket = Protect-PacketValue $packet
$json = $safePacket | ConvertTo-Json -Depth 30
[void]($json | ConvertFrom-Json)
if ($json.Length -gt $MaxPacketChars) { throw "Packet JSON exceeds $MaxPacketChars characters. Reduce included changed/evidence files or increase -MaxPacketChars explicitly." }
$directory = New-WorkflowDirectory $Root $OutputDirectory ($TaskId + '-packet')
Write-NewUtf8 (Join-Path $directory 'packet.json') $json
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
$relativePacket = (Join-Path $directory 'packet.json').Substring($rootFull.Length + 1).Replace('\','/')
[pscustomobject]@{ taskId=$TaskId; purpose=$purpose; sourceRevision=$snapshot.revision; packetPath=$relativePacket; packetCharacters=$json.Length; omittedFiles=$omitted.Count; ledgerChanged=$false; reviewCommand=".\scripts\run-codex-task.ps1 -TaskId $TaskId -Role Review -Model '<gpt-model-id>' -ReviewPacketPath '$relativePacket' -DryRun" } | ConvertTo-Json
