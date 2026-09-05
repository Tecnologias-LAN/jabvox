require 'rails_helper'

RSpec.describe DeleteObjectJob, type: :job do
  describe '#perform' do
    context 'when object is heavy (Inbox)' do
      let!(:account) { create(:account) }
      let!(:inbox) { create(:inbox, account: account) }

      before do
        create_list(:conversation, 3, account: account, inbox: inbox)
        ReportingEvent.create!(account: account, inbox: inbox, name: 'inbox_metric', value: 1.0)
      end

      it 'enqueues on the low queue' do
        expect { described_class.perform_later(inbox) }
          .to have_enqueued_job(described_class).with(inbox).on_queue('low')
      end

      it 'pre-deletes heavy associations and then destroys the object' do
        conv_ids = inbox.conversations.pluck(:id)
        ci_ids = inbox.contact_inboxes.pluck(:id)
        contact_ids = inbox.contacts.pluck(:id)
        re_ids = inbox.reporting_events.pluck(:id)

        described_class.perform_now(inbox)

        # Reload associations to ensure database state is current
        expect(Conversation.where(id: conv_ids).reload).to be_empty
        expect(ContactInbox.where(id: ci_ids).reload).to be_empty
        expect(ReportingEvent.where(id: re_ids).reload).to be_empty
        # Contacts should not be deleted for inbox destroy
        expect(Contact.where(id: contact_ids).reload).not_to be_empty
        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    # Regression: an inbox with a bulk WhatsApp batch (RESTRICT FK to inboxes,
    # plus recipients with a RESTRICT FK back to the batch) used to raise
    # ActiveRecord::InvalidForeignKey and reappear on reload. The job must clear
    # those rows first and actually delete the inbox.
    context 'when the inbox has bulk WhatsApp batches (RESTRICT FK)' do
      let!(:account) { create(:account) }
      let!(:inbox) { create(:inbox, account: account) }
      let!(:batch) do
        JabvoxBulkWhatsappBatch.create!(account: account, inbox: inbox, status_jabvox: 'sent')
      end

      before do
        JabvoxBulkWhatsappRecipient.create!(
          account: account, bulk_whatsapp_batch_id: batch.id,
          phone_number_jabvox: '+573001112233', status_jabvox: 'sent'
        )
      end

      it 'clears the batch + recipients and deletes the inbox' do
        described_class.perform_now(inbox)

        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(JabvoxBulkWhatsappBatch.where(id: batch.id)).to be_empty
        expect(JabvoxBulkWhatsappRecipient.where(bulk_whatsapp_batch_id: batch.id)).to be_empty
      end
    end

    # The 3 delete modes, each on an inbox loaded with the FK-blocking rows so
    # the mode exercises the full cleanup path.
    describe 'delete modes' do
      let!(:account) { create(:account) }
      let!(:inbox) { create(:inbox, account: account) }
      let!(:other_inbox) { create(:inbox, account: account) }
      let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
      let(:contact_id) { conversation.contact_id }

      before do
        # FK-blocking rows (the bug) so every mode must clear them.
        batch = JabvoxBulkWhatsappBatch.create!(account: account, inbox: inbox, status_jabvox: 'sent')
        JabvoxBulkWhatsappRecipient.create!(account: account, bulk_whatsapp_batch_id: batch.id,
                                            phone_number_jabvox: '+57300', status_jabvox: 'sent')
        ReportingEvent.create!(account: account, inbox: inbox, name: 'm', value: 1.0)
      end

      it 'inbox_only: moves conversations to the target inbox and deletes the inbox' do
        described_class.perform_now(inbox, nil, nil, 'inbox_only', other_inbox.id)

        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
        # conversation preserved, moved to the target inbox
        expect(conversation.reload.inbox_id).to eq(other_inbox.id)
        # contact preserved
        expect(Contact.where(id: contact_id)).not_to be_empty
      end

      it 'inbox_conversations: deletes the inbox and its conversations, keeps contacts' do
        conv_id = conversation.id
        described_class.perform_now(inbox, nil, nil, 'inbox_conversations')

        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(Conversation.where(id: conv_id)).to be_empty
        expect(Contact.where(id: contact_id)).not_to be_empty
      end

      it 'inbox_leads_conversations: deletes the inbox, its conversations and the leads/contacts' do
        conv_id = conversation.id
        JabvoxLead.find_or_create_by!(account: account, contact_id: contact_id) do |l|
          l.lead_number = (account.jabvox_leads.maximum(:lead_number) || 0) + 1
        end
        described_class.perform_now(inbox, nil, nil, 'inbox_leads_conversations')

        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(Conversation.where(id: conv_id)).to be_empty
        expect(Contact.where(id: contact_id)).to be_empty
        expect(JabvoxLead.where(contact_id: contact_id)).to be_empty
      end

      it 'defaults to inbox_conversations for an unknown mode' do
        conv_id = conversation.id
        described_class.perform_now(inbox, nil, nil, 'garbage_mode')

        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(Conversation.where(id: conv_id)).to be_empty
      end

      it 'deletes ONLY the selected inbox, never the others' do
        described_class.perform_now(inbox, nil, nil, 'inbox_conversations')

        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(other_inbox.reload).to be_present
      end
    end

    context 'when object is heavy (Account)' do
      let!(:account) { create(:account) }
      let!(:inbox1) { create(:inbox, account: account) }
      let!(:inbox2) { create(:inbox, account: account) }

      before do
        create_list(:conversation, 2, account: account, inbox: inbox1)
        create_list(:conversation, 1, account: account, inbox: inbox2)
        ReportingEvent.create!(account: account, name: 'acct_metric', value: 2.5)
        ReportingEvent.create!(account: account, inbox: inbox1, name: 'acct_inbox_metric', value: 3.5)
      end

      it 'pre-deletes conversations, contacts, inboxes and reporting events and then destroys the account' do
        conv_ids = account.conversations.pluck(:id)
        contact_ids = account.contacts.pluck(:id)
        inbox_ids = account.inboxes.pluck(:id)
        re_ids = account.reporting_events.pluck(:id)

        described_class.perform_now(account)

        # Reload associations to ensure database state is current
        expect(Conversation.where(id: conv_ids).reload).to be_empty
        expect(Contact.where(id: contact_ids).reload).to be_empty
        expect(Inbox.where(id: inbox_ids).reload).to be_empty
        expect(ReportingEvent.where(id: re_ids).reload).to be_empty
        expect { account.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when object is regular (Label)' do
      it 'just destroys the object' do
        label = create(:label)

        described_class.perform_now(label)

        expect { label.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
