# Changelog

## [Unreleased]

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
