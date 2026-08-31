# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Jabvox::EmailSendTemplateNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let!(:smtp) do
    account.create_jabvox_smtp_config!(address: 'smtp.ej.com', from_email: 'no-reply@ej.com',
                                       from_name: 'Jabvox')
  end
  let(:template) do
    account.jabvox_email_templates.create!(name: 'Bienvenida', subject: 'Hola {{contact_name}}',
                                           body: '<p>Tu correo: {{contact_email}}</p>')
  end
  # NUNCA se envía tráfico real: el servicio de correo queda mockeado siempre.
  let(:sender) { instance_double(Jabvox::EmailSenderService, deliver!: true) }

  before { allow(Jabvox::EmailSenderService).to receive(:new).and_return(sender) }

  describe described_class do
    let(:contact) { create(:contact, account: account, name: 'Ana Ruiz', email: 'ana@ej.com') }

    it 'envía la plantilla al email del contacto INTERPOLANDO sus datos' do
      result = run_node(described_class, ctx, { 'templateId' => template.id, 'contactId' => contact.id })

      expect(result).to be_ok
      expect(Jabvox::EmailSenderService).to have_received(:new)
        .with(hash_including(to: 'ana@ej.com', subject: 'Hola Ana Ruiz',
                             html_body: '<p>Tu correo: ana@ej.com</p>'))
      expect(result.output).to include('sent' => true, 'contact_id' => contact.id,
                                       'template_id' => template.id)
    end

    it 'falla si el contacto no tiene email' do
      sin_email = create(:contact, account: account, name: 'Sin correo', email: nil)

      expect(run_node(described_class, ctx, { 'templateId' => template.id, 'contactId' => sin_email.id }).error)
        .to match(/no tiene email/)
    end

    it 'falla si la plantilla llega vacía' do
      expect(run_node(described_class, ctx, { 'templateId' => '', 'contactId' => contact.id }).error)
        .to match(/Falta la plantilla/)
    end

    it 'no encuentra una plantilla de otra cuenta' do
      ajena = create(:account).jabvox_email_templates.create!(name: 'X', subject: 's', body: 'b')

      expect(run_node(described_class, ctx, { 'templateId' => ajena.id, 'contactId' => contact.id }).error)
        .to match(/no existe en esta cuenta/)
    end

    it 'falla claro si la cuenta no tiene SMTP configurado' do
      smtp.update!(address: nil)

      expect(run_node(described_class, ctx, { 'templateId' => template.id, 'contactId' => contact.id }).error)
        .to match(/no tiene SMTP configurado/)
    end

    it 'no envía a un contacto de OTRA cuenta' do
      ajeno = create(:contact, account: create(:account), email: 'x@ej.com')

      expect(run_node(described_class, ctx, { 'templateId' => template.id, 'contactId' => ajeno.id }).error)
        .to match(/no existe en esta cuenta/)
      expect(Jabvox::EmailSenderService).not_to have_received(:new)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::EmailSendTestNode do
    it 'envía la plantilla TAL CUAL, sin interpolar' do
      result = run_node(described_class, ctx, { 'templateId' => template.id, 'to' => 'pruebas@ej.com' })

      expect(result).to be_ok
      expect(Jabvox::EmailSenderService).to have_received(:new)
        .with(hash_including(to: 'pruebas@ej.com', subject: 'Hola {{contact_name}}',
                             html_body: '<p>Tu correo: {{contact_email}}</p>'))
    end

    it 'falla si el email destino llega vacío' do
      expect(run_node(described_class, ctx, { 'templateId' => template.id, 'to' => '' }).error)
        .to match(/Falta el email destino/)
    end

    it 'rechaza un email destino con formato inválido' do
      expect(run_node(described_class, ctx, { 'templateId' => template.id, 'to' => 'pruebas@ej' }).error)
        .to match(/no es válido/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::EmailSendMessageNode do
    let(:base) { { 'to' => 'jefe@ej.com', 'subject' => 'Informe', 'body' => "Linea 1\nLinea 2" } }

    it 'envía texto plano escapando el cuerpo y respetando los saltos de línea' do
      result = run_node(described_class, ctx, base)

      expect(result).to be_ok
      expect(Jabvox::EmailSenderService).to have_received(:new)
        .with(hash_including(to: 'jefe@ej.com', subject: 'Informe', html_body: 'Linea 1<br>Linea 2'))
    end

    it 'escapa el HTML del cuerpo cuando isHtml no está activo' do
      run_node(described_class, ctx, base.merge('body' => '<b>hola</b>'))

      expect(Jabvox::EmailSenderService).to have_received(:new)
        .with(hash_including(html_body: '&lt;b&gt;hola&lt;/b&gt;'))
    end

    it 'respeta el HTML tal cual cuando isHtml está activo' do
      run_node(described_class, ctx, base.merge('body' => '<b>hola</b>', 'isHtml' => true))

      expect(Jabvox::EmailSenderService).to have_received(:new)
        .with(hash_including(html_body: '<b>hola</b>'))
    end

    it 'falla si falta el asunto' do
      expect(run_node(described_class, ctx, base.merge('subject' => '')).error)
        .to match(/Falta el asunto/)
    end

    it 'falla si el mensaje llega vacío' do
      expect(run_node(described_class, ctx, base.merge('body' => '   ')).error)
        .to match(/Falta el mensaje del correo/)
    end

    it 'rechaza un correo destino inválido' do
      expect(run_node(described_class, ctx, base.merge('to' => 'no-es-un-correo')).error)
        .to match(/no es válido/)
    end

    it 'reporta el fallo del SMTP en vez de dar el envío por bueno' do
      allow(sender).to receive(:deliver!).and_raise(StandardError, 'conexión rechazada')

      expect(run_node(described_class, ctx, base).error)
        .to match(/No se pudo enviar el correo a jefe@ej.com: conexión rechazada/)
    end
  end
end
