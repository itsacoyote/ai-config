# Code Smells — the Fowler Baseline

A fixed set of code smells (Fowler, _Refactoring_, ch. 3) used as a review baseline. It applies to every diff, even in a repo that documents no coding standards of its own. Canonical here; `efficiency-review` and `senior-review` link to it rather than restating it.

## Binding rules

- **The repo overrides.** A documented repo standard (CONTRIBUTING.md, CODING_STANDARDS.md, a rules file) always wins; where it endorses something the baseline would flag, suppress the smell.
- **Always a judgment call.** Each smell is a labelled heuristic ("possible Feature Envy"), never a hard violation. Report it as a smell with the hunk quoted; don't present it as a rule breach.
- **Skip anything tooling already enforces.** Formatters, linters, and typecheckers catch their own class of problems mechanically — review effort belongs on the judgment calls they can't make.

## The smells

Each reads *what it is* → *how to fix*; match against the diff under review:

- **Mysterious Name** — a function, variable, or type whose name doesn't reveal what it does or holds. → rename it; if no honest name comes, the design's murky.
- **Duplicated Code** — the same logic shape appears in more than one hunk or file in the change. → extract the shared shape, call it from both.
- **Feature Envy** — a method that reaches into another object's data more than its own. → move the method onto the data it envies.
- **Data Clumps** — the same few fields or params keep travelling together (a type wanting to be born). → bundle them into one type, pass that.
- **Primitive Obsession** — a primitive or string standing in for a domain concept that deserves its own type. → give the concept its own small type.
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type recurs across the change. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery** — one logical change forces scattered edits across many files in the diff. → gather what changes together into one module.
- **Divergent Change** — one file or module is edited for several unrelated reasons. → split so each module changes for one reason.
- **Speculative Generality** — abstraction, parameters, or hooks added for needs the spec doesn't have. → delete it; inline back until a real need shows.
- **Message Chains** — long `a.b().c().d()` navigation the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man** — a class or function that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest** — a subclass or implementer that ignores or overrides most of what it inherits. → drop the inheritance, use composition.

## Overlap with the YAGNI/simplification criteria

**Speculative Generality** and **Middle Man** restate ideas the `efficiency-review` criteria already carry ("abstraction with no second user", "redundant indirection") — same finding, and the smell label just names it. Don't double-report: one finding, cite whichever framing fits the fix.
