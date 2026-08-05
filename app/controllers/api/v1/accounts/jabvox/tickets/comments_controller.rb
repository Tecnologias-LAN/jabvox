# Comentarios de un ticket. Las notas internas (private_jabvox) solo las ven/crean
# quienes pueden gestionar el ticket (staff/resolver asignado); un requester nunca
# ve ni crea notas internas.
class Api::V1::Accounts::Jabvox::Tickets::CommentsController <
      Api::V1::Accounts::Jabvox::Tickets::BaseController
  before_action :set_ticket

  def index
    @comments = @ticket.comments.includes(:user).order(created_at: :asc)
    @comments = @comments.public_comments unless can_manage_ticket?
  end

  def create
    is_private = ActiveModel::Type::Boolean.new.cast(params[:private]) && can_manage_ticket?
    @comment = @ticket.comments.create!(user: Current.user, body_jabvox: params.require(:body),
                                        private_jabvox: is_private)
    @ticket.log_activity!('commented', actor: Current.user, metadata: { private: is_private })
    Jabvox::Tickets::NotificationService.new(@ticket, actor: Current.user).comment_added(@comment)
    render :show, status: :created
  end

  private

  def set_ticket
    @ticket = JabvoxTicket.find(params[:ticket_id])
    authorize @ticket, :show?
  end

  def can_manage_ticket?
    JabvoxTicketPolicy.new(pundit_user, @ticket).update?
  end
end
