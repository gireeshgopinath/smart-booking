# Development decisions and open inputs

| Decision | Baseline | Status and reason |
| --- | --- | --- |
| Governing scope | Master v2 whole application; backend v1 retained contracts | Adopted from explicit source precedence |
| Repository root | Current booking workspace; no nested checkout | Adopted to keep artifacts, source and later app together |
| Task completion | Executed acceptance checks plus GPT review, tied to source | Adopted from evidence contract; implementer cannot self-approve |
| T26 dependency wording | T01–T25 only | Clarification of retained backend checkpoint; avoids T41 cycle |
| Initial task state | All T01–T42 TODO | Observed absence of implementation |
| Technology | Java 25, stable Boot 4.x, compatible Spring AI, React/TypeScript | Retained source baseline; actual dependency versions resolved in T01/T27 |
| Cache | Valkey | Design document selection within original Redis/Valkey option |
| Local model | Explicit provider plus exact served model ID | Both providers supported; compatibility and quality require a trial |
| Hosted GPT reviewer | Current signed-in Codex model, or explicitly selected available model | Avoid inventing an account model ID; no API key required merely to use this existing chat |
| Product AI versus coding AI | Separate runtimes, budgets and permissions | Development Codex shell tools never become product tools |
| Missing pack | Reconstructed baselines with provenance labels | Original R01–R30 definitions, A01–A20 document and starter schema absent |

## Inputs that do not block foundation work

The owner chooses pilot geography, launch language bundle, live calendar/SMTP test accounts, production issuer, cloud account/region, resource budget and subscription strategy before pilot activation. Use English and synthetic low-sensitivity demo records during implementation; T30 adds a second-language test bundle without asserting a commercial launch language. Real billing remains excluded.

Actual Java installation and Docker engine activation are environment work required for the relevant build/integration gates. No source task is marked complete because the tools merely exist. Launch-model selection and measured capacity can be revisited after the local capability trial and the first accepted slice.
