require 'spec_helper'

describe Wordmove::Deployer::SystemAdapter do
  let(:ssh_options) do
    {
      host: 'example.com',
      user: 'deploy',
      port: 22,
      key: '/path/to/key'
    }
  end

  let(:adapter) { described_class.new(ssh_options) }
  let(:logger) { double('Logger') }

  before do
    adapter.logger = logger
    allow(logger).to receive(:task_step)
  end

  describe '#exec!' do
    it 'builds correct ssh command and executes it' do
      command = 'ls -la'
      expected_ssh_command = 'ssh -i /path/to/key deploy@example.com ls\\ -la'

      mock_status = double('Process::Status', success?: true, exitstatus: 0)
      expect(Open3).to receive(:capture3).with(expected_ssh_command)
                          .and_return(['stdout', 'stderr', mock_status])

      result = adapter.exec!(command)
      expect(result).to eq(['stdout', 'stderr', 0])
    end

    it 'handles commands with single quotes in password' do
      command = "mysql --password='test' db"
      expected_ssh_command = 'ssh -i /path/to/key deploy@example.com mysql\\ --password\\=\\\'test\\\'\\ db'

      mock_status = double('Process::Status', success?: true, exitstatus: 0)
      expect(Open3).to receive(:capture3).with(expected_ssh_command)
                          .and_return(['', '', mock_status])

      adapter.exec!(command)
    end
  end

  describe '#get' do
    it 'downloads file from remote to local' do
      remote_path = '/remote/path/file.txt'
      local_path = '/local/path/file.txt'
      expected_scp_command = 'scp -i /path/to/key deploy@example.com:/remote/path/file.txt /local/path/file.txt'

      expect(adapter).to receive(:system).with(expected_scp_command)

      adapter.get(remote_path, local_path)
    end
  end

  describe '#put' do
    it 'uploads file from local to remote' do
      local_path = '/local/path/file.txt'
      remote_path = '/remote/path/file.txt'
      expected_scp_command = 'scp -i /path/to/key /local/path/file.txt deploy@example.com:/remote/path/file.txt'

      expect(adapter).to receive(:system).with(expected_scp_command)

      adapter.put(local_path, remote_path)
    end
  end

  describe '#delete' do
    it 'deletes remote file' do
      remote_path = '/remote/path/file.txt'
      expected_ssh_command = 'ssh -i /path/to/key deploy@example.com rm\\ -rf\\ /remote/path/file.txt'

      expect(adapter).to receive(:system).with(expected_ssh_command)

      adapter.delete(remote_path)
    end
  end

  describe '#get_directory' do
    it 'syncs directory from remote to local' do
      remote_path = '/remote/path/'
      local_path = '/local/path/'
      expected_rsync_command = 'rsync -avz -e "ssh -i /path/to/key" /remote/path/ /local/path/'

      expect(adapter).to receive(:system).with(expected_rsync_command)

      adapter.get_directory(remote_path, local_path)
    end

    it 'includes exclude and include patterns' do
      remote_path = '/remote/path/'
      local_path = '/local/path/'
      exclude_patterns = ['*.tmp', 'cache/']
      include_patterns = ['important/']
      expected_rsync_command = 'rsync -avz -e "ssh -i /path/to/key" --exclude=\'*.tmp\' --exclude=\'cache/\' --include=\'important/\' /remote/path/ /local/path/'

      expect(adapter).to receive(:system).with(expected_rsync_command)

      adapter.get_directory(remote_path, local_path, exclude_patterns, include_patterns)
    end
  end

  describe 'command building with custom port' do
    let(:ssh_options) do
      {
        host: 'example.com',
        user: 'deploy',
        port: 2222,
        key: '/path/to/key'
      }
    end

    it 'includes port in ssh command' do
      command = 'ls'
      expected_ssh_command = 'ssh -p 2222 -i /path/to/key deploy@example.com ls'

      mock_status = double('Process::Status', success?: true, exitstatus: 0)
      expect(Open3).to receive(:capture3).with(expected_ssh_command)
                          .and_return(['', '', mock_status])

      adapter.exec!(command)
    end

    it 'includes port in scp command' do
      remote_path = '/remote/file'
      local_path = '/local/file'
      expected_scp_command = 'scp -P 2222 -i /path/to/key deploy@example.com:/remote/file /local/file'

      expect(adapter).to receive(:system).with(expected_scp_command)

      adapter.get(remote_path, local_path)
    end
  end

  describe 'command building without key' do
    let(:ssh_options) do
      {
        host: 'example.com',
        user: 'deploy',
        port: 22
      }
    end

    it 'builds ssh command without key option' do
      command = 'ls'
      expected_ssh_command = 'ssh deploy@example.com ls'

      mock_status = double('Process::Status', success?: true, exitstatus: 0)
      expect(Open3).to receive(:capture3).with(expected_ssh_command)
                          .and_return(['', '', mock_status])

      adapter.exec!(command)
    end
  end
end
