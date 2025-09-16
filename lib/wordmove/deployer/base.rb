require 'net/http'

module Wordmove
  module Deployer
    class Base
      attr_reader :options, :logger, :environment

      class << self
        def deployer_for(cli_options)
          movefile = Wordmove::Movefile.new(cli_options[:config])
          movefile.load_dotenv(cli_options)

          options = movefile.fetch.merge! cli_options
          environment = movefile.environment(cli_options)

          return FTP.new(environment, options) if options[environment][:ftp]

          return Ssh::WpcliSqlAdapter.new(environment, options) if options[environment][:ssh] && options[:global][:sql_adapter] == 'wpcli'

          return Ssh::DefaultSqlAdapter.new(environment, options) if options[environment][:ssh] && options[:global][:sql_adapter] == 'default'

          raise NoAdapterFound, "No valid adapter found."
        end

        def current_dir
          '.'
        end

        def logger(secrets)
          Logger.new($stdout, secrets).tap { |l| l.level = Logger::DEBUG }
        end
      end

      def initialize(environment, options = {})
        @environment = environment.to_sym
        @options = options

        movefile_secrets = Wordmove::Movefile.new(options[:config]).secrets
        @logger = self.class.logger(movefile_secrets)
      end

      def push_db
        logger.task "Pushing Database"
      end

      def pull_db
        logger.task "Pulling Database"
      end

      def remote_get_directory; end

      def remote_put_directory; end

      def exclude_dir_contents(path)
        "#{path}/*"
      end

      def push_wordpress
        logger.task "Pushing wordpress core"

        local_path = local_options[:wordpress_path]
        remote_path = remote_options[:wordpress_path]
        exclude_wp_content = exclude_dir_contents(local_wp_content_dir.relative_path)
        exclude_paths = paths_to_exclude.push(exclude_wp_content)

        remote_put_directory(local_path, remote_path, exclude_paths)
      end

      def pull_wordpress
        logger.task "Pulling wordpress core"

        local_path = local_options[:wordpress_path]
        remote_path = remote_options[:wordpress_path]
        exclude_wp_content = exclude_dir_contents(remote_wp_content_dir.relative_path)
        exclude_paths = paths_to_exclude.push(exclude_wp_content)

        remote_get_directory(remote_path, local_path, exclude_paths)
      end

      protected

      def paths_to_exclude
        remote_options[:exclude] || []
      end

      def run(cmd)
        if cmd.nil? || cmd.empty?
          logger.error("Empty command passed to run method")
          return false
        end

        logger.task(cmd)
        return if simulate?

        system(cmd.to_s) || raise("Error executing command: #{cmd}")
      end

      def download(url, local_path)
        logger.task("Downloading #{url}")

        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          request = Net::HTTP::Get.new(uri)

          http.request(request) do |response|
            raise "Failed to download file: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

            File.open(local_path, 'wb') do |file|
              response.read_body do |chunk|
                file.write(chunk)
              end
            end
          end
        end
      end

      def simulate?
        options[:simulate]
      end

      [
        WordpressDirectory::Path::WP_CONTENT,
        WordpressDirectory::Path::PLUGINS,
        WordpressDirectory::Path::MU_PLUGINS,
        WordpressDirectory::Path::THEMES,
        WordpressDirectory::Path::UPLOADS,
        WordpressDirectory::Path::LANGUAGES
      ].each do |type|
        %i[remote local].each do |location|
          define_method "#{location}_#{type}_dir" do
            options = send("#{location}_options")
            WordpressDirectory.new(type, options)
          end
        end
      end

      def mysql_dump_command(options, save_to_path)
        command = ["mysqldump"]
        command << "--host=#{Shellwords.escape(options[:host])}" if options[:host].present?
        command << "--port=#{Shellwords.escape(options[:port])}" if options[:port].present?
        command << "--user=#{Shellwords.escape(options[:user])}" if options[:user].present?
        command << "--password=#{Shellwords.escape(options[:password])}" if options[:password].present?
        command << "--result-file=\"#{save_to_path}\""
        command << Shellwords.split(options[:mysqldump_options]) if options[:mysqldump_options].present?
        command << Shellwords.escape(options[:name])
        command.join(" ")
      end

      def mysql_import_command(dump_path, options)
        command = ["mysql"]
        command << "--host=#{Shellwords.escape(options[:host])}" if options[:host].present?
        command << "--port=#{Shellwords.escape(options[:port])}" if options[:port].present?
        command << "--user=#{Shellwords.escape(options[:user])}" if options[:user].present?
        command << "--password=#{Shellwords.escape(options[:password])}" if options[:password].present?
        command << "--database=#{Shellwords.escape(options[:name])}"
        command << Shellwords.split(options[:mysql_options]) if options[:mysql_options].present?
        command << "--execute=\"SET autocommit=0;SOURCE #{dump_path};COMMIT\""
        command.join(" ")
      end

      def compress_command(path)
        command = ["gzip"]
        command << "-9"
        command << "-f"
        command << "\"#{path}\""
        command.join(" ")
      end

      def uncompress_command(path)
        command = ["gzip"]
        command << "-d"
        command << "-f"
        command << "\"#{path}\""
        command.join(" ")
      end

      def local_delete(path)
        logger.task_step true, "delete: '#{path}'"
        File.delete(path) unless simulate?
      end

      def save_local_db(local_dump_path)
        # dump local mysql into file
        run mysql_dump_command(local_options[:database], local_dump_path)
      end

      def remote_options
        options[environment].clone
      end

      def local_options
        options[:local].clone
      end
    end
  end
end
