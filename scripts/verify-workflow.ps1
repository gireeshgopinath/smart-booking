[CmdletBinding()]
param([string]$Root, [int]$ExpectedTaskCount=42)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
$manifest = Read-WorkflowJson (Resolve-WorkspacePath $Root 'contracts/tasks.json' -MustExist)
$ledger = Read-WorkflowJson (Resolve-WorkspacePath $Root 'docs/execution/task-ledger.json' -MustExist)
if ([string]$manifest.schemaVersion -notin @('1','1.0') -or [string]$ledger.schemaVersion -notin @('1','1.0')) { throw 'Unsupported manifest or ledger schemaVersion.' }
$tasks = @($manifest.tasks)
if ($tasks.Count -ne $ExpectedTaskCount) { throw "Expected $ExpectedTaskCount tasks; found $($tasks.Count)." }
$byId = @{}
foreach ($task in $tasks) {
    if ($task.id -notmatch '^T[0-9]{2}$' -or $byId.ContainsKey($task.id)) { throw "Invalid or duplicate task ID: $($task.id)" }
    if (-not $task.title -or -not $task.specPath) { throw "Missing task title or specPath: $($task.id)" }
    if (Test-SensitivePath $task.specPath) { throw 'Feature spec cannot be a credential file.' }
    $spec = Get-BoundedText $Root $task.specPath 90000
    if (-not $spec.Contains($task.id)) { throw "Spec does not identify task $($task.id)." }
    $byId[$task.id] = $task
}
foreach ($task in $tasks) {
    foreach ($dep in @($task.dependencies)) {
        if (-not $byId.ContainsKey($dep) -or $dep -eq $task.id) { throw "Invalid dependency $dep in $($task.id)." }
    }
}
$marks = @{}
function Visit-Task {
    param([string]$Id)
    if ($marks.ContainsKey($Id)) {
        if ($marks[$Id] -eq 'VISITING') { throw "Dependency cycle at $Id" }
        return
    }
    $marks[$Id] = 'VISITING'
    foreach ($dep in @($byId[$Id].dependencies)) { Visit-Task $dep }
    $marks[$Id] = 'DONE'
}
foreach ($task in $tasks) { Visit-Task $task.id }
if (@($ledger.tasks).Count -ne $tasks.Count) { throw 'Task manifest and ledger counts differ.' }
$ledgerIds = @{}
foreach ($row in @($ledger.tasks)) {
    if (-not $byId.ContainsKey($row.id) -or $ledgerIds.ContainsKey($row.id)) { throw "Unknown or duplicate ledger task: $($row.id)" }
    $ledgerIds[$row.id] = $true
    if ($row.status -notin @('TODO','IN_PROGRESS','PASS','FAIL','BLOCKED')) { throw "Unknown task ledger status: $($row.status); model result statuses belong in run reports." }
    if ($row.reviewStatus -notin @('PENDING','APPROVED','CHANGES_REQUIRED')) { throw "Unknown review status: $($row.reviewStatus)" }
    if ($row.attempts -lt 0) { throw 'Attempt count cannot be negative.' }
    if ($row.status -eq 'PASS') {
        if ($row.reviewStatus -ne 'APPROVED' -or -not $row.revision -or @($row.evidence).Count -eq 0) { throw "PASS task lacks review/revision/evidence: $($row.id)" }
        [void](Get-TaskContext $Root $row.id -RequireReady)
        foreach ($item in @($row.evidence)) {
            $path = if ($item -is [string]) { $item } else { $item.path }
            [void](Resolve-WorkspacePath $Root $path -MustExist)
        }
    }
}
foreach ($schemaPath in @('contracts/local-result.schema.json','contracts/review-result.schema.json')) {
    $schema = Read-WorkflowJson (Resolve-WorkspacePath $Root $schemaPath -MustExist)
    if ($schema.type -ne 'object' -or $schema.additionalProperties -ne $false -or @($schema.required).Count -eq 0) { throw "Result schema is not a strict object: $schemaPath" }
}
$parseErrors = New-Object 'System.Collections.Generic.List[string]'
foreach ($script in @(Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1' -File)) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    foreach ($errorItem in @($errors)) { $parseErrors.Add($script.Name + ': ' + $errorItem.Message) }
}
if ($parseErrors.Count -gt 0) { throw ($parseErrors -join "`n") }
$linkCount = 0
$snapshot = Get-SourceSnapshot $Root
$markdownPaths = @($snapshot.files | Where-Object { $_.path -like 'docs/*.md' -or $_.path -in @('README.md','AGENTS.md') } | ForEach-Object {$_.path})
foreach ($metadataPath in @('docs/execution/task-ledger.md','docs/execution/next-step.md')) {
    if (Test-Path -LiteralPath (Join-Path $Root $metadataPath)) { $markdownPaths += $metadataPath }
}
foreach ($relative in @($markdownPaths | Sort-Object -Unique)) {
    $filePath = Resolve-WorkspacePath $Root $relative -MustExist
    $markdown = [IO.File]::ReadAllText($filePath, [Text.Encoding]::UTF8)
    foreach ($match in [regex]::Matches($markdown, '\[[^\]]+\]\((?<target><[^>]+>|[^\s\)]+)(?:\s+"[^"]*")?\)')) {
        $target = $match.Groups['target'].Value.Trim([char[]]'<>')
        if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $target.StartsWith('#')) { continue }
        $target = [Uri]::UnescapeDataString(($target -split '#',2)[0])
        $linkedPath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $filePath) $target))
        $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
        if (-not $linkedPath.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Documentation link leaves workspace: $relative -> $target" }
        if (-not (Test-Path -LiteralPath $linkedPath)) { throw "Broken documentation link: $relative -> $target" }
        $linkCount++
    }
}
$ready = @($tasks | Where-Object { $taskToCheck=$_; $notReady=@($taskToCheck.dependencies | Where-Object { $depId=$_; @($ledger.tasks | Where-Object {$_.id -eq $depId -and $_.status -eq 'PASS' -and $_.reviewStatus -eq 'APPROVED'}).Count -ne 1 }); $notReady.Count -eq 0 } | ForEach-Object {$_.id})
[pscustomobject]@{ valid=$true; taskCount=$tasks.Count; graph='ACYCLIC'; specs='ALL_EXIST'; ledger='CONSISTENT'; scripts='PARSE_OK'; documentationLinks=$linkCount; dependencyReady=$ready; applicationImplemented=$false; note='This check validates planning/workflow artifacts only. Runtime and feature acceptance are separate.' } | ConvertTo-Json -Depth 10
