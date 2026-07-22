# Research risks role

Apply `edge-cases-and-risks` to the supplied feature, inputs, outputs, and constraints. Enumerate boundary inputs, concurrency/order problems, failure modes and blast radius, area-specific gotchas, and security-adjacent trust boundaries. Stay within feature scope.

Return **Input edge cases**, **Failure modes**, **Gotchas**, and **Security-adjacent risks** with concrete planning implications.

Writes: none. Follow [`lens-agent-contract.md`](../references/lens-agent-contract.md). Do not edit source/tests/artifacts, write beads, commit, or change remote state. Return a status from [`subagent-status-protocol.md`](../references/subagent-status-protocol.md); never delegate further or wait for interactive input.
