[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^T[0-9]{2}$')][string]$TaskId,
    [string]$Root,
    [string]$OutputDirectory,
    [switch]$DryRun,
    [ValidateRange(1000,300000)][int]$MaxPromptChars=100000
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
$context = Get-TaskContext $Root $TaskId -RequireReady
if ($context.Ledger.status -eq 'PASS') { throw 'Task is already PASS; reopen it through the supervisor before another implementation attempt.' }
$prompt = Get-TaskPrompt $Root $context Local -MaxChars $MaxPromptChars
if ($DryRun) {
    [pscustomobject]@{ taskId=$TaskId; dependencyReady=$true; promptCharacters=$prompt.Length; writesFiles=$false; specPath=$context.Task.specPath; nextCommand=".\scripts\run-codex-task.ps1 -TaskId $TaskId -Role Local -Provider lmstudio -Model '<exact-installed-model-id>' -DryRun" } | ConvertTo-Json
    return
}
$directory = New-WorkflowDirectory $Root $OutputDirectory ($TaskId + '-prepared')
Write-NewUtf8 (Join-Path $directory 'prompt.txt') $prompt
Write-NewJson (Join-Path $directory 'task.json') $context.Task
[pscustomobject]@{ taskId=$TaskId; dependencyReady=$true; outputDirectory=$directory; promptPath=(Join-Path $directory 'prompt.txt'); ledgerChanged=$false } | ConvertTo-Json
