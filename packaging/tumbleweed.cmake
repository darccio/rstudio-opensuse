# Loaded after upstream CPackConfig.cmake. Keep upstream layout and scriptlets.
set(CPACK_RPM_PACKAGE_LICENSE "AGPL-3.0-only")
set(CPACK_RPM_PACKAGE_RELEASE "$ENV{RPM_RELEASE}")
set(CPACK_RPM_PACKAGE_VERSION "$ENV{RSTUDIO_VERSION}")
set(CPACK_RPM_PACKAGE_ARCHITECTURE "x86_64")
set(CPACK_RPM_PACKAGE_REQUIRES "R-base >= 3.6.0, libxkbcommon-x11-0, libsqlite3-0")
# Upstream disables automatic dependency discovery. Enable it so the RPM records
# actual ELF requirements from this Tumbleweed build, including bundled tools.
set(CPACK_RPM_PACKAGE_AUTOREQPROV "yes")
set(CPACK_RPM_PACKAGE_AUTOREQ "yes")
set(CPACK_RPM_PACKAGE_AUTOPROV "yes")
set(CPACK_RPM_FILE_NAME "RPM-DEFAULT")
set(CPACK_RPM_PACKAGE_RELOCATABLE FALSE)
set(CPACK_PACKAGE_RELOCATABLE FALSE)
# Copilot ships optional native tools for multiple architectures. Remove its
# ARM64 Linux tools before RPM scans the staged files for ELF dependencies.
list(APPEND CPACK_PRE_BUILD_SCRIPTS "${CMAKE_CURRENT_LIST_DIR}/prepare-rpm.cmake")
# RPM defaults to /var/tmp, which is not writable in restricted native builds.
string(APPEND CPACK_RPM_SPEC_MORE_DEFINE "\n%define _tmppath /tmp\n")
