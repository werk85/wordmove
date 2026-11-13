require 'shellwords'

module Wordmove
  # Opens an interactive shell (ssh) or FTP session (lftp) on a remote environment.
  # FTP takes precedence over SSH, matching Deployer::Base.deployer_for.
  class Connector
    attr_reader :environment, :remote_options, :logger

    def initialize(cli_options)
      movefile = Wordmove::Movefile.new(cli_options[:config])
      movefile.load_dotenv(cli_options)

      options = movefile.fetch.merge!(cli_options)
      @environment = movefile.environment(cli_options)
      @remote_options = options[environment] || {}
      @logger = Logger.new($stdout, movefile.secrets).tap { |l| l.level = Logger::DEBUG }
    end

    def protocol
      return :ftp if remote_options[:ftp]
      return :ssh if remote_options[:ssh]

      raise NoAdapterFound, "No ssh or ftp configuration found for environment \"#{environment}\"."
    end

    # Returns [env, argv] for Kernel.exec. Passwords travel only through env, never argv.
    def command
      protocol == :ftp ? lftp_command : ssh_command
    end

    def connect!
      env, argv = command
      ensure_executable!(argv.first)

      logger.task("Connecting to #{environment} via #{protocol}")
      logger.warn("Gateway passwords can't be passed to ssh -J; enter it at the prompt.") if gateway_password?
      logger.plain(argv.shelljoin)
      $stdout.flush

      Kernel.exec(env, *argv)
    end

    private

    def gateway_password?
      protocol == :ssh && remote_options.dig(:ssh, :gateway, :password).present?
    end

    def wordpress_path
      remote_options[:wordpress_path].presence
    end

    # ssh.password is deliberately not used: ssh prompts for whatever the server
    # requires, which also covers accounts demanding a key plus a password.
    def ssh_command
      ssh = remote_options[:ssh]

      argv = ["ssh"]
      argv.push("-p", ssh[:port].to_s) if ssh[:port].present?
      argv.push("-i", ssh[:key].to_s) if ssh[:key].present?
      argv.push("-J", jump_host(ssh[:gateway])) if ssh[:gateway].present?

      if wordpress_path
        argv.push("-t", ssh_target(ssh[:user], ssh[:host]))
        argv.push("cd #{Shellwords.escape(wordpress_path)} && exec $SHELL -l")
      else
        argv.push(ssh_target(ssh[:user], ssh[:host]))
      end

      [{}, argv]
    end

    def jump_host(gateway)
      target = ssh_target(gateway[:user], gateway[:host])
      gateway[:port].present? ? "#{target}:#{gateway[:port]}" : target
    end

    def ssh_target(user, host)
      user.present? ? "#{user}@#{host}" : host.to_s
    end

    def lftp_command
      ftp = remote_options[:ftp]
      env = {}

      argv = ["lftp"]
      argv.push("-p", ftp_port(ftp).to_s)
      argv.push("-u", ftp[:user].to_s) if ftp[:user].present?
      if ftp[:password].present?
        env["LFTP_PASSWORD"] = ftp[:password].to_s
        argv.push("--env-password")
      end
      argv.push("-e", lftp_startup_commands(ftp))
      argv.push("#{ftp[:scheme].presence || 'ftp'}://#{ftp[:host]}")

      [env, argv]
    end

    # Same defaults as Photocopier::FTP#inferred_port.
    def ftp_port(ftp)
      return ftp[:port] if ftp[:port].present?

      ftp[:scheme] == 'sftp' ? 22 : 21
    end

    def lftp_startup_commands(ftp)
      commands = ["set ftp:passive-mode #{ftp[:passive] || 'false'}"]
      commands << "cd #{Shellwords.escape(wordpress_path)}" if wordpress_path
      commands.join('; ')
    end

    def ensure_executable!(name)
      found = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, name)
        File.file?(path) && File.executable?(path)
      end
      return if found

      raise MissingExecutable, "`#{name}` was not found in your PATH. Please install it to use `wordmove connect`."
    end
  end
end
