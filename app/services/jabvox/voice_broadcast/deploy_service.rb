# frozen_string_literal: true

require 'net/ssh'
require 'net/scp'

# Sube por SSH/SCP el WAV transcodificado del voice broadcast a la carpeta de sonidos
# de Asterisk en el PBX (servidores separados). Reutiliza las credenciales SSH del
# CdrConfig (las mismas que descargan las grabaciones). El dialplan referencia el
# audio con Playback(<SOUNDS_SUBDIR>/<filename>) SIN extensión.
class Jabvox::VoiceBroadcast::DeployService
  SSH_TIMEOUT = 20
  # Subcarpeta dedicada dentro de la ruta de sonidos del PBX (aislada por cuenta).
  # El dialplan usará: Playback(jabvox-vb/<filename>)
  SOUNDS_BASE = '/var/lib/asterisk/sounds/jabvox-vb'

  def initialize(account)
    @account = account
    @cfg = account.jabvox_cdr_config # reutiliza SSH del servidor de grabaciones
  end

  # Sube LOCAL_DIR/<filename>.wav al PBX. Devuelve true/false.
  def deploy(filename)
    return false unless ssh_configured?

    local = Jabvox::VoiceBroadcast::AudioService.local_path(filename)
    return false unless File.exist?(local)

    safe = safe_name(filename)
    remote = "#{SOUNDS_BASE}/#{safe}.wav"
    Net::SSH.start(@cfg.ssh_host, @cfg.ssh_username, ssh_options) do |ssh|
      # Asegura la carpeta destino (idempotente) y sube el archivo.
      ssh.exec!("mkdir -p #{shellescape(SOUNDS_BASE)} && chmod 755 #{shellescape(SOUNDS_BASE)}")
      ssh.scp.upload!(local, remote)
    end
    Rails.logger.info "[VoiceBroadcast] audio desplegado | #{remote}"
    true
  rescue Net::SSH::Exception, StandardError => e
    Rails.logger.error "[VoiceBroadcast] deploy failed | #{e.message}"
    false
  ensure
    # El WAV local ya no se necesita tras subirlo (evita acumular en tmp).
    FileUtils.rm_f(local) if local && File.exist?(local)
  end

  # Borra el audio del PBX (retención/limpieza al eliminar un broadcast).
  def remove(filename)
    return false unless ssh_configured?

    safe = safe_name(filename)
    remote = "#{SOUNDS_BASE}/#{safe}.wav"
    Net::SSH.start(@cfg.ssh_host, @cfg.ssh_username, ssh_options) do |ssh|
      ssh.exec!("rm -f #{shellescape(remote)}")
    end
    true
  rescue Net::SSH::Exception, StandardError => e
    Rails.logger.warn "[VoiceBroadcast] remove audio failed | #{e.message}"
    false
  end

  # Referencia que el dialplan pasa a Playback() (subcarpeta relativa a sounds,
  # SIN extensión). Asterisk resuelve /var/lib/asterisk/sounds/jabvox-vb/<file>.
  def self.playback_ref(filename)
    "jabvox-vb/#{filename.to_s.gsub(/[^a-z0-9_]/i, '')}"
  end

  private

  def ssh_configured?
    @cfg&.ssh_host.present? && @cfg&.ssh_username.present?
  end

  # Nombre base saneado: solo el basename, sin comodines ni metacaracteres, para
  # que nunca se cuele path traversal ni inyección en el scp/exec remoto.
  def safe_name(filename)
    File.basename(filename.to_s).gsub(/[^a-z0-9_]/i, '')
  end

  def ssh_options
    { password: @cfg.ssh_password, port: @cfg.ssh_port, timeout: SSH_TIMEOUT,
      non_interactive: true, number_of_password_prompts: 1, verify_host_key: :never }
  end

  def shellescape(str)
    "'#{str.to_s.gsub("'", "'\\\\''")}'"
  end
end
