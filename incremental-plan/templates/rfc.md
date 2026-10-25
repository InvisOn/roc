# <Title>

<!-- Soft limits: aim for about 140 lines for a step with no decisions,
300 for a step with decisions, and 450 for a branch. Each section's
"Aim" line is a guide, not a rule. If a section runs long, move shared
context to Background and trim command output to the lines that matter. -->

- **Status:** Draft | Review | Accepted | Done
- **Scope:** Branch | Step
- **Plan row:** <#> <name>
- **Branch:** <branch>
- **Fork PR:** <#N or "not yet">
- **Parent:** <the branch doc, for a step; "none" for a branch>
- **Base:** <upstream commit>
- **Head:** <commit the doc describes>

## Abstract

> One paragraph: what this brings in, the decisions it needs, the recommended
> answers, and how it is shown not to change what it must not change.
> Aim: one paragraph, about 8 lines.

## Problem

> Why this change is needed now, and what goes wrong without it.
> Aim: about 15 lines for a step, 20 for a branch.

### Breakages you can run

> Commit: <hash>. For each example: the directory to run from, the commands
> (one per line), the output you get, the output that's right, and the
> file:line that causes it. If nothing can be run yet, say why.
> Aim: about 50 lines for a step, 60 for a branch. Show only the output lines
> that matter.

## What this enables

> What becomes possible beyond fixing the breakages: later plan steps it
> unblocks, other targets or work that benefit (for upstream as well as for
> arm32), and tools or tests it makes possible. Mark each item as either
> "follows directly" or "possible later, not planned".
> Aim: about 10 lines for a step, 25 for a branch.

## Background

> What a reader needs to follow the rest: terms, the source commits on the
> reference branch, earlier decisions, links to primers.
> Aim: about 20 lines for a step, 40 for a branch.

## Discussion

> The constraints that narrow the choices (AGENTS.md rules, output unchanged,
> review size, plan order).
> Aim: about 10 lines for a step, 15 for a branch.

### Alternatives considered

> Whole approaches the constraints rule out. One line each, plus "Rejected
> because" (one or two lines, citing a constraint above). If one needs more,
> it's still open: move it to Decisions. "None" is fine.
> Aim: about 3 lines per alternative, 20 lines in all.

- **<alternative>.** Rejected because <reason>.

## Decisions

<!-- Aim: about 20 lines per decision. Shared context goes in Background. -->

### D1. <question>

- **Status:** Proposed | Accepted | Rejected | Superseded by <Dn>
- **Context:** <why this question comes up>
- **Alternatives:**
  1. <option>. Implications: <review size, conflicts, later steps, tests>
  2. <option>. Implications: …
- **Recommendation:** Alternative <n>.
- **Consequences:** <what follows from the choice, good and bad>

### D2. …

## Risks

<!-- Aim: about 7 lines per risk, 35 lines for a step, 50 for a branch. -->

### R1. <what could go wrong>

- **Likelihood:** Low | Medium | High
- **Impact:** Low | Medium | High
- **How we'd notice:** <the test, check or review step that would catch it,
  or "nothing would catch it" if so>
- **Mitigation:** <what we do to make it less likely or less harmful>
- **If it happens:** <what we do then>

### R2. …

## Testing

> What proves it works, with the commands (one per line, with the directory
> to run from) and the expected output.
> Aim: about 25 lines for a step, 40 for a branch. Show only the output lines
> that matter.

## Recommendation

> All decisions together, and the commit list (or sub-step list) that follows.
> Aim: about 15 lines for a step, 40 for a branch (with the sub-step list).
