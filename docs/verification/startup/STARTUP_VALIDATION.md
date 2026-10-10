# Development startup pack validation

Preparation date: 10 October 2026. This report evaluates support artifacts and development tooling. No booking application feature or release gate has run, and all T01–T42 remain TODO.

## Confirmed starting observations

The initial workspace contained only the three supplied design files. Codex CLI 0.162.1, LM Studio, Ollama, Git and Node were available. Java was missing on PATH. Docker CLI 29.8.0 was present while its Linux engine was unavailable. The source documents are preserved with SHA-256 records in `docs/sources/source-manifest.json`.

LM Studio's loopback `/v1/models` returned `qwen3.8-flash-next`, `qwen3.8-27b` and an embedding model. The owner selected LM Studio with an installed model. Ollama inventory worked through its CLI, but direct port 11434 inventory was unavailable at that observation.

## Local model capability trial

The isolated arithmetic fixture began with a deliberately incorrect seat-count function and ten independent behavioral assertions, including seven invalid-input cases. Its initial Node test exited 1 with actual 8 versus expected 5. The model was asked to read the fixture, edit only the function, run the unchanged tests and inspect the diff.

At 12:19:08 Europe/Berlin (10:19:08 UTC), Codex started against the loaded LM Studio `qwen3.8-flash-next`. It requested workspace-write, but the startup header displayed read-only. It also reported fallback model metadata and an inventory decode warning. LM Studio reported prompt processing for the 75.44 GB model, 262144-token context and four parallel slots. No tool event, code change or final message was observed during the bounded attempt. Only the scoped trial Codex process was stopped. LM Studio returned to IDLE.

The independent test afterward still exited 1 and the function was unchanged. Result: **development model capability NOT_VERIFIED; trial timed out**. This is neither a successful coding trial nor product gate V16. Observations and an unchanged synthetic fixture are saved in `local-model-trial.json`, `local-model-trial-observations.txt`, `local-model-fixture-test.txt` and `local-model-fixture/`.

The documented per-command MXC probe later printed `MXC_OK` and exited 0. It changed no saved configuration. This verifies that probe only; it does not retrospectively validate the trial's effective permissions. The workflow wrapper preserves user configuration and allows explicit Windows sandbox selection.

A read-only estimate for `qwen3.8-27b` at 32768 context/one parallel slot reported 21.73 GiB, while observed free system RAM was 10.1 GiB. No second model was loaded. Deliberately adjust the LM Studio load to a measured smaller configuration before retrying, rather than loading both models blindly.

## Artifact verification

The feature agent checked all 42 packet headings, catalog links and dependency sets against the master plan. T26 is the retained T01–T25 backend checkpoint. A20 is the final release precheck at T41; T42 owner acceptance is separate H01 to avoid a verification workflow cycle.

The architecture agent validated the blueprint schema and synthetic salon example with Draft 2020-12 `jsonschema` 4.25.1 in an isolated temporary dependency directory. Eight negative structures were rejected. Evidence with artifact hashes is in `docs/architecture/contract-validation.json`. These are structural startup-schema checks; semantic publication and application behavior remain T31 onward.

The final workflow suite passed thirteen checks on PowerShell 7.6.5 and Windows PowerShell 5.1.26100.9444 using an isolated mock CLI. It verified dependency rejection, strict result handling, safe JSON redaction, review transport, overwrite rejection, local PASS rejection, preserved nonzero exits, failure/timeout diagnostics, rejection of diagnostic approval and owned process termination. The suite also rejected a Markdown-ledger edit. Both ledger files are guarded against model edits. These tests establish wrapper behavior, not GPT availability or local model capability.

Final evidence is saved in `workflow-self-test-powershell-7.json`, `workflow-self-test-powershell-5.1.json`, `workflow-consistency.json`, `T01-preparation-preview.json`, `T01-execution-preview.json` and `tooling-manifest.json`. The consistency checker reports 42 tasks, an acyclic graph and only T01 dependency-ready. `pack-consistency.json` confirms all three source hashes, 493 authored local Markdown links, contract/example JSON parsing and gate coverage. `agent-doctor.json` preserves the observed missing Java/stopped Docker/reachable LM Studio states.

Application operator commands, migrations, browser journeys, live inference in the app, Compose/kind deployments, restore and scale remain NOT_RUN. No task was promoted by preparation tooling or the mock suite.

## Exact next action

Complete the bounded coding-model trial with effective workspace permissions, resolve Java 25, and execute T01 only. Use GPT-backed Codex to review the actual compatibility trial, build patch and command evidence. No dependency-ready T02 is claimed yet.
