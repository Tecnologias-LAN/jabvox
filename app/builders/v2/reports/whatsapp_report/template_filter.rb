# Filtro y listado por plantilla de WhatsApp para el reporte. Una plantilla puede
# enviarse por masivo (JabvoxBulkWhatsappRecipient.template_name_jabvox) o 1-a-1
# (message.additional_attributes.template_params.name); ambas fuentes se combinan.
module V2::Reports::WhatsappReport::TemplateFilter
  TEMPLATE_NAME_SQL = "additional_attributes -> 'template_params' ->> 'name'".freeze

  # Restringe el scope de conversaciones a las que usaron la plantilla indicada.
  def filter_by_template(scope)
    return scope if params[:template_name].blank?

    conv_ids = (template_conv_ids_from_bulk + template_conv_ids_from_messages).uniq
    conv_ids.empty? ? scope.none : scope.where(id: conv_ids)
  end

  # Nombres de plantilla distintos (para el desplegable), de ambas fuentes.
  def template_names
    from_bulk = JabvoxBulkWhatsappRecipient.where(account_id: account.id)
                                           .where.not(template_name_jabvox: [nil, ''])
                                           .distinct.pluck(:template_name_jabvox)
    from_messages = account.messages.where(message_type: %i[outgoing template])
                           .where("#{TEMPLATE_NAME_SQL} IS NOT NULL")
                           .pluck(Arel.sql(TEMPLATE_NAME_SQL))
    (from_bulk + from_messages).compact.reject(&:blank?).uniq.sort
  end

  private

  def template_conv_ids_from_bulk
    JabvoxBulkWhatsappRecipient
      .where(account_id: account.id, template_name_jabvox: params[:template_name])
      .where.not(conversation_id: nil).distinct.pluck(:conversation_id)
  end

  def template_conv_ids_from_messages
    account.messages
           .where(message_type: %i[outgoing template])
           .where("#{TEMPLATE_NAME_SQL} = ?", params[:template_name])
           .pluck(:conversation_id).compact.uniq
  end
end
