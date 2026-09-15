require 'rails_helper'

describe ContactMergeAction do
  subject(:contact_merge) { described_class.new(account: account, base_contact: base_contact, mergee_contact: mergee_contact).perform }

  let!(:account) { create(:account) }
  let!(:base_contact) do
    create(:contact, identifier: 'base_contact', email: 'old@old.com', phone_number: '', custom_attributes: { val_test: 'old', val_empty_old: '' },
                     account: account)
  end
  let!(:mergee_contact) do
    create(:contact, identifier: '', email: 'new@new.com', phone_number: '+12212345',
                     custom_attributes: { val_test: 'new', val_new: 'new', val_empty_new: '' }, account: account)
  end

  before do
    2.times.each do
      create(:conversation, contact: base_contact)
      create(:conversation, contact: mergee_contact)
      create(:message, sender: mergee_contact)
      create(:note, contact: mergee_contact, account: mergee_contact.account)
    end
  end

  describe '#perform' do
    it 'deletes mergee_contact' do
      contact_merge
      expect { mergee_contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'copies information from mergee contact to base contact' do
      contact_merge
      base_contact.reload
      expect(base_contact.identifier).to eq('base_contact')
      expect(base_contact.email).to eq('old@old.com')
      expect(base_contact.phone_number).to eq('+12212345')
      expect(base_contact.custom_attributes['val_test']).to eq('old')
      expect(base_contact.custom_attributes['val_new']).to eq('new')
      expect(base_contact.custom_attributes['val_empty_old']).to eq('')
      expect(base_contact.custom_attributes['val_empty_new']).to eq('')
    end

    context 'when base contact and merge contact are same' do
      it 'does not delete contact' do
        mergee_contact = base_contact
        contact_merge
        expect(mergee_contact.reload).not_to be_nil
      end
    end

    context 'when mergee contact has conversations' do
      it 'moves the conversations to base contact' do
        contact_merge
        expect(base_contact.conversations.count).to be 4
      end
    end

    context 'when mergee contact has contact inboxes' do
      it 'moves the contact inboxes to base contact' do
        contact_merge
        expect(base_contact.contact_inboxes.count).to be 4
      end
    end

    context 'when mergee contact has messages' do
      it 'moves the messages to base contact' do
        contact_merge
        expect(base_contact.messages.count).to be 2
      end
    end

    context 'when mergee contact has notes' do
      it 'moves the notes to base contact' do
        expect(base_contact.notes.count).to be 0
        expect(mergee_contact.notes.count).to be 2

        contact_merge

        expect(base_contact.reload.notes.count).to be 2
      end
    end

    # Regresión: en producción, cada contacto nuevo dispara su propio
    # Jabvox::ContactLeadsIntegration#jabvox_create_lead (after_commit), así que llega
    # con SU PROPIO JabvoxLead ya creado. Fusionar dos contactos que ambos ya tienen lead
    # violaba index_jabvox_leads_on_account_id_and_contact_id al intentar mover el lead
    # del mergee al mismo contact_id que el lead del base (widget de Soporte: 500 en
    # PATCH /api/v1/widget/contact/set_user).
    context 'when both contacts already have their own jabvox lead' do
      let!(:base_lead) { create(:jabvox_lead, account: account, contact: base_contact) }
      let!(:mergee_lead) { create(:jabvox_lead, account: account, contact: mergee_contact) }

      it 'does not raise a unique constraint violation' do
        expect { contact_merge }.not_to raise_error
      end

      it 'keeps the base contact lead untouched' do
        contact_merge
        expect(JabvoxLead.exists?(id: base_lead.id)).to be(true)
        expect(base_contact.reload.jabvox_leads.count).to eq(1)
      end

      it 'discards the mergee lead (it is deleted along with the mergee contact)' do
        contact_merge
        expect(JabvoxLead.exists?(id: mergee_lead.id)).to be(false)
      end
    end

    context 'when only the mergee contact has a jabvox lead' do
      let!(:mergee_lead) { create(:jabvox_lead, account: account, contact: mergee_contact) }

      it 'moves the lead to the base contact' do
        contact_merge
        expect(mergee_lead.reload.contact_id).to eq(base_contact.id)
      end
    end

    context 'when contacts belong to a different account' do
      it 'throws an exception' do
        new_account = create(:account)
        expect do
          described_class.new(account: new_account, base_contact: base_contact,
                              mergee_contact: mergee_contact).perform
        end.to raise_error('contact does not belong to the account')
      end
    end
  end
end
