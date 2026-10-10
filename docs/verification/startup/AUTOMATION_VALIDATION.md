# Automatic controller validation

Verified on 10 October 2026, before the live development campaign. These are controller regression results, not application task acceptance. The three supplied source files retain their recorded SHA-256 hashes, and isolated tests preserved both actual application ledgers.

| Suite | Cases | PowerShell 7.6.5 | Windows PowerShell 5.1 |
| --- | ---: | --- | --- |
| Environment and local admission | 21 | PASS | PASS |
| Actual bounded process helpers | 24 | PASS | PASS |
| Sequential campaign, failover and recovery | 25 | PASS | PASS |
| Independent verifier and clean-stage safeguards | 19 | PASS | PASS |

All 89 cases passed on both hosts. The existing workflow suite also passed its 13 cases on PowerShell 7. Workflow validation found 42 tasks, an acyclic dependency graph, synchronized ledgers, valid scripts and all feature packets. Canonical extraction retains 160 original acceptance criteria and 435 allowed-path entries.

Process tests use real owned child PowerShell processes and an isolated mock Codex CLI. Local admission tests execute real Node assertions but mock model responses. Campaign tests execute the actual controller loop against isolated two-task fixtures, mocked providers/environment and synthetic verifier evidence. Verifier tests use real child PowerShell for feature checks; Maven distribution/download/build are mocked. No suite promotes a real application task, demonstrates live model capability or establishes a clean application build.

Evidence:

- Environment: [PS7 report](../../execution/runs/automation-environment-test-20261010T153149864Z-d14972ef/self-test-summary.json), [PS5.1 report](../../execution/runs/automation-environment-test-20261010T153055351Z-409c6cbd/self-test-summary.json).
- Processes: [PS7 report](../../execution/runs/automation-core-test-20261010T154006049Z-2113b093/self-test-summary.json), [PS5.1 report](../../execution/runs/automation-core-test-20261010T154055265Z-adfa2180/self-test-summary.json).
- Campaign: [PS7 report](../../execution/runs/controller-selftest-20261010T154437082Z-dd257cd2/controller-self-test.json), [PS5.1 report](../../execution/runs/controller-selftest-20261010T154437572Z-1acb3ffe/controller-self-test.json).
- Verifier: [PS7 report](../../execution/runs/automation-verification-self-test-20261010T154653607Z-98806f2f/self-test-report.json), [PS5.1 report](../../execution/runs/automation-verification-self-test-20261010T154704178Z-a20861f4/self-test-report.json).

Run `scripts/test-automation-environment.ps1`, `scripts/test-automation-core.ps1`, `scripts/test-automation-controller.ps1`, `scripts/test-automation-verification.ps1` and `scripts/test-workflow.ps1` before changing controller protocols. Run `scripts/verify-workflow.ps1` for artifact integrity. Live acceptance separately requires the actual independent verification and GPT review recorded by `scripts/start-development.ps1`.
