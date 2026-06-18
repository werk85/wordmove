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

### Docker base image bump Ruby 3.1 → 3.3 (2026-06-18) — hotfix
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
- **Scoping is the deletion-safety mechanism.** `--delete` is hardcoded in both Photocopier
  adapters and intentionally left untouched; confining the transferred subtree confines the
  delete. Verified against rsync's include-before-exclude ordering (first-match-wins).
