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
