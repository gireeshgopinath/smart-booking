# Initial repository assessment

Assessed on 10 October 2026 before application implementation. The workspace initially contained two Markdown execution plans and one Word design document. It contained no `.git` repository, source code, Maven/Node build, dependency lock, Compose configuration or application test suite. Nothing reusable can be claimed beyond the supplied design material.

The startup pack adds instructions, contracts, feature packets, ledger, prompts and development support scripts. These are preparation artifacts. T01 still requires a real pinned build baseline and review.

## Observed workstation

| Item | Observed state |
| --- | --- |
| Workspace | `C:\Users\giree\OneDrive\Desktop\booking` |
| Codex CLI | 0.162.1; local `exec --help` supports OSS providers, sandbox, output schema and final-message file |
| Ollama CLI | 0.34.2; nine local models listed, including `qwen3.5:9b`; `gpt-oss` absent |
| Ollama server | Loopback port 11434 refused direct HTTP inventory during assessment |
| LM Studio CLI | commit `69d945a`; local models include `qwen3.8-27b` and loaded `qwen3.8-flash-next` |
| LM Studio server | Loopback `/v1/models` returned those IDs plus an embedding model; inventory alone does not prove Codex tool compatibility |
| GPU | NVIDIA GeForce RTX 5080 Laptop GPU; 16,303 MiB reported by `nvidia-smi` |
| System memory | 95.4 GiB reported by CIM; available memory during workloads unmeasured |
| Docker CLI | 29.8.0; Linux engine named pipe unavailable at assessment |
| Java and Maven | Not found on current PATH; Maven will be supplied by the wrapper, JDK still required |
| Other tools | Node, npm, Python, uv and Git present; application-compatible versions not yet locked |

These are a point-in-time inventory, not claims that services are configured correctly or fit in memory. Re-run the doctor before work. Inspect any later Git initialization and preserve original files. Root layout is an adopted clarification of the older nested-layout suggestion.

## T01 remaining work

Select and validate a Java 25 toolchain and stable compatible Spring Boot/Spring AI combination using official version documentation. Create the Maven wrapper and minimal build configuration in this root. Lock actual plugin versions and record the trial. Establish a reproducible clean build and evidence. Inspect the frontend requirements but leave the React framework lock to T27, as assigned by the master plan. Review the actual patch and command output before accepting T01.

## T01-S01 implementation assessment — 10 October 2026 UTC

This dated section supplements the historical preparation assessment above. The
current automatic work order authorizes full T01 in bounded sessions. This session
implements only the inventory and preservation slice; no parent acceptance or T02
readiness is asserted. Implementation uses the controller-authorized GPT failover.

The root already contains unreviewed POMs, Maven wrapper scripts/properties, two
build-only modules, Java baseline tests and historical build/formatting logs.
The implementer preserves those files. The existing tests check JVM feature, class-file target,
Jackson resolution/roundtrip and basic record validation. They do not yet establish
the required provider-free Boot context or Spring AI converter compatibility.
Pinned declarations and historical transcripts remain unverified until S02–S04.
No dependency manifest or T01 baseline ADR existed at this session's start.

Current direct probes observe Temurin Java runtime `25.0.4.1+1-LTS` and javac
`25.0.4.1`, standalone Maven missing, Git status/revision commands exiting 128
because this root has no repository, and Docker version exiting 1 with daemon
access denied. No Git initialization, prerequisite installation, inference,
model download or service restart is performed. Loopback TCP probes are inventory
only and never imply authenticated health or working model inference.

`scripts/verify/verify-T01-inventory.ps1` defaults to this workspace without
parameters. It reads the Word document's paragraphs and table cells directly from
OOXML, reconciles Master T01–T42 and backend T01–T26 headings against task index and
packets, compares all three original documents' bytes/SHA-256 to the immutable
source manifest, and lists adopted replacements separately from supplied files.
Original R01–R30 definitions and twelve original ADRs remain unrecovered.

Fresh output is written to `docs/verification/T01/independent/`, with unique
inventory runs and archives of previous verifier-owned output under
`docs/verification/T01/inventory-runs/`. Each report records UTC times, command,
environment and a reproducible no-Git source fingerprint. Fingerprint inputs omit
generated outputs, caches, credential paths and reparse points. Private live
controller outputs are listed by metadata with null hashes, without reading active
transcripts or lock bytes. Historical test junctions are listed without following
them; source junctions and reparse points in output/input paths are rejected.

The controller's latest available planning `before-source.json` supplies the
starting preservation basis while its implementation snapshot is pending. The
audit checks unrelated covered files and records its exclusions explicitly.
The preexisting root `.t01-neg-exits.json` is a generated historical diagnostic
created after that planner snapshot and present in this session's starting
capture; it is preserved and inventoried. Staging-pointer metadata is retained
without resolving or reusing its external locations. The session's own starting
source and protected-file captures are under
`docs/verification/T01/session-s01-20261010T155804479Z/`.

S02 official compatibility/checksum verification, S03 library compatibility tests,
S04 clean isolated build and failure controls, S05 secret scanning and S06 complete
independent verification/review remain mandatory. Inventory success alone cannot
accept T01. No ledger, next-step, controller, protocol, source plan, feature packet
or human acceptance record is changed by this slice.

Preservation blocker observed during the slice: the historical
`negatives/D-wrapper-checksum-mismatch.log` changed from 522 to 839 bytes at
`2026-10-10T16:04:30.2465191Z`, referencing a new external Temp invocation.
The inventory-only controls do not run Maven or write this log. Its current bytes
are retained; the final preservation audit must fail on this mismatch. Investigate
the unrelated writer before asserting preservation or parent acceptance. The
read-only review and minimal diagnostic are recorded in the T01 review packet.
