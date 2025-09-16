require 'shellwords'
require 'open3'

module Wordmove
  module Deployer
    class SystemAdapter
        attr_accessor :logger
        attr_reader :ssh_options

        def initialize(ssh_options)
          @ssh_options = ssh_options
          @logger = nil
        end

        def exec!(command)
          ssh_command = build_ssh_command(command)
          logger&.task_step(false, "Executing: #{ssh_command}")
          stdout, stderr, status = Open3.capture3(ssh_command)

          exit_code = status.is_a?(Integer) ? status : status.exitstatus
          success = status.is_a?(Integer) ? (status == 0) : status.success?

          return [stdout, stderr, exit_code] if success

          [stdout, stderr, exit_code]
        end

        def get(remote_path, local_path)
          scp_command = build_scp_get_command(remote_path, local_path)
          logger&.task_step(false, "Downloading: #{remote_path} -> #{local_path}")
          system(scp_command)
        end

        def put(local_path, remote_path)
          scp_command = build_scp_put_command(local_path, remote_path)
          logger&.task_step(false, "Uploading: #{local_path} -> #{remote_path}")
          system(scp_command)
        end

        def get_directory(remote_path, local_path, exclude_patterns = [], include_patterns = [])
          rsync_command = build_rsync_command(remote_path, local_path, exclude_patterns, include_patterns)
          logger&.task_step(false, "Syncing directory: #{remote_path} -> #{local_path}")
          system(rsync_command)
        end

        def put_directory(local_path, remote_path, exclude_patterns = [], include_patterns = [])
          rsync_command = build_rsync_command(local_path, remote_path, exclude_patterns, include_patterns)
          logger&.task_step(false, "Syncing directory: #{local_path} -> #{remote_path}")
          system(rsync_command)
        end

        def delete(remote_path)
          rm_command = build_ssh_command("rm -rf #{Shellwords.escape(remote_path)}")
          logger&.task_step(false, "Deleting: #{remote_path}")
          system(rm_command)
        end

        private

        def build_ssh_command(command)
          host = ssh_options[:host]
          user = ssh_options[:user]
          port = ssh_options[:port] || 22
          key_path = ssh_options[:key]

          cmd_parts = ["ssh"]
          cmd_parts << "-p #{port}" if port != 22
          cmd_parts << "-i #{Shellwords.escape(key_path)}" if key_path
          cmd_parts << "#{user}@#{host}"
          cmd_parts << Shellwords.escape(command)

          cmd_parts.join(" ")
        end

        def build_scp_get_command(remote_path, local_path)
          host = ssh_options[:host]
          user = ssh_options[:user]
          port = ssh_options[:port] || 22
          key_path = ssh_options[:key]

          cmd_parts = ["scp"]
          cmd_parts << "-P #{port}" if port != 22
          cmd_parts << "-i #{Shellwords.escape(key_path)}" if key_path

          cmd_parts << "#{user}@#{host}:#{remote_path}"
          cmd_parts << local_path

          cmd_parts.join(" ")
        end

        def build_scp_put_command(local_path, remote_path)
          host = ssh_options[:host]
          user = ssh_options[:user]
          port = ssh_options[:port] || 22
          key_path = ssh_options[:key]

          cmd_parts = ["scp"]
          cmd_parts << "-P #{port}" if port != 22
          cmd_parts << "-i #{Shellwords.escape(key_path)}" if key_path

          cmd_parts << local_path
          cmd_parts << "#{user}@#{host}:#{remote_path}"

          cmd_parts.join(" ")
        end

        def build_rsync_command(source, destination, exclude_patterns = [], include_patterns = [])
          host = ssh_options[:host]
          user = ssh_options[:user]
          port = ssh_options[:port] || 22
          key_path = ssh_options[:key]

          cmd_parts = ["rsync", "-avz"]
          cmd_parts << "--port=#{port}" if port != 22
          cmd_parts << "-e \"ssh -i #{Shellwords.escape(key_path)}\"" if key_path

          exclude_patterns.each { |pattern| cmd_parts << "--exclude='#{pattern}'" }
          include_patterns.each { |pattern| cmd_parts << "--include='#{pattern}'" }

          cmd_parts << source
          cmd_parts << destination

          cmd_parts.join(" ")
        end
      end
    end
end
