[CmdletBinding()]
param([string]$Root)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
. (Join-Path $PSScriptRoot 'automation-verification.ps1')
$fixture = New-WorkflowDirectory $Root '' 'automation-verification-self-test'
$script:TestRoot = $fixture
$script:ForcedExitCode = $null
$script:ForcedTimeout = $false
$script:DistributionFailure = $false
$script:BuildExitCode = 0
$script:CapturedBuild = $null
$script:ConflictStage = $false
$script:UseJunctionStage = $false
$hostExecutable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

# Synthetic T01 distribution/build execution is explicit. Feature check scripts
# run in a real child PowerShell; these tests never invoke Maven or a model.
function Invoke-AutomationCommand {
    param([string]$Root,[string]$Command,[string[]]$Arguments,[string]$RunDirectory,[int]$MaxRunSeconds)
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $stdout = Join-Path $RunDirectory 'stdout.log'
    $stderr = Join-Path $RunDirectory 'stderr.log'
    $code = 0; $timedOut = $false; $out = ''; $err = ''
    if ($Arguments -contains '-RequestPath') {
        $requestPath = $Arguments[[array]::IndexOf($Arguments,'-RequestPath')+1]
        $request = Read-WorkflowJson $requestPath
        if ($script:DistributionFailure) { $code=8; $err='MOCK distribution mismatch' }
        else { Write-NewJson $request.report ([ordered]@{passed=$true;sha256=$request.sha256;mockOnly=$true}) }
        $out='MOCK official-download transport only'
    } elseif ($Command -match 'mvnw\.cmd$') {
        $script:CapturedBuild = [pscustomobject]@{root=$Root;arguments=$Arguments;maxRunSeconds=$MaxRunSeconds;wrapper=$Command}
        $code=$script:BuildExitCode
        $out='MOCK Maven build only; not application build evidence'
    } elseif ($script:ForcedTimeout) {
        $code=124; $timedOut=$true; $out='MOCK owned timeout'
    } elseif ($null -ne $script:ForcedExitCode) {
        $code=[int]$script:ForcedExitCode; $err='MOCK nonzero process exit'
    } else {
        $result = Invoke-NativeCapture $Command $Arguments
        $code=$result.exitCode; $out=$result.output
        if ($script:ConflictStage -or $script:UseJunctionStage) {
            $stage = Join-Path (Split-Path -Parent $RunDirectory) 'clean-stage'
            if ($script:UseJunctionStage) {
                [void](New-Item -ItemType Junction -Path $stage -Target (Join-Path $script:TestRoot 'src/junction-target'))
            } else { [void][IO.Directory]::CreateDirectory($stage) }
        }
    }
    Write-NewUtf8 $stdout $out
    Write-NewUtf8 $stderr $err
    return [pscustomobject]@{exitCode=$code;timedOut=$timedOut;stdoutPath=$stdout;stderrPath=$stderr;evidencePaths=@($stdout,$stderr);durationSeconds=0}
}

function New-TestPlan {
    param([string]$TaskId='T02',[string]$Script='scripts/verify/check.ps1',[string]$Evidence='docs/verification/T02/result.json')
    return [pscustomobject]@{taskId=$TaskId;goal='Synthetic workflow gate';allowedPaths=@('src/');steps=@('Run fixture assertion');verificationScripts=@($Script);acceptanceMapping=@([pscustomobject]@{criterion='Actual fixture assertion result exists';evidenceExpected=@($Evidence)});externalGates=@()}
}

function Invoke-TestVerification {
    param($Plan,[string]$TaskId='T02')
    return Invoke-AutomationVerification -Root $fixture -Task ([pscustomobject]@{id=$TaskId}) -Plan $Plan -RunDirectory ('docs/execution/runs/case-' + [Guid]::NewGuid().ToString('N')) -Config ([pscustomobject]@{verificationTimeoutSeconds=20})
}

$assertionScript = @'
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$source = Join-Path $root 'src/value.txt'
if ((Get-Content -LiteralPath $source -Raw).Trim() -ne 'four') { throw 'Independent fixture assertion failed.' }
$directory = Join-Path $root 'docs/verification/T02'
[void][IO.Directory]::CreateDirectory($directory)
[IO.File]::WriteAllText((Join-Path $directory 'result.json'),'{"assertion":"source value equals four","passed":true}')
exit 0
'@
Write-NewUtf8 (Join-Path $fixture 'scripts/verify/check.ps1') $assertionScript
Write-NewUtf8 (Join-Path $fixture 'src/value.txt') 'four'
Write-NewUtf8 (Join-Path $fixture 'docs/execution/task-ledger.json') '{"tasks":[]}'
Write-NewUtf8 (Join-Path $fixture 'docs/execution/task-ledger.md') 'Fixture ledger only'
Write-NewUtf8 (Join-Path $fixture 'docs/execution/next-step.md') 'Fixture next step only'
$results = New-Object 'System.Collections.Generic.List[object]'

$valid = Invoke-TestVerification (New-TestPlan)
if (-not $valid.passed) { throw ('Valid independent fixture check failed: ' + ($valid.failureReasons -join '; ')) }
$report = Read-WorkflowJson (Join-Path $fixture $valid.reportPath)
foreach ($item in @($report.evidence)) {
    if ((Get-FileHash -LiteralPath (Join-Path $fixture $item.path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.sha256) { throw 'Evidence hash does not match actual check output.' }
}
if ($report.taskApproval -ne 'REQUIRES_INDEPENDENT_GPT_REVIEW') { throw 'Execution gate claimed task approval.' }
$results.Add([pscustomobject]@{check='real assertion script, evidence hashes and separate review requirement';result='PASS'})

$emptyPlan = New-TestPlan
$emptyPlan.verificationScripts=@()
$empty = Invoke-TestVerification $emptyPlan
if ($empty.passed -or ($empty.failureReasons -join ' ') -notmatch 'Missing verificationScripts') { throw 'Empty check list was accepted.' }
$results.Add([pscustomobject]@{check='empty verification list rejected';result='PASS'})

Write-NewUtf8 (Join-Path $fixture 'scripts/verify/stub.ps1') "Write-Output 'PASS'`nexit 0"
$stub = Invoke-TestVerification (New-TestPlan -Script 'scripts/verify/stub.ps1')
if ($stub.passed -or ($stub.failureReasons -join ' ') -notmatch 'stub') { throw 'Generic success stub was accepted.' }
$results.Add([pscustomobject]@{check='success stub rejected';result='PASS'})

$outside = Invoke-TestVerification (New-TestPlan -Script '../outside.ps1')
if ($outside.passed -or ($outside.failureReasons -join ' ') -notmatch 'outside allowed directories') { throw 'Script traversal was accepted.' }
$results.Add([pscustomobject]@{check='script path escape rejected';result='PASS'})

$script:ForcedExitCode=9
$nonzero = Invoke-TestVerification (New-TestPlan)
$script:ForcedExitCode=$null
if ($nonzero.passed -or @($nonzero.checks | Where-Object {$_.name -match 'Feature verification' -and $_.details.exitCode -eq 9}).Count -ne 1) { throw 'Nonzero verification exit was hidden.' }
$results.Add([pscustomobject]@{check='nonzero check exit preserved and fails gate';result='PASS'})

$script:ForcedTimeout=$true
$timeout = Invoke-TestVerification (New-TestPlan)
$script:ForcedTimeout=$false
if ($timeout.passed -or @($timeout.checks | Where-Object {$_.name -match 'Feature verification' -and $_.details.timedOut -and $_.details.exitCode -eq 124}).Count -ne 1) { throw 'Timed-out verification was accepted.' }
$results.Add([pscustomobject]@{check='timeout exit 124 preserved and fails gate';result='PASS'})

$missing = Invoke-TestVerification (New-TestPlan -Evidence 'docs/verification/T02/absent.json')
if ($missing.passed -or ($missing.failureReasons -join ' ') -notmatch 'Missing verification file') { throw 'Missing acceptance evidence was accepted.' }
$results.Add([pscustomobject]@{check='missing criterion evidence rejected';result='PASS'})

$sourceEvidence = Invoke-TestVerification (New-TestPlan -Evidence 'src/value.txt')
if ($sourceEvidence.passed -or ($sourceEvidence.failureReasons -join ' ') -notmatch 'Acceptance evidence must be') { throw 'Source file was accepted as execution evidence.' }
$results.Add([pscustomobject]@{check='source cannot replace execution evidence';result='PASS'})

Write-NewUtf8 (Join-Path $fixture 'docs/verification/T02/stale.json') '{"passed":true,"scope":"Old fixture evidence"}'
[IO.File]::SetLastWriteTimeUtc((Join-Path $fixture 'docs/verification/T02/stale.json'),[DateTime]::UtcNow.AddDays(-1))
$stale = Invoke-TestVerification (New-TestPlan -Evidence 'docs/verification/T02/stale.json')
if ($stale.passed -or ($stale.failureReasons -join ' ') -notmatch 'Stale acceptance evidence') { throw 'Stale acceptance evidence was accepted.' }
$results.Add([pscustomobject]@{check='old criterion evidence must be refreshed by independent verification';result='PASS'})

$mutator = $assertionScript.Replace("exit 0", "[IO.File]::WriteAllText((Join-Path `$root 'src/value.txt'),'mutated')`nexit 0")
Write-NewUtf8 (Join-Path $fixture 'scripts/verify/mutate.ps1') $mutator
$mutation = Invoke-TestVerification (New-TestPlan -Script 'scripts/verify/mutate.ps1')
[IO.File]::WriteAllText((Join-Path $fixture 'src/value.txt'),'four')
if ($mutation.passed -or @($mutation.checks | Where-Object {$_.name -eq 'Verification preserves source and supervisor state' -and $_.details.unexpectedChangedPaths -contains 'src/value.txt'}).Count -ne 1) { throw 'Unexpected source mutation was accepted.' }
$results.Add([pscustomobject]@{check='verification source mutation rejected';result='PASS'})

$ledgerMutator = $assertionScript.Replace("exit 0", "[IO.File]::WriteAllText((Join-Path `$root 'docs/execution/task-ledger.md'),'forbidden PASS')`nexit 0")
Write-NewUtf8 (Join-Path $fixture 'scripts/verify/ledger-mutate.ps1') $ledgerMutator
$ledgerMutation = Invoke-TestVerification (New-TestPlan -Script 'scripts/verify/ledger-mutate.ps1')
[IO.File]::WriteAllText((Join-Path $fixture 'docs/execution/task-ledger.md'),'Fixture ledger only')
if ($ledgerMutation.passed -or @($ledgerMutation.checks | Where-Object {$_.name -eq 'Verification preserves source and supervisor state' -and $_.details.unexpectedChangedPaths -contains 'docs/execution/task-ledger.md'}).Count -ne 1) { throw 'Verification ledger mutation was accepted.' }
$results.Add([pscustomobject]@{check='supervisor ledger mutation rejected';result='PASS'})

$secretScript = $assertionScript.Replace('"passed":true','"passed":true,"api_key":"synthetic-secret-should-not-be-reported"')
Write-NewUtf8 (Join-Path $fixture 'scripts/verify/secret.ps1') $secretScript
$secret = Invoke-TestVerification (New-TestPlan -Script 'scripts/verify/secret.ps1')
if ($secret.passed -or ($secret.failureReasons -join ' ') -notmatch 'Credential indicator') { throw 'Credential-bearing evidence was accepted.' }
$results.Add([pscustomobject]@{check='credential indicator in evidence fails gate';result='PASS'})

foreach ($source in @('Booking_Application_Master_Execution_Plan.md','Booking_Backend_Local_Agent_Execution_Plan.md','Booking_Application_Design_and_Development.docx')) {
    Copy-Item -LiteralPath (Join-Path $Root $source) -Destination (Join-Path $fixture $source)
}
$t01Check = $assertionScript.Replace('docs/verification/T02','docs/verification/T01')
Write-NewUtf8 (Join-Path $fixture 'scripts/verify/t01.ps1') $t01Check
Write-NewUtf8 (Join-Path $fixture 'pom.xml') '<project><properties><java.version>25</java.version><spring-boot.version>4.1.1</spring-boot.version><spring-ai.version>2.0.1</spring-ai.version></properties><modules><module>modules/domain</module></modules></project>'
Write-NewUtf8 (Join-Path $fixture '.mvn/wrapper/maven-wrapper.properties') "distributionUrl=https://archive.apache.org/dist/maven/maven-3/3.10.0/binaries/apache-maven-3.10.0-bin.zip`ndistributionSha256Sum=$('a' * 64)"
Write-NewUtf8 (Join-Path $fixture 'mvnw.cmd') '@REM MOCK wrapper; never executed as a real Maven build'
Write-NewUtf8 (Join-Path $fixture 'mvnw') '# MOCK wrapper'
Write-NewUtf8 (Join-Path $fixture 'modules/domain/pom.xml') '<project><version>0.1.0</version></project>'
Write-NewUtf8 (Join-Path $fixture 'modules/domain/src/value.txt') 'Build source fixture'
Write-NewUtf8 (Join-Path $fixture 'modules/domain/target/stale.txt') 'Must not stage stale build output'
Write-NewUtf8 (Join-Path $fixture '.t01-stage-path.txt') 'C:\unrelated\must-never-be-read-executed-or-deleted'
Write-NewUtf8 (Join-Path $fixture 'docs/execution/dependency-manifest.json') '{"java":"25","maven":"3.10.0","springBoot":"4.1.1","springAI":"2.0.1","lookupDate":"2026-10-10","officialSources":["https://docs.spring.io/spring-boot/system-requirements.html"]}'
Write-NewUtf8 (Join-Path $fixture 'docs/adr/001-dependency-compatibility.md') ('# Dependency compatibility fixture' + "`n" + 'This is synthetic documentation for checking automation contracts only. Actual compatibility needs the official sources, the independent clean build and GPT review. Source: https://docs.spring.io/spring-boot/system-requirements.html')
$t01Plan = New-TestPlan -TaskId T01 -Script 'scripts/verify/t01.ps1' -Evidence 'docs/verification/T01/result.json'
$t01 = Invoke-TestVerification $t01Plan T01
if (-not $t01.passed) { throw ('Mock T01 flow failed: ' + ($t01.failureReasons -join '; ')) }
$stage = $script:CapturedBuild.root
if ($stage -notmatch '[\\/]docs[\\/]execution[\\/]runs[\\/]' -or (Test-Path -LiteralPath (Join-Path $stage 'modules/domain/target/stale.txt')) -or (Test-Path -LiteralPath (Join-Path $stage '.t01-stage-path.txt')) -or $script:CapturedBuild.arguments -notcontains 'clean' -or $script:CapturedBuild.arguments -notcontains 'verify') { throw 'Clean build staging or command contract failed.' }
if (-not (Test-Path -LiteralPath (Join-Path $fixture '.t01-stage-path.txt'))) { throw 'External staging pointer was altered.' }
$results.Add([pscustomobject]@{check='T01 independent hash/pin gates and clean-stage command (distribution/build mocked)';result='PASS'})

$script:ConflictStage=$true
$conflictingStage = Invoke-TestVerification $t01Plan T01
$script:ConflictStage=$false
if ($conflictingStage.passed -or ($conflictingStage.failureReasons -join ' ') -notmatch 'preexisting clean-stage') { throw 'Preexisting clean stage was reused.' }
$results.Add([pscustomobject]@{check='T01 preexisting clean stage rejected';result='PASS'})

Write-NewUtf8 (Join-Path $fixture 'src/junction-target/canary.txt') 'No writes through junction'
$canaryHash = (Get-FileHash -LiteralPath (Join-Path $fixture 'src/junction-target/canary.txt') -Algorithm SHA256).Hash
$script:UseJunctionStage=$true
$junctionStage = Invoke-TestVerification $t01Plan T01
$script:UseJunctionStage=$false
if ($junctionStage.passed -or ($junctionStage.failureReasons -join ' ') -notmatch 'reparse point' -or @(Get-ChildItem -LiteralPath (Join-Path $fixture 'src/junction-target') -Force).Count -ne 1 -or (Get-FileHash -LiteralPath (Join-Path $fixture 'src/junction-target/canary.txt') -Algorithm SHA256).Hash -cne $canaryHash) { throw 'Junction was followed or target changed.' }
$results.Add([pscustomobject]@{check='T01 junction stage rejected before any target writes';result='PASS'})

$script:BuildExitCode=7
$badBuild = Invoke-TestVerification $t01Plan T01
$script:BuildExitCode=0
if ($badBuild.passed -or @($badBuild.checks | Where-Object {$_.name -match 'actual clean-stage' -and $_.details.exitCode -eq 7}).Count -ne 1) { throw 'Failed clean Maven check was accepted.' }
$results.Add([pscustomobject]@{check='T01 failed build exit prevents passing (build mocked)';result='PASS'})

$script:DistributionFailure=$true
$badDistribution = Invoke-TestVerification $t01Plan T01
$script:DistributionFailure=$false
if ($badDistribution.passed -or @($badDistribution.checks | Where-Object {$_.name -match 'independent Maven distribution' -and -not $_.passed}).Count -ne 1) { throw 'Failed distribution checksum was accepted.' }
$results.Add([pscustomobject]@{check='T01 failed distribution proof prevents passing (download mocked)';result='PASS'})

$pomPath = Join-Path $fixture 'pom.xml'
$stablePom = Get-Content -LiteralPath $pomPath -Raw -Encoding UTF8
[IO.File]::WriteAllText($pomPath,$stablePom.Replace('4.1.1','4.1.1-RC1'))
$unstable = Invoke-TestVerification $t01Plan T01
[IO.File]::WriteAllText($pomPath,$stablePom)
if ($unstable.passed -or ($unstable.failureReasons -join ' ') -notmatch 'stable Spring Boot') { throw 'Unstable dependency baseline was accepted.' }
$results.Add([pscustomobject]@{check='T01 release-candidate dependency pin rejected';result='PASS'})

$sourcePath = Join-Path $fixture 'Booking_Application_Master_Execution_Plan.md'
[IO.File]::AppendAllText($sourcePath,"`nForbidden source alteration")
$badSource = Invoke-TestVerification $t01Plan T01
if ($badSource.passed -or @($badSource.checks | Where-Object {$_.name -eq 'T01 supplied source preservation' -and -not $_.passed}).Count -ne 1) { throw 'Changed original source was accepted.' }
$results.Add([pscustomobject]@{check='T01 immutable original-source hash prevents manifest substitution';result='PASS'})

$output = [ordered]@{schemaVersion='1.0';passed=$true;checks=$results.ToArray();checkCount=$results.Count;fixture=$fixture;scope='Automation regression tests only. Feature scripts use real child PowerShell; T01 Maven/download are synthetic mocks. No application acceptance or live model capability claimed.';powershellVersion=$PSVersionTable.PSVersion.ToString()}
Write-NewJson (Join-Path $fixture 'self-test-report.json') $output
$output | ConvertTo-Json -Depth 12
