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
end
