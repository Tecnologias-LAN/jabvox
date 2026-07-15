# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxManagementQuestion do
  let(:account) { create(:account) }
  let(:state) do
    account.jabvox_management_states.create!(
      name_jabvox: 'Buzón de voz', state_group_jabvox: 'Llamada', service_type_jabvox: 'No'
    )
  end

  def build_question(attrs = {})
    state.questions.build({ label: 'Q', question_type: 'text' }.merge(attrs))
  end

  describe 'question_type validation' do
    it 'accepts the supported types including multiselect' do
      %w[text number date boolean].each do |t|
        expect(build_question(question_type: t)).to be_valid
      end
      expect(build_question(question_type: 'list', options: ['A'])).to be_valid
      expect(build_question(question_type: 'multiselect', options: ['A'])).to be_valid
    end

    it 'rejects unknown types' do
      expect(build_question(question_type: 'radio')).not_to be_valid
    end
  end

  describe 'options presence for option types' do
    it 'requires options for list and multiselect' do
      expect(build_question(question_type: 'list', options: [])).not_to be_valid
      expect(build_question(question_type: 'multiselect', options: [])).not_to be_valid
    end

    it 'does not require options for non-option types' do
      expect(build_question(question_type: 'text', options: [])).to be_valid
    end
  end

  describe 'visibility normalization' do
    it 'keeps a well-formed rule set' do
      q = build_question(
        label: 'B',
        visibility: { 'logic' => 'or',
                      'rules' => [{ 'question' => 'A', 'operator' => 'equals', 'value' => 'Si' }] }
      )
      q.save!
      expect(q.reload.visibility).to eq(
        'logic' => 'or',
        'rules' => [{ 'question' => 'A', 'operator' => 'equals', 'value' => 'Si' }]
      )
    end

    it 'drops the value for the answered operator' do
      q = build_question(label: 'B',
                         visibility: { 'rules' => [{ 'question' => 'A', 'operator' => 'answered', 'value' => 'x' }] })
      q.save!
      expect(q.reload.visibility['rules'].first).to eq('question' => 'A', 'operator' => 'answered')
    end

    it 'coerces invalid logic/operator to safe defaults' do
      q = build_question(label: 'B',
                         visibility: { 'logic' => 'xor', 'rules' => [{ 'question' => 'A', 'operator' => 'nope', 'value' => 'x' }] })
      q.save!
      expect(q.reload.visibility['logic']).to eq('and')
      expect(q.reload.visibility['rules'].first['operator']).to eq('equals')
    end

    it 'normalizes junk visibility to an empty hash' do
      q = build_question(label: 'B', visibility: { 'logic' => 'x', 'rules' => [{ 'foo' => 'bar' }, 'not a hash'] })
      q.save!
      expect(q.reload.visibility).to eq({})
      expect(q.reload).to be_unconditional
    end

    it 'caps the number of rules' do
      rules = Array.new(20) { |i| { 'question' => "Q#{i}", 'operator' => 'answered' } }
      q = build_question(label: 'B', visibility: { 'rules' => rules })
      q.save!
      expect(q.reload.visibility['rules'].size).to eq(described_class::MAX_VISIBILITY_RULES)
    end
  end

  describe 'self-reference guard' do
    it 'rejects a question that depends on itself' do
      q = build_question(
        label: 'Motivo',
        visibility: { 'rules' => [{ 'question' => 'Motivo', 'operator' => 'equals', 'value' => 'x' }] }
      )
      expect(q).not_to be_valid
      expect(q.errors[:visibility]).to be_present
    end
  end

  describe 'lead_field normalization' do
    it 'keeps allowed namespaces' do
      %w[contact.phone_number contact.custom.ciclo_c contact.additional.country lead.lead_number].each do |lf|
        q = build_question(lead_field: lf)
        q.save!
        expect(q.reload.lead_field).to eq(lf)
      end
    end

    it 'drops values without an allowed namespace' do
      q = build_question(lead_field: 'evil.rm_rf')
      q.save!
      expect(q.reload.lead_field).to eq('')
    end

    it 'defaults lead_field_locked to false and persists true' do
      q = build_question(lead_field: 'contact.name', lead_field_locked: true)
      q.save!
      expect(q.reload.lead_field_locked).to be(true)
    end
  end
end
