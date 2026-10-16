---
name: Build or packaging problem
about: Report a reproducible problem with this recipe or its RPM
title: ''
labels: ''
assignees: ''
---

Describe what happened and what you expected. For vulnerabilities, use the
private contact in SECURITY.md instead of a public issue.

**Environment**

- Recipe revision and `release.env`:
- Tumbleweed snapshot (`cat /etc/os-release`) and architecture (`uname -m`):
- Container engine and version:
- R version and desktop session, if relevant:

**Reproduction**

Include the exact command and whether it fails while fetching, building,
packaging, verifying, installing, or running RStudio.

**Logs**

Attach the relevant log and its final error after removing credentials and
private data. State which checks passed and whether any tests were skipped.
