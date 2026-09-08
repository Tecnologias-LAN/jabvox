# frozen_string_literal: true

require 'rails_helper'

# Tests de REGRESIÓN de la auditoría exhaustiva de autorización de Hermes.
# Cubren los 3 bugs corregidos y las invariantes de seguridad que deben mantenerse.
RSpec.describe 'Jabvox::Hermes authorization audit', type: :model do
  let(:account) { create(:account) }

  # Activa TODOS los módulos jabvox de la cuenta (para no depender del gate de módulo).
  before do
    Account.column_names.select { |c| c.end_with?('_enabled_jabvox') }.each do |col|
      account.update_column(col, true) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def agent_with(perms)
    role = create(:custom_role, account: account, permissions: perms)
    user = create(:user)
    create(:account_user, account: account, user: user, role: :agent, custom_role: role)
    user
  end

  def allows?(user, tool)
    Jabvox::Hermes::Authorizer.new(account: account, user: user).authorize(tool).allowed?
  end

  describe 'invariante: cero tools destructivas' do
    it 'ninguna tool tiene nombre ni método destructivo' do
      Jabvox::Hermes::ToolRegistry::TOOLS.each do |name, spec|
        expect(name).not_to match(/delete|destroy|remove|purge|erase|truncate/i)
        expect(spec[:method].to_s.upcase).not_to eq('DELETE')
        expect(spec[:permission].to_s).to be_in(%w[read create write])
      end
    end

    it 'los handlers del dialer (redial/exclude) NO borran filas' do
      src = File.read(Rails.root.join('app/services/jabvox/hermes/service_handlers.rb'))
      # Extrae el cuerpo de redial_dialer_lead y exclude_dialer_lead
      %w[redial_dialer_lead exclude_dialer_lead].each do |method|
        body = src[/def #{method}.*?\n  end/m]
        expect(body).to be_present
        expect(body).not_to match(/\.destroy!?\b/), "#{method} no debe llamar destroy"
      end
    end
  end

  describe 'BUG #2: automatizaciones avanzadas gestionables por conversation_manage' do
    it 'un rol con conversation_manage puede crear/guardar/activar flujos' do
      user = agent_with(['conversation_manage'])
      expect(allows?(user, 'create_flow')).to be(true)
      expect(allows?(user, 'save_flow_graph')).to be(true)
      expect(allows?(user, 'set_flow_status')).to be(true)
    end

    it 'la lectura de flujos es libre para cualquier miembro' do
      user = agent_with(['jabvox_products_manage']) # otro permiso cualquiera
      expect(allows?(user, 'get_flows')).to be(true)
    end

    it 'sin conversation_manage no puede gestionar flujos' do
      user = agent_with(['jabvox_products_manage'])
      expect(allows?(user, 'create_flow')).to be(false)
    end
  end

  describe 'BUG #3: manage implica lectura (no exige el permiso view por separado)' do
    it 'jabvox_analytics_manage permite ejecutar SQL read-only (tool de lectura)' do
      user = agent_with(['jabvox_analytics_manage'])
      expect(allows?(user, 'run_analytics_query')).to be(true)
      expect(allows?(user, 'get_analytics_dashboards')).to be(true)
    end

    it 'jabvox_analytics_access (solo view) lee pero NO escribe (read != write)' do
      user = agent_with(['jabvox_analytics_access'])
      expect(allows?(user, 'run_analytics_query')).to be(true)
      expect(allows?(user, 'create_analytics_dashboard')).to be(false)
      expect(allows?(user, 'update_analytics_dashboard')).to be(false)
    end
  end

  describe 'permisos de acción no estándar (send/use/assign) conceden gestión de SU módulo' do
    it 'jabvox_bulk_whatsapp_send permite crear un envío masivo' do
      user = agent_with(['jabvox_bulk_whatsapp_send'])
      expect(allows?(user, 'create_bulk_whatsapp_batch')).to be(true)
    end

    it 'jabvox_voice_broadcast_manage gestiona VB pero no otros módulos' do
      user = agent_with(['jabvox_voice_broadcast_manage'])
      expect(allows?(user, 'create_voice_broadcast')).to be(true)
      expect(allows?(user, 'start_voice_broadcast')).to be(true)
      expect(allows?(user, 'create_whatsapp_group')).to be(false)
      expect(allows?(user, 'create_product')).to be(false)
    end
  end

  describe 'aislamiento entre módulos (no escalamiento cross-module)' do
    it 'un permiso de un módulo no abre tools de escritura de otro' do
      user = agent_with(['jabvox_tasks_manage'])
      expect(allows?(user, 'create_task')).to be(true)
      %w[create_product create_voice_broadcast create_whatsapp_group create_analytics_dashboard
         create_sms_campaign create_affiliate].each do |tool|
        expect(allows?(user, tool)).to be(false), "#{tool} no debería estar permitido"
      end
    end
  end

  describe 'usuario sin permisos y agente base' do
    it 'un custom role vacío no puede escribir nada' do
      user = agent_with([])
      write_perms = %w[create write]
      writes = Jabvox::Hermes::ToolRegistry::TOOLS.select { |_, s| write_perms.include?(s[:permission].to_s) }.keys
      writes.each { |t| expect(allows?(user, t)).to be(false), "#{t} no debería permitirse a rol vacío" }
    end
  end

  describe 'módulos excluidos' do
    it 'ninguna tool declara un módulo excluido' do
      excluded = %w[jabvox_voip jabvox_softphone jabvox_lead_delete jabvox_saldo
                    jabvox_response_bot jabvox_ai_chat_provisioning]
      Jabvox::Hermes::ToolRegistry::TOOLS.each_value do |spec|
        expect(excluded).not_to include(spec[:feature].to_s)
      end
    end

    it 'jabvox_ai_chat es solo lectura' do
      ai = Jabvox::Hermes::ToolRegistry::TOOLS.select { |_, s| s[:feature].to_s == 'jabvox_ai_chat' }
      ai.each_value { |s| expect(s[:permission].to_s).to eq('read') }
    end
  end
end
