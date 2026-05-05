class Api::V1::Accounts::Jabvox::AiChatMessagesController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled

  def my_access
    perm = JabvoxAiChatUserPermission.for(Current.account.id, current_user.id)
    render json: {
      can_use: perm.persisted? ? perm.can_use_jabvox : true,
      can_use_models: perm.persisted? ? perm.can_use_models_jabvox : true,
      can_use_documents: perm.persisted? ? perm.can_use_documents_jabvox : true
    }
  end

  def sessions
    sessions_data = JabvoxAiChatMessage
                    .where(account_id: Current.account.id, user_id: current_user.id)
                    .select(:session_id_jabvox, :created_at)
                    .group(:session_id_jabvox, :created_at)
                    .order(created_at: :asc)

    grouped = sessions_data.each_with_object({}) do |m, h|
      sid = m.session_id_jabvox
      h[sid] ||= { session_id: sid, created_at: m.created_at, last_message_at: m.created_at }
      h[sid][:last_message_at] = m.created_at if m.created_at > h[sid][:last_message_at]
    end

    render json: grouped.values.sort_by { |s| s[:last_message_at] }.reverse
  end

  def index
    session_id = params[:session_id]
    page = (params[:page] || 1).to_i
    per = 50

    messages = JabvoxAiChatMessage
               .where(account_id: Current.account.id, user_id: current_user.id, session_id_jabvox: session_id)
               .order(created_at: :asc)
               .offset((page - 1) * per)
               .limit(per)

    render json: messages.map { |m| message_json(m) }
  end

  def create
    check_access!
    return if performed?

    check_open_chats_limit!
    return if performed?

    session_id = params[:session_id].presence || SecureRandom.uuid
    mode = params[:mode].presence&.in?(%w[model documents]) ? params[:mode] : 'model'

    model_record = find_model(params[:model_id])
    raise 'No hay ningún modelo de IA configurado para esta cuenta.' unless model_record

    history = JabvoxAiChatMessage
                .where(account: Current.account, user: current_user, session_id_jabvox: session_id)
                .order(:created_at)
                .last(20)

    service = Jabvox::AiChatService.new(account: Current.account, user: current_user, model_record: model_record)
    response_text = service.send_message(content: params[:content], session_id: session_id, mode: mode, history: history)

    user_msg = JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user,
      session_id_jabvox: session_id, role_jabvox: 'user', content_jabvox: params[:content],
      metadata_jabvox: { mode: mode }
    )
    assistant_msg = JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user,
      session_id_jabvox: session_id, role_jabvox: 'assistant', content_jabvox: response_text,
      metadata_jabvox: { mode: mode, model: model_record.model_jabvox }
    )

    render json: { session_id: session_id, message: message_json(assistant_msg) }, status: :created
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    JabvoxAiChatMessage.where(
      account_id: Current.account.id,
      user_id: current_user.id,
      session_id_jabvox: params[:id]
    ).destroy_all
    head :ok
  end

  private

  def check_feature_enabled
    render json: { error: 'Chat IA no está habilitado para esta cuenta.' }, status: :forbidden unless Current.account.jabvox_ai_chat_enabled_jabvox
  end

  def check_access!
    perm = JabvoxAiChatUserPermission.for(Current.account.id, current_user.id)
    can_use = perm.persisted? ? perm.can_use_jabvox : true
    render json: { error: 'No tienes acceso al Chat IA.' }, status: :forbidden and return unless can_use
  end

  def check_open_chats_limit!
    max = Current.account.jabvox_ai_chat_max_open_chats_jabvox
    return unless max > 0

    count = JabvoxAiChatMessage
            .where(account_id: Current.account.id, user_id: current_user.id)
            .distinct.count(:session_id_jabvox)
    return unless count >= max
    return if params[:session_id].present?

    render json: { error: "Has alcanzado el límite de #{max} conversaciones abiertas." }, status: :unprocessable_entity
  end

  def find_model(model_id)
    if model_id.present?
      Current.account.jabvox_ai_chat_models.find_by(id: model_id)
    else
      JabvoxAiChatModel.default_for(Current.account.id) ||
        Current.account.jabvox_ai_chat_models.first
    end
  end

  def message_json(m)
    { id: m.id, session_id: m.session_id_jabvox, role: m.role_jabvox, content: m.content_jabvox, metadata: m.metadata_jabvox, created_at: m.created_at }
  end
end
