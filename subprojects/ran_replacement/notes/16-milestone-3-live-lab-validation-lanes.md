# Milestone 3 Live-Lab Validation Lanes

Status: draft

## Goal

Turn the milestone-2 standards baseline and public-surface claim set into
reviewable live-lab validation lanes for the declared
`n79_single_ru_single_ue_lab_v1` profile.

This note does not widen the supported interface subset. It defines how the
repo proves the already-declared claim set in a real lab and how operators
review the resulting evidence.

## Milestone Boundary

- Milestone 2 answers which public surfaces and standards-subset behaviors are
  claimed. Its inputs live in notes `05` through `12`.
- Milestone 3 answers what real-lab proof makes those claims credible and
  operator-reviewable. Its inputs live in notes `13` through `16`.
- If a change widens the supported standards subset or changes the claimed
  interface vocabulary, it is milestone-2 work, not milestone-3 validation
  work.
- If a change affects how a real-lab run is prepared, reviewed, summarized, or
  accepted, it is milestone-3 work.

## Lane 1: Target-Host And Operator Workflow Validation

Purpose:

- prove the lane can be prepared, executed, and rolled back in a real lab
  without hidden operator steps

Scope:

- target-host readiness, RU readiness, UE readiness, and core-link readiness
- `precheck -> plan -> apply -> verify -> capture-artifacts -> rollback`
- failure classes and first-debug-artifact routing

Primary notes:

- `03-target-host-readiness-and-lab-gates.md`
- `13-milestone-1-acceptance-runbook.md`

Evidence expectations:

- `precheck` names the target profile, core endpoint, RU or UE assumptions, and
  rollback target
- the operator sequence has explicit go or no-go checks at each mutable step
- failure classes point to the first artifact a reviewer should inspect
- soak window and retry rules are named instead of implied

Review question:

- can an operator explain why a run is `blocked`, `degraded`, or `pass`
  without SSH archaeology?

## Lane 2: Live-Lab Acceptance Dossier And Operator Evidence Bundle

Purpose:

- package the live-lab outcome into an operator-readable acceptance dossier
  that connects real-lab observations to the declared public-surface claims

Scope:

- compare report
- rollback evidence
- attach, registration, PDU session, and ping summary
- compatibility-claim cross-reference
- acceptance reviewer checklist

Primary notes:

- `14-compare-report-and-rollback-evidence-templates.md`

Evidence expectations:

- every live-lab pass or fail statement cites a compare report, rollback
  artifact, or explicit request or status artifact
- the dossier says whether each claim is only standards-baseline defined or is
  now live-lab validated
- the dossier stays readable without raw log access

Review question:

- can a reviewer tell which claim was proven, which claim remains baseline-only,
  and why?

## Lane 3: Dashboard And Remote-Run Claim Surface Review

Purpose:

- keep UI and remote-run surfaces honest about the difference between
  compatibility claims and live-lab proof

Scope:

- mission cards, inspector views, and remote-run summaries
- vocabulary for `blocked`, `degraded`, `pass`, `compatibility-defined`, and
  `live-lab validated`
- negative-space rules that prevent overclaiming

Primary notes:

- `15-dashboard-fixture-mapping.md`

Evidence expectations:

- each surface names the claim category it is reporting
- failure summaries point to the first blocked interface and the next artifact
  to inspect
- remote-run summaries keep `rollback_target`, `gate_class`, and the
  first-failed interface visible

Review question:

- do operator-facing surfaces distinguish declared compatibility from proven
  live-lab validation?

## Lane Review Order

1. Confirm the milestone-2 claim set and public-surface vocabulary are frozen.
2. Review Lane 1 so live runs are bounded and auditable.
3. Review Lane 2 so acceptance evidence is bundled and replayable.
4. Review Lane 3 so operator-facing surfaces report the correct claim category.

## Exit Rule

Milestone 3 validation is ready for implementation only when:

- the lane split above is explicit in repo docs
- each lane has named evidence expectations
- operator-facing acceptance bundle requirements are reviewable without hidden
  lab knowledge
- dashboard and summary surfaces cannot imply live-lab proof when only
  standards-baseline evidence exists

## Non-Goals

- redefining the standards subsets from notes `05` through `12`
- widening interface claims beyond the milestone-2 baseline
- replacing runtime hot paths
