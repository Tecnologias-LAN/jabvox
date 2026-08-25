# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Hermes::ToolRegistry do
  describe 'política: sin tools destructivas' do
    it 'no incluye ninguna tool con método :delete' do
      methods = described_class.all.values.map { |spec| spec[:method] }
      expect(methods).not_to include(:delete)
    end

    it 'no incluye ninguna tool con permiso delete/destroy' do
      perms = described_class.all.values.map { |spec| spec[:permission] }
      expect(perms & %w[delete destroy]).to be_empty
    end

    it 'ya no registra delete_label' do
      expect(described_class.exists?('delete_label')).to be(false)
      expect(described_class.find('delete_label')).to be_nil
    end

    it 'assert_no_destructive_tools! no lanza con el catálogo actual' do
      expect { described_class.assert_no_destructive_tools! }.not_to raise_error
    end

    it 'assert_no_destructive_tools! lanza si se inyecta una tool destructiva' do
      poisoned = described_class::TOOLS.merge(
        'nuke' => { permission: 'delete', method: :delete, path: 'labels/:id', mcp: 'jabvox_core' }
      )
      stub_const('Jabvox::Hermes::ToolRegistry::TOOLS', poisoned)
      expect { described_class.assert_no_destructive_tools! }
        .to raise_error(/Tools destructivas prohibidas/)
    end
  end

  describe 'tools conservadas (no se rompió el catálogo)' do
    %w[get_labels create_label update_label get_conversations_meta reply_conversation
       get_report_summary].each do |tool|
      it "sigue registrando #{tool}" do
        expect(described_class.exists?(tool)).to be(true)
      end
    end
  end
end
