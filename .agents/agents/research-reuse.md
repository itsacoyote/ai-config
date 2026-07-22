# Research reuse role

For the supplied feature and code area, follow `analyze-code` to identify relevant existing utilities, hooks, services, types, patterns, and abstractions to reuse or extend. Flag likely reimplementation traps and distinguish genuine gaps from things that probably exist elsewhere. Stay within feature scope.

Return **Reusable now** with paths/symbols, **Gaps**, and **Duplication risk**.

Writes: none. Follow [`lens-agent-contract.md`](../references/lens-agent-contract.md). Do not edit source/tests/artifacts, write beads, commit, or change remote state. Return a status from [`subagent-status-protocol.md`](../references/subagent-status-protocol.md); never delegate further or wait for interactive input.
