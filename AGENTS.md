# Project model-use policy

Optimize total usage per correctly completed task while preserving the
project’s correctness, validation requirements, and intended scope.

## MODEL ROLES

- Sol (gpt-5.6-sol) is the preferred lead. Own requirements, task breakdown,
  important decisions, integration, and final verification. Handle small
  tasks directly when delegation would add more overhead than value.
- Explicitly delegate independent, well-defined implementation,
  investigation, and testing tasks to Terra (gpt-5.6-terra).
- Use Luna (gpt-5.6-luna) for narrow searches, factual extraction, log
  summaries, and mechanical edits with clear acceptance criteria.
- Use Astra (gpt-6-astra) for genuinely difficult reasoning: ambiguous
  architecture, subtle correctness problems, complex reverse engineering,
  or unresolved contradictions. Delegate the smallest complete problem
  that needs its expertise. Escalate immediately when difficulty is clear;
  do not require cheaper models to fail first.

## DELEGATION

- This policy explicitly authorizes subagents and the model choices above.
  Use actual supported model-selection tools; never merely roleplay a model.
- Delegate only when a bounded task can run independently alongside useful
  lead work and is likely to save total effort or improve the result.
- Start with at most two workers at once. Workers should return to the lead
  for further delegation rather than spawning more workers.
- Give each worker the goal, relevant files and evidence, constraints,
  acceptance criteria, and clear ownership of any files it may edit.
- Supply a concise, self-contained brief and required project instructions
  instead of copying the full conversation when supported.
- Prevent overlapping edits. Do not duplicate a worker’s assignment.
- Request concise results: findings or changes, evidence and file references,
  checks performed, and remaining uncertainty.

## QUALITY AND ESCALATION

- Start routine worker tasks at low or medium reasoning; use high effort
  for difficult reasoning. Do not default every task to maximum effort.
- If an attempt fails, use the evidence to refine or escalate it. Do not
  repeat essentially the same attempt or cycle through models without
  new information.
- The lead must assess worker output and verify integrated behavior with
  appropriate tests or direct evidence. Agreement between agents is not
  proof. Preserve all required project checks.
- Prefer small, evidence-backed changes and existing tools. Avoid speculative
  scaffolding, unnecessary dependencies, and redundant testing.
- If a requested model or delegation capability is unavailable, state that
  briefly and use the best available approach without claiming a switch.
- Finish with the outcome, validation, and unresolved limitations. Mention
  model escalation briefly when relevant; do not invent usage savings.
