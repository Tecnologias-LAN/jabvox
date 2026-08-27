# frozen_string_literal: true

require 'rails_helper'

# Subtemas de categorías: parent_id self-reference, scopes roots/subtopics y las
# validaciones (no auto-referencia, mismo tipo que el padre).
RSpec.describe JabvoxTicketCategory do
  let(:account) { create(:account) }
  let(:parent) { create(:jabvox_ticket_category, account: account, category_type_jabvox: :incident) }

  describe 'jerarquía padre/hijo' do
    it 'un tema raíz no tiene parent y aparece en .roots' do
      expect(parent.subtopic?).to be(false)
      expect(described_class.roots).to include(parent)
    end

    it 'un subtema referencia a su padre y aparece en .subtopics' do
      child = create(:jabvox_ticket_category, account: account,
                                              category_type_jabvox: :incident, parent: parent)
      expect(child.subtopic?).to be(true)
      expect(parent.children).to include(child)
      expect(described_class.subtopics).to include(child)
      expect(described_class.roots).not_to include(child)
    end

    it 'al borrar el padre, los hijos quedan sin parent (nullify)' do
      child = create(:jabvox_ticket_category, account: account,
                                              category_type_jabvox: :incident, parent: parent)
      parent.destroy!
      expect(child.reload.parent_id).to be_nil
    end
  end

  describe 'validaciones' do
    it 'rechaza que un tema sea su propio padre' do
      parent.update_column(:parent_id, parent.id) # rubocop:disable Rails/SkipsModelValidations
      expect(parent.reload).not_to be_valid
    end

    it 'rechaza un subtema de distinto tipo que el padre' do
      child = build(:jabvox_ticket_category, account: account,
                                             category_type_jabvox: :requirement, parent: parent)
      expect(child).not_to be_valid
      expect(child.errors[:parent_id].join).to match(/mismo tipo/)
    end

    it 'acepta un subtema del mismo tipo que el padre' do
      child = build(:jabvox_ticket_category, account: account,
                                             category_type_jabvox: :incident, parent: parent)
      expect(child).to be_valid
    end
  end
end
