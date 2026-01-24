# Ubuntu 22.04 test container for juvy
FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    bash \
    git \
    rsync \
    curl \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install bats-core and helpers via npm
RUN npm install -g bats

# Install bats helper libraries
RUN mkdir -p /usr/local/lib/bats && \
    git clone --depth 1 https://github.com/bats-core/bats-support.git /usr/local/lib/bats/bats-support && \
    git clone --depth 1 https://github.com/bats-core/bats-assert.git /usr/local/lib/bats/bats-assert

# Configure git globally (tests run as root)
RUN git config --global user.name "Test User" && \
    git config --global user.email "test@example.com" && \
    git config --global init.defaultBranch main

WORKDIR /workspace

# Default command runs tests
CMD ["bats", "tests/bats"]
