[CmdletBinding()]
param([string]$Root)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
$checks = New-Object 'System.Collections.Generic.List[object]'
foreach ($name in @('codex','git','java','docker','ollama')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    $checks.Add([pscustomobject]@{ name=$name; state=$(if ($command) {'FOUND'} else {'MISSING'}); path=$(if ($command) {$command.Source} else {$null}) })
}
try { $cli = Get-CodexCommand; $checks.Add([pscustomobject]@{ name='codex-flags'; state='OK'; detail=$cli.version }) }
catch { $checks.Add([pscustomobject]@{ name='codex-flags'; state='BLOCKED'; detail=$_.Exception.Message }) }
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $docker = Invoke-NativeCapture 'docker' @('info','--format','{{.ServerVersion}}')
    $checks.Add([pscustomobject]@{ name='docker-engine'; state=$(if ($docker.exitCode -eq 0) {'RUNNING'} else {'STOPPED_OR_UNREACHABLE'}); detail=$docker.output.Trim() })
}
foreach ($provider in @('ollama','lmstudio')) {
    try { $inventory = Get-LocalModelInventory $provider; $checks.Add([pscustomobject]@{ name=$provider; state='REACHABLE'; detail=$inventory }) }
    catch { $checks.Add([pscustomobject]@{ name=$provider; state='UNREACHABLE_OR_OVERRIDE'; detail=$_.Exception.Message }) }
}
try {
    $manifest = Read-WorkflowJson (Resolve-WorkspacePath $Root 'contracts/tasks.json' -MustExist)
    $ledger = Read-WorkflowJson (Resolve-WorkspacePath $Root 'docs/execution/task-ledger.json' -MustExist)
    $checks.Add([pscustomobject]@{ name='workflow'; state='FOUND'; tasks=@($manifest.tasks).Count; ledgerTasks=@($ledger.tasks).Count })
} catch { $checks.Add([pscustomobject]@{ name='workflow'; state='BLOCKED'; detail=$_.Exception.Message }) }
[pscustomobject]@{ readOnly=$true; observedAtUtc=[DateTime]::UtcNow.ToString('o'); powershell=$PSVersionTable.PSVersion.ToString(); checks=$checks.ToArray(); nextStep='Choose an exact installed model ID. Reachability is not a tool-use compatibility test. Install JDK/start Docker before runtime-dependent tasks. No packages, models, services, or configuration were changed.' } | ConvertTo-Json -Depth 10
