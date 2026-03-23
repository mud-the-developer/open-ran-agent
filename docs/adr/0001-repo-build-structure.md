# ADR 0001: Repo Build Structure

## Status

Accepted

## Context

The repository needs multiple OTP applications, shared configuration, consistent tooling, and room for selective Erlang or native code where timing-sensitive work demands it.

## Decision

Use a Mix umbrella as the top-level build structure.

Inside the umbrella:

- default to Elixir for app definitions, ops-facing modules, and most supervision logic
- allow Erlang modules inside apps where protocol or transport code benefits from it
- keep timing-sensitive southbound transport in native sidecars outside the BEAM scheduler

## Consequences

Positive:

- one repo and one release discipline for many OTP apps
- strong developer ergonomics for docs, config, tests, and tooling
- easy coexistence of Elixir and Erlang modules

Negative:

- some protocol-heavy modules may later need Erlang refactors
- native build and release orchestration still needs a separate story

## Alternatives Considered

- Pure rebar3 primary build: better Erlang-first story, weaker UX for ops and docs-first bootstrap.
- Hybrid top-level build: more flexible, but adds early complexity without proving value for MVP.
