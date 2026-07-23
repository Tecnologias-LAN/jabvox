require 'net/ssh'
require 'net/scp'
require 'open3'

# Downloads a call recording from the PBX over SSH/SCP into a local temp file.
# The caller is responsible for cleaning up the returned Tempfile.
class Jabvox::CdrRecordingService
  SSH_TIMEOUT = 15
  # Timeout de la conversión de audio a MP3 (segundos).
  TRANSCODE_TIMEOUT = 30

  def initialize(config)
    @config = config
  end

  # Descarga la grabación y devuelve un archivo REPRODUCIBLE en el navegador.
  # Las grabaciones de Asterisk suelen ser WAV con códec GSM (0x0031), que el
  # elemento <audio> del navegador NO decodifica (mostraba 0 segundos). Aquí
  # convertimos a MP3 con ffmpeg. Devuelve { file:, content_type:, ext: } o nil.
  # Si ffmpeg no está disponible o la conversión falla, cae al archivo original
  # (mejor entregar el WAV crudo que nada).
  def download_playable(recording_file)
    src = download(recording_file)
    return nil if src.nil?

    mp3 = transcode_to_mp3(src.path)
    if mp3
      # Ya tenemos el MP3: el WAV original se borra de inmediato (no llena disco).
      src.close!
      { file: mp3, content_type: 'audio/mpeg', ext: '.mp3' }
    else
      # Fallback: el archivo original (WAV). Puede no reproducir si es GSM, pero
      # es preferible a no entregar nada; el content_type se decide en el caller.
      { file: src, content_type: nil, ext: File.extname(recording_file.to_s) }
    end
  rescue StandardError => e
    # Ante cualquier fallo, no dejar temporales huérfanos.
    src&.close!
    Rails.logger.error "[CDR] download_playable falló: #{e.message}"
    nil
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

  # Convierte el archivo de audio a MP3 con ffmpeg. Devuelve un Tempfile .mp3 con
  # contenido, o nil si ffmpeg no está o la conversión falla/da vacío. ffmpeg
  # decodifica el WAV-GSM de Asterisk sin problema y produce MP3 universal.
  def transcode_to_mp3(src_path)
    out = Tempfile.new(['cdr_recording', '.mp3'], binmode: true)
    # -y sobrescribe, -i entrada, -codec:a libmp3lame, -q:a 5 (~128kbps VBR).
    cmd = ['ffmpeg', '-y', '-i', src_path, '-codec:a', 'libmp3lame', '-q:a', '5', out.path]
    _stdout, stderr, status = Open3.capture3(*cmd, binmode: true)
    if status.success? && File.size(out.path).positive?
      out.rewind
      out
    else
      Rails.logger.warn "[CDR] transcodificación a MP3 falló: #{stderr.to_s[0, 300]}"
      out.close!
      nil
    end
  rescue Errno::ENOENT
    # ffmpeg no instalado: caemos al archivo original.
    Rails.logger.warn '[CDR] ffmpeg no está instalado; se entrega el audio sin convertir.'
    out&.close!
    nil
  rescue StandardError => e
    Rails.logger.warn "[CDR] error transcodificando grabación: #{e.message}"
    out&.close!
    nil
  end

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
