FROM ruby:3.1-bullseye

LABEL maintainer="martin@werk85.de"

ENV WORDMOVE_WORKDIR="/html"
WORKDIR /html

# Install system dependencies
RUN apt-get update && \
    apt-get install -y curl apt-transport-https ca-certificates gnupg2 && \
    curl -sSL https://packages.sury.org/php/apt.gpg | apt-key add - && \
    echo "deb https://packages.sury.org/php/ bullseye main" | tee /etc/apt/sources.list.d/php.list && \
    apt-get update && \
    apt-get install -y \
    openssh-client \
    rsync \
    default-mysql-client \
    php8.2-cli \
    php8.2-mysql \
    php8.2-curl \
    php8.2-xml \
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