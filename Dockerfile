# --- GLOBAL SCOPE ALIASES ---
# Define the source image here so we can alias it
ARG GLITCHTIP_VERSION=6.1.6
ARG GLITCHTIP_IMAGE=registry.gitlab.com/glitchtip/glitchtip-frontend:${GLITCHTIP_VERSION}

# This is the "magic" fix: Assign the dynamic image to a static alias
FROM ${GLITCHTIP_IMAGE} AS glitchtip_source

# --- BASE IMAGE ---
FROM registry.access.redhat.com/ubi9/python-312:9.7-1778000623@sha256:21739f35258f21e23a7e02e79c763f2a69e605416fedd54b6ec9c5ef68fd1f43 AS base

# Use the static alias 'glitchtip_source' instead of the variable
COPY --from=glitchtip_source /code/LICENSE /licenses/LICENSE

ARG GLITCHTIP_VERSION
ENV GLITCHTIP_VERSION=${GLITCHTIP_VERSION}
LABEL konflux.additional-tags="${GLITCHTIP_VERSION}"

# --- BUILDER ---
FROM base AS builder
ENV \
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    UV_COMPILE_BYTECODE="true" \
    UV_NO_CACHE=true

COPY --from=ghcr.io/astral-sh/uv:0.11.12@sha256:3a59a3cdd5f7c217faa36e32dbc7fddbb0412889c2a0a5229f6d790e5a019dd7 /uv /bin/uv

# Use the static alias here as well
COPY --from=glitchtip_source --chown=1001:root /code ./

RUN uv sync --frozen --no-group dev

COPY bin/* ./bin/
COPY appsre ./appsre
COPY patches ./patches

RUN cat patches/00-skip-user-invitation-process.patch | patch -p1 && \
    cat patches/04-aws-s3-endpoint-url.patch | patch -p1 && \
    cat patches/09-prometheus-metrics.patch | patch -p1 && \
    cat patches/08-ingest-prometheus-middleware.patch | patch -p1

# --- FINAL PROD IMAGE ---
FROM base AS prod
ENV PORT=8000
EXPOSE ${PORT}

RUN if [ -z "${GLITCHTIP_VERSION}" ]; then echo "Error: GLITCHTIP_VERSION is not set." >&2; false; fi

COPY --from=builder $APP_ROOT/ $APP_ROOT/

RUN SECRET_KEY=ci ./manage.py collectstatic --noinput

CMD ["./bin/start.sh"]

# --- TEST IMAGE ---
FROM prod AS test
COPY --from=ghcr.io/astral-sh/uv:0.11.12@sha256:3a59a3cdd5f7c217faa36e32dbc7fddbb0412889c2a0a5229f6d790e5a019dd7 /uv /bin/uv
ENV \
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    UV_NO_CACHE=true

COPY Makefile pyproject.toml ./
COPY acceptance/ ./acceptance/
RUN make test
