class Api::V1::Accounts::Jabvox::Tasks::StagesController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :set_board
  before_action :set_stage, only: %i[update destroy]
  # Managing stages is custom-role gated; standard agents keep historical behavior, admins pass.
  before_action -> { jabvox_gate!('jabvox_tasks_manage') }, only: %i[create update destroy reorder]
  # Borrar solo el administrador: un tablero o una columna arrastran en cascada
  # todas sus tareas, y eso no se delega en ningún rol.
  before_action :ensure_admin_for_destroy!, only: %i[destroy]

  # Tope defensivo al reordenar: un tablero real tiene unas pocas columnas. Sin él, una
  # lista enorme obligaría a construir un CASE gigante antes siquiera de validar nada.
  MAX_STAGES = 100

  def index
    render json: @board.stages.ordered.map { |s| serialize(s) }
  end

  def create
    stage = @board.stages.new(stage_params)
    stage.account = Current.account
    if stage.save
      render json: serialize(stage), status: :created
    else
      render json: { errors: stage.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    render json: { errors: [duplicate_role_message] }, status: :unprocessable_entity
  end

  def update
    if @stage.update(stage_params)
      render json: serialize(@stage)
    else
      render json: { errors: @stage.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    render json: { errors: [duplicate_role_message] }, status: :unprocessable_entity
  end

  def destroy
    @stage.destroy!
    head :no_content
  end

  # Reordena las columnas del tablero según el orden de ids recibido.
  #
  # Los ids llegan del cliente, así que se intersecan con los del tablero ANTES de tocar
  # nada: un id de otro tablero o de otra cuenta se descarta en silencio en vez de mover
  # columnas ajenas. La posición se deriva del índice en la lista ya validada, nunca de un
  # número que mande el cliente.
  def reorder
    ids = Array(params[:stage_ids]).first(MAX_STAGES).map(&:to_i).select(&:positive?).uniq
    own = @board.stages.where(id: ids).pluck(:id)
    ordered = ids & own
    return render json: { errors: ['stage_ids requerido'] }, status: :unprocessable_entity if ordered.empty?

    apply_order(ordered)
    render json: @board.stages.ordered.map { |s| serialize(s) }
  end

  private

  # Una sola sentencia con CASE en vez de N updates: un tablero con muchas columnas no
  # debe costar una consulta por columna. Los ids ya están validados contra el tablero, y
  # aun así viajan como parámetros ligados, no interpolados en el SQL.
  def apply_order(ordered_ids)
    cases = ordered_ids.each_with_index.map { |_, i| "WHEN ? THEN #{i}" }.join(' ')
    sql = ActiveRecord::Base.sanitize_sql_array(
      ["position_jabvox = CASE id #{cases} END", *ordered_ids]
    )
    # rubocop:disable Rails/SkipsModelValidations
    @board.stages.where(id: ordered_ids).update_all(sql)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Solo puede haber una columna inicial, una de completadas y una de inactivas por
  # tablero: lo garantiza un índice único parcial. Sin capturarlo, el intento salía como
  # un 500 con una página de error en vez de decir qué pasó.
  def duplicate_role_message
    I18n.t('jabvox.tasks.stage_role_taken',
           default: 'Ya hay otra columna con ese papel en este tablero')
  end

  def set_board
    @board = Current.account.jabvox_task_boards.find(params[:board_id])
  end

  def set_stage
    @stage = @board.stages.find(params[:id])
  end

  def stage_params
    params.require(:stage).permit(:name_jabvox, :color_jabvox, :position_jabvox, :role_jabvox,
                                  :card_sort_jabvox)
  end

  def serialize(stage)
    {
      id: stage.id, name_jabvox: stage.name_jabvox, color_jabvox: stage.color_jabvox,
      position_jabvox: stage.position_jabvox, role_jabvox: stage.role_jabvox,
      card_sort_jabvox: stage.card_sort_jabvox
    }
  end
end
