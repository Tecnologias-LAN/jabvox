# frozen_string_literal: true

# Aprovisiona por cuenta (idempotente): team → MCPs por defecto → virtual server → scoped
# token, y persiste el handoff (token cifrado). Re-ejecutar reconcilia por external_id.
class ContextForge::AccountProvisioner
  # MCPs por defecto que se crean para cada cuenta al aprovisionar.
  DEFAULT_MCPS = [
    { kind: 'jabvox_core', name: 'Jabvox Core (cuenta)' },
    { kind: 'analytics_db', name: 'Analytics DB (cuenta)' },
    { kind: 'reports', name: 'Reportes (cuenta)' }
  ].freeze

  Result = Struct.new(:success, :handoff, :error, :steps, keyword_init: true) do
    def success? = success
  end

  def initialize(account, service: ContextForge::Service.new, extra_mcps: [])
    @account = account
    @service = service
    @extra_mcps = extra_mcps
    @steps = []
  end

  def call
    return guard_config unless ContextForge::Service.configured?

    @handoff = JabvoxContextForgeHandoff.find_or_create_by!(account_id: @account.id)
    @handoff.mark_provisioning!
    run_pipeline
  rescue StandardError => e
    Rails.logger.error("[ContextForge] provisioner error account=#{@account.id}: #{e.class}")
    @handoff&.mark_failed!("#{e.class}: #{e.message}")
    Result.new(success: false, error: e.message, steps: @steps)
  end

  private

  # Encadena las 4 etapas; corta en la primera que falle y deja el handoff en 'failed'.
  def run_pipeline
    team = step('team') { @service.ensure_team(@account) }
    return failed(team) unless team.success?

    team_id = dig_id(team.data)
    mcp_ids = provision_mcps(team_id)
    return failed(@last_fail) if @last_fail

    vserver = step('virtual_server') do
      @service.ensure_virtual_server(@account, team_id: team_id, mcp_server_ids: mcp_ids)
    end
    return failed(vserver) unless vserver.success?

    vs_id = dig_id(vserver.data)
    token = step('scoped_token') do
      @service.issue_scoped_token(@account, team_id: team_id, virtual_server_id: vs_id)
    end
    return failed(token) unless token.success?

    persist_ready(@handoff, team_id, vs_id, token.data)
    Result.new(success: true, handoff: @handoff.reload, steps: @steps)
  end

  def provision_mcps(team_id)
    @last_fail = nil
    (DEFAULT_MCPS + @extra_mcps).filter_map do |mcp|
      res = step("mcp:#{mcp[:kind]}") do
        @service.ensure_mcp_server(@account, team_id: team_id, kind: mcp[:kind],
                                             name: mcp[:name], config: mcp[:config] || {})
      end
      unless res.success?
        @last_fail = res
        break
      end
      dig_id(res.data)
    end
  end

  def persist_ready(handoff, team_id, vs_id, token_data)
    handoff.mark_ready!(
      contextforge_base_url: ContextForge::Service.base_url,
      team_id: team_id,
      virtual_server_id: vs_id,
      scoped_token: token_data.is_a?(Hash) ? (token_data['token'] || token_data['access_token']) : token_data,
      mcp_servers: @steps.select { |s| s[:name].start_with?('mcp:') }
                         .map { |s| { kind: s[:name].delete_prefix('mcp:'), ok: s[:ok] } }
    )
  end

  def step(name)
    res = yield
    ok = res.respond_to?(:success?) ? res.success? : true
    @steps << { name: name, ok: ok, error: (res.error if res.respond_to?(:error) && !ok) }
    Rails.logger.info("[ContextForge] account=#{@account.id} step=#{name} ok=#{ok}")
    res
  end

  def failed(res)
    @handoff.mark_failed!(res.error)
    Result.new(success: false, error: res.error, steps: @steps)
  end

  def guard_config
    Result.new(success: false, error: 'ContextForge no está configurado en el super admin.', steps: [])
  end

  def dig_id(data)
    return data if data.is_a?(String)

    data.is_a?(Hash) ? (data['id'] || data['external_id']) : nil
  end
end
