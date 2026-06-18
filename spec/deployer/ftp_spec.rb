require 'spec_helper'

describe Wordmove::Deployer::FTP do
  let(:options) do
    { config: movefile_path_for("multi_environments") }
  end

  let(:deployer) do
    options[:environment] = "production"
    described_class.deployer_for(options.deep_symbolize_keys)
  end

  describe "#initialize" do
    it "creates an FTPAdapter instance" do
      expect(deployer.instance_variable_get(:@copier)).to be_a Wordmove::Deployer::FTPAdapter
    end
  end

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
end
