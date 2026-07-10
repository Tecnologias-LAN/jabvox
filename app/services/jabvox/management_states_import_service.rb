# frozen_string_literal: true

# Imports management states (with their questions) from the JSON produced by
# the export endpoint. Upserts by state name: existing names are updated (their
# questions replaced), new names are created, and states NOT present in the
# file are left untouched — importing can never silently delete data.
#
# All-or-nothing: any invalid entry rolls the whole import back and the errors
# list says exactly which entries failed and why.
module Jabvox
  class ManagementStatesImportService
    MAX_STATES = 200
    MAX_QUESTIONS = 50

    Result = Struct.new(:created, :updated, :errors) do
      def valid?
        errors.empty?
      end
    end

    def initialize(account, payload)
      @account = account
      @payload = payload
    end

    def call
      states = extract_states
      return Result.new(0, 0, ['Formato inválido: el JSON debe tener una lista "states".']) if states.nil?
      return Result.new(0, 0, ['El archivo no contiene estados.']) if states.empty?
      return Result.new(0, 0, ["Máximo #{MAX_STATES} estados por importación."]) if states.size > MAX_STATES

      import_all(states)
    end

    private

    def extract_states
      payload = @payload.is_a?(Hash) ? @payload.with_indifferent_access : {}
      states = payload[:states]
      states.is_a?(Array) ? states : nil
    end

    def import_all(states)
      created = 0
      updated = 0
      errors = []

      ActiveRecord::Base.transaction do
        states.each_with_index do |raw, idx|
          attrs, error = sanitize_state(raw, idx)
          if error
            errors << error
            next
          end

          begin
            upsert_state(attrs) ? (updated += 1) : (created += 1)
          rescue ActiveRecord::RecordInvalid => e
            errors << "Estado ##{idx + 1} (#{attrs[:name_jabvox]}): #{e.record.errors.full_messages.join(', ')}"
          end
        end
        raise ActiveRecord::Rollback if errors.any?
      end

      errors.any? ? Result.new(0, 0, errors) : Result.new(created, updated, errors)
    end

    # Returns true when an existing state was updated, false when created.
    # A substate is identified by its (group, name) pair — the same substate
    # name may exist under different groups (e.g. "Toma de pedido" in Llamada
    # and in Whatsapp).
    def upsert_state(attrs)
      state = @account.jabvox_management_states.find_by(
        name_jabvox: attrs[:name_jabvox], state_group_jabvox: attrs[:state_group_jabvox]
      )
      if state
        state.questions.destroy_all
        state.update!(attrs)
        true
      else
        @account.jabvox_management_states.create!(attrs)
        false
      end
    end

    def sanitize_state(raw, idx)
      return [nil, "Estado ##{idx + 1}: debe ser un objeto."] unless raw.is_a?(Hash)

      raw = raw.with_indifferent_access
      name = raw[:name_jabvox].to_s.strip.first(150)
      return [nil, "Estado ##{idx + 1}: el nombre es obligatorio."] if name.blank?

      questions = raw[:questions]
      questions = [] unless questions.is_a?(Array)
      return [nil, "Estado ##{idx + 1} (#{name}): máximo #{MAX_QUESTIONS} preguntas."] if questions.size > MAX_QUESTIONS

      # Drop questions with no label (blank/junk entries) so one stray empty
      # question in the file doesn't fail the whole import on the model's
      # presence validation; 'list' questions with no options are dropped too.
      sanitized_questions = questions
                            .map { |q| sanitize_question(q, 0) }
                            .reject { |q| q[:label].blank? }
                            .reject { |q| q[:question_type] == 'list' && q[:options].empty? }
                            .each_with_index.map { |q, i| q.merge(position: i) }

      [{
        name_jabvox: name,
        state_group_jabvox: raw[:state_group_jabvox].to_s.strip.first(150),
        usage_info_jabvox: raw[:usage_info_jabvox].to_s.strip.first(2000),
        managed_jabvox: cast_bool(raw[:managed_jabvox], default: true),
        contact_jabvox: cast_bool(raw[:contact_jabvox], default: false),
        effective_contact_jabvox: cast_bool(raw[:effective_contact_jabvox], default: false),
        advisory_jabvox: cast_bool(raw[:advisory_jabvox], default: false),
        service_type_jabvox: raw[:service_type_jabvox].to_s.strip.presence&.first(100) || 'No',
        positivity_level_jabvox: raw[:positivity_level_jabvox].to_i.clamp(0, 100),
        color_jabvox: sanitize_color(raw[:color_jabvox]),
        is_active_jabvox: cast_bool(raw[:is_active_jabvox], default: true),
        note_mode: sanitize_note_mode(raw[:note_mode]),
        position_jabvox: raw[:position_jabvox].to_i.clamp(0, 10_000),
        questions_attributes: sanitized_questions
      }, nil]
    end

    def sanitize_question(raw, position)
      raw = raw.is_a?(Hash) ? raw.with_indifferent_access : {}
      type = JabvoxManagementQuestion::QUESTION_TYPES.include?(raw[:question_type].to_s) ? raw[:question_type].to_s : 'text'
      options = Array(raw[:options]).map { |o| o.to_s.first(250) }.reject(&:blank?).first(100)
      {
        label: raw[:label].to_s.strip.first(250),
        question_type: type,
        required: cast_bool(raw[:required], default: false),
        options: options,
        position: position
      }
    end

    def sanitize_color(value)
      value.to_s.match?(/\A#[0-9A-Fa-f]{6}\z/) ? value.to_s : '#6366f1'
    end

    def sanitize_note_mode(value)
      JabvoxManagementState::NOTE_MODES.include?(value.to_s) ? value.to_s : 'optional'
    end

    def cast_bool(value, default:)
      return default if value.nil?

      ActiveModel::Type::Boolean.new.cast(value) ? true : false
    end
  end
end
