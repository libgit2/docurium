# Dependencies we need available when running
ARG RUN_DEPS="ruby-dev llvm libclang-3.8-dev python-pygments libffi6"

FROM debian:stretch-slim as builder

# Extra dependencies we need in the build container
ARG BUILD_DEPS="git cmake pkg-config build-essential libffi-dev libssl-dev"

# takes the global value defined above
ARG RUN_DEPS

# We need these packages to build ruby extensions, rugged and to parse the C
# code. pygments is there to highlight the code examples.
RUN apt update && \
    apt install -y --no-install-recommends ${BUILD_DEPS} ${RUN_DEPS} && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /docurium

# This is here so we can provide a unique argument per run so docker does not
# consider the rest of the file cached and wealways install the latest version
# of docurium
ARG CACHEBUST=1

COPY . /docurium/
RUN gem build docurium && gem install docurium-*.gem --no-ri --no-rdoc

FROM debian:stretch-slim

# takes the global value defined above
ARG RUN_DEPS
RUN apt update && \
    apt install -y --no-install-recommends ${RUN_DEPS} && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /var/lib/gems/ /var/lib/gems/
COPY --from=builder /usr/local/bin/cm /usr/local/bin/cm
