---
name: house-style
description: Example org-shipped skill. TRIGGER when the user asks for ACME's house style, internal formatting conventions, or how org-layer skills work. Replace this with a real house skill (or delete it) when adapting the org package.
user-invocable: true
allowed-tools: "Read"
---

# House Style (example org skill)

This is a trivial placeholder skill that ships in the **org layer** at
`~/.config/konrad/org/skills/house-style/`. konrad's entrypoint copies org
skills into opencode's skill directory **between** the baked skills and the
user's own (`baked < org < user`), so an org can ship house skills its whole
fleet sees without forking the image.

It exists to demonstrate the mechanism. When adapting the org package, replace
this with a real house skill — or delete the `skills/` directory entirely if
your org doesn't ship skills.

## Example: ACME house style

When asked to apply ACME house style:

- Headings in sentence case, never Title Case.
- One space after a period, never two.
- Dates as ISO `YYYY-MM-DD`.
- Refer to the company as "ACME" in body text, "ACME Corporation" only in
  legal/formal contexts.
