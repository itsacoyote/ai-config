---
name: wait-what
description: Use when a reply lost you — re-pitches the assistant's last message with brief context first, in ASD-STE100 Simplified Technical English, using the project's own vocabulary.
disable-model-invocation: true
---

# Wait, What?

Wait — I don't understand where you've got to here. Re-pitch your last message:

1. Two or three sentences of context first — what we're doing and why this step exists.
2. Then the point itself, in ASD-STE100 Simplified Technical English: short sentences,
   one idea per sentence, active voice, no idioms.
3. Use the project's own vocabulary (its `CLAUDE.md` / `AGENTS.md`, docs) — not synonyms
   you invented mid-conversation.
4. Keep the global reply shape: outcome first, **Your move:** last.

Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT).
