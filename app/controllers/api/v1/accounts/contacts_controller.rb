class Api::V1::Accounts::ContactsController < Api::V1::Accounts::BaseController
  include Sift
  sort_on :email, type: :string
  sort_on :name, internal_name: :order_on_name, type: :scope, scope_params: [:direction]
  sort_on :phone_number, type: :string
  sort_on :last_activity_at, internal_name: :order_on_last_activity_at, type: :scope, scope_params: [:direction]
  sort_on :created_at, internal_name: :order_on_created_at, type: :scope, scope_params: [:direction]
  sort_on :company_name, internal_name: :order_on_company_name, type: :scope, scope_params: [:direction]
  sort_on :city, internal_name: :order_on_city, type: :scope, scope_params: [:direction]
  sort_on :country, internal_name: :order_on_country_name, type: :scope, scope_params: [:direction]

  RESULTS_PER_PAGE = 15
  # Tamaños que el usuario puede elegir en el pie de la lista. Se valida contra esta lista
  # para que un `per_page` arbitrario no pueda pedir la tabla entera.
  ALLOWED_PER_PAGE = [15, 25, 50, 100].freeze

  before_action :check_authorization
  before_action :set_current_page, only: [:index, :active, :search, :filter]
  before_action :fetch_contact, only: [:show, :update, :destroy, :avatar, :contactable_inboxes, :destroy_custom_attributes]
  before_action :set_include_contact_inboxes, only: [:index, :active, :search, :filter, :show, :update]

  def index
    @contacts = fetch_contacts(resolved_contacts)
    @contacts_count = @contacts.total_count
  end

  def search
    render json: { error: 'Specify search string with parameter q' }, status: :unprocessable_entity if params[:q].blank? && return

    contacts = Current.account.contacts.where(
      'name ILIKE :search OR email ILIKE :search OR phone_number ILIKE :search OR ' \
      'contacts.username ILIKE :search OR contacts.identifier LIKE :search',
      search: "%#{params[:q].strip}%"
    ).visible_to(Current.account_user)
    @contacts = fetch_contacts_with_has_more(contacts)
  end

  # POST /contacts/import_preview
  # Analiza las filas ANTES de importar y devuelve qué se crearía, qué ya
  # existe en la cuenta (por teléfono o correo exactos) y qué filas traen ya el
  # prefijo internacional. Es de solo lectura: no escribe nada.
  def import_preview
    return render(json: { error: I18n.t('errors.contacts.import.country_required') }, status: :unprocessable_entity) \
      unless Jabvox::LeadIdentityService.valid_country?(params[:country])

    rows = import_preview_rows
    return render(json: { error: I18n.t('errors.contacts.import.failed') }, status: :unprocessable_entity) if rows.blank?

    render json: Jabvox::LeadImportPreviewService.new(Current.account, rows, country_iso: params[:country]).call
  end

  def import
    render json: { error: I18n.t('errors.contacts.import.failed') }, status: :unprocessable_entity and return if params[:import_file].blank?
    return render(json: { error: I18n.t('errors.contacts.import.country_required') }, status: :unprocessable_entity) \
      unless Jabvox::LeadIdentityService.valid_country?(params[:country])

    ActiveRecord::Base.transaction do
      import = Current.account.data_imports.create!(data_type: 'contacts', source_metadata: import_metadata)
      import.import_file.attach(params[:import_file])
    end

    head :ok
  end

  def export
    column_names = params['column_names']
    filter_params = { :payload => params.permit!['payload'], :label => params.permit!['label'] }
    Account::ContactsExportJob.perform_later(Current.account.id, Current.user.id, column_names, filter_params)
    head :ok, message: I18n.t('errors.contacts.export.success')
  end

  def sample_import
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: 'Contacts') do |sheet|
      sheet.add_row %w[name email phone_number identifier company location campaign]
      sheet.add_row ['John Doe', 'john@example.com', '+15417543010', 'abc123', 'Acme Corp', 'New York', 'Spring 2026']
      sheet.add_row ['Jane Smith', 'jane@example.com', '+15417543011', 'def456', 'Widget Co', 'Los Angeles', '']
    end
    send_data package.to_stream.read,
              filename: 'import-contacts-sample.xlsx',
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

  # returns online contacts
  def active
    online_ids = ::OnlineStatusTracker.get_available_contact_ids(Current.account.id)
    contacts = Current.account.contacts.where(id: online_ids).visible_to(Current.account_user)
    @contacts = fetch_contacts(contacts)
    @contacts_count = @contacts.total_count
  end

  def show; end

  def filter
    result = ::Contacts::FilterService.new(Current.account, Current.user, params.permit!).perform
    contacts = result[:contacts]
    @contacts_count = result[:count]
    @contacts = fetch_contacts(contacts)
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue => e
    render_could_not_create_error(e.message)
  end

  def contactable_inboxes
    @all_contactable_inboxes = Contacts::ContactableInboxesService.new(contact: @contact).get
    @contactable_inboxes = @all_contactable_inboxes.select { |contactable_inbox| policy(contactable_inbox[:inbox]).show? }
  end

  # TODO : refactor this method into dedicated contacts/custom_attributes controller class and routes
  def destroy_custom_attributes
    @contact.custom_attributes = @contact.custom_attributes.excluding(params[:custom_attributes])
    @contact.save!
  end

  def create
    ActiveRecord::Base.transaction do
      @contact = find_existing_contact || Current.account.contacts.new
      attrs = permitted_params.except(:avatar_url).to_h
      attrs['name'] = @contact.name if @contact.persisted? && better_name?(@contact.name, attrs['name'])
      @contact.assign_attributes(attrs)
      @contact.save!
      @contact_inbox = build_contact_inbox
      process_avatar_from_url
    end
  end

  def update
    @contact.assign_attributes(contact_update_params)
    @contact.save!
    process_avatar_from_url
  end

  def destroy
    conversation_ids = @contact.conversations.select(:id)
    JabvoxKanbanConversationStage.where(conversation_id: conversation_ids).or(
      JabvoxKanbanConversationStage.where(contact_id: @contact.id)
    ).delete_all
    JabvoxCalendarEvent.where(contact_id: @contact.id).delete_all
    JabvoxSmsMessage.where(contact_id: @contact.id).delete_all
    @contact.destroy!
    head :ok
  end

  def avatar
    @contact.avatar.purge if @contact.avatar.attached?
    @contact
  end

  private

  # Solo se leen las tres claves que definen identidad y nombre. Cualquier otra
  # clave del payload se descarta: la vista previa no debe poder usarse para
  # sondear campos arbitrarios.
  IMPORT_PREVIEW_KEYS = %w[name email phone_number phone].freeze

  # País y política de duplicados del import, guardados en el DataImport para
  # que el job aplique exactamente lo que el usuario confirmó en la vista previa.
  # duplicate_policy solo admite los dos valores conocidos; cualquier otro cae
  # en 'skip' (no tocar el lead existente), que es la opción segura.
  def import_metadata
    policy = params[:duplicate_policy].to_s
    {
      'country' => params[:country].to_s.strip.upcase,
      'duplicate_policy' => (DataImport::DUPLICATE_POLICIES.include?(policy) ? policy : 'skip')
    }
  end

  def import_preview_rows
    Array(params[:rows]).filter_map do |row|
      next unless row.respond_to?(:to_unsafe_h) || row.is_a?(Hash)

      hash = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row
      hash.stringify_keys.slice(*IMPORT_PREVIEW_KEYS).presence
    end
  end

  # TODO: Move this to a finder class
  def resolved_contacts
    return @resolved_contacts if @resolved_contacts

    crm_v2 = Current.account.feature_enabled?('crm_v2')
    @resolved_contacts = Current.account.contacts.resolved_contacts(use_crm_v2: crm_v2).visible_to(Current.account_user)
    @resolved_contacts = @resolved_contacts.tagged_with(params[:labels], any: true) if params[:labels].present?
    @resolved_contacts
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def fetch_contacts(contacts)
    # Build includes hash to avoid separate query when contact_inboxes are needed
    includes_hash = { avatar_attachment: [:blob] }
    includes_hash[:contact_inboxes] = { inbox: :channel } if @include_contact_inboxes

    filtrate(contacts)
      .includes(includes_hash)
      .page(@current_page)
      .per(results_per_page)
  end

  # Tamaño de página pedido por el usuario, acotado a los valores permitidos.
  def results_per_page
    requested = params[:per_page].to_i
    ALLOWED_PER_PAGE.include?(requested) ? requested : RESULTS_PER_PAGE
  end

  def fetch_contacts_with_has_more(contacts)
    includes_hash = { avatar_attachment: [:blob] }
    includes_hash[:contact_inboxes] = { inbox: :channel } if @include_contact_inboxes

    # Calculate offset manually to fetch one extra record for has_more check
    per_page = results_per_page
    offset = (@current_page.to_i - 1) * per_page
    results = filtrate(contacts)
              .includes(includes_hash)
              .offset(offset)
              .limit(per_page + 1)
              .to_a

    @has_more = results.size > per_page
    results = results.first(per_page) if @has_more
    @contacts_count = results.size
    results
  end

  def build_contact_inbox
    return if params[:inbox_id].blank?

    inbox = Current.account.inboxes.find(params[:inbox_id])
    ContactInboxBuilder.new(
      contact: @contact,
      inbox: inbox,
      source_id: params[:source_id]
    ).perform
  end

  def find_existing_contact
    identifier = permitted_params[:identifier].presence
    phone = permitted_params[:phone_number].presence
    username = permitted_params[:username].to_s.sub(/\A@+/, '').strip.presence

    contact = Current.account.contacts.find_by(identifier: identifier) if identifier.present?
    contact ||= Current.account.contacts.find_by(phone_number: phone) if phone.present?
    contact ||= Current.account.contacts.where('LOWER(username) = ?', username.downcase).first if username.present?
    contact
  end

  # Returns true if existing_name is better than new_name (prefer human names over numeric IDs)
  def better_name?(existing_name, new_name)
    return false if existing_name.blank?
    return true if new_name.blank?

    existing_looks_human = existing_name !~ /\A[\d\s\+\-\.@]+\z/
    new_looks_numeric = new_name =~ /\A[\d\s\+\-\.@]+\z/

    existing_looks_human && new_looks_numeric
  end

  def permitted_params
    params.permit(:name, :identifier, :email, :phone_number, :username, :avatar, :blocked, :avatar_url, additional_attributes: {},
                                                                                                        custom_attributes: {})
  end

  def contact_custom_attributes
    return @contact.custom_attributes.merge(permitted_params[:custom_attributes]) if permitted_params[:custom_attributes]

    @contact.custom_attributes
  end

  def contact_additional_attributes
    return @contact.additional_attributes.merge(permitted_params[:additional_attributes]) if permitted_params[:additional_attributes]

    @contact.additional_attributes
  end

  def contact_update_params
    permitted_params.except(:custom_attributes, :avatar_url)
                    .merge({ custom_attributes: contact_custom_attributes })
                    .merge({ additional_attributes: contact_additional_attributes })
                    .merge(jabvox_campaign_params)
  end

  # La campaña del contacto se elige POR NOMBRE desde la ficha (el desplegable lista los
  # nombres de la cuenta). Antes esto vivía en el lead; ahora es una columna del contacto.
  # Solo se toca cuando la clave viene en la petición: omitirla no desasigna.
  def jabvox_campaign_params
    return {} unless params.key?(:jabvox_campaign_name)

    name = params[:jabvox_campaign_name].to_s.strip
    return { jabvox_campaign_id: nil } if name.blank?

    campaign = Current.account.jabvox_campaigns.find_by(name_jabvox: name)
    campaign ? { jabvox_campaign_id: campaign.id } : {}
  end

  def set_include_contact_inboxes
    @include_contact_inboxes = if params[:include_contact_inboxes].present?
                                 params[:include_contact_inboxes] == 'true'
                               else
                                 true
                               end
  end

  def fetch_contact
    contact_scope = Current.account.contacts
    contact_scope = contact_scope.includes(contact_inboxes: [:inbox]) if @include_contact_inboxes
    @contact = contact_scope.find(params[:id])
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@contact, params[:avatar_url]) if params[:avatar_url].present?
  end

  def render_error(error, error_status)
    render json: error, status: error_status
  end
end

Api::V1::Accounts::ContactsController.prepend_mod_with('Api::V1::Accounts::ContactsController')
