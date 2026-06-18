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

  context "comma-list push (two slugs)" do
    let(:deployer) { deployer_with(plugins: "alpha,beta") }

    before do
      allow(deployer).to receive(:assert_local_slug_dir!)
      allow(deployer).to receive(:logger).and_return(double(task: nil))
    end

    it "drives two scoped transfers, one per slug" do
      include_args = []
      allow(deployer).to receive(:remote_put_directory) do |_local, _remote, _exclude, include|
        include_args << include
      end
      deployer.send(:push_plugins)
      expect(include_args.size).to eq(2)
      expect(include_args.flatten).to include("/wp-content/plugins/alpha/")
      expect(include_args.flatten).to include("/wp-content/plugins/beta/")
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
end
