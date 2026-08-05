# Siembra un conjunto de categorías/temas por defecto para una cuenta recién
# habilitada en el módulo de tickets. Es idempotente: no duplica una categoría si
# ya existe otra con el mismo nombre en la cuenta.
class Jabvox::Tickets::DefaultCategoriesService
  DEFAULTS = [
    {
      name: 'Falla técnica', type: :incident, color: '#E5484D',
      response: 30, resolution: 240, position: 0
    },
    {
      name: 'Solicitud de acceso', type: :request, color: '#0091FF',
      response: 60, resolution: 480, position: 1
    },
    {
      name: 'Requerimiento funcional', type: :requirement, color: '#30A46C',
      response: 120, resolution: 2880, position: 2
    },
    {
      name: 'Consulta general', type: :request, color: '#F76B15',
      response: 60, resolution: 1440, position: 3
    }
  ].freeze

  def initialize(account)
    @account = account
  end

  def call
    DEFAULTS.each do |attrs|
      next if existing_names.include?(attrs[:name].downcase)

      create_category(attrs)
    end
    @account.jabvox_ticket_categories.count
  end

  private

  def existing_names
    @existing_names ||= JabvoxTicketCategory.for_account(@account.id)
                                            .pluck(:name_jabvox)
                                            .map(&:downcase)
  end

  def create_category(attrs)
    JabvoxTicketCategory.create!(
      account: @account,
      name_jabvox: attrs[:name],
      category_type_jabvox: attrs[:type],
      color_jabvox: attrs[:color],
      sla_response_minutes_jabvox: attrs[:response],
      sla_resolution_minutes_jabvox: attrs[:resolution],
      position_jabvox: attrs[:position],
      active_jabvox: true
    )
  end
end
