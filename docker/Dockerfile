FROM ruby:3.2-slim-bookworm

LABEL maintainer="martin@werk85.de"

ENV WORDMOVE_WORKDIR="/html"
WORKDIR /html

# Install system dependencies
RUN apt-get update && apt-get install -y \
    openssh-client \
    rsync \
    default-mysql-client \
    curl \
    php-cli \
    php-mysql \
    php-curl \
    php-xml \
    lftp \
    build-essential \
    git \
    libffi-dev \
    libffi8 \
    pkg-config \
    libyaml-dev \
    ssl-cert \
    libsodium-dev \
    && rm -rf /var/lib/apt/lists/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Install SSH-related gems for better key support
RUN gem install ed25519 -v "<2" && \
    gem install bcrypt_pbkdf -v "<2" && \
    gem install net-ssh

# Copy the gemspec and Gemfile
COPY wordmove.gemspec Gemfile ./

# Copy the whole project
COPY . .

# Install the gem from source
RUN bundle install \
    && rake build \
    && gem install pkg/wordmove-*.gem

ENTRYPOINT ["wordmove"]
CMD ["help"]