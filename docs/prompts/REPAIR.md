# Focused repair prompt

Resume only task Txx and the named finding from the latest GPT review. Read the task packet and actual failed command output. State the reproduced root cause, change the smallest relevant scope, rerun the failing behavior and necessary regression checks, then produce a new evidence report. Preserve unrelated changes and original acceptance criteria. Do not relax tenant, approval, allocation or simulator constraints. Do not mark PASS.

If the same root cause has failed twice, stop speculative repairs and write a diagnostic packet containing: expected versus actual behavior, minimal synthetic reproduction, command/exit code, environment and source revision, relevant source/patch, attempted fixes and a specific question for the GPT supervisor. Redact secrets and capabilities.
