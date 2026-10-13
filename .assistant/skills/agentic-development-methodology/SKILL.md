---
name: agentic-development-methodology
description: Agentic Development Methodology. Process rules for Plan and Build, not Pascal style. free-pascal-engineer wins on code shape, naming, forms, registration, and Git commits.
when-to-use: Plan and Build, next to free-pascal-engineer. Not Chat, and not a question that is only about Pascal formatting.
modes: plan, build
---

# Agentic Development Methodology

Process only. Pascal, Lazarus, and Michell Computing style in `free-pascal-engineer` win on code shape. Git commit shape, global registration, forms, and naming stay in that skill and are not restated here.

Do not apply a skill named BEHAVE on the same turn as this one. If a user-level `~/.grok/skills/BEHAVE` copy exists, leave that directory until asked to retire the name.

Wording: Must / never is mandatory. Should / prefer is a strong default. May is optional.

- Trivial task: a small, local change with clear intent, low risk, and reversible by discarding the change without cascading consequences. A trivial task stays trivial. Do not open a pre-implementation questionnaire for a one-line fix.
- Minor or contained ambiguity: uncertainty that does not affect external behavior, interfaces, stored data, safety, or reversibility.
- Harmful pattern: an existing pattern that materially reduces clarity, correctness, maintainability, or safe implementation.
- Working code: code that currently satisfies its observable purpose, even if it is imperfect internally.

When rules pull in different directions:

1. Host safety rules, then the active mode contract. Plan writes the plan and does not edit source. Build is the go-ahead and implements. An explicit instruction does not override either.
2. An explicit instruction in the current request or the active plan, including a commit that instruction already authorizes.
3. `free-pascal-engineer` for Pascal, Lazarus, and Michell Computing style.
4. The process rules in this skill.
5. Generic advice.

Before acting on a risky assumption, state it. Do not pick a source or an interpretation silently when the choice affects behaviour, interfaces, data, or safety. For a minor or contained ambiguity, proceed and state the assumption.

If the baseline is already broken, say so before changing code, define success against that baseline, and do not claim full verification while unrelated failures remain.

After non-trivial work, report what changed, what was verified, what was not verified, and what was noticed and left untouched.

A hard-stop citation does not outrank the mode contract or an explicit instruction.
