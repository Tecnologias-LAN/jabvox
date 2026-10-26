require 'rails_helper'

describe Conversations::FilterService do
  subject(:filter_service) { described_class }

  let!(:account) { create(:account) }
  let!(:user_1) { create(:user, account: account) }
  let!(:user_2) { create(:user, account: account) }
  let!(:campaign_1) { create(:campaign, title: 'Test Campaign', account: account) }
  let!(:campaign_2) { create(:campaign, title: 'Campaign', account: account) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  let!(:user_2_assigned_conversation) { create(:conversation, account: account, inbox: inbox, assignee: user_2) }
  let!(:en_conversation_1) do
    create(:conversation, account: account, inbox: inbox, assignee: user_1, campaign_id: campaign_1.id,
                          status: 'pending', additional_attributes: { 'browser_language': 'en' })
  end
  let!(:en_conversation_2) do
    create(:conversation, account: account, inbox: inbox, assignee: user_1, campaign_id: campaign_2.id,
                          status: 'pending', additional_attributes: { 'browser_language': 'en' })
  end

  before do
    create(:inbox_member, user: user_1, inbox: inbox)
    create(:inbox_member, user: user_2, inbox: inbox)

    en_conversation_1.update!(custom_attributes: { conversation_additional_information: 'test custom data' })
    en_conversation_2.update!(custom_attributes: { conversation_additional_information: 'test custom data', conversation_type: 'platinum' })
    user_2_assigned_conversation.update!(custom_attributes: { conversation_type: 'platinum', conversation_created: '2022-01-19' })
    create(:conversation, account: account, inbox: inbox, assignee: user_1)

    create(:custom_attribute_definition,
           attribute_key: 'conversation_type',
           account: account,
           attribute_model: 'conversation_attribute',
           attribute_display_type: 'list',
           attribute_values: %w[regular platinum gold])
    create(:custom_attribute_definition,
           attribute_key: 'conversation_created',
           account: account,
           attribute_model: 'conversation_attribute',
           attribute_display_type: 'date')
    create(:custom_attribute_definition,
           attribute_key: 'conversation_additional_information',
           account: account,
           attribute_model: 'conversation_attribute',
           attribute_display_type: 'text')
  end

  describe '#perform' do
    context 'with query present' do
      let!(:params) { { payload: [], page: 1 } }
      let(:payload) do
        [
          {
            attribute_key: 'browser_language',
            filter_operator: 'equal_to',
            values: 'en',
            query_operator: 'AND',
            custom_attribute_type: ''
          }.with_indifferent_access,
          {
            attribute_key: 'status',
            filter_operator: 'not_equal_to',
            values: %w[resolved],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
      end

      it 'filter conversations by additional_attributes and status' do
        params[:payload] = payload
        result = filter_service.new(params, user_1, account).perform
        conversations = account.conversations.where("additional_attributes ->> 'browser_language' IN (?) AND status IN (?)", ['en'], [1, 2])
        expect(result[:count][:all_count]).to eq conversations.count
      end

      it 'filter conversations by priority' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1, priority: :high)
        params[:payload] = [
          {
            attribute_key: 'priority',
            filter_operator: 'equal_to',
            values: ['high'],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expect(result[:conversations].length).to eq 1
        expect(result[:conversations][0][:id]).to eq conversation.id
      end

      it 'filter conversations by multiple priority values' do
        high_priority = create(:conversation, account: account, inbox: inbox, assignee: user_1, priority: :high)
        urgent_priority = create(:conversation, account: account, inbox: inbox, assignee: user_1, priority: :urgent)
        create(:conversation, account: account, inbox: inbox, assignee: user_1, priority: :low)

        params[:payload] = [
          {
            attribute_key: 'priority',
            filter_operator: 'equal_to',
            values: %w[high urgent],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expect(result[:conversations].length).to eq 2
        expect(result[:conversations].pluck(:id)).to include(high_priority.id, urgent_priority.id)
      end

      it 'filter conversations with not_equal_to priority operator' do
        create(:conversation, account: account, inbox: inbox, assignee: user_1, priority: :high)
        create(:conversation, account: account, inbox: inbox, assignee: user_1, priority: :urgent)
        low_priority = create(:conversation, account: account, inbox: inbox, assignee: user_1, priority: :low)
        medium_priority = create(:conversation, account: account, inbox: inbox, assignee: user_1, priority: :medium)

        params[:payload] = [
          {
            attribute_key: 'priority',
            filter_operator: 'not_equal_to',
            values: %w[high urgent],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform

        # Only include conversations with medium and low priority, excluding high and urgent
        expect(result[:conversations].length).to eq 2
        expect(result[:conversations].pluck(:id)).to include(low_priority.id, medium_priority.id)
      end

      it 'filters conversations by contact' do
        account.conversations.destroy_all

        contact = create(:contact, :with_email, account: account)
        other_contact = create(:contact, :with_email, account: account)
        matching_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1, contact: contact)
        create(:conversation, account: account, inbox: inbox, assignee: user_1, contact: other_contact)

        params[:payload] = [
          {
            attribute_key: 'contact_id',
            filter_operator: 'equal_to',
            values: [contact.id],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]

        result = filter_service.new(params, user_1, account).perform

        expect(result[:count][:all_count]).to eq 1
        expect(result[:conversations].pluck(:id)).to contain_exactly(matching_conversation.id)
      end

      it 'filters conversations using not_equal_to contact operator' do
        account.conversations.destroy_all

        contact = create(:contact, :with_email, account: account)
        other_contact = create(:contact, :with_email, account: account)
        create(:conversation, account: account, inbox: inbox, assignee: user_1, contact: contact)
        other_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1, contact: other_contact)

        params[:payload] = [
          {
            attribute_key: 'contact_id',
            filter_operator: 'not_equal_to',
            values: [contact.id],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]

        result = filter_service.new(params, user_1, account).perform

        expect(result[:count][:all_count]).to eq 1
        expect(result[:conversations].pluck(:id)).to contain_exactly(other_conversation.id)
      end

      it 'applies inbox permissions when filtering conversations by contact' do
        account.conversations.destroy_all

        contact = create(:contact, :with_email, account: account)
        restricted_inbox = create(:inbox, account: account)
        accessible_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1, contact: contact)
        create(:conversation, account: account, inbox: restricted_inbox, contact: contact)

        params[:payload] = [
          {
            attribute_key: 'contact_id',
            filter_operator: 'equal_to',
            values: [contact.id],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]

        result = filter_service.new(params, user_1, account).perform

        expect(result[:count][:all_count]).to eq 1
        expect(result[:conversations].pluck(:id)).to contain_exactly(accessible_conversation.id)
      end

      it 'filter conversations by additional_attributes and status with pagination' do
        params[:payload] = payload
        params[:page] = 2
        result = filter_service.new(params, user_1, account).perform
        conversations = account.conversations.where("additional_attributes ->> 'browser_language' IN (?) AND status IN (?)", ['en'], [1, 2])
        expect(result[:count][:all_count]).to eq conversations.count
      end

      it 'filters items with contains filter_operator with values being an array' do
        params[:payload] = [{
          attribute_key: 'browser_language',
          filter_operator: 'equal_to',
          values: %w[tr fr],
          query_operator: '',
          custom_attribute_type: ''
        }.with_indifferent_access]

        create(:conversation, account: account, inbox: inbox, assignee: user_1, campaign_id: campaign_1.id,
                              status: 'pending', additional_attributes: { 'browser_language': 'fr' })
        create(:conversation, account: account, inbox: inbox, assignee: user_1, campaign_id: campaign_1.id,
                              status: 'pending', additional_attributes: { 'browser_language': 'tr' })

        result = filter_service.new(params, user_1, account).perform
        expect(result[:count][:all_count]).to be 2
      end

      it 'filters conversations by display_id substring' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1)
        create(:conversation, account: account, inbox: inbox, assignee: user_1)

        params[:payload] = [{
          attribute_key: 'display_id',
          filter_operator: 'contains',
          values: [conversation.display_id.to_s],
          query_operator: nil,
          custom_attribute_type: ''
        }.with_indifferent_access]

        result = filter_service.new(params, user_1, account).perform

        expect(result[:count][:all_count]).to eq(1)
        expect(result[:conversations].pluck(:id)).to contain_exactly(conversation.id)
      end

      it 'filters items with does not contain filter operator with values being an array' do
        params[:payload] = [{
          attribute_key: 'browser_language',
          filter_operator: 'not_equal_to',
          values: %w[tr en],
          query_operator: '',
          custom_attribute_type: ''
        }.with_indifferent_access]

        create(:conversation, account: account, inbox: inbox, assignee: user_1, campaign_id: campaign_1.id,
                              status: 'pending', additional_attributes: { 'browser_language': 'fr' })
        create(:conversation, account: account, inbox: inbox, assignee: user_1, campaign_id: campaign_1.id,
                              status: 'pending', additional_attributes: { 'browser_language': 'tr' })

        result = filter_service.new(params, user_1, account).perform

        expect(result[:count][:all_count]).to be 1
        expect(result[:conversations].first.additional_attributes['browser_language']).to eq 'fr'
      end

      it 'filter conversations by additional_attributes with NOT_IN filter' do
        payload = [{ attribute_key: 'conversation_type', filter_operator: 'not_equal_to', values: 'platinum', query_operator: nil,
                     custom_attribute_type: 'conversation_attribute' }.with_indifferent_access]
        params[:payload] = payload
        result = filter_service.new(params, user_1, account).perform
        conversations = account.conversations.where(
          "custom_attributes ->> 'conversation_type' NOT IN (?) OR custom_attributes ->> 'conversation_type' IS NULL", ['platinum']
        )
        expect(result[:count][:all_count]).to eq conversations.count
      end

      it 'filter conversations by tags' do
        user_2_assigned_conversation.update_labels('support')
        params[:payload] = [
          {
            attribute_key: 'assignee_id',
            filter_operator: 'equal_to',
            values: [user_1.id, user_2.id],
            query_operator: 'AND'
          }.with_indifferent_access,
          {
            attribute_key: 'labels',
            filter_operator: 'equal_to',
            values: ['support'],
            query_operator: 'AND'
          }.with_indifferent_access,
          {
            attribute_key: 'labels',
            filter_operator: 'not_equal_to',
            values: ['random-label'],
            query_operator: nil
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expect(result[:count][:all_count]).to be 1
      end

      it 'filter conversations by is_present filter_operator' do
        params[:payload] = [
          {
            attribute_key: 'assignee_id',
            filter_operator: 'equal_to',
            values: [
              user_1.id,
              user_2.id
            ],
            query_operator: 'AND',
            custom_attribute_type: ''
          }.with_indifferent_access,
          {
            attribute_key: 'campaign_id',
            filter_operator: 'is_present',
            values: [],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform

        expect(result[:count][:all_count]).to be 2
        expect(result[:conversations].pluck(:campaign_id).sort).to eq [campaign_2.id, campaign_1.id].sort
      end

      it 'handles invalid query conditions' do
        params[:payload] = [
          {
            attribute_key: 'assignee_id',
            filter_operator: 'equal_to',
            values: [
              user_1.id,
              user_2.id
            ],
            query_operator: 'INVALID',
            custom_attribute_type: ''
          }.with_indifferent_access,
          {
            attribute_key: 'campaign_id',
            filter_operator: 'is_present',
            values: [],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]

        expect { filter_service.new(params, user_1, account).perform }.to raise_error(CustomExceptions::CustomFilter::InvalidQueryOperator)
      end
    end
  end

  describe '#perform on custom attribute' do
    context 'with query present' do
      let!(:params) { { payload: [], page: 1 } }

      it 'filter by custom_attributes and labels' do
        user_2_assigned_conversation.update_labels('support')
        params[:payload] = [
          {
            attribute_key: 'conversation_type',
            filter_operator: 'equal_to',
            values: ['platinum'],
            query_operator: 'AND'
          }.with_indifferent_access,
          {
            attribute_key: 'conversation_created',
            filter_operator: 'is_less_than',
            values: ['2022-01-20'],
            query_operator: 'OR',
            custom_attribute_type: ''
          }.with_indifferent_access,
          {
            attribute_key: 'labels',
            filter_operator: 'equal_to',
            values: ['support'],
            query_operator: nil
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expect(result[:conversations].length).to be 1
        expect(result[:conversations][0][:id]).to be user_2_assigned_conversation.id
      end

      it 'filter by custom_attributes and labels with custom_attribute_type nil' do
        user_2_assigned_conversation.update_labels('support')
        params[:payload] = [
          {
            attribute_key: 'conversation_type',
            filter_operator: 'equal_to',
            values: ['platinum'],
            query_operator: 'AND'
          }.with_indifferent_access,
          {
            attribute_key: 'conversation_created',
            filter_operator: 'is_less_than',
            values: ['2022-01-20'],
            query_operator: 'OR',
            custom_attribute_type: nil
          }.with_indifferent_access,
          {
            attribute_key: 'labels',
            filter_operator: 'equal_to',
            values: ['support'],
            query_operator: nil
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expect(result[:conversations].length).to be 1
        expect(result[:conversations][0][:id]).to be user_2_assigned_conversation.id
      end

      it 'filter by custom_attributes' do
        params[:payload] = [
          {
            attribute_key: 'conversation_type',
            filter_operator: 'equal_to',
            values: ['platinum'],
            query_operator: 'AND',
            custom_attribute_type: ''
          }.with_indifferent_access,
          {
            attribute_key: 'conversation_created',
            filter_operator: 'is_less_than',
            values: ['2022-01-20'],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expect(result[:conversations].length).to be 1
      end

      it 'filter by custom_attributes with custom_attribute_type nil' do
        params[:payload] = [
          {
            attribute_key: 'conversation_type',
            filter_operator: 'equal_to',
            values: ['platinum'],
            query_operator: 'AND',
            custom_attribute_type: nil
          }.with_indifferent_access,
          {
            attribute_key: 'conversation_created',
            filter_operator: 'is_less_than',
            values: ['2022-01-20'],
            query_operator: nil,
            custom_attribute_type: nil
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expect(result[:conversations].length).to be 1
      end

      it 'filter by custom_attributes and additional_attributes' do
        conversations = user_1.conversations
        conversations[0].update!(additional_attributes: { 'browser_language': 'en' }, custom_attributes: { conversation_type: 'silver' })
        conversations[1].update!(additional_attributes: { 'browser_language': 'en' }, custom_attributes: { conversation_type: 'platinum' })
        conversations[2].update!(additional_attributes: { 'browser_language': 'tr' }, custom_attributes: { conversation_type: 'platinum' })

        params[:payload] = [
          {
            attribute_key: 'conversation_type',
            filter_operator: 'equal_to',
            values: ['platinum'],
            query_operator: 'AND',
            custom_attribute_type: ''
          }.with_indifferent_access,
          {
            attribute_key: 'browser_language',
            filter_operator: 'not_equal_to',
            values: 'en',
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expect(result[:conversations].length).to be 1
      end
    end
  end

  describe '#perform on date filter' do
    context 'with query present' do
      let!(:params) { { payload: [], page: 1 } }

      it 'filter by created_at' do
        params[:payload] = [
          {
            attribute_key: 'created_at',
            filter_operator: 'is_greater_than',
            values: ['2022-01-20'],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expected_count = account.conversations.where('created_at > ?', DateTime.parse('2022-01-20')).count
        expect(result[:conversations].length).to eq expected_count
      end

      it 'binds created_at comparison values as dates' do
        date_value = '2024-01-01'
        params[:payload] = [
          {
            attribute_key: 'created_at',
            filter_operator: 'is_greater_than',
            values: [date_value],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]

        service = filter_service.new(params, user_1, account)
        filters = service.instance_variable_get(:@filters)['conversations']
        condition_query = service.send(:build_condition_query, filters, params[:payload].first, 0)

        expect(condition_query).to include('(conversations.created_at)::date > :value_0')
        expect(service.instance_variable_get(:@filter_values)['value_0']).to eq(Date.iso8601(date_value))
      end

      it 'rejects invalid created_at comparison values' do
        malicious_value = "2024-01-01'::date OR (SELECT pg_sleep(5)) IS NOT NULL --"
        params[:payload] = [
          {
            attribute_key: 'created_at',
            filter_operator: 'is_greater_than',
            values: [malicious_value],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]

        expect { filter_service.new(params, user_1, account).perform }.to raise_error(CustomExceptions::CustomFilter::InvalidValue)
      end

      it 'filter by created_at and conversation_type' do
        params[:payload] = [
          {
            attribute_key: 'conversation_type',
            filter_operator: 'equal_to',
            values: ['platinum'],
            query_operator: 'AND',
            custom_attribute_type: ''
          }.with_indifferent_access,
          {
            attribute_key: 'created_at',
            filter_operator: 'is_greater_than',
            values: ['2022-01-20'],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expected_count = account.conversations.where("created_at > ? AND custom_attributes->>'conversation_type' = ?",
                                                     DateTime.parse('2022-01-20'), 'platinum').count

        expect(result[:conversations].length).to eq expected_count
      end

      context 'with x_days_before filter' do
        before do
          Time.zone = 'UTC'
          en_conversation_1.update!(last_activity_at: (Time.zone.today - 4.days))
          en_conversation_2.update!(last_activity_at: (Time.zone.today - 5.days))
          user_2_assigned_conversation.update!(last_activity_at: (Time.zone.today - 2.days))
        end

        it 'filter by last_activity_at 3_days_before and custom_attributes' do
          params[:payload] = [
            {
              attribute_key: 'last_activity_at',
              filter_operator: 'days_before',
              values: [3],
              query_operator: 'AND',
              custom_attribute_type: ''
            }.with_indifferent_access,
            {
              attribute_key: 'conversation_type',
              filter_operator: 'equal_to',
              values: ['platinum'],
              query_operator: nil,
              custom_attribute_type: ''
            }.with_indifferent_access
          ]

          expected_count = account.conversations.where("last_activity_at < ? AND custom_attributes->>'conversation_type' = ?",
                                                       (Time.zone.today - 3.days), 'platinum').count

          result = filter_service.new(params, user_1, account).perform
          expect(result[:conversations].length).to eq expected_count
        end

        it 'filter by last_activity_at 2_days_before' do
          params[:payload] = [
            {
              attribute_key: 'last_activity_at',
              filter_operator: 'days_before',
              values: [3],
              query_operator: nil,
              custom_attribute_type: ''
            }.with_indifferent_access
          ]

          expected_count = account.conversations.where('last_activity_at < ?', (Time.zone.today - 2.days)).count

          result = filter_service.new(params, user_1, account).perform
          expect(result[:conversations].length).to eq expected_count
        end
      end
    end
  end

  describe '#perform on date filter with no current account' do
    before do
      Current.account = nil
    end

    context 'with query present' do
      let!(:params) { { payload: [], page: 1 } }

      it 'filter by created_at' do
        params[:payload] = [
          {
            attribute_key: 'created_at',
            filter_operator: 'is_greater_than',
            values: ['2022-01-20'],
            query_operator: nil,
            custom_attribute_type: ''
          }.with_indifferent_access
        ]
        result = filter_service.new(params, user_1, account).perform
        expected_count = account.conversations.where('created_at > ?', DateTime.parse('2022-01-20')).count

        expect(Current.account).to be_nil
        expect(result[:conversations].length).to eq expected_count
      end
    end
  end

  describe '#base_relation' do
    let!(:account) { create(:account) }
    let!(:user_1) { create(:user, account: account, role: :agent) }
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let!(:inbox_1) { create(:inbox, account: account) }
    let!(:inbox_2) { create(:inbox, account: account) }
    let!(:params) { { payload: [], page: 1 } }

    before do
      account.conversations.destroy_all

      # Make user_1 a regular agent with access to inbox_1 only
      create(:inbox_member, user: user_1, inbox: inbox_1)

      # Create conversations in both inboxes
      create(:conversation, account: account, inbox: inbox_1)
      create(:conversation, account: account, inbox: inbox_2)
    end

    it 'returns all conversations for administrators, even for inboxes they are not members of' do
      service = filter_service.new(params, admin, account)
      result = service.perform
      expect(result[:conversations].count).to eq 2
    end

    it 'filters conversations by inbox membership for non-administrators' do
      service = filter_service.new(params, user_1, account)
      result = service.perform
      expect(result[:conversations].count).to eq 1
    end
  end

  # Antes el orden estaba hardcodeado a last_activity_at dentro del filtro, así que
  # el selector "Ordenar por" no tenía efecto con filtros activos. Ahora respeta
  # params[:sort_by] reutilizando el mismo mapa que las vistas normales.
  describe '#perform with sort_by' do
    let!(:account) { create(:account) }
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

    let!(:old_conv) { create(:conversation, account: account, inbox: inbox) }
    let!(:new_conv) { create(:conversation, account: account, inbox: inbox) }

    before do
      account.conversations.where.not(id: [old_conv.id, new_conv.id]).destroy_all
      old_conv.update!(created_at: 3.days.ago, last_activity_at: 3.days.ago)
      new_conv.update!(created_at: 1.hour.ago, last_activity_at: 1.hour.ago)
    end

    def ids_for(sort_by)
      params = { payload: [], page: 1, sort_by: sort_by }
      filter_service.new(params, admin, account).perform[:conversations].map(&:id)
    end

    it 'orders by created_at_asc (más antigua primero)' do
      expect(ids_for('created_at_asc')).to eq [old_conv.id, new_conv.id]
    end

    it 'orders by created_at_desc (más reciente primero)' do
      expect(ids_for('created_at_desc')).to eq [new_conv.id, old_conv.id]
    end

    it 'orders by last_activity_at_asc' do
      expect(ids_for('last_activity_at_asc')).to eq [old_conv.id, new_conv.id]
    end

    it 'defaults to last_activity_at_desc when sort_by is missing' do
      params = { payload: [], page: 1 }
      expect(filter_service.new(params, admin, account).perform[:conversations].map(&:id))
        .to eq [new_conv.id, old_conv.id]
    end

    it 'falls back to last_activity_at_desc on an unknown sort_by (no explota)' do
      expect(ids_for('valor_invalido_xyz')).to eq [new_conv.id, old_conv.id]
    end

    # Los scopes con ORDER complejo (joins / columnas de otras tablas) no deben
    # romper al combinarse con el includes/permission del filtro.
    %w[unread waiting_since_asc waiting_since_desc priority_desc priority_asc
       priority_desc_created_at_asc].each do |sort_by|
      it "does not raise for sort_by=#{sort_by}" do
        expect { ids_for(sort_by) }.not_to raise_error
      end
    end
  end

  # AGRUPACIÓN (paréntesis) en filtros de conversación: "A AND (B OR C)".
  describe '#perform with condition GROUPS (parentheses)' do
    let!(:account) { create(:account) }
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

    let!(:conv_high_vip) { create(:conversation, account: account, inbox: inbox, priority: :high) }
    let!(:conv_high_plain) { create(:conversation, account: account, inbox: inbox, priority: :high) }
    let!(:conv_low_vip) { create(:conversation, account: account, inbox: inbox, priority: :low) }

    before do
      account.conversations.where.not(id: [conv_high_vip.id, conv_high_plain.id, conv_low_vip.id]).destroy_all
      conv_high_vip.update!(label_list: ['vip'])
      conv_low_vip.update!(label_list: ['vip'])
    end

    def run(payload)
      params = ActionController::Parameters.new(payload: payload, page: 1).permit!
      filter_service.new(params, admin, account).perform[:conversations].map(&:id)
    end

    # prioridad = high  AND  ( etiqueta vip  OR  etiqueta premium )
    it 'matches A AND (B OR C): only high-priority with vip/premium' do
      payload = [
        { attribute_key: 'priority', filter_operator: 'equal_to', values: ['high'], query_operator: 'AND' },
        { type: 'group', query_operator: nil, child_operator: 'OR', conditions: [
          { attribute_key: 'labels', filter_operator: 'equal_to', values: ['vip'], query_operator: 'OR' },
          { attribute_key: 'labels', filter_operator: 'equal_to', values: ['premium'], query_operator: nil }
        ] }
      ]
      ids = run(payload)
      expect(ids).to include(conv_high_vip.id)       # high + vip  -> sí
      expect(ids).not_to include(conv_low_vip.id)    # low + vip   -> no (falla la obligatoria)
      expect(ids).not_to include(conv_high_plain.id) # high sin etiqueta -> no (falla el grupo)
    end

    it 'keeps backward compatibility with a flat payload (no groups)' do
      payload = [
        { attribute_key: 'priority', filter_operator: 'equal_to', values: ['high'], query_operator: nil }
      ]
      ids = run(payload)
      expect(ids).to contain_exactly(conv_high_vip.id, conv_high_plain.id)
    end

    # SEGURIDAD (capa 1 — validación): un query_operator de grupo que no sea AND/OR
    # se rechaza con InvalidQueryOperator antes de construir el SQL.
    it 'rejects an invalid group query_operator (validation layer)' do
      params = ActionController::Parameters.new(
        payload: [
          { attribute_key: 'priority', filter_operator: 'equal_to', values: ['high'], query_operator: 'AND' },
          { type: 'group', query_operator: ') OR 1=1 --', child_operator: 'OR',
            conditions: [
              { attribute_key: 'labels', filter_operator: 'equal_to', values: ['vip'], query_operator: nil }
            ] }
        ],
        page: 1
      ).permit!
      expect { filter_service.new(params, admin, account).perform }
        .to raise_error(CustomExceptions::CustomFilter::InvalidQueryOperator)
    end

    # SEGURIDAD (capa 2 — normalización): aunque se saltara la validación, el operador
    # del grupo se normaliza a AND/OR o se descarta; nunca se interpola texto crudo.
    it 'normalizes group operators so no SQL injection reaches the WHERE' do
      # child_operator malicioso: se fuerza a OR por defecto; query_operator vacío (último).
      payload = [
        { attribute_key: 'priority', filter_operator: 'equal_to', values: ['high'], query_operator: 'AND' },
        { type: 'group', query_operator: nil, child_operator: '; DROP TABLE conversations; --',
          conditions: [
            { attribute_key: 'labels', filter_operator: 'equal_to', values: ['vip'], query_operator: nil }
          ] }
      ]
      ids = run(payload)
      expect(ids).to include(conv_high_vip.id)
      expect(ids).not_to include(conv_low_vip.id) # low priority -> excluido por la obligatoria
      # La tabla sigue existiendo (si hubiera inyección de DROP, esto fallaría).
      expect(Conversation.count).to be >= 3
    end
  end
end
