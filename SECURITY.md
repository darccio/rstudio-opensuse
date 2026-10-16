# Security

Report vulnerabilities in these build scripts, RPM packaging, or publishing
instructions privately to [cc@dario.cat](mailto:cc@dario.cat). Include the pinned
release and recipe revision, affected command, impact, and reproduction steps.
Do not send credentials or sensitive user data. Coordinate disclosure with the
maintainer before posting exploit details publicly.

Maintenance focuses on the current recipe and version in `release.env` on
Tumbleweed x86_64. Older RPMs are not a separately maintained security branch.
This volunteer project has no guaranteed response or fix schedule.

For a vulnerability in RStudio itself or a bundled dependency, use the affected
upstream project's security reporting process, starting with
[RStudio's security policy](https://github.com/rstudio/rstudio/security/policy).
Also contact this project's maintainer when a recipe update or rebuild is needed.
The dependencies downloaded during a build have their own release and security
lifecycles; successful recipe tests or an RPM dependency check are not a
vulnerability audit of those components.

Publishing credentials belong in the maintainer's local OBS configuration or
hosting service, outside Git. The included GitHub workflow has read-only
repository access and performs no uploads or signing. Report a compromised
package or repository signing key privately to the maintainer as well.
