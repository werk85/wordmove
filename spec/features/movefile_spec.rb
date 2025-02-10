describe Wordmove::Generators::Movefile do
  let(:movefile) { 'movefile.yml' }
  let(:tmpdir) { "/tmp/wordmove" }

  before do
    @pwd = Dir.pwd
    FileUtils.mkdir(tmpdir)
    Dir.chdir(tmpdir)
  end

  after do
    Dir.chdir(@pwd)
    FileUtils.rm_rf(tmpdir)
  end

  context "::start" do
    before do
      silence_stream($stdout) { Wordmove::Generators::Movefile.start }
    end

    it 'creates a Movefile' do
      expect(File.exist?(movefile)).to be true
    end

    it 'fills local wordpress_path using shell path' do
      yaml = if Gem::Version.new(YAML::VERSION) >= Gem::Version.new('4.0')
               YAML.safe_load(ERB.new(File.read(movefile)).result, permitted_classes: [],
                                                                   permitted_symbols: [], aliases: true)
             else
               YAML.safe_load(ERB.new(File.read(movefile)).result, [], [], true)
             end
      expect(yaml['local']['wordpress_path']).to eq(Dir.pwd)
    end

    it 'fills database configuration defaults' do
      yaml = if Gem::Version.new(YAML::VERSION) >= Gem::Version.new('4.0')
               YAML.safe_load(ERB.new(File.read(movefile)).result, permitted_classes: [],
                                                                   permitted_symbols: [], aliases: true)
             else
               YAML.safe_load(ERB.new(File.read(movefile)).result, [], [], true)
             end
      expect(yaml['local']['database']['name']).to eq('database_name')
      expect(yaml['local']['database']['user']).to eq('user')
      expect(yaml['local']['database']['password']).to eq('password')
      expect(yaml['local']['database']['host']).to eq('127.0.0.1')
    end

    it 'creates a Movifile having a "global.sql_adapter" key' do
      yaml = if Gem::Version.new(YAML::VERSION) >= Gem::Version.new('4.0')
               YAML.safe_load(ERB.new(File.read(movefile)).result, permitted_classes: [],
                                                                   permitted_symbols: [], aliases: true)
             else
               YAML.safe_load(ERB.new(File.read(movefile)).result, [], [], true)
             end
      expect(yaml['global']).to be_present
      expect(yaml['global']['sql_adapter']).to be_present
      expect(yaml['global']['sql_adapter']).to eq('wpcli')
    end
  end

  context "database configuration" do
    let(:wp_config) { File.join(File.dirname(__FILE__), "../fixtures/wp-config.php") }

    before do
      FileUtils.cp(wp_config, ".")
      silence_stream($stdout) { Wordmove::Generators::Movefile.start }
    end

    it 'fills database configuration from wp-config' do
      yaml = if Gem::Version.new(YAML::VERSION) >= Gem::Version.new('4.0')
               YAML.safe_load(ERB.new(File.read(movefile)).result, permitted_classes: [],
                                                                   permitted_symbols: [], aliases: true)
             else
               YAML.safe_load(ERB.new(File.read(movefile)).result, [], [], true)
             end
      expect(yaml['local']['database']['name']).to eq('wordmove_db')
      expect(yaml['local']['database']['user']).to eq('wordmove_user')
      expect(yaml['local']['database']['password']).to eq('wordmove_password')
      expect(yaml['local']['database']['host']).to eq('wordmove_host')
    end
  end
end
