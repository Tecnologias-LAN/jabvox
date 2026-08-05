# CRUD de tickets + acciones de ciclo de vida (assign/change_status/resolve/reopen/
# rate). El listado y el acceso individual se filtran por JabvoxTicketPolicy::Scope y
# authorize, así que un requester nunca ve ni toca tickets ajenos por la API.
class Api::V1::Accounts::Jabvox::Tickets::TicketsController <
      Api::V1::Accounts::Jabvox::Tickets::BaseController
  include Api::V1::Accounts::Jabvox::Tickets::TicketFilters

  before_action :set_ticket,
                only: %i[show update destroy assign change_status resolve reopen rate restore merge]

  def index
    per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : DEFAULT_PER_PAGE
    scoped = policy_scope(JabvoxTicket)
    scoped = apply_filters(scoped)
    @total = scoped.count
    @tickets = apply_sort(scoped.includes(:category, :requester, :assignee, :contact))
               .page(params[:page] || 1).per(per_page)
  end

  def show; end

  def create
    return if replay_idempotent_create

    @ticket = build_ticket
    authorize @ticket, :create?
    @ticket.save!
    attach_files(@ticket)
    Jabvox::Tickets::AfterCreateService.new(@ticket, actor: Current.user).call
    remember_idempotent_create(@ticket)
    render :show, status: :created
  end

  def update
    authorize @ticket, :update?
    @ticket.update!(update_params)
    render :show
  end

  # Soft delete: archiva sin perder historial ni romper métricas.
  def destroy
    authorize @ticket, :destroy?
    @ticket.archive!(actor: Current.user)
    head :no_content
  end

  def assign
    authorize @ticket, :assign?
    assignee = params[:assignee_id].present? ? User.find(params[:assignee_id]) : nil
    @ticket.assign_to!(assignee, actor: Current.user)
    Jabvox::Tickets::NotificationService.new(@ticket, actor: Current.user).ticket_assigned
    render :show
  end

  def change_status
    authorize @ticket, :change_status?
    @ticket.change_status!(params.require(:status), actor: Current.user)
    Jabvox::Tickets::NotificationService.new(@ticket, actor: Current.user).status_changed
    render :show
  end

  def resolve
    authorize @ticket, :resolve?
    @ticket.resolve!(resolution: params[:resolution], resolution_type: params[:resolution_type],
                     actor: Current.user)
    Jabvox::Tickets::NotificationService.new(@ticket, actor: Current.user).ticket_resolved
    render :show
  end

  def reopen
    authorize @ticket, :reopen?
    @ticket.reopen!(actor: Current.user)
    Jabvox::Tickets::NotificationService.new(@ticket, actor: Current.user).ticket_reopened
    render :show
  end

  def rate
    authorize @ticket, :rate?
    @ticket.rate!(rating: params[:rating], comment: params[:comment], actor: Current.user)
    render :show
  end

  # Restaura un ticket archivado (soft-deleted).
  def restore
    authorize @ticket, :destroy?
    @ticket.update!(deleted_at_jabvox: nil)
    @ticket.log_activity!('restored', actor: Current.user)
    render :show
  end

  # Fusiona este ticket en otro (duplicados): lo marca resuelto como duplicate,
  # deja rastro en la bitácora de ambos y lo archiva.
  def merge
    authorize @ticket, :update?
    target = JabvoxTicket.find(params.require(:target_id))
    authorize target, :show?
    Jabvox::Tickets::MergeService.new(source: @ticket, target: target, actor: Current.user).call
    render :show
  end

  # Acción en lote: asigna/cierra/archiva varios tickets de una. La autorización
  # ocurre por ticket dentro del servicio (respeta la policy de cada uno).
  def bulk_action
    skip_authorization
    result = Jabvox::Tickets::BulkActionService.new(
      account: Current.account, actor: Current.user, policy: method(:authorize_for_bulk),
      action: params[:bulk_action_type], ids: Array(params[:ids]), value: params[:value]
    ).call
    render json: result
  end

  private

  # Autorización usada por el servicio de lote (respeta la policy por ticket).
  def authorize_for_bulk(ticket, query)
    authorize ticket, query
  end

  def set_ticket
    @ticket = JabvoxTicket.find(params[:id])
    authorize @ticket, :show?
  end

  # Idempotencia: si un create con la misma Idempotency-Key ya produjo un ticket,
  # devuelve ese en vez de duplicar (protege ante doble submit / reintentos de red).
  def replay_idempotent_create
    key = idempotency_cache_key
    return false if key.nil?

    existing_id = Rails.cache.read(key)
    return false if existing_id.nil?

    @ticket = JabvoxTicket.find_by(id: existing_id)
    return false if @ticket.nil?

    render :show, status: :ok
    true
  end

  def remember_idempotent_create(ticket)
    key = idempotency_cache_key
    Rails.cache.write(key, ticket.id, expires_in: 24.hours) if key
  end

  def idempotency_cache_key
    raw = request.headers['Idempotency-Key'].presence
    return nil if raw.nil?

    "jabvox_tickets/idempotency/#{Current.account.id}/#{Current.user.id}/#{raw}"
  end

  def build_ticket
    ticket = Current.account.jabvox_tickets.new(create_params)
    ticket.requester = Current.user
    inherit_from_conversation(ticket)
    ticket
  end

  # Crear-desde-conversación: hereda contacto y conversación.
  def inherit_from_conversation(ticket)
    return if params[:conversation_id].blank?

    conv = Current.account.conversations.find_by(display_id: params[:conversation_id])
    return if conv.nil?

    ticket.conversation_id = conv.id
    ticket.contact_id = conv.contact_id
  end

  def attach_files(ticket)
    ticket.attachments.attach(params[:attachments]) if params[:attachments].present?
  end

  def create_params
    params.permit(:title_jabvox, :description_jabvox, :ticket_category_id, :priority_jabvox,
                  custom_attributes_jabvox: {})
  end

  def update_params
    params.permit(:title_jabvox, :description_jabvox, :ticket_category_id, :priority_jabvox,
                  custom_attributes_jabvox: {})
  end
end
