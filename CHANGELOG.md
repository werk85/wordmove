# Changelog

## [Unreleased]

## [5.4.0] - 2026-11-13

### Added

- `wordmove connect -e <env> [-c <movefile>]` opens an interactive session on a remote environment:
  `lftp` if `ftp` is configured (honouring `scheme`, `port`, `passive`), otherwise `ssh` (honouring
  `port`, `key`, `gateway` via `ssh -J`); an error if neither is configured. The session starts in
  `wordpress_path`. `ssh.password` is not used, so ssh prompts for whatever the server requires
  (e.g. key plus password); the FTP password is passed via `LFTP_PASSWORD`, never on the command
  line. (#2)
- `mysql_options` is accepted by the Movefile schemas (`wordmove doctor`).

### Changed

- Docker image: base `ruby:3.3-bullseye` → `ruby:3.3-trixie` (Debian 13) with PHP 8.4 from
  Debian main; the sury repository and `apt-key` are gone. The PHP image tag is derived from the
  Dockerfile: `siriwan/wordmove:php8.4`, `:php8.4-<version>`. The bundled MySQL client is now
  MariaDB 11.8, which verifies TLS certificates by default; see README for
  `--skip-ssl-verify-server-cert`. (#3)
- photocopier 1.4.1 is vendored into `lib/wordmove/photocopier` (MIT); wordmove now depends on
  `net-ssh ~> 7.3`, `net-scp ~> 4.0`, `net-sftp ~> 4.0`, `net-ssh-gateway`, `net-ftp`, `ed25519`
  and `bcrypt_pbkdf` directly.

### Fixed

- SSH database transfers failing against current OpenSSH servers (`Ed25519::VerifyError` /
  no Ed25519 host key support): net-ssh 6.1 was pinned by photocopier. (#3)
- Docker image build failing with 404s from the end-of-life Debian 11 security repository.
- CI: the test workflows use the latest Ruby 3.3.x; 3.2.2 isn't available on ubuntu-26.04 runners.

### Upgrade notes

- Images built `FROM siriwan/wordmove:latest` that patch photocopier's gemspec, install
  net-ssh 7 as system gems, or use `apt-key`/sury will fail to build. Remove those steps; pin
  `FROM siriwan/wordmove:php8.4-5.4.0` instead of `:latest`.

## [5.3.1] - 2026-06-18

### Fixed

- Docker image: bump base from `ruby:3.1-bullseye` to `ruby:3.3-bullseye`. A floating build had
  resolved `i18n 1.15.0`, which requires Ruby >= 3.2 (`Fiber[]`) and crashed wordmove at startup
  on the Ruby 3.1 image. `Gemfile.lock` is now committed (linux + darwin platforms) and the image
  builds with `BUNDLE_FROZEN=true`, so dependency resolution is reproducible. (5.3.0 had no
  RubyGems release; the broken `siriwan/wordmove:5.3.0` Docker tag is superseded by 5.3.1.)

## [5.3.0] - 2026-06-18

### Added

- Per-slug scoping for `--themes`/`-t`, `--plugins`/`-p` and `--mu_plugins`/`-m`: the flags now accept an optional value (e.g. `--plugins=mawinti` or `--plugins=a,b`) to sync only the named subdirectories. A scoped sync confines the mirror's `--delete` to that subtree, leaving sibling themes/plugins on the target untouched. Bare flags still mean "all" (backward compatible). Scoped pull is supported over SSH only; scoped pull over FTP is refused to avoid local data loss.
- `--experimental-db` flag for database sync operations using system-native SSH commands instead of Ruby net-ssh library. This addresses compatibility issues with modern SSH servers (e.g., Ed25519::VerifyError).

### Changed

- `--themes`, `--plugins` and `--mu_plugins` changed from boolean to optional-value flags. As a result their boolean negations (`--no-themes` / `--no-plugins` / `--no-mu_plugins`) are no longer accepted; omit the flag to skip a component.

see https://github.com/welaika/wordmove/releases
