# Account grouping

## Concept

Any Claude or Codex profile can be assigned to a `ProfileGroup`: `none`,
`work`, or `personal`. Grouping is account-level and cross-provider — a
"Work" Claude account and a "Work" Codex account land in the same popover
section, because the point is separating a person's work and personal
accounts regardless of which CLI they belong to.

## Storage

`group` is a field on `ProfileCustomization` (the same label+tint+group type
Claude and Codex profiles both use, each in its own per-provider dictionary —
see [claude-multi-account.md](claude-multi-account.md#customization) and
[codex-multi-account.md](codex-multi-account.md#customization)). An
unassigned profile has `group == .none`, which also makes it part of
`ProfileCustomization.isEmpty`, so an ungrouped, unlabeled, untinted profile
still persists nothing.

## Popover rendering

`UsagePopoverView` buckets `enabledDisplayProviders` by group in a fixed
order — Work, Personal, Other (ungrouped) — and only shows section headers
once more than one bucket is non-empty. Nobody who hasn't assigned a group
sees any new chrome: with everything ungrouped, the popover renders exactly
as it did before grouping existed.

## Settings

A `ProfileGroupPicker` sits next to the existing label field and
`ProfileTintPicker` on every Claude and Codex account row. The Codex section
used to list only non-default accounts (the default one had just the
Sessions-directory field); it now lists every Codex profile, default
included, so the default account can be grouped like any other — matching
how Claude's row list already included its default profile.
