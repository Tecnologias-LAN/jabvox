# frozen_string_literal: true

# Imports typifications from the JSON produced by the export endpoint. Upserts
# by name: an existing name is updated, a new name is created, and names NOT in
# the file are left untouched — importing never deletes data.
#
# All-or-nothing: any invalid entry rolls the whole import back and the errors
# list says which entry failed and why. The file is pure DATA — nothing is
# executed; every field is coerced through a strict whitelist before it can
# reach the DB (no mass assignment, no extra keys, no code paths).
module Jabvox
  class TypificationsImportService
    MAX_ITEMS = 2_000

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
      items = extract_items
      return Result.new(0, 0, ['Formato inválido: el JSON debe tener una lista "typifications".']) if items.nil?
      return Result.new(0, 0, ['El archivo no contiene tipificaciones.']) if items.empty?
      return Result.new(0, 0, ["Máximo #{MAX_ITEMS} tipificaciones por importación."]) if items.size > MAX_ITEMS

      import_all(items)
    end

    private

    def extract_items
      payload = @payload.is_a?(Hash) ? @payload.with_indifferent_access : {}
      items = payload[:typifications]
      items.is_a?(Array) ? items : nil
    end

    def import_all(items)
      created = 0
      updated = 0
      errors = []

      ActiveRecord::Base.transaction do
        items.each_with_index do |raw, idx|
          attrs, error = sanitize(raw, idx)
          if error
            errors << error
            next
          end

          begin
            upsert(attrs) ? (updated += 1) : (created += 1)
          rescue ActiveRecord::RecordInvalid => e
            errors << "Tipificación ##{idx + 1} (#{attrs[:name]}): #{e.record.errors.full_messages.join(', ')}"
          end
        end
        raise ActiveRecord::Rollback if errors.any?
      end

      errors.any? ? Result.new(0, 0, errors) : Result.new(created, updated, errors)
    end

    # Returns true when an existing typification was updated, false when created.
    def upsert(attrs)
      tp = @account.jabvox_typifications.find_by(name: attrs[:name])
      if tp
        tp.update!(attrs)
        true
      else
        @account.jabvox_typifications.create!(attrs)
        false
      end
    end

    def sanitize(raw, idx)
      return [nil, "Tipificación ##{idx + 1}: debe ser un objeto."] unless raw.is_a?(Hash)

      raw = raw.with_indifferent_access
      name = raw[:name].to_s.strip.first(150)
      return [nil, "Tipificación ##{idx + 1}: el nombre es obligatorio."] if name.blank?

      [{
        name: name,
        description: raw[:description].to_s.strip.first(1000),
        is_active: cast_bool(raw[:is_active], default: true)
      }, nil]
    end

    def cast_bool(value, default:)
      return default if value.nil?

      ActiveModel::Type::Boolean.new.cast(value) ? true : false
    end
  end
end
