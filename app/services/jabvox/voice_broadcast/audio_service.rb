# frozen_string_literal: true

require 'open3'

# Valida y transcodifica el audio subido para el voice broadcast a formato nativo de
# Asterisk (WAV PCM 8kHz mono 16-bit), que Playback() reproduce sin transcodificar en
# vivo. Valida por CONTENIDO real (magic bytes vía ffprobe), no por extensión, acota
# tamaño y duración, y sanea el nombre. El resultado se deja en un directorio local
# fuera del webroot; el DeployService lo sube al PBX por SSH.
class Jabvox::VoiceBroadcast::AudioService
  MAX_BYTES = 10 * 1024 * 1024           # 10 MB
  MAX_DURATION_MS = 5 * 60 * 1000        # 5 min
  ACCEPTED_CODECS = %w[mp3 pcm_s16le pcm_u8 vorbis opus gsm aac].freeze
  # Directorio local (fuera del webroot) donde guardamos el WAV transcodificado.
  LOCAL_DIR = Rails.root.join('tmp/jabvox_voice_broadcast').freeze

  Result = Struct.new(:success, :filename, :duration_ms, :error, keyword_init: true)

  def initialize(account)
    @account = account
  end

  # Recibe un UploadedFile de Rails y un id de broadcast para nombrar el destino.
  # Devuelve Result(success:, filename:, duration_ms:, error:).
  def process(uploaded, broadcast_id) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return err('Archivo vacío') if uploaded.nil? || uploaded.size.to_i.zero?
    return err('El audio supera el tamaño máximo (10 MB).') if uploaded.size.to_i > MAX_BYTES

    src = copy_to_tmp(uploaded)
    meta = probe(src)
    return err(meta[:error]) unless meta[:ok]
    return err('Formato de audio no soportado.') unless ACCEPTED_CODECS.include?(meta[:codec])
    return err('El audio supera la duración máxima (5 min).') if meta[:duration_ms] > MAX_DURATION_MS

    filename = build_filename(broadcast_id)
    out = transcode(src, filename)
    return err('No se pudo transcodificar el audio.') unless out

    Result.new(success: true, filename: filename, duration_ms: meta[:duration_ms])
  ensure
    FileUtils.rm_f(src) if src && File.exist?(src)
  end

  # Ruta local absoluta del WAV transcodificado (para que el DeployService lo suba).
  def self.local_path(filename)
    LOCAL_DIR.join("#{filename}.wav").to_s
  end

  private

  def err(msg)
    Result.new(success: false, error: msg)
  end

  def copy_to_tmp(uploaded)
    FileUtils.mkdir_p(LOCAL_DIR)
    tmp = LOCAL_DIR.join("upload_#{SecureRandom.hex(8)}").to_s
    File.binwrite(tmp, uploaded.read)
    tmp
  end

  # ffprobe: lee el CONTENIDO real (magic bytes) — codec y duración. Rechaza si el
  # archivo no es un audio válido, sin importar su extensión/nombre.
  def probe(path)
    cmd = ['ffprobe', '-v', 'error', '-select_streams', 'a:0',
           '-show_entries', 'stream=codec_name:format=duration',
           '-of', 'default=noprint_wrappers=1:nokey=0', path]
    stdout, _stderr, status = Open3.capture3(*cmd)
    return { ok: false, error: 'El archivo no es un audio válido.' } unless status.success?

    codec = stdout[/codec_name=(\S+)/, 1].to_s
    dur_s = stdout[/duration=([\d.]+)/, 1].to_f
    return { ok: false, error: 'El audio no tiene pista de sonido.' } if codec.blank? || dur_s <= 0

    { ok: true, codec: codec, duration_ms: (dur_s * 1000).round }
  rescue Errno::ENOENT
    { ok: false, error: 'ffprobe no está instalado en el servidor.' }
  rescue StandardError => e
    { ok: false, error: "No se pudo analizar el audio: #{e.message}" }
  end

  # WAV PCM 8kHz mono 16-bit (formato que Asterisk reproduce nativo).
  def transcode(src, filename)
    FileUtils.mkdir_p(LOCAL_DIR)
    out = self.class.local_path(filename)
    cmd = ['ffmpeg', '-y', '-i', src, '-ar', '8000', '-ac', '1',
           '-acodec', 'pcm_s16le', '-f', 'wav', out]
    _o, stderr, status = Open3.capture3(*cmd, binmode: true)
    if status.success? && File.size(out).positive?
      out
    else
      Rails.logger.warn "[VoiceBroadcast] transcode failed: #{stderr.to_s[0, 300]}"
      FileUtils.rm_f(out)
      nil
    end
  rescue Errno::ENOENT
    Rails.logger.warn '[VoiceBroadcast] ffmpeg no instalado'
    nil
  rescue StandardError => e
    Rails.logger.warn "[VoiceBroadcast] transcode error: #{e.message}"
    nil
  end

  # Nombre base seguro y único, SIN extensión (Playback lo usa sin extensión).
  # Solo caracteres [a-z0-9_], cero riesgo de path traversal en el dialplan.
  def build_filename(broadcast_id)
    "vb_#{@account.id}_#{broadcast_id.to_i}_#{SecureRandom.hex(6)}".gsub(/[^a-z0-9_]/i, '')
  end
end
