require 'spec_helper'

describe Wordmove::Connector do
  let(:movefile) { movefile_path_for('connect') }

  def connector_for(environment)
    silence_stream($stdout) { described_class.new(config: movefile, environment: environment) }
  end

  describe "#protocol" do
    it "picks ssh when only ssh is configured" do
      expect(connector_for('ssh_plain').protocol).to eq(:ssh)
    end

    it "picks ftp when only ftp is configured" do
      expect(connector_for('ftp_plain').protocol).to eq(:ftp)
    end

    it "prefers ftp when both are configured" do
      expect(connector_for('both').protocol).to eq(:ftp)
    end

    it "raises NoAdapterFound when neither is configured" do
      expect { connector_for('no_protocol').protocol }.to raise_error(Wordmove::NoAdapterFound, /no_protocol/)
    end
  end

  describe "environment selection" do
    it "raises UndefinedEnvironment for an unknown environment" do
      expect { connector_for('nope') }.to raise_error(Wordmove::UndefinedEnvironment)
    end

    it "raises UndefinedEnvironment when several environments exist and none is given" do
      expect { connector_for(nil) }.to raise_error(Wordmove::UndefinedEnvironment)
    end
  end

  describe "#command over ssh" do
    it "opens a login shell inside wordpress_path and ignores ssh.password" do
      env, argv = connector_for('ssh_plain').command

      expect(env).to eq({})
      expect(argv).to eq(["ssh", "-t", "deploy@ssh.example.com", "cd /var/www/my\\ site && exec $SHELL -l"])
      expect(argv.join(' ')).not_to include("ssh-secret")
    end

    it "passes port, key and gateway" do
      _env, argv = connector_for('ssh_full').command

      expect(argv).to eq(["ssh", "-p", "2222", "-i", "~/.ssh/id_deploy", "-J", "jump@bastion.example.com", "ssh.example.com"])
    end

    it "uses the bare host when no user is configured" do
      _env, argv = connector_for('ssh_no_user').command

      expect(argv).to eq(%w[ssh configured-alias])
    end
  end

  describe "#command over ftp" do
    it "passes the password through LFTP_PASSWORD, never argv" do
      env, argv = connector_for('ftp_plain').command

      expect(env).to eq("LFTP_PASSWORD" => "ftp-secret")
      expect(argv).to eq([
                           "lftp", "-p", "21", "-u", "ftpuser", "--env-password",
                           "-e", "set ftp:passive-mode true; cd /htdocs",
                           "ftp://ftp.example.com"
                         ])
      expect(argv.join(' ')).not_to include("ftp-secret")
    end

    it "honours the sftp scheme, infers port 22 and lets lftp prompt without a password" do
      env, argv = connector_for('ftp_sftp').command

      expect(env).to eq({})
      expect(argv).to eq(["lftp", "-p", "22", "-u", "ftpuser", "-e", "set ftp:passive-mode false", "sftp://sftp.example.com"])
    end
  end

  describe "#connect!" do
    it "execs the command with its environment" do
      connector = connector_for('ftp_plain')
      env, argv = connector.command
      allow(connector).to receive(:ensure_executable!)

      expect(Kernel).to receive(:exec).with(env, *argv)
      silence_stream($stdout) { connector.connect! }
    end

    it "warns about a gateway password and still connects" do
      connector = connector_for('ssh_full')
      allow(connector).to receive(:ensure_executable!)
      allow(Kernel).to receive(:exec)

      expect(connector.logger).to receive(:warn).with(/Gateway password/)
      silence_stream($stdout) { connector.connect! }
    end

    it "raises MissingExecutable when the binary is not on PATH" do
      connector = connector_for('ssh_plain')
      stub_const('ENV', ENV.to_h.merge('PATH' => '/nonexistent'))

      expect(Kernel).not_to receive(:exec)
      expect { silence_stream($stdout) { connector.connect! } }.to raise_error(Wordmove::MissingExecutable, /ssh/)
    end
  end
end
