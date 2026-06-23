# frozen_string_literal: true

# Reporte interno de Chat IA para el módulo Analytics de Jabvox.
#
# Fuente principal: jabvox_ai_chat_messages (siempre acotado por la cuenta vía
# la asociación account.jabvox_ai_chat_messages, nunca un scope global).
#
# Lógica de negocio: solo se cuentan las PREGUNTAS HUMANAS, es decir, las filas
# con role_jabvox = 'user' (se ignoran las respuestas del asistente con
# role_jabvox = 'assistant'). Las métricas se agrupan por usuario (user_id) y
# por día sobre created_at. Las sesiones (session_id_jabvox) se cuentan como
# valores distintos para estimar conversaciones.
#
# NOTA: La tabla no tiene columna de estado ni FK de agente separada; user_id es
# el único FK de usuario disponible.
module Jabvox
  module Analytics
    module Reports
      class ChatAiReportService
        USER_ROLE = 'user'

        def initialize(account:, date_from: nil, date_to: nil, filters: {})
          raise ArgumentError, 'account is required' if account.nil?

          @account = account
          @date_from = date_from
          @date_to = date_to
          @filters = filters || {}
        end

        def call
          {
            summary: summary,
            series: series,
            by_user: by_user,
            by_user_day: by_user_day
          }
        end

        private

        attr_reader :account, :date_from, :date_to, :filters

        # Scope base: SIEMPRE arranca de la asociación de la cuenta y se limita a
        # las preguntas humanas (role_jabvox = 'user'). Filtro adicional: user_id.
        def scope
          relation = account.jabvox_ai_chat_messages.where(role_jabvox: USER_ROLE)
          relation = relation.where('jabvox_ai_chat_messages.created_at >= ?', date_from) if date_from.present?
          relation = relation.where('jabvox_ai_chat_messages.created_at <= ?', date_to) if date_to.present?
          relation = relation.where(user_id: filter_agent_id) if filter_agent_id
          relation
        end

        # Id de usuario solicitado (agent_id o user_id en @filters).
        def filter_agent_id
          @filter_agent_id ||= begin
            raw = filters['agent_id'].presence || filters['user_id'].presence
            raw && raw.to_i
          end
        end

        def summary
          {
            total_questions: scope.count,
            distinct_users: scope.distinct.count(:user_id),
            distinct_sessions: scope.distinct.count(:session_id_jabvox)
          }
        end

        # Serie temporal por día sobre created_at (preguntas humanas por día).
        def series
          scope.group('DATE(jabvox_ai_chat_messages.created_at)').count.sort.map do |day, count|
            { date: day.to_s, questions: count }
          end
        end

        # Total de preguntas y sesiones distintas por usuario.
        def by_user
          questions = scope.group(:user_id).count
          sessions = scope.group(:user_id).distinct.count(:session_id_jabvox)
          questions.sort_by { |_user_id, count| -count }.map do |user_id, count|
            {
              user_id: user_id,
              name: user_name(user_id),
              questions: count,
              sessions: sessions[user_id] || 0
            }
          end
        end

        # Desglose por usuario y día (matriz user_id x día) sobre created_at.
        def by_user_day
          scope
            .group(:user_id, 'DATE(jabvox_ai_chat_messages.created_at)')
            .count
            .map do |(user_id, day), count|
              {
                user_id: user_id,
                name: user_name(user_id),
                date: day.to_s,
                questions: count
              }
            end
            .sort_by { |row| [row[:date], -row[:questions]] }
        end

        def user_name(user_id)
          return nil if user_id.nil?

          user_names[user_id]
        end

        # Nombres de usuario acotados a los autores presentes en el scope, una
        # sola query (User no tiene account_id directo, pero los ids ya están
        # limitados por la cuenta vía el scope de mensajes).
        def user_names
          @user_names ||= User.where(id: scope.distinct.pluck(:user_id)).pluck(:id, :name).to_h
        end
      end
    end
  end
end
