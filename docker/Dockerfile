FROM ruby:3.3-trixie

LABEL maintainer="martin@werk85.de"

ENV WORDMOVE_WORKDIR="/html"
WORKDIR /html

# Install system dependencies (Debian 13 ships PHP 8.4 in main)
RUN apt-get update && \
    apt-get install -y \
    curl \
    ca-certificates \
    openssh-client \
    rsync \
    default-mysql-client \
    php8.4-cli \
    php8.4-mysql \
    php8.4-curl \
    php8.4-xml \
    lftp \
    build-essential \
    git \
    libffi-dev \
    pkg-config \
    libyaml-dev \
    ssl-cert \
    libsodium-dev \
    && rm -rf /var/lib/apt/lists/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Copy the gemspec and Gemfile
COPY wordmove.gemspec Gemfile ./

# Copy the whole project
COPY . .

# Install dependencies and build wordmove gem.
# BUNDLE_FROZEN: fail the build if Gemfile.lock is out of sync with the Gemfile,
# instead of silently re-resolving (which is how an incompatible dep slipped in).
RUN BUNDLE_FROZEN=true bundle install \
    && rake build \
    && gem install pkg/wordmove-*.gem

# Create a wrapper script for backward compatibility
RUN echo '#!/bin/sh\nexec bundle exec wordmove "$@"' > /usr/local/bin/wordmove \
    && chmod +x /usr/local/bin/wordmove

# Set the entrypoint to run wordmove from bundle
ENTRYPOINT ["bundle", "exec", "wordmove"]
CMD ["help"]