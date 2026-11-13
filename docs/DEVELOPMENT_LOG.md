# Development Log

A living, developer-facing record of work in this fork: features delivered, open
findings worth revisiting, and intentional decisions / known limitations.

This complements — does not replace — the user-facing `CHANGELOG.md` (release notes)
and the per-feature plan docs under `docs/superpowers/plans/`.

> Note: the repo's `doc/` directory is gitignored (YARD/rdoc output), so tracked
> developer docs live under `docs/` instead.

How to use it:
- Add a **Delivered features** entry when a feature lands (link its plan + version).
- Add to the **Refinement backlog** whenever a non-blocking issue is knowingly deferred.
- Record a **Decision / known limitation** when a tradeoff is made on purpose, so it
  isn't re-litigated later.

---

## Delivered features

### photocopier vendored, net-ssh 6.1 → 7.3 (2026-11-13), issue #3
- **What:** photocopier 1.4.1 (337 lines, MIT) is copied to `lib/wordmove/photocopier/`
  with its LICENSE and an origin header per file. The module name `Photocopier` is kept,
  so call sites (`Deployer::SSH`, `Deployer::FTP`, `Hook`) and spec stubs are unchanged.
- **Why:** photocopier pins `net-ssh ~> 6.1` (plus net-scp/net-sftp 3 with `net-ssh < 7`),
  and Bundler can't override a dependency's constraint. Vendoring moves the net-* constraints
  into wordmove's gemspec, so `gem install wordmove` users get net-ssh 7 too, not just the
  Docker image (a fork or submodule would only have fixed Bundler-based installs).
- **Dependencies:** `net-ssh ~> 7.3` (7.3.10), `net-scp ~> 4.0`, `net-sftp ~> 4.0`,
  `net-ssh-gateway ~> 2.0`, `net-ftp ~> 0.1.3`, plus `ed25519 ~> 1.3` and
  `bcrypt_pbkdf ~> 1.1`. The Dockerfile's `gem install ed25519 bcrypt_pbkdf net-ssh` is
  removed: those system gems were never loadable under `bundle exec`.
- **Verified** against a local OpenSSH 10.3 container, through `Photocopier::SSH#exec!` (the
  DB-transfer path), forcing the `ssh-ed25519` host key:
  `siriwan/wordmove:latest` (net-ssh 6.1.0) → `could not settle on host_key algorithm`
  (client offers no Ed25519); new image (net-ssh 7.3.10) → OK. The issue's exact KEX
  (`diffie-hellman-group-exchange-sha256`) couldn't be reproduced, because OpenSSH 10.3 no
  longer offers it.

### Docker base Debian 11 → 13, PHP 8.2 → 8.4, PHP tag from Dockerfile (2026-11-13), issue #3 (partial)
- **Symptom:** `docker build -f docker/Dockerfile .` failed at `apt-get install` with
  404s from `deb.debian.org/debian-security` (curl, gnupg, ca-certificates). Bullseye LTS
  ended 2026-08-31; its security pool is gone while the image still references it.
- **Fix:** `FROM ruby:3.3-trixie`. Debian 13 ships PHP 8.4 in main, so the sury repo and the
  deprecated `apt-key` step are dropped; packages are `php8.4-*`.
- **Tags:** `.github/workflows/docker.yml` derives the PHP tag from the first
  `php<major>.<minor>-cli` package in `docker/Dockerfile` (fails the job if none is found),
  publishing `:php8.4`, `:php8.4-<sha>` and, on a version bump, `:php8.4-<version>`.
- **MySQL client:** `default-mysql-client` is now MariaDB 11.8, which verifies the server's
  TLS certificate by default. README documents `--skip-ssl-verify-server-cert` via
  `mysql_options`/`mysqldump_options`; `mysql_options` added to both Movefile schemas so
  `wordmove doctor` accepts it (it was already used by `mysql_import_command`).
- **net-ssh:** see "photocopier vendored" above.

### `wordmove connect` — unreleased (2026-11-13), issue #2
- **What:** `wordmove connect -e <env> [-c <movefile>]` replaces the wordmove process
  (`Kernel.exec`) with an interactive `lftp` (if `ftp` is configured) or `ssh` (if `ssh` is
  configured) session; neither → `NoAdapterFound`, exit 1. FTP wins when both exist, matching
  `Deployer::Base.deployer_for`. Starts in `wordpress_path` when set
  (`ssh -t … 'cd <path> && exec $SHELL -l'` / lftp `-e 'cd <path>'`).
- **SSH:** honours `port`, `key`, `gateway` (`-J user@host[:port]`). Missing binary →
  `MissingExecutable`, exit 1.
- **FTP:** honours `scheme`, `port` (inferred 22/21 like Photocopier), `passive`.
- **Key files:** `lib/wordmove/connector.rb`, `lib/wordmove/cli.rb`,
  `spec/connector_spec.rb`, `spec/fixtures/movefiles/connect`. Suite 159 examples, RuboCop clean.

### Per-slug scoping for `push`/`pull` — v5.3.0 (2026-06-18)
- **What:** `--themes`/`-t`, `--plugins`/`-p`, `--mu_plugins`/`-m` accept an optional value
  (`--plugins=mawinti`, `--plugins=a,b`, `-p mawinti`). Bare flag still means "all".
  A scoped sync transfers only that subtree, confining the adapters' hardcoded `--delete`
  to the named slug (the feature is also the safety fix).
- **Adapters:** SSH scopes via rsync `--include`/`--exclude` globs; FTP scopes by pointing
  source/dest paths at the slug subdir. Scoped push: both adapters. Scoped pull: SSH only.
- **Guards:** scoped push asserts the local slug dir exists (`LocalPathNotFound`); scoped
  pull on SSH verifies the remote dir via `test -d` (`RemotePathNotFound`); scoped pull on
  FTP is a hard refusal (see limitations).
- **Plan:** [superpowers/plans/2026-06-18-per-slug-scoping.md](superpowers/plans/2026-06-18-per-slug-scoping.md)
- **Branch:** `feature/per-slug-scoping` (commits `80112d3`..`0973b67`). Suite 142 examples,
  RuboCop clean. Final whole-branch review: ready to merge.
- **Key files:** `lib/wordmove/cli.rb`, `lib/wordmove/deployer/base.rb`,
  `lib/wordmove/deployer/ssh.rb`, `lib/wordmove/deployer/ftp.rb`,
  `lib/wordmove/exceptions.rb`.

### Docker image version tagging (2026-06-18)
- **What:** `.github/workflows/docker.yml` reads `Wordmove::VERSION` from
  `lib/wordmove/version.rb` and conditionally adds version tags `siriwan/wordmove:<version>`
  and `siriwan/wordmove:php8.2-<version>` alongside the always-present `:latest`, `:php8.2`,
  and `:<sha>` tags. The full tag list is assembled in a `Compute image tags` shell step
  (output via a heredoc to `$GITHUB_OUTPUT`).
- **Version tags are gated:** they are emitted only when the push actually changed
  `version.rb` — computed by `git diff --name-only <before>..<sha>` (checkout uses
  `fetch-depth: 0` so the `before` commit is present). Unknown/missing `before` (first push,
  force-push, non-push event) falls back to "changed=true" as a safe default. This prevents an
  unrelated master push from overwriting an already-published `:<version>` image.
- **Trigger unchanged:** still on push to `master`.
- **Versioning procedure:** source of truth is `lib/wordmove/version.rb` (bumped manually);
  `rake release` (via `bundler/gem_tasks`) tags git `v<version>` and publishes the gem to
  RubyGems — independent of the Docker image.

### Docker base image bump Ruby 3.1 → 3.3 (2026-06-18) — hotfix, shipped as v5.3.1
- **Symptom:** `siriwan/wordmove:latest` crashed at startup —
  `i18n-1.15.0/lib/i18n.rb: undefined method '[]' for Fiber:Class (NoMethodError)`
  before any wordmove logic ran.
- **Root cause:** `Gemfile.lock` is gitignored, so each image build floats to the latest
  gems. `activesupport ~> 6.1` allows i18n up to 1.15.x; i18n **1.15.0 requires Ruby ≥ 3.2**
  (uses `Fiber[]`), but the base was `ruby:3.1-bullseye`. The previous/working image had
  resolved i18n 1.14.7 (3.1-compatible); the `--no-cache` rebuild swept in 1.15.0.
  Verified: i18n 1.15.0 crashes on 3.1, loads OK on 3.2/3.3; 1.14.7 loads on 3.1.
- **Fix:** `docker/Dockerfile` `FROM ruby:3.1-bullseye` → `ruby:3.3-bullseye` (Debian 11
  unchanged, so the PHP sury repo line still applies). Rebuilt + verified `wordmove help push`
  runs on 3.3.
- **Reproducibility (done):** `Gemfile.lock` is now committed (removed from `.gitignore`),
  generated on Ruby 3.3 with platforms `x86_64-linux aarch64-linux arm64-darwin x86_64-darwin`
  so the multi-arch image build and local macOS dev both resolve from it without mutation.
  The Dockerfile build runs `BUNDLE_FROZEN=true bundle install`, so a `Gemfile` change without
  a matching lock update fails the build loudly instead of silently re-resolving. Update deps
  deliberately via `bundle update` (re-resolves all locked platforms), then commit the lock.

---

## Refinement backlog (open, non-blocking)

- **[medium] Scoped FTP pull can now be fixed in-house.** With photocopier vendored, a
  remote-dir existence check can be added to `Photocopier::FTP` directly (see limitation below).
- **[medium] Scoped pull over FTP is unsupported.** It currently raises `RemotePathNotFound`
  on purpose. Supporting it safely needs a spike on an lftp-based remote-dir-existence probe
  (Photocopier's FTP adapter exposes no directory-check API). See limitation below.
- **[low] No end-to-end test for unscoped FTP push/pull.** The `*[nil].compact` → `path()`
  equivalence is relied upon but only covered indirectly; add a regression spec.
- **[low] No dedicated unit test for SSH scoped *pull* path builders.** `pull_include_paths`/
  `pull_exclude_paths` with a slug mirror the push builders (which are tested) but aren't
  asserted directly.
- **[low] Docker workflow could also publish to GHCR.** `.github/workflows/docker.yml` pushes
  only to Docker Hub. Consider adding a `ghcr.io` login + tags so downstreams have a choice.
- **[low] Test-double / helper polish from task reviews.** e.g. pull-guard tests assert the
  guard is called but not the subsequent yield; `instance_double(WordpressDirectory)` is
  load-order sensitive in isolated runs. Cosmetic.

---

## Decisions & known limitations

- **`--no-themes` / `--no-plugins` / `--no-mu_plugins` removed.** Overloading these flags from
  boolean to optional-value (string) means Thor no longer synthesizes the `--no-` negation
  (that's a boolean-only feature). To skip a component, omit its flag. The `--all --no-X`
  ("everything except X") idiom is the one lost capability. Shipped as a minor bump despite
  this, since bare flags and `--all` behave exactly as before.
- **`-p=foo` is not supported; use `-p foo` or `--plugins=foo`.** Thor's `=` value binding is
  reliable for long options and space-form short options, but `-p=foo` binds `"=foo"`.
- **Scoped FTP pull refused (data-safety).** lftp's `find -d 1 <remote> || mkdir -p <remote>`
  would create an empty remote dir on a mistyped slug and then mirror emptiness *down*,
  wiping the local copy. With no remote-existence check available, refusing is the safe choice.
- **`connect` ignores `ssh.password` (no sshpass).** Some accounts demand a key *and* a
  password, and the Movefile password isn't necessarily the login password; plain ssh
  prompts for whatever the server wants (incl. 2FA). Possible later opt-in flag to use
  `sshpass -e`. Gateway passwords can't be passed through `-J` → warning, user types it.
- **`connect` passes the FTP password only via `LFTP_PASSWORD` + `--env-password`**, never
  on argv (would be visible in `ps`). Without a password, lftp prompts.
- **`connect` flushes `$stdout` before `exec`;** otherwise buffered log lines are lost when
  stdout isn't a TTY.
- **photocopier is vendored, not forked.** It's small, essentially unmaintained upstream, and
  vendoring is the only option that also fixes RubyGems installs. Local changes to
  `lib/wordmove/photocopier/` are expected; keep the MIT notice.
- **Scoping is the deletion-safety mechanism.** `--delete` is hardcoded in both Photocopier
  adapters and intentionally left untouched; confining the transferred subtree confines the
  delete. Verified against rsync's include-before-exclude ordering (first-match-wins).
