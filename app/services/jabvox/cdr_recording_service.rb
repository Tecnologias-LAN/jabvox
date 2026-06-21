require 'net/ssh'
require 'net/scp'

# Downloads a call recording from the PBX over SSH/SCP into a local temp file.
# The caller is responsible for cleaning up the returned Tempfile.
class Jabvox::CdrRecordingService
  SSH_TIMEOUT = 15

  def initialize(config)
    @config = config
  end

  # Verifies SSH credentials by opening a connection and running a trivial command.
  def test_connection
    Net::SSH.start(@config.ssh_host, @config.ssh_username, ssh_options) do |ssh|
      ssh.exec!('echo ok')
    end
    { success: true, message: 'Conexión SSH/SFTP con el servidor de grabaciones establecida.' }
  rescue Net::SSH::Exception, StandardError => e
    { success: false, message: e.message }
  end

  # Resolves the recording path on the PBX and downloads it.
  # `recording_file` is the bare filename from the cdr.recordingfile column.
  # Returns a Tempfile (binmode) or nil if not found / not configured.
  def download(recording_file)
    return nil unless @config.recordings_configured?
    return nil if recording_file.blank?

    remote_path = resolve_remote_path(recording_file)
    return nil if remote_path.blank?

    tmp = Tempfile.new(['cdr_recording', File.extname(recording_file).presence || '.wav'], binmode: true)
    Net::SSH.start(@config.ssh_host, @config.ssh_username, ssh_options) do |ssh|
      ssh.scp.download!(remote_path, tmp.path)
    end
    tmp.rewind
    tmp
  rescue Net::SSH::Exception, StandardError => e
    Rails.logger.error "[CDR] recording download failed: #{e.message}"
    tmp&.close!
    nil
  end

  private

  # Asterisk stores recordings in date-bucketed subfolders; `find` locates the file
  # regardless of layout. Falls back to joining the configured base path.
  def resolve_remote_path(recording_file)
    base = @config.recordings_path.to_s
    safe_name = recording_file.to_s.gsub(/['"`$;|&]/, '')
    found = nil
    Net::SSH.start(@config.ssh_host, @config.ssh_username, ssh_options) do |ssh|
      found = ssh.exec!("find #{shellescape(base)} -name #{shellescape(safe_name)} -type f 2>/dev/null | head -1").to_s.strip
    end
    found.presence || File.join(base, safe_name)
  rescue Net::SSH::Exception, StandardError => e
    Rails.logger.error "[CDR] recording path resolution failed: #{e.message}"
    nil
  end

  def ssh_options
    {
      password: @config.ssh_password,
      port: @config.ssh_port,
      timeout: SSH_TIMEOUT,
      non_interactive: true,
      number_of_password_prompts: 1,
      verify_host_key: :never
    }
  end

  def shellescape(str)
    "'#{str.to_s.gsub("'", "'\\\\''")}'"
  end
end
