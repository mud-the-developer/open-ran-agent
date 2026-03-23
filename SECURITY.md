# Security Policy

## Supported scope

This repository is an open-source bootstrap and architecture workspace for Open RAN operations tooling.

Security-sensitive areas include:

- operational mutation paths exposed through `bin/ranctl`
- remote deploy and evidence-fetch helpers under `ops/deploy/`
- config and artifact handling
- public examples that could accidentally contain private lab data

## Reporting

If you find a security issue, do not open a public issue with exploit details.

Instead, report it privately to the repository maintainer with:

- affected path or component
- impact summary
- reproduction steps
- suggested mitigation if available

## Public disclosure

- private lab credentials, tokens, IMSIs, keys, and environment-specific addresses should never be committed
- examples in this repository should remain sanitized and non-production
