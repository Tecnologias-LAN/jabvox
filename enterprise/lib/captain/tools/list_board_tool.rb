# frozen_string_literal: true

# Tool nativa de Jabvox IA: lista los tableros de tareas de la cuenta con sus
# etapas, para que el asistente sepa a qué tablero/etapa puede crear una tarea
# (el agente elige el tablero). Devuelve los IDs que luego usa la tool crear_tarea.
class Captain::Tools::ListBoardTool < Captain::Tools::BasePublicTool
  description 'Lista los tableros de tareas disponibles y sus etapas (con sus IDs). ' \
              'Úsala para saber a qué tablero y etapa se puede crear una tarea antes ' \
              'de usar la herramienta de crear tarea.'

  def perform(_tool_context, **_args)
    boards = @assistant.account.jabvox_task_boards.active.ordered.includes(:stages)
    return 'No hay tableros de tareas configurados en esta cuenta.' if boards.empty?

    log_tool_usage('listar_tableros_tareas', { boards: boards.size })
    boards.map { |board| describe_board(board) }.join("\n\n")
  end

  private

  def describe_board(board)
    stages = board.stages.ordered
    etapas = if stages.any?
               stages.map { |s| "  - Etapa \"#{s.name_jabvox}\" (id: #{s.id})" }.join("\n")
             else
               '  (sin etapas)'
             end
    "Tablero \"#{board.name_jabvox}\" (id: #{board.id}):\n#{etapas}"
  end
end
