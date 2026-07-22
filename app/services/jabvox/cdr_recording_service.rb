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

    # Defensa en profundidad: nos quedamos SOLO con el nombre base. Aunque el
    # nombre viene de datos server-side (columna recordingfile del PBX / fila de
    # análisis), un valor con `../`, ruta absoluta o comodines de glob (`*?[`)
    # permitiría leer/descargar un archivo distinto al solicitado. File.basename
    # elimina cualquier componente de directorio y sanitize_name los comodines.
    safe_name = sanitize_name(recording_file)
    remote_path = safe_name.present? ? resolve_remote_path(safe_name) : nil
    return nil if remote_path.blank?

    tmp = Tempfile.new(['cdr_recording', File.extname(safe_name).presence || '.wav'], binmode: true)
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
  # `safe_name` YA viene saneado (solo nombre base, sin comodines) por sanitize_name.
  def resolve_remote_path(safe_name)
    base = @config.recordings_path.to_s
    found = nil
    Net::SSH.start(@config.ssh_host, @config.ssh_username, ssh_options) do |ssh|
      found = ssh.exec!("find #{shellescape(base)} -name #{shellescape(safe_name)} -type f 2>/dev/null | head -1").to_s.strip
    end
    # Solo aceptamos un resultado que caiga DENTRO del directorio base configurado;
    # cualquier ruta fuera de la base se descarta y se usa el fallback base/name.
    return found if found.present? && path_within_base?(found, base)

    File.join(base, safe_name)
  rescue Net::SSH::Exception, StandardError => e
    Rails.logger.error "[CDR] recording path resolution failed: #{e.message}"
    nil
  end

  # Nombre de archivo seguro: solo el basename (elimina `/` y `..`) y sin comodines
  # de glob ni metacaracteres de shell que find/scp pudieran interpretar.
  def sanitize_name(recording_file)
    File.basename(recording_file.to_s).gsub(/[*?\[\]'"`$;|&]/, '')
  end

  # true si `path` (ruta remota devuelta por find) está bajo `base`. Normaliza
  # ambos con expand_path (colapsa `..`) para bloquear escapes del directorio base.
  def path_within_base?(path, base)
    normalized = File.expand_path(path)
    root = File.expand_path(base)
    normalized == root || normalized.start_with?("#{root}/")
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
