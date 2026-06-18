# Per-slug scoping for push/pull Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `--themes/-t`, `--plugins/-p`, `--mu_plugins/-m` take an optional `=slug[,slug]` value so push/pull syncs only the named subdirectories, with `--delete` safely confined to that subtree.

**Architecture:** Overload the three flags from `:boolean` to `:string` with `lazy_default: ""` (bare flag still means "all"). A shared `Deployer::Base` helper turns the option value into a slug list and iterates; SSH scopes via its existing rsync `--include`/`--exclude` glob builders (pointed at `relative_path(slug)`), FTP scopes by pointing source/dest at `path(slug)`. A pre-transfer guard asserts the slug dir exists so a typo can't trigger `--delete` against a real remote/local directory.

**Tech Stack:** Ruby ≥ 3.0, Thor ~> 1.3, RSpec, RuboCop, Photocopier 1.4.1 (SSH/rsync + FTP/lftp adapters).

## Global Constraints

- Ruby `>= 3.0.0`.
- RuboCop must pass: line length ≤ 200, method length ≤ 100, class length ≤ 200.
- `rake` (RSpec + RuboCop) must be green at the end of every task.
- `--delete` is hardcoded in both adapters and is NOT to be modified: `photocopier/ssh.rb:84` (`'--delete'`), `photocopier/ftp.rb:80` (`mirror --delete`). Safety comes from scoping the transferred subtree, not from touching `--delete`.
- Backward compatibility: bare `-t`/`-p`/`-m`, and `--all`, must behave exactly as today.
- Photocopier's verified public APIs: SSH adapter exposes `exec!(cmd) -> [stdout, stderr, exit_code]` (`photocopier/ssh.rb`). FTP adapter exposes **no** public directory-existence check (`photocopier/ftp.rb` only has `get/put_file/delete/get_directory/put_directory`). Therefore **scoped pull is supported on SSH only**; scoped pull over FTP must fail loud (Task 7), not silently risk local data loss.
- Scope decision: this plan delivers scoped **push on both adapters**, scoped **pull on SSH**, and an explicit unsupported-error for scoped **pull on FTP** (the real-world driver is push; FTP-pull scoping is a documented follow-up requiring an lftp-probe spike).

---

### Task 1: CLI flags accept an optional value

**Files:**
- Modify: `lib/wordmove/cli.rb:23-25`
- Test: `spec/cli_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: after parsing, `options[:themes]`, `options[:plugins]`, `options[:mu_plugins]` are `String` (`""` for bare flag, the value for `--plugins=foo`) or absent (`nil`) when the flag is omitted. `uploads`, `languages`, `wordpress`, `db` remain `Boolean`.

- [ ] **Step 1: Write the failing parsing tests**

Add to `spec/cli_spec.rb` (inside the top-level `describe Wordmove::CLI do`):

```ruby
context "scoped plugin/theme flags" do
  let(:movefile) { movefile_path_for("multi_environments") }

  # Capture the options hash the deployer would receive, without running a real transfer.
  def captured_options_for(argv)
    captured = nil
    # Plain double (not instance_double): push_<task> lives on the SSH/FTP
    # subclasses, not on Base, so a verified double would reject push_plugins.
    null_deployer = double("deployer").as_null_object
    allow(Wordmove::Deployer::Base).to receive(:deployer_for) do |opts|
      captured = opts
      null_deployer
    end
    allow(Wordmove::Hook).to receive(:run)
    silence_stream($stdout) { Wordmove::CLI.start(argv) }
    captured
  end

  it "binds bare --plugins to an empty string (means: all)" do
    opts = captured_options_for(["push", "--plugins", "-e", "staging", "-c", movefile])
    expect(opts[:plugins]).to eq("")
  end

  it "binds --plugins=foo to the slug" do
    opts = captured_options_for(["push", "--plugins=foo", "-e", "staging", "-c", movefile])
    expect(opts[:plugins]).to eq("foo")
  end

  it "binds a comma list" do
    opts = captured_options_for(["push", "--plugins=foo,bar", "-e", "staging", "-c", movefile])
    expect(opts[:plugins]).to eq("foo,bar")
  end

  it "binds the short space form -p foo" do
    opts = captured_options_for(["push", "-p", "foo", "-e", "staging", "-c", movefile])
    expect(opts[:plugins]).to eq("foo")
  end

  it "leaves plugins absent when the flag is omitted" do
    opts = captured_options_for(["push", "-t", "-e", "staging", "-c", movefile])
    expect(opts[:plugins]).to be_nil
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/cli_spec.rb -e "scoped plugin/theme flags"`
Expected: FAIL — bare `--plugins` raises a Thor "requires an argument" error (option is still `:boolean`), so `opts` is never captured.

- [ ] **Step 3: Change the option types**

In `lib/wordmove/cli.rb`, replace lines 23-25:

```ruby
      themes: { aliases: "-t", type: :boolean },
      plugins: { aliases: "-p", type: :boolean },
      mu_plugins: { aliases: "-m", type: :boolean },
```

with:

```ruby
      themes: { aliases: "-t", type: :string, lazy_default: "" },
      plugins: { aliases: "-p", type: :string, lazy_default: "" },
      mu_plugins: { aliases: "-m", type: :string, lazy_default: "" },
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/cli_spec.rb -e "scoped plugin/theme flags"`
Expected: PASS (all 5 examples).

- [ ] **Step 5: Run the full CLI spec to confirm no regression**

Run: `bundle exec rspec spec/cli_spec.rb`
Expected: PASS. Note: the existing `--all` / "excluding one of the components" examples pass options as a hash directly to `cli.invoke`, so they are unaffected by the parsing change. (See Task 8 for the `--no-*` doc note.)

- [ ] **Step 6: Commit**

```bash
git add lib/wordmove/cli.rb spec/cli_spec.rb
git commit -m "feat(cli): allow --themes/--plugins/--mu_plugins to take an optional slug value"
```

---

### Task 2: `selected_slugs` helper + exceptions

**Files:**
- Modify: `lib/wordmove/deployer/base.rb` (add helper near other `protected` methods, after line 84)
- Modify: `lib/wordmove/exceptions.rb`
- Test: `spec/deployer/base_spec.rb`

**Interfaces:**
- Consumes: `options[<task>.to_sym]` produced by Task 1.
- Produces: `Deployer::Base#selected_slugs(task) -> Array<String>` (empty array means "all"). New exceptions `Wordmove::LocalPathNotFound`, `Wordmove::RemotePathNotFound`.

- [ ] **Step 1: Write the failing tests**

Add to `spec/deployer/base_spec.rb` (inside `describe Wordmove::Deployer::Base do`):

```ruby
context "#selected_slugs" do
  def deployer_with(extra)
    described_class.new(:dummy_env, { config: movefile_path_for("multi_environments") }.merge(extra))
  end

  it "splits a comma list and trims whitespace" do
    expect(deployer_with(plugins: "a, b ,c").send(:selected_slugs, "plugins")).to eq(%w[a b c])
  end

  it "returns [] for an empty string (bare flag = all)" do
    expect(deployer_with(plugins: "").send(:selected_slugs, "plugins")).to eq([])
  end

  it "returns [] for a boolean true (uploads/languages stay unscoped)" do
    expect(deployer_with(uploads: true).send(:selected_slugs, "uploads")).to eq([])
  end

  it "returns [] when the option is absent" do
    expect(deployer_with({}).send(:selected_slugs, "plugins")).to eq([])
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/deployer/base_spec.rb -e "#selected_slugs"`
Expected: FAIL with `NoMethodError: ... selected_slugs`.

- [ ] **Step 3: Add the exceptions**

In `lib/wordmove/exceptions.rb`, add inside `module Wordmove` (after line 9):

```ruby
  class LocalPathNotFound < StandardError; end
  class RemotePathNotFound < StandardError; end
```

- [ ] **Step 4: Add the helper**

In `lib/wordmove/deployer/base.rb`, after `paths_to_exclude` (line 84), add:

```ruby
      # Returns the list of slugs requested for a task, or [] meaning "all".
      # Boolean tasks (uploads/languages) and the bare-flag empty string both yield [].
      def selected_slugs(task)
        value = options[task.to_sym]
        return [] unless value.is_a?(String)

        value.split(',').map(&:strip).reject(&:empty?)
      end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/deployer/base_spec.rb -e "#selected_slugs"`
Expected: PASS (4 examples).

- [ ] **Step 6: Commit**

```bash
git add lib/wordmove/deployer/base.rb lib/wordmove/exceptions.rb spec/deployer/base_spec.rb
git commit -m "feat(deployer): add selected_slugs helper and path-not-found exceptions"
```

---

### Task 3: `each_selected_slug` iterator + push/pull guards

**Files:**
- Modify: `lib/wordmove/deployer/base.rb`
- Test: `spec/deployer/base_spec.rb`

**Interfaces:**
- Consumes: `selected_slugs` (Task 2).
- Produces:
  - `Deployer::Base#each_selected_slug(task, action) { |slug| ... }` — yields `nil` once when "all"; otherwise yields each slug after running the guard for `action` (`:push` or `:pull`).
  - `Deployer::Base#assert_local_slug_dir!(task, slug)` — raises `Wordmove::LocalPathNotFound` unless the local dir exists.
  - `Deployer::Base#assert_remote_slug_dir!(task, slug)` — base raises `Wordmove::ImplementInSubclassError`; overridden in SSH (Task 6) and FTP (Task 7).

- [ ] **Step 1: Write the failing tests**

Add to `spec/deployer/base_spec.rb`:

```ruby
context "#each_selected_slug" do
  let(:deployer) do
    described_class.new(:dummy_env, config: movefile_path_for("multi_environments"))
  end

  it "yields nil once when no slugs are selected" do
    allow(deployer).to receive(:selected_slugs).and_return([])
    expect { |b| deployer.send(:each_selected_slug, "plugins", :push, &b) }
      .to yield_with_args(nil)
  end

  it "yields each slug when scoped and the local dir exists (push)" do
    allow(deployer).to receive(:selected_slugs).and_return(%w[a b])
    allow(deployer).to receive(:assert_local_slug_dir!)
    expect { |b| deployer.send(:each_selected_slug, "plugins", :push, &b) }
      .to yield_successive_args("a", "b")
  end

  it "raises LocalPathNotFound on a scoped push to a missing local dir" do
    allow(deployer).to receive(:selected_slugs).and_return(%w[typo])
    # Base built directly has no merged :local options, so stub the dir lookup
    # to a known-missing path. Do NOT change Base#initialize to work around this.
    dir = instance_double(WordpressDirectory, path: "/no/such/plugins/typo")
    allow(deployer).to receive(:local_plugins_dir).and_return(dir)
    expect { deployer.send(:each_selected_slug, "plugins", :push) { |_| } }
      .to raise_error(Wordmove::LocalPathNotFound, /typo/)
  end

  it "delegates the pull guard to assert_remote_slug_dir!" do
    allow(deployer).to receive(:selected_slugs).and_return(%w[a])
    expect(deployer).to receive(:assert_remote_slug_dir!).with("plugins", "a")
    deployer.send(:each_selected_slug, "plugins", :pull) { |_| }
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/deployer/base_spec.rb -e "#each_selected_slug"`
Expected: FAIL with `NoMethodError: ... each_selected_slug`.

- [ ] **Step 3: Add the iterator and guards**

In `lib/wordmove/deployer/base.rb`, directly below `selected_slugs` (from Task 2), add:

```ruby
      # Yields nil once for "all"; otherwise guards then yields each slug.
      def each_selected_slug(task, action)
        slugs = selected_slugs(task)
        return yield(nil) if slugs.empty?

        slugs.each do |slug|
          case action
          when :push then assert_local_slug_dir!(task, slug)
          when :pull then assert_remote_slug_dir!(task, slug)
          end
          yield slug
        end
      end

      def assert_local_slug_dir!(task, slug)
        path = send("local_#{task}_dir").path(slug)
        return if File.directory?(path)

        raise Wordmove::LocalPathNotFound,
              "No local #{task} dir '#{slug}' at #{path} — aborting to avoid deleting the remote."
      end

      # SSH and FTP override this. Base refuses so a new adapter can't silently skip the guard.
      def assert_remote_slug_dir!(_task, _slug)
        raise Wordmove::ImplementInSubclassError
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/deployer/base_spec.rb -e "#each_selected_slug"`
Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/wordmove/deployer/base.rb spec/deployer/base_spec.rb
git commit -m "feat(deployer): add each_selected_slug iterator with push/pull existence guards"
```

---

### Task 4: SSH path builders accept an optional slug

**Files:**
- Modify: `lib/wordmove/deployer/ssh.rb:121-171`
- Test: `spec/deployer/ssh/path_scoping_spec.rb` (create)

**Interfaces:**
- Consumes: `WordpressDirectory#relative_path(*args)` (joins extra segments — `wordpress_directory.rb:33-40`).
- Produces: `push_inlcude_paths(task, slug = nil)`, `push_exclude_paths(task, slug = nil)`, `pull_include_paths(task, slug = nil)`, `pull_exclude_paths(task, slug = nil)`. With `slug = nil` the output is identical to today's. (Keep the existing misspelling `push_inlcude_paths`.)

- [ ] **Step 1: Write the failing test**

Create `spec/deployer/ssh/path_scoping_spec.rb`:

```ruby
require 'spec_helper'

describe Wordmove::Deployer::Ssh::DefaultSqlAdapter do
  let(:deployer) do
    Wordmove::Deployer::Base.deployer_for(
      config: movefile_path_for("multi_environments"),
      environment: "staging"
    )
  end

  context "#push_inlcude_paths" do
    it "scopes includes to the slug subtree when a slug is given" do
      expect(deployer.send(:push_inlcude_paths, "plugins", "mawinti"))
        .to eq(["/wp-content/plugins/mawinti/", "/wp-content/plugins/", "/wp-content/"])
    end

    it "covers the whole plugins dir when no slug is given" do
      expect(deployer.send(:push_inlcude_paths, "plugins"))
        .to eq(["/wp-content/plugins/", "/wp-content/"])
    end
  end

  context "#push_exclude_paths" do
    it "protects siblings inside the slug's parent dirs" do
      expect(deployer.send(:push_exclude_paths, "plugins", "mawinti"))
        .to eq(["/wp-content/plugins/*", "/wp-content/*", "/*"])
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/deployer/ssh/path_scoping_spec.rb`
Expected: FAIL — `push_inlcude_paths` takes 1 arg (`ArgumentError: wrong number of arguments (given 2, expected 1)`).

- [ ] **Step 3: Add the optional slug to all four builders**

In `lib/wordmove/deployer/ssh.rb`, change the four method signatures and the `Pathname.new(...)` argument in each. Replace lines 121-171 with:

```ruby
      def push_inlcude_paths(task, slug = nil)
        Pathname.new(send(:"local_#{task}_dir").relative_path(*[slug].compact))
                .ascend
                .each_with_object([]) do |directory, array|
                  path = directory.to_path
                  path.prepend('/') unless path.match? %r{^/}
                  path.concat('/') unless path.match? %r{/$}
                  array << path
                end
      end

      def push_exclude_paths(task, slug = nil)
        Pathname.new(send(:"local_#{task}_dir").relative_path(*[slug].compact))
                .dirname
                .ascend
                .each_with_object([]) do |directory, array|
                  path = directory.to_path
                  path.prepend('/') unless path.match? %r{^/}
                  path.concat('/') unless path.match? %r{/$}
                  path.concat('*')
                  array << path
                end
                .concat(paths_to_exclude)
                .concat(['/*'])
      end

      def pull_include_paths(task, slug = nil)
        Pathname.new(send(:"remote_#{task}_dir").relative_path(*[slug].compact))
                .ascend
                .each_with_object([]) do |directory, array|
                  path = directory.to_path
                  path.prepend('/') unless path.match? %r{^/}
                  path.concat('/') unless path.match? %r{/$}
                  array << path
                end
      end

      def pull_exclude_paths(task, slug = nil)
        Pathname.new(send(:"remote_#{task}_dir").relative_path(*[slug].compact))
                .dirname
                .ascend
                .each_with_object([]) do |directory, array|
                  path = directory.to_path
                  path.prepend('/') unless path.match? %r{^/}
                  path.concat('/') unless path.match? %r{/$}
                  path.concat('*')
                  array << path
                end
                .concat(paths_to_exclude)
                .concat(['/*'])
      end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/deployer/ssh/path_scoping_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/wordmove/deployer/ssh.rb spec/deployer/ssh/path_scoping_spec.rb
git commit -m "feat(ssh): make rsync include/exclude builders accept an optional slug"
```

---

### Task 5: SSH push/pull loop over selected slugs

**Files:**
- Modify: `lib/wordmove/deployer/ssh.rb:102-119`
- Test: `spec/deployer/ssh/scoped_transfer_spec.rb` (create)

**Interfaces:**
- Consumes: `each_selected_slug` (Task 3), the four slug-aware builders (Task 4).
- Produces: `push_<task>` / `pull_<task>` call `remote_put_directory` / `remote_get_directory` once per selected slug (once with `nil` when "all").

- [ ] **Step 1: Write the failing test**

Create `spec/deployer/ssh/scoped_transfer_spec.rb`:

```ruby
require 'spec_helper'

describe Wordmove::Deployer::Ssh::DefaultSqlAdapter do
  def deployer_with(extra)
    Wordmove::Deployer::Base.deployer_for(
      { config: movefile_path_for("multi_environments"), environment: "staging" }.merge(extra)
    )
  end

  context "scoped push" do
    let(:deployer) { deployer_with(plugins: "mawinti") }

    before do
      allow(deployer).to receive(:assert_local_slug_dir!) # bypass filesystem
      allow(deployer).to receive(:logger).and_return(double(task: nil))
    end

    it "transfers only the scoped subtree" do
      expect(deployer).to receive(:remote_put_directory).once do |_local, _remote, exclude, include|
        expect(include).to include("/wp-content/plugins/mawinti/")
        expect(exclude).to include("/wp-content/plugins/*")
      end
      deployer.send(:push_plugins)
    end
  end

  context "unscoped push (bare flag)" do
    let(:deployer) { deployer_with(plugins: "") }

    before { allow(deployer).to receive(:logger).and_return(double(task: nil)) }

    it "transfers the whole plugins dir once" do
      expect(deployer).to receive(:remote_put_directory).once do |_local, _remote, _exclude, include|
        expect(include).to eq(["/wp-content/plugins/", "/wp-content/"])
      end
      deployer.send(:push_plugins)
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/deployer/ssh/scoped_transfer_spec.rb`
Expected: FAIL — the scoped example's `include` does not contain the slug path (current code ignores slugs).

- [ ] **Step 3: Rewrite the generated push/pull task methods**

In `lib/wordmove/deployer/ssh.rb`, replace lines 102-119 with:

```ruby
      %w[uploads themes plugins mu_plugins languages].each do |task|
        define_method "push_#{task}" do
          logger.task "Pushing #{task.titleize}"
          each_selected_slug(task, :push) do |slug|
            remote_put_directory(local_options[:wordpress_path],
                                 remote_options[:wordpress_path],
                                 push_exclude_paths(task, slug),
                                 push_inlcude_paths(task, slug))
          end
        end

        define_method "pull_#{task}" do
          logger.task "Pulling #{task.titleize}"
          each_selected_slug(task, :pull) do |slug|
            remote_get_directory(remote_options[:wordpress_path],
                                 local_options[:wordpress_path],
                                 pull_exclude_paths(task, slug),
                                 pull_include_paths(task, slug))
          end
        end
      end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/deployer/ssh/scoped_transfer_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/wordmove/deployer/ssh.rb spec/deployer/ssh/scoped_transfer_spec.rb
git commit -m "feat(ssh): loop push/pull over selected slugs"
```

---

### Task 6: SSH remote-existence guard for scoped pull

**Files:**
- Modify: `lib/wordmove/deployer/ssh.rb` (add `assert_remote_slug_dir!` in the `private` section)
- Test: `spec/deployer/ssh/scoped_transfer_spec.rb`

**Interfaces:**
- Consumes: the SSH `@copier`'s `exec!(cmd) -> [stdout, stderr, exit_code]` (verified in `photocopier/ssh.rb`).
- Produces: SSH override of `assert_remote_slug_dir!(task, slug)` — raises `Wordmove::RemotePathNotFound` when the remote dir is absent.

- [ ] **Step 1: Write the failing test**

Add to `spec/deployer/ssh/scoped_transfer_spec.rb`:

```ruby
  context "scoped pull guard" do
    let(:deployer) { deployer_with(plugins: "typo") }

    before { allow(deployer).to receive(:logger).and_return(double(task: nil)) }

    it "raises and runs no transfer when the remote dir is missing" do
      copier = deployer.instance_variable_get(:@copier)
      allow(copier).to receive(:exec!).and_return(["", "", 1])
      expect(deployer).not_to receive(:remote_get_directory)
      expect { deployer.send(:pull_plugins) }
        .to raise_error(Wordmove::RemotePathNotFound, /typo/)
    end

    it "proceeds when the remote dir exists" do
      copier = deployer.instance_variable_get(:@copier)
      allow(copier).to receive(:exec!).and_return(["", "", 0])
      expect(deployer).to receive(:remote_get_directory).once
      deployer.send(:pull_plugins)
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/deployer/ssh/scoped_transfer_spec.rb -e "scoped pull guard"`
Expected: FAIL — base `assert_remote_slug_dir!` raises `ImplementInSubclassError`, not `RemotePathNotFound`.

- [ ] **Step 3: Implement the SSH guard**

In `lib/wordmove/deployer/ssh.rb`, add inside the `private` section (e.g. after the `pull_exclude_paths` method):

```ruby
      def assert_remote_slug_dir!(task, slug)
        path = send("remote_#{task}_dir").path(slug)
        _stdout, _stderr, exit_code = @copier.exec!("test -d #{Shellwords.escape(path)}")
        return if exit_code.zero?

        raise Wordmove::RemotePathNotFound,
              "No remote #{task} dir '#{slug}' at #{path} — aborting to avoid deleting local data."
      end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/deployer/ssh/scoped_transfer_spec.rb -e "scoped pull guard"`
Expected: PASS (2 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/wordmove/deployer/ssh.rb spec/deployer/ssh/scoped_transfer_spec.rb
git commit -m "feat(ssh): guard scoped pull against a missing remote slug dir"
```

---

### Task 7: FTP scoped push + scoped-pull refusal

**Files:**
- Modify: `lib/wordmove/deployer/ftp.rb:72-86` (task loop) and add `assert_remote_slug_dir!`
- Test: `spec/deployer/ftp_spec.rb`

**Interfaces:**
- Consumes: `each_selected_slug` (Task 3), `WordpressDirectory#path(*args)` (`wordpress_directory.rb:25-27`), `paths_to_exclude`.
- Produces: FTP `push_<task>` / `pull_<task>` point source/dest at `path(slug)`; FTP override of `assert_remote_slug_dir!` raises `Wordmove::RemotePathNotFound` (scoped FTP pull unsupported — no public remote-dir check in Photocopier FTP).

- [ ] **Step 1: Write the failing tests**

Add to `spec/deployer/ftp_spec.rb` (the file already sets up `deployer` for `production`/FTP):

```ruby
  context "scoped push" do
    let(:options) { { config: movefile_path_for("multi_environments"), plugins: "mawinti" } }

    before do
      allow(deployer).to receive(:assert_local_slug_dir!)
      allow(deployer).to receive(:logger).and_return(double(task: nil))
    end

    it "points local and remote paths at the slug subdir" do
      expect(deployer).to receive(:remote_put_directory).once do |local, remote, _exclude|
        expect(local).to end_with("wp-content/plugins/mawinti")
        expect(remote).to end_with("wp-content/plugins/mawinti")
      end
      deployer.send(:push_plugins)
    end
  end

  context "scoped pull" do
    let(:options) { { config: movefile_path_for("multi_environments"), plugins: "mawinti" } }

    before { allow(deployer).to receive(:logger).and_return(double(task: nil)) }

    it "refuses (unsupported) and runs no transfer" do
      expect(deployer).not_to receive(:remote_get_directory)
      expect { deployer.send(:pull_plugins) }
        .to raise_error(Wordmove::RemotePathNotFound, /FTP/)
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/deployer/ftp_spec.rb -e "scoped"`
Expected: FAIL — scoped push ignores the slug (paths end at `.../plugins`), and scoped pull raises `ImplementInSubclassError`, not `RemotePathNotFound`.

- [ ] **Step 3: Rewrite the FTP task loop and add the refusal guard**

In `lib/wordmove/deployer/ftp.rb`, replace lines 72-86 with:

```ruby
      %w[uploads themes plugins mu_plugins languages].each do |task|
        define_method "push_#{task}" do
          logger.task "Pushing #{task.titleize}"
          each_selected_slug(task, :push) do |slug|
            local_path = send("local_#{task}_dir").path(*[slug].compact)
            remote_path = send("remote_#{task}_dir").path(*[slug].compact)
            remote_put_directory(local_path, remote_path, paths_to_exclude)
          end
        end

        define_method "pull_#{task}" do
          logger.task "Pulling #{task.titleize}"
          each_selected_slug(task, :pull) do |slug|
            local_path = send("local_#{task}_dir").path(*[slug].compact)
            remote_path = send("remote_#{task}_dir").path(*[slug].compact)
            remote_get_directory(remote_path, local_path, paths_to_exclude)
          end
        end
      end

      def assert_remote_slug_dir!(task, slug)
        raise Wordmove::RemotePathNotFound,
              "Scoped pull over FTP is not supported (slug '#{slug}' for #{task}): " \
              "Photocopier's FTP adapter can't verify the remote dir, and lftp would " \
              "mkdir it and wipe the local copy. Use SSH, or pull all and prune locally."
      end
```

(Place `assert_remote_slug_dir!` in the existing `private` section, which begins at `ftp.rb:70`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/deployer/ftp_spec.rb -e "scoped"`
Expected: PASS (2 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/wordmove/deployer/ftp.rb spec/deployer/ftp_spec.rb
git commit -m "feat(ftp): scoped push to slug subdir; refuse scoped pull (unsupported)"
```

---

### Task 8: Documentation — usage + `--no-*` regression note

**Files:**
- Modify: `README.md` (usage/flags section)
- Modify: `lib/wordmove/cli.rb` (the `desc` strings for `push`/`pull` if they enumerate flags — otherwise README only)

**Interfaces:**
- Consumes: behavior delivered in Tasks 1-7.
- Produces: user-facing docs. No code behavior change, so this task has no unit test; verification is the full suite staying green plus a manual `--help` check.

- [ ] **Step 1: Document the new syntax**

In `README.md`, in the flags/usage section, add:

```markdown
- `-t`, `--themes[=SLUG[,SLUG]]` — push/pull themes. Bare flag = all themes;
  `--themes=twentytwenty` = only that theme; `--themes=a,b` = only those.
- `-p`, `--plugins[=SLUG[,SLUG]]` — same, for plugins.
- `-m`, `--mu_plugins[=SLUG[,SLUG]]` — same, for must-use plugins.

Scoped syncs confine rsync/lftp `--delete` to the named subtree, so sibling
themes/plugins on the target are left untouched. Use `--plugins=foo` or the
short `-p foo` form; `-p=foo` is not supported.

Scoped **pull** is supported over SSH only. Over FTP it is refused (the FTP
adapter can't verify the remote dir and would risk deleting your local copy).
```

- [ ] **Step 2: Document the removed `--no-*` negation**

In `README.md`, add a short note near the same section:

```markdown
> **Note (v5.3+):** `--themes`, `--plugins`, and `--mu_plugins` now take an
> optional value, so the boolean negations `--no-themes` / `--no-plugins` /
> `--no-mu_plugins` are no longer accepted. To skip a component, simply omit
> its flag (or with `--all`, you can no longer single one of these out via
> `--no-…`).
```

- [ ] **Step 3: Verify the help text**

Run: `bundle exec exe/wordmove help push`
Expected: the three flags show as taking an optional value (Thor renders `[THEMES]` etc.).

- [ ] **Step 4: Commit**

```bash
git add README.md lib/wordmove/cli.rb
git commit -m "docs: document scoped --themes/--plugins/--mu_plugins and --no-* removal"
```

---

### Final verification

- [ ] **Run the whole suite + linter**

Run: `bundle exec rake`
Expected: RSpec all green, RuboCop no offenses.

- [ ] **Manual smoke (throwaway remote, optional but recommended)**

  - SSH: `wordmove push --plugins=mawinti -e staging` → confirm sibling remote plugins are NOT deleted.
  - SSH typo: `wordmove push --plugins=nope -e staging` → aborts with `LocalPathNotFound`, no rsync run.
  - FTP: `wordmove push --plugins=mawinti -e production` → only `mawinti` mirrored; siblings intact.
  - FTP pull: `wordmove pull --plugins=mawinti -e production` → refused with the FTP message.

---

## Self-Review

**1. Spec coverage vs. corrected design notes:**
- CLI overload + lazy_default + comma list + short form → Task 1. ✓
- `selected_slugs` treats boolean `true` as "all" (the uploads/languages bug) → Task 2 + explicit test. ✓
- `each_selected_slug` carries `action` so the guard knows direction → Task 3. ✓
- Push guard fires on BOTH adapters (rsync silently deletes a missing remote slug; it does not error) → Task 3 (`assert_local_slug_dir!` in shared Base, used by both). ✓
- Pull guard: SSH real remote check (Task 6); FTP refusal because no verified remote-dir API (Task 7). ✓
- `--no-*` regression documented → Task 8. ✓
- `-p=foo` unreliability / `-p foo` canonical → Task 1 test + Task 8 docs. ✓

**2. Placeholder scan:** No "TBD"/"handle appropriately"/"similar to Task N". Every code step shows full code; the previously-broken `raise … \n unless` modifier is replaced with `return if … ; raise …`. No fabricated Photocopier API — SSH `exec!` is verified; FTP remote-check is explicitly declared unsupported rather than invented.

**3. Type consistency:** `selected_slugs(task)`, `each_selected_slug(task, action)`, `assert_local_slug_dir!(task, slug)`, `assert_remote_slug_dir!(task, slug)`, and the four SSH builders `(task, slug = nil)` are named identically everywhere they appear (Tasks 2-7). The misspelling `push_inlcude_paths` is preserved consistently (Tasks 4-5).
