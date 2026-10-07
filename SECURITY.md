<!--
SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Security policy

konrad's job is to be a boundary: an agent that runs code, reads files and talks to models, kept inside a container the user decides about. A way through that boundary is a vulnerability, and reports are very welcome.

## Reporting a vulnerability

**Email [gitlab-reply+jbauss2-konrad-3917-issue-@git.nrw](mailto:gitlab-reply+jbauss2-konrad-3917-issue-@git.nrw).** This is the project's GitLab Service Desk address: your email becomes a confidential issue that only the maintainer can read, and replies reach you by email. You need no account; gitlab.git.nrw doesn't offer open sign-up, so email is the way in for everyone.

Please don't report vulnerabilities as a public issue, a merge request comment, or on the GitHub mirror (it takes no issues or reports).

Helpful to include:

- `konrad --version` (CLI and image), the engine (Podman or apple/container) and the host OS.
- What crosses the boundary, and the steps or a proof of concept to reproduce it.
- Whether it needs a non-default setting (`KONRAD_WORKSPACE_GUARD=0`, `--no-firewall`, an org layer, …).

## What counts

In scope, as described in [ARCHITECTURE.md](ARCHITECTURE.md):

- **Escaping the sandbox**: the agent reaching the host filesystem, processes or devices beyond the mounts konrad sets up.
- **Getting past the network boundary**: the egress firewall's allow-list, or `konrad code`'s seal of the host and the local network.
- **Deferred escape**: getting the host to run code the agent planted in the workspace, past the workspace guard.
- **Credential exposure**: provider keys, tokens or config secrets reaching the agent, the workspace, or anywhere konrad promises they don't go.
- **Supply chain**: the image build, the installer, `konrad update` and the background refresh.

Out of scope:

- What the agent may do inside the sandbox by design: edit the workspace, reach allowed hosts, run tools.
- A model doing something unwanted inside those limits (prompt injection that stays inside the sandbox included), unless it leads to one of the above.
- Bugs in upstream projects (opencode, Podman, apple/container) that konrad doesn't make worse; please report those upstream.
- Findings already recorded in [SECURITY-AUDIT.md](SECURITY-AUDIT.md) or tracked in [ROADMAP.md](ROADMAP.md).

## What to expect

konrad is maintained by one person, so handling is best effort, without fixed response times. Only the latest release is supported (pre-1.0, see [README → Status](README.md#status)), and fixes ship as a new release. Once a fix is out, the issue is made public and the [CHANGELOG](CHANGELOG.md) notes it, crediting you if you'd like.
