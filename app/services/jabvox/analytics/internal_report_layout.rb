# Declares, per internal report, the set of widgets to create on its dashboard:
# a row of KPI cards (from summary metrics), an optional time series line, and
# bar/table widgets for each breakdown section. Drives InternalReportSeeder.
#
# Metric keys here MUST match the actual `summary` keys returned by each
# report service (verified against the services), or the KPI shows blank.
#
# Each widget: { type:, title:, section: (report hash key), metric: (summary key) }
class Jabvox::Analytics::InternalReportLayout
  LAYOUTS = {
    'sales' => {
      kpis: [%w[orders_count Pedidos], %w[sales_count Ventas], %w[sales_total Ingresos], %w[quote_to_sale_rate Conversión]],
      series: true,
      sections: [%w[by_status Estado bar], %w[by_doc_type Tipo bar], %w[top_products Productos table], %w[top_contacts Contactos table]]
    },
    'calls' => {
      kpis: [%w[total_calls Llamadas], %w[dialer_answered Contestadas], %w[dialer_calls Dialer], %w[avg_dialer_duration_seconds Duración]],
      series: true,
      sections: [%w[by_agent Agente table], %w[by_extension Extensión table], %w[by_status Estado bar]]
    },
    'agents' => {
      kpis: [%w[active_agents Agentes], %w[total_calls Llamadas], ['ai_chat_messages', 'Chat IA']],
      series: true,
      sections: [%w[by_agent Agente table], ['by_dialer_state', 'Estado dialer', 'bar'], ['by_app_state', 'Estado app', 'bar']]
    },
    'whatsapp' => {
      kpis: [%w[conversations Conversaciones], %w[messages Mensajes], %w[incoming_messages Entrantes], %w[outgoing_messages Salientes]],
      series: true,
      sections: [%w[by_status Estado bar], %w[by_agent Agente table]]
    },
    'email' => {
      kpis: [%w[total_sent Enviados], %w[delivered Entregados], %w[failed Fallidos], %w[delivery_rate Tasa]],
      series: true,
      sections: [%w[by_status Estado bar], %w[by_source Origen bar]]
    },
    'sms' => {
      kpis: [%w[total_messages Mensajes], %w[sent Enviados], %w[failed Fallidos], %w[delivery_rate Tasa]],
      series: true,
      sections: [%w[by_status Estado bar], %w[by_campaign Campaña table]]
    },
    'chat_internal' => {
      kpis: [%w[total_messages Mensajes], %w[total_chats Chats], %w[active_senders Usuarios]],
      series: true,
      sections: [%w[by_type Tipo bar], %w[by_sender Usuario table]]
    },
    'chat_ai' => {
      kpis: [%w[total_questions Consultas], %w[distinct_users Usuarios], %w[distinct_sessions Sesiones]],
      series: true,
      sections: [%w[by_user Usuario table]]
    },
    'cdr_analysis' => {
      kpis: [%w[total_analyses Análisis], %w[passed Aprobados], %w[pass_rate Tasa], %w[avg_final_score Score]],
      series: true,
      sections: [%w[by_status Estado bar], %w[by_pipeline Pipeline table]]
    },
    'audio_analysis' => {
      kpis: [%w[total_analyses Total], %w[passed Aprobados], %w[pass_rate Tasa], %w[average_score Score]],
      series: true,
      sections: [%w[by_status Estado bar], %w[by_sentiment Sentimiento bar], %w[by_agent Agente table]]
    },
    'overview' => {
      kpis: [%w[total_conversations Conversaciones], %w[resolved_conversations Resueltas], %w[open_conversations Abiertas],
             %w[resolution_rate Resolución]],
      series: true,
      sections: [%w[by_inbox Bandeja bar], %w[by_label Etiqueta table]]
    },
    'conversations' => {
      kpis: [%w[total_conversations Total], %w[resolved Resueltas], %w[open Abiertas], %w[pending Pendientes]],
      series: true,
      sections: [%w[by_status Estado bar], %w[by_team Equipo table], %w[by_inbox Bandeja table]]
    },
    'csat' => {
      kpis: [%w[total_responses Respuestas], %w[average_rating Promedio], %w[satisfaction_rate Satisfacción]],
      series: false,
      sections: [%w[by_rating Calificación bar], %w[by_agent Agente table]]
    },
    'report_agents' => {
      kpis: [%w[active_agents Agentes], %w[resolved_conversations Resueltas], %w[csat_responses CSAT]],
      series: true,
      sections: [%w[by_agent Agente table]]
    },
    'report_inboxes' => {
      kpis: [%w[total_conversations Conversaciones], %w[resolved Resueltas], %w[open Abiertas], %w[active_inboxes Bandejas]],
      series: true,
      sections: [%w[by_inbox Bandeja table]]
    },
    'report_labels' => {
      kpis: [%w[total_taggings Usos], %w[distinct_labels Etiquetas], %w[tagged_conversations Conversaciones]],
      series: true,
      sections: [%w[by_label Etiqueta\ (gráfico) bar], %w[by_label Etiqueta\ (detalle) table]]
    }
  }.freeze

  def self.for(key)
    LAYOUTS[key.to_s]
  end
end
