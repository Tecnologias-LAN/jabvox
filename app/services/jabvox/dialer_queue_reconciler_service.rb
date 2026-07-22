# frozen_string_literal: true

# Reconcilia las colas del dialer en Asterisk contra las sesiones activas en Redis.
#
# Regla ESTRICTA: un agente solo puede ser miembro de la cola de la campaña a la
# que está conectado AHORA (sesión viva en Redis). Cualquier otra membresía es
# fantasma y se elimina:
#   - agente que cerró el navegador / se le cayó la red (nunca llamó a disconnect)
#   - sesión Redis expirada por TTL
#   - agente en la cola de una campaña distinta a la que está conectado
#
# Solo ejecuta QueueRemove de miembros; NUNCA crea, modifica ni elimina colas.
#
# Fuentes de verdad:
#   - Conectados: SET Redis  jabvox_dialer_connected_<account>
#   - Estado del agente:     jabvox_dialer_agent_<account>_<user>  (trae campaign_id + extension)
#   - Miembros reales:       QueueStatus de Asterisk (DialerService#dialer_queue_members)
module Jabvox
  class DialerQueueReconcilerService
    def self.reconcile_account(account)
      new(account).reconcile
    end

    def initialize(account)
      @account = account
    end

    # Devuelve { reachable:, removed: }.
    #   reachable: false  => no se pudo hablar con el PBX (apagado/inalcanzable);
    #                        el job cachea la cuenta para saltarla un rato.
    #   removed:          => nº de miembros fantasma removidos.
    def reconcile
      config = @account.jabvox_voip_config
      return { reachable: true, removed: 0 } if config&.host.blank?

      service = Jabvox::DialerService.new(config)
      # queue_exists? hace una conexión AMI corta; si el PBX no responde lo sabemos
      # rápido y sin recorrer nada. (Cualquier cola sirve de "ping"; usamos una
      # inexistente: solo nos importa si el socket AMI respondió.)
      return { reachable: false, removed: 0 } unless service.ami_reachable?

      members_by_queue = service.dialer_queue_members
      return { reachable: true, removed: 0 } if members_by_queue.empty?

      removed = remove_phantoms(service, members_by_queue, legit_memberships)
      { reachable: true, removed: removed }
    rescue StandardError => e
      Rails.logger.error "❌ [QueueReconciler] cuenta=#{@account.id} #{e.class}: #{e.message}"
      { reachable: false, removed: 0 }
    end

    private

    # Quita de cada cola a los miembros que NO estén en el set de membresías
    # legítimas. Devuelve cuántos removió.
    def remove_phantoms(service, members_by_queue, legit)
      removed = 0
      members_by_queue.each do |queue, exts|
        exts.uniq.each do |ext|
          next if legit.include?("#{queue}|#{ext}")

          service.remove_from_queue(queue, ext)
          removed += 1
          Rails.logger.info "🧹 [QueueReconciler] cuenta=#{@account.id} removido fantasma queue=#{queue} ext=#{ext}"
        end
      end
      removed
    end

    # Conjunto de membresías legítimas AHORA: por cada agente conectado, la cola de
    # su campaña actual con su extensión. Solo cuenta si tiene campaña y extensión.
    def legit_memberships
      set = Set.new
      connected_agent_ids.each do |uid|
        state = agent_state(uid)
        next unless state

        campaign_id = state[:campaign_id]
        ext = state[:extension].to_s
        next if campaign_id.blank? || ext.blank?

        set << "dialer_camp_#{campaign_id}|#{ext}"
      end
      set
    end

    def connected_agent_ids
      Redis::Alfred.smembers("jabvox_dialer_connected_#{@account.id}").map(&:to_i)
    rescue StandardError
      []
    end

    def agent_state(uid)
      raw = Redis::Alfred.get("jabvox_dialer_agent_#{@account.id}_#{uid}")
      raw ? JSON.parse(raw, symbolize_names: true) : nil
    rescue StandardError
      nil
    end
  end
end
