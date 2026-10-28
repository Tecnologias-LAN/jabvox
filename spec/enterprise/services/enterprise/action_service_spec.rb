require 'rails_helper'

describe ActionService do
  let(:account) { create(:account) }

  describe '#assign_company' do
    let(:conversation) { create(:conversation, account: account) }
    let(:contact) { conversation.contact }
    let(:company) { create(:company, account: account) }
    let(:action_service) { described_class.new(conversation) }

    context 'when the companies feature is enabled' do
      before do
        account.enable_features!('companies')
        # El contacto del factory trae email con dominio corporativo y se autoasocia a una
        # empresa por dominio (callback associate_company_from_email). Lo limpiamos para que
        # los casos de "no debe asignar" partan de company_id nil y sean deterministas.
        contact.update!(email: nil, company_id: nil)
      end

      it 'links the conversation contact to a company of the account' do
        action_service.assign_company([company.id])
        expect(contact.reload.company_id).to eq(company.id)
      end

      it 'syncs company_name into additional_attributes via the model callback' do
        action_service.assign_company([company.id])
        expect(contact.reload.additional_attributes['company_name']).to eq(company.name)
      end

      it 'unassigns the company when the value is "nil"' do
        contact.update!(company: company)
        action_service.assign_company(['nil'])
        expect(contact.reload.company_id).to be_nil
      end

      it 'ignores a company that belongs to another account' do
        other_company = create(:company, account: create(:account))
        action_service.assign_company([other_company.id])
        expect(contact.reload.company_id).to be_nil
      end

      it 'does nothing when the company does not exist' do
        action_service.assign_company([company.id + 999])
        expect(contact.reload.company_id).to be_nil
      end
    end

    context 'when the companies feature is disabled' do
      before do
        # Determinista: el módulo companies viene habilitado por defecto en features.yml, así
        # que para este caso lo apagamos explícitamente y partimos de un contacto sin empresa
        # (el factory lo autoasocia por dominio de email).
        account.disable_features!('companies')
        contact.update_columns(email: nil, company_id: nil) # rubocop:disable Rails/SkipsModelValidations
      end

      it 'does not link the contact to any company' do
        action_service.assign_company([company.id])
        expect(contact.reload.company_id).to be_nil
      end
    end
  end

  describe '#add_sla' do
    let(:sla_policy) { create(:sla_policy, account: account) }
    let(:conversation) { create(:conversation, account: account) }
    let(:action_service) { described_class.new(conversation) }

    context 'when sla_policy_id is present' do
      it 'adds the sla policy to the conversation and create applied_sla entry' do
        action_service.add_sla([sla_policy.id])
        expect(conversation.reload.sla_policy_id).to eq(sla_policy.id)

        # check if appliedsla table entry is created with matching attributes
        applied_sla = AppliedSla.last
        expect(applied_sla.account_id).to eq(account.id)
        expect(applied_sla.sla_policy_id).to eq(sla_policy.id)
        expect(applied_sla.conversation_id).to eq(conversation.id)
        expect(applied_sla.sla_status).to eq('active')
      end

      it 'does not add the sla policy when contact is blocked' do
        conversation.contact.update!(blocked: true)

        expect { action_service.add_sla([sla_policy.id]) }.not_to change(AppliedSla, :count)
        expect(conversation.reload.sla_policy_id).to be_nil
      end
    end

    context 'when sla_policy_id is not present' do
      it 'does not add the sla policy to the conversation' do
        action_service.add_sla(nil)
        expect(conversation.reload.sla_policy_id).to be_nil
      end
    end

    context 'when conversation already has a sla policy' do
      it 'does not add the new sla policy to the conversation' do
        existing_sla_policy = sla_policy
        new_sla_policy = create(:sla_policy, account: account)
        conversation.update!(sla_policy_id: existing_sla_policy.id)
        action_service.add_sla([new_sla_policy.id])
        expect(conversation.reload.sla_policy_id).to eq(existing_sla_policy.id)
      end
    end

    context 'when sla_policy is not found' do
      it 'does not add the sla policy to the conversation' do
        action_service.add_sla([sla_policy.id + 1])
        expect(conversation.reload.sla_policy_id).to be_nil
      end
    end
  end
end
