# Fusiona un ticket (source) en otro (target), tratándolo como duplicado: mueve los
# comentarios al destino, deja un rastro en la bitácora de ambos, marca el origen
# como resuelto/duplicado y lo archiva. No borra datos.
class Jabvox::Tickets::MergeService
  def initialize(source:, target:, actor: nil)
    @source = source
    @target = target
    @actor = actor
  end

  def call
    raise ArgumentError, 'No se puede fusionar un ticket consigo mismo' if @source.id == @target.id

    ActiveRecord::Base.transaction do
      move_comments
      annotate
      close_source
    end
    @source
  end

  private

  def move_comments
    @source.comments.update_all(ticket_id: @target.id) # rubocop:disable Rails/SkipsModelValidations
    # Recalcula el counter_cache de comentarios en ambos tickets tras mover.
    recount_comments(@target)
    recount_comments(@source)
  end

  def recount_comments(ticket)
    count = JabvoxTicketComment.where(ticket_id: ticket.id).count
    ticket.update_column(:comments_count_jabvox, count) # rubocop:disable Rails/SkipsModelValidations
  end

  def annotate
    @target.log_activity!('merge_received', from: @source.display_id_jabvox, actor: @actor,
                                            metadata: { source_ticket_id: @source.id })
    @source.log_activity!('merged_into', to: @target.display_id_jabvox, actor: @actor,
                                         metadata: { target_ticket_id: @target.id })
  end

  def close_source
    unless @source.status_resolved? || @source.status_closed?
      @source.update!(status_jabvox: :resolved, resolution_type_jabvox: :duplicate,
                      resolution_jabvox: "Fusionado en ##{@target.display_id_jabvox}",
                      resolved_at_jabvox: Time.current)
    end
    @source.archive!(actor: @actor)
  end
end
