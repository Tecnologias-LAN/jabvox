# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::ManagementStatesImportService do
  let(:account) { create(:account) }

  def import(states)
    described_class.new(account, { 'states' => states }.with_indifferent_access).call
  end

  describe 'multiselect and conditional visibility' do
    let(:states) do
      [{
        'name_jabvox' => 'Buzón de voz', 'state_group_jabvox' => 'Llamada', 'service_type_jabvox' => 'No',
        'questions' => [
          { 'label' => 'Transferencia a SAC', 'question_type' => 'boolean' },
          { 'label' => 'Motivo SAC', 'question_type' => 'list', 'options' => %w[A B],
            'visibility' => { 'logic' => 'and',
                              'rules' => [{ 'question' => 'Transferencia a SAC', 'operator' => 'equals', 'value' => 'true' }] } },
          { 'label' => 'Canales', 'question_type' => 'multiselect', 'options' => %w[Chat OV TV] }
        ]
      }]
    end

    it 'imports multiselect and visibility rules intact' do
      result = import(states)
      expect(result).to be_valid
      expect(result.created).to eq(1)

      state = account.jabvox_management_states.find_by(name_jabvox: 'Buzón de voz')
      canales = state.questions.find_by(label: 'Canales')
      motivo = state.questions.find_by(label: 'Motivo SAC')

      expect(canales.question_type).to eq('multiselect')
      expect(motivo.visibility['rules'].first).to include('question' => 'Transferencia a SAC', 'operator' => 'equals')
    end

    it 'drops multiselect questions with no options' do
      states.first['questions'] << { 'label' => 'Vacio', 'question_type' => 'multiselect', 'options' => [] }
      import(states)
      state = account.jabvox_management_states.find_by(name_jabvox: 'Buzón de voz')
      expect(state.questions.pluck(:label)).not_to include('Vacio')
    end

    it 'normalizes malformed visibility to empty on import' do
      states.first['questions'] << { 'label' => 'Basura', 'question_type' => 'text',
                                     'visibility' => { 'logic' => 'zzz', 'rules' => [{ 'foo' => 1 }] } }
      import(states)
      state = account.jabvox_management_states.find_by(name_jabvox: 'Buzón de voz')
      expect(state.questions.find_by(label: 'Basura').visibility).to eq({})
    end
  end

  describe 'stress: large and hostile payloads' do
    it 'handles a state with many questions without error' do
      questions = Array.new(40) { |i| { 'label' => "Q#{i}", 'question_type' => 'text' } }
      result = import([{ 'name_jabvox' => 'Big', 'state_group_jabvox' => 'Llamada',
                         'service_type_jabvox' => 'No', 'questions' => questions }])
      expect(result).to be_valid
      expect(account.jabvox_management_states.find_by(name_jabvox: 'Big').questions.count).to eq(40)
    end

    it 'coerces unknown question types to text instead of failing' do
      result = import([{ 'name_jabvox' => 'Weird', 'state_group_jabvox' => 'Llamada', 'service_type_jabvox' => 'No',
                         'questions' => [{ 'label' => 'X', 'question_type' => 'radio' }] }])
      expect(result).to be_valid
      q = account.jabvox_management_states.find_by(name_jabvox: 'Weird').questions.first
      expect(q.question_type).to eq('text')
    end

    it 'ignores non-hash rules and rules without a question' do
      result = import([{ 'name_jabvox' => 'R', 'state_group_jabvox' => 'Llamada', 'service_type_jabvox' => 'No',
                         'questions' => [{ 'label' => 'X', 'question_type' => 'text',
                                           'visibility' => { 'rules' => ['bad', { 'operator' => 'equals' }] } }] }])
      expect(result).to be_valid
      expect(account.jabvox_management_states.find_by(name_jabvox: 'R').questions.first.visibility).to eq({})
    end

    it 'imports lead_field mappings and drops disallowed namespaces' do
      result = import([{ 'name_jabvox' => 'LF', 'state_group_jabvox' => 'Llamada', 'service_type_jabvox' => 'No',
                         'questions' => [
                           { 'label' => 'Tel', 'question_type' => 'text', 'lead_field' => 'contact.phone_number', 'lead_field_locked' => true },
                           { 'label' => 'Malo', 'question_type' => 'text', 'lead_field' => 'system.secret' }
                         ] }])
      expect(result).to be_valid
      state = account.jabvox_management_states.find_by(name_jabvox: 'LF')
      expect(state.questions.find_by(label: 'Tel').lead_field).to eq('contact.phone_number')
      expect(state.questions.find_by(label: 'Tel').lead_field_locked).to be(true)
      expect(state.questions.find_by(label: 'Malo').lead_field).to eq('')
    end

    it 're-imports (upsert) replacing questions for the same group+name' do
      import([{ 'name_jabvox' => 'U', 'state_group_jabvox' => 'Llamada', 'service_type_jabvox' => 'No',
                'questions' => [{ 'label' => 'Old', 'question_type' => 'text' }] }])
      import([{ 'name_jabvox' => 'U', 'state_group_jabvox' => 'Llamada', 'service_type_jabvox' => 'No',
                'questions' => [{ 'label' => 'New', 'question_type' => 'multiselect', 'options' => ['a'] }] }])
      state = account.jabvox_management_states.find_by(name_jabvox: 'U', state_group_jabvox: 'Llamada')
      expect(state.questions.pluck(:label)).to eq(['New'])
    end
  end
end
