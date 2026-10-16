# CPack runs this after installation into its staging directory.
if(NOT CPACK_TEMPORARY_DIRECTORY OR CPACK_TEMPORARY_DIRECTORY STREQUAL "/")
  message(FATAL_ERROR "CPack must supply a package staging directory")
endif()
if(NOT IS_DIRECTORY "${CPACK_TEMPORARY_DIRECTORY}/usr/lib/rstudio")
  message(FATAL_ERROR "RStudio package staging directory is missing")
endif()
set(copilot "${CPACK_TEMPORARY_DIRECTORY}/usr/lib/rstudio/resources/app/bin/copilot-language-server-js")
foreach(relative IN ITEMS
    compiled/linux/arm64
    bin/linux/arm64
    node_modules/@github/copilot-linux-arm64
    node_modules/@github/copilot-sdk-linux-arm64
    node_modules/@microsoft/mxc-sdk/bin/arm64)
  if(EXISTS "${copilot}/${relative}")
    message(STATUS "Omitting Copilot ARM64 tools: ${relative}")
    file(REMOVE_RECURSE "${copilot}/${relative}")
  endif()
  # CMake also records absolute install destinations separately from the staged
  # tree; RPM must not turn removed entries into stale %config file records.
  list(FILTER CPACK_ABSOLUTE_DESTINATION_FILES EXCLUDE REGEX
    "^/usr/lib/rstudio/resources/app/bin/copilot-language-server-js/${relative}(/|$)")
endforeach()
