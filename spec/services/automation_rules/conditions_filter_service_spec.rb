require 'rails_helper'

RSpec.describe AutomationRules::ConditionsFilterService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:email_channel) { create(:channel_email, account: account) }
  let(:email_inbox) { create(:inbox, channel: email_channel, account: account) }
  let(:message) do
    create(:message, account: account, conversation: conversation, content: 'test text', inbox: conversation.inbox, message_type: :incoming)
  end
  let(:rule) { create(:automation_rule, account: account) }

  before do
    conversation = create(:conversation, account: account)
    conversation.contact.update(phone_number: '+918484828282', email: 'test@test.com')
    create(:conversation, account: account)
    create(:conversation, account: account)
  end

  describe '#perform' do
    context 'when conditions based on filter_operator equal_to' do
      before do
        rule.conditions = [{ 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' }]
        rule.save
      end

      context 'when conditions in rule matches with object' do
        it 'will return true' do
          expect(described_class.new(rule, conversation, { changed_attributes: { status: [nil, 'open'] } }).perform).to be(true)
        end
      end

      context 'when conditions in rule does not match with object' do
        it 'will return false' do
          conversation.update(status: 'resolved')
          expect(described_class.new(rule, conversation, { changed_attributes: { status: %w[open resolved] } }).perform).to be(false)
        end
      end
    end

    context 'when conditions based on filter_operator start_with' do
      before do
        contact = conversation.contact
        contact.update(phone_number: '+918484848484')
        rule.conditions = [
          { 'values': ['+918484'], 'attribute_key': 'phone_number', 'query_operator': 'OR', 'filter_operator': 'starts_with' },
          { 'values': ['test'], 'attribute_key': 'email', 'query_operator': nil, 'filter_operator': 'contains' }
        ]
        rule.save
      end

      context 'when conditions in rule matches with object' do
        it 'will return true' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end
      end

      context 'when conditions in rule does not match with object' do
        it 'will return false' do
          conversation.contact.update(phone_number: '+918585858585')
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end
      end
    end

    context 'when conditions based on messages attributes' do
      context 'when filter_operator is equal_to' do
        before do
          rule.conditions = [
            { 'values': ['test text'], 'attribute_key': 'content', 'query_operator': 'AND', 'filter_operator': 'equal_to' },
            { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
        end

        it 'will return true when conditions matches' do
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conditions in rule does not match' do
          message.update!(message_type: :outgoing)
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filtering private notes' do
        before do
          rule.conditions = [
            { 'values': [true], 'attribute_key': 'private_note', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
        end

        it 'will return true when the message is a private note' do
          message.update!(private: true)

          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when the message is not a private note' do
          message.update!(private: false)

          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filter_operator is on processed_message_content' do
        before do
          rule.conditions = [
            { 'values': ['help'], 'attribute_key': 'content', 'query_operator': 'AND', 'filter_operator': 'contains' },
            { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
        end

        let(:conversation) { create(:conversation, account: account, inbox: email_inbox) }
        let(:message) do
          create(:message, account: account, conversation: conversation, content: "We will help you\n\n\n test",
                           inbox: conversation.inbox, message_type: :incoming,
                           content_attributes: { email: { text_content: { quoted: 'We will help you' } } })
        end

        it 'will return true for processed_message_content matches' do
          message
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when processed_message_content does no match' do
          rule.update(conditions: [{ 'values': ['text'], 'attribute_key': 'content', 'query_operator': nil, 'filter_operator': 'contains' }])

          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filtering messages based on conversation attributes' do
        let(:conversation) { create(:conversation, account: account, status: :open, priority: :high) }
        let(:message) do
          create(:message, account: account, conversation: conversation, content: 'Test message',
                           inbox: conversation.inbox, message_type: :incoming)
        end

        it 'will return true when conversation status matches' do
          rule.update(conditions: [{ 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' }])
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conversation status does not match' do
          rule.update(conditions: [{ 'values': ['resolved'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' }])
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(false)
        end

        it 'will return true when conversation priority matches' do
          rule.update(conditions: [{ 'values': ['high'], 'attribute_key': 'priority', 'query_operator': nil, 'filter_operator': 'equal_to' }])
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end
      end
    end

    context 'when conditions based on labels' do
      before do
        conversation.add_labels(['bug'])
      end

      context 'when filter_operator is equal_to' do
        before do
          rule.conditions = [
            { 'values': ['bug'], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
        end

        it 'will return true when conversation has the label' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conversation does not have the label' do
          rule.conditions = [
            { 'values': ['feature'], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filter_operator is not_equal_to' do
        before do
          rule.conditions = [
            { 'values': ['feature'], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'not_equal_to' }
          ]
          rule.save
        end

        it 'will return true when conversation does not have the label' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conversation has the label' do
          conversation.add_labels(['feature'])
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end

        # Caso que estaba roto: una conversación SIN NINGUNA etiqueta debe cumplir
        # "No igual a feature" (no tiene esa etiqueta). Antes devolvía false porque
        # `tags.name != 'feature'` sobre un LEFT JOIN da NULL cuando no hay filas.
        it 'will return true when conversation has NO labels at all' do
          conversation.update_labels([])
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end
      end

      context 'when filter_operator is is_present' do
        before do
          rule.conditions = [
            { 'values': [], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'is_present' }
          ]
          rule.save
        end

        it 'will return true when conversation has any labels' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conversation has no labels' do
          conversation.update_labels([])
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filter_operator is is_not_present' do
        before do
          rule.conditions = [
            { 'values': [], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'is_not_present' }
          ]
          rule.save
        end

        it 'will return false when conversation has any labels' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end

        it 'will return true when conversation has no labels' do
          conversation.update_labels([])
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end
      end

      # Regla real de producción: "mensaje entrante Y Etiquetas No igual a
      # asesor-diferente" (asignar a un agente). Debe disparar para el cliente que
      # escribe SIN la etiqueta asesor-diferente, tenga o no otras etiquetas, y NO
      # disparar si ya tiene asesor-diferente. Una SOLA condición de etiqueta cubre
      # ambos casos, sin necesidad del OR "No está presente".
      context 'when combining incoming message AND labels not_equal_to (regla asignación)' do
        let(:incoming) do
          create(:message, account: account, conversation: conversation, content: 'hola',
                           inbox: conversation.inbox, message_type: :incoming)
        end

        before do
          conversation.update_labels([])
          rule.conditions = [
            { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': 'AND', 'filter_operator': 'equal_to' },
            { 'values': ['asesor-diferente'], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'not_equal_to' }
          ]
          rule.save
        end

        it 'dispara: entrante y SIN ninguna etiqueta (cliente nuevo)' do
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(true)
        end

        it 'dispara: entrante y con OTRA etiqueta distinta de asesor-diferente' do
          conversation.add_labels(['interesado'])
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(true)
        end

        it 'NO dispara: entrante pero con la etiqueta asesor-diferente' do
          conversation.add_labels(['asesor-diferente'])
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(false)
        end
      end
    end

    # AGRUPACIÓN (paréntesis): "A AND (B OR C)". El grupo envuelve varias
    # condiciones entre paréntesis y las une con su propio operador (OR/AND),
    # permitiendo "obligatoria Y (una de varias)".
    context 'when using a GROUP of conditions (parentheses)' do
      let(:incoming) do
        create(:message, account: account, conversation: conversation, content: 'hola',
                         inbox: conversation.inbox, message_type: :incoming)
      end

      # entrante Y ( etiqueta=vip  O  etiqueta=premium )
      def build_rule(child_operator)
        conversation.update_labels([])
        rule.conditions = [
          { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': 'AND', 'filter_operator': 'equal_to' },
          { 'type': 'group', 'query_operator': nil, 'child_operator': child_operator, 'conditions': [
            { 'values': ['vip'], 'attribute_key': 'labels', 'query_operator': 'OR', 'filter_operator': 'equal_to' },
            { 'values': ['premium'], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ] }
        ]
        rule.save
      end

      context 'with child_operator OR (cumplir una)' do
        before { build_rule('OR') }

        it 'dispara si tiene vip' do
          conversation.add_labels(['vip'])
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(true)
        end

        it 'dispara si tiene premium' do
          conversation.add_labels(['premium'])
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(true)
        end

        it 'NO dispara si no tiene ninguna de las dos' do
          conversation.add_labels(['otra'])
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(false)
        end

        it 'NO dispara si cumple el grupo pero NO es entrante (la obligatoria falla)' do
          conversation.add_labels(['vip'])
          outgoing = create(:message, account: account, conversation: conversation, content: 'resp',
                                      inbox: conversation.inbox, message_type: :outgoing)
          expect(described_class.new(rule, conversation, { message: outgoing, changed_attributes: {} }).perform).to be(false)
        end
      end

      # child_operator AND: grupo donde se deben cumplir TODAS las hijas. Usamos
      # dos atributos distintos (etiqueta + prioridad), porque "tags.name = A AND
      # tags.name = B" nunca es cierto sobre una sola fila del join de etiquetas
      # (eso es una limitación del operador equal_to sobre labels, no del grupo).
      context 'with child_operator AND (cumplir todas)' do
        before do
          conversation.update_labels([])
          rule.conditions = [
            { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': 'AND', 'filter_operator': 'equal_to' },
            { 'type': 'group', 'query_operator': nil, 'child_operator': 'AND', 'conditions': [
              { 'values': ['vip'], 'attribute_key': 'labels', 'query_operator': 'AND', 'filter_operator': 'equal_to' },
              { 'values': ['urgent'], 'attribute_key': 'priority', 'query_operator': nil, 'filter_operator': 'equal_to' }
            ] }
          ]
          rule.save
        end

        it 'dispara si tiene vip Y prioridad urgent' do
          conversation.add_labels(['vip'])
          conversation.update!(priority: 'urgent')
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(true)
        end

        it 'NO dispara si tiene vip pero NO prioridad urgent' do
          conversation.add_labels(['vip'])
          conversation.update!(priority: 'low')
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(false)
        end
      end

      # Tu caso real: entrante Y ( No igual a asesor-diferente  O  sin etiquetas ).
      context 'with the real production pattern' do
        before do
          conversation.update_labels([])
          rule.conditions = [
            { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': 'AND', 'filter_operator': 'equal_to' },
            { 'type': 'group', 'query_operator': nil, 'child_operator': 'OR', 'conditions': [
              { 'values': ['asesor-diferente'], 'attribute_key': 'labels', 'query_operator': 'OR', 'filter_operator': 'not_equal_to' },
              { 'values': [], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'is_not_present' }
            ] }
          ]
          rule.save
        end

        it 'dispara: cliente nuevo sin etiquetas' do
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(true)
        end

        it 'dispara: con otra etiqueta distinta de asesor-diferente' do
          conversation.add_labels(['interesado'])
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(true)
        end

        it 'NO dispara: con la etiqueta asesor-diferente' do
          conversation.add_labels(['asesor-diferente'])
          expect(described_class.new(rule, conversation, { message: incoming, changed_attributes: {} }).perform).to be(false)
        end
      end
    end
  end

  context 'when conditions based on contact country_code' do
    before do
      conversation.update(additional_attributes: { country_code: 'US' })
      conversation.contact.update(additional_attributes: { country_code: 'IN' })
      rule.conditions = [
        { 'values': ['IN'], 'attribute_key': 'country_code', 'query_operator': nil, 'filter_operator': 'equal_to' }
      ]
      rule.save
    end

    it 'matches against the contact additional_attributes' do
      expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
    end

    it 'returns false when the contact country_code does not match' do
      conversation.contact.update(additional_attributes: { country_code: 'GB' })
      expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
    end
  end

  # Jabvox: condicion de franja horaria (current_time). Se evalua en Ruby contra
  # la zona America/Bogota, por eso se congela el tiempo con travel_to.
  context 'when condition is based on current_time (franja horaria)' do
    def perform_at(bogota_time, options = {})
      travel_to(Time.find_zone('America/Bogota').parse(bogota_time)) do
        described_class.new(rule, conversation, { changed_attributes: {} }.merge(options)).perform
      end
    end

    context 'with is_between within the same day (08:00-18:00)' do
      before do
        rule.conditions = [{ 'values': { 'from': '08:00', 'to': '18:00' }, 'attribute_key': 'current_time',
                             'query_operator': nil, 'filter_operator': 'is_between' }]
        rule.save
      end

      it 'matches when current time is inside the range' do
        expect(perform_at('2026-10-21 10:30:00')).to be(true)
      end

      it 'does not match when current time is outside the range' do
        expect(perform_at('2026-10-21 20:30:00')).to be(false)
      end

      it 'does not match exactly at the end bound (exclusive)' do
        expect(perform_at('2026-10-21 18:00:00')).to be(false)
      end
    end

    context 'with is_between crossing midnight (18:30-08:00)' do
      before do
        rule.conditions = [{ 'values': { 'from': '18:30', 'to': '08:00' }, 'attribute_key': 'current_time',
                             'query_operator': nil, 'filter_operator': 'is_between' }]
        rule.save
      end

      it 'matches late at night (before midnight)' do
        expect(perform_at('2026-10-21 23:00:00')).to be(true)
      end

      it 'matches early in the morning (after midnight)' do
        expect(perform_at('2026-10-21 03:00:00')).to be(true)
      end

      it 'does not match during the day' do
        expect(perform_at('2026-10-21 12:00:00')).to be(false)
      end
    end

    context 'with is_not_between (inverse of the range)' do
      before do
        rule.conditions = [{ 'values': { 'from': '08:00', 'to': '18:00' }, 'attribute_key': 'current_time',
                             'query_operator': nil, 'filter_operator': 'is_not_between' }]
        rule.save
      end

      it 'matches when current time is outside the range' do
        expect(perform_at('2026-10-21 20:30:00')).to be(true)
      end

      it 'does not match when current time is inside the range' do
        expect(perform_at('2026-10-21 10:30:00')).to be(false)
      end
    end

    context 'when combined with another condition (message_type incoming AND franja)' do
      before do
        message
        rule.conditions = [
          { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': 'AND', 'filter_operator': 'equal_to' },
          { 'values': { 'from': '18:30', 'to': '08:00' }, 'attribute_key': 'current_time',
            'query_operator': nil, 'filter_operator': 'is_between' }
        ]
        rule.save
      end

      it 'matches when both the message is incoming and the time is in range' do
        expect(perform_at('2026-10-21 23:00:00', { message: message })).to be(true)
      end

      it 'does not match when the time is out of range even if the message is incoming' do
        expect(perform_at('2026-10-21 12:00:00', { message: message })).to be(false)
      end
    end

    context 'with an invalid or incomplete range' do
      before do
        rule.conditions = [{ 'values': { 'from': '18:30', 'to': '' }, 'attribute_key': 'current_time',
                             'query_operator': nil, 'filter_operator': 'is_between' }]
        rule.save
      end

      it 'does not match' do
        expect(perform_at('2026-10-21 23:00:00')).to be(false)
      end
    end
  end

  # Jabvox: condicion por TIPO de contenido del mensaje (attachment_type).
  # Se evalua en Ruby sobre el mensaje del evento (message_created), igual que la
  # franja horaria. 'text' = mensaje sin adjuntos.
  context 'when condition is based on attachment_type (tipo de contenido)' do
    def mensaje_con_adjunto(tipo)
      msg = create(:message, account: account, conversation: conversation,
                             inbox: conversation.inbox, message_type: :incoming, content: 'hola')
      msg.attachments.create!(account_id: account.id, file_type: tipo) unless tipo.nil?
      msg
    end

    def match?(tipo_mensaje, operador, tipo_buscado)
      rule.conditions = [{ 'values' => [tipo_buscado], 'attribute_key' => 'attachment_type',
                           'query_operator' => nil, 'filter_operator' => operador }]
      rule.save!
      msg = mensaje_con_adjunto(tipo_mensaje)
      described_class.new(rule, msg.conversation, { message: msg, changed_attributes: {} }).perform
    end

    it 'matchea cuando el mensaje contiene una imagen' do
      expect(match?(:image, 'contains', 'image')).to be(true)
    end

    it 'matchea cuando el mensaje contiene un audio' do
      expect(match?(:audio, 'contains', 'audio')).to be(true)
    end

    it 'NO matchea cuando se busca imagen pero el adjunto es audio' do
      expect(match?(:audio, 'contains', 'image')).to be(false)
    end

    it "matchea 'text' cuando el mensaje no tiene adjuntos" do
      expect(match?(nil, 'contains', 'text')).to be(true)
    end

    it "NO matchea 'text' cuando el mensaje sí tiene adjunto" do
      expect(match?(:image, 'contains', 'text')).to be(false)
    end

    it 'does_not_contain: matchea cuando el mensaje NO tiene ese tipo' do
      expect(match?(:audio, 'does_not_contain', 'image')).to be(true)
    end

    it 'does_not_contain: NO matchea cuando el mensaje SÍ tiene ese tipo' do
      expect(match?(:image, 'does_not_contain', 'image')).to be(false)
    end

    # La UI ofrece "Igual a"/"Distinto de" además de "Contiene"/"No contiene"
    # (OPERATOR_TYPES_2). Para esta condición equal_to == contains y
    # not_equal_to == does_not_contain: una regla guardada con "Igual a" debe disparar
    # (antes fallaba la validación y se desactivaba sola).
    it 'equal_to: matchea cuando el mensaje es de ese tipo (= contains)' do
      expect(match?(:audio, 'equal_to', 'audio')).to be(true)
    end

    it 'equal_to: NO matchea cuando el mensaje es de otro tipo' do
      expect(match?(:audio, 'equal_to', 'image')).to be(false)
    end

    it 'not_equal_to: matchea cuando el mensaje NO es de ese tipo (= does_not_contain)' do
      expect(match?(:audio, 'not_equal_to', 'image')).to be(true)
    end

    it 'not_equal_to: NO matchea cuando el mensaje SÍ es de ese tipo' do
      expect(match?(:audio, 'not_equal_to', 'audio')).to be(false)
    end

    it 'combinado con message_type incoming (ambas deben cumplirse)' do
      rule.conditions = [
        { 'values' => ['incoming'], 'attribute_key' => 'message_type', 'query_operator' => 'AND', 'filter_operator' => 'equal_to' },
        { 'values' => ['image'], 'attribute_key' => 'attachment_type', 'query_operator' => nil, 'filter_operator' => 'contains' }
      ]
      rule.save!
      msg = mensaje_con_adjunto(:image)
      expect(described_class.new(rule, msg.conversation, { message: msg, changed_attributes: {} }).perform).to be(true)
    end
  end
end
