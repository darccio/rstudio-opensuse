ARG BASE_IMAGE=registry.opensuse.org/opensuse/tumbleweed:latest
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG BUILD_UID=1000
ARG BUILD_GID=1000
ARG JOBS=4
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=UTC
RUN zypper --non-interactive refresh && \
    if rpm -q busybox-gawk >/dev/null 2>&1; then \
        zypper --non-interactive install --no-recommends -- gawk -busybox-gawk; \
    fi && \
    zypper --non-interactive install --no-recommends ca-certificates gawk git bash coreutils shadow
COPY release.env /recipe/release.env
COPY scripts/common.sh scripts/fetch-source.sh /recipe/scripts/
RUN bash /recipe/scripts/fetch-source.sh /opt/rstudio-source
COPY scripts/install-system-dependencies.sh /recipe/scripts/
RUN bash /recipe/scripts/install-system-dependencies.sh
COPY scripts/install-dependencies.sh scripts/run-upstream-dependencies.sh /recipe/scripts/
RUN JOBS="$JOBS" bash /recipe/scripts/install-dependencies.sh /opt/rstudio-source --upstream-only
COPY build.sh Makefile Containerfile README.md /recipe/
COPY .dockerignore /recipe/.dockerignore
COPY scripts/ /recipe/scripts/
COPY packaging/ /recipe/packaging/
COPY tests/ /recipe/tests/
COPY docs/ /recipe/docs/
RUN (getent group "$BUILD_GID" >/dev/null || groupadd --gid "$BUILD_GID" builder) && \
    useradd --uid "$BUILD_UID" --gid "$BUILD_GID" --create-home builder && \
    chown -R "$BUILD_UID:$BUILD_GID" /opt/rstudio-source
USER builder
WORKDIR /opt/rstudio-source
ENTRYPOINT ["/bin/bash", "/recipe/scripts/build-source.sh", "/opt/rstudio-source", "/output"]
