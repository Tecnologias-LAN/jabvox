# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Jabvox::CalendarCreateEventNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  # El evento cuelga del primer ADMINISTRADOR de la cuenta: un run no tiene
  # sesión y `user_id` es obligatorio en JabvoxCalendarEvent.
  let!(:admin) { create(:user, account: account, role: :administrator) }

  describe described_class do
    it 'crea el evento y deriva el fin a +1 hora cuando no se indica' do
      result = run_node(described_class, ctx,
                        { 'title' => 'Llamada', 'start' => '2026-09-01 09:00' })

      expect(result).to be_ok
      event = account.jabvox_calendar_events.last
      expect(result.output['id']).to eq(event.id)
      expect(event.end_at).to eq(event.start_at + 1.hour)
      expect(event.event_type).to eq('reminder')
      expect(event.status).to eq('pending')
    end

    it 'cuelga el evento del primer administrador de la cuenta' do
      run_node(described_class, ctx, { 'title' => 'Llamada', 'start' => '2026-09-01 09:00' })

      expect(account.jabvox_calendar_events.last.user_id).to eq(admin.id)
    end

    it 'con "todo el día" el fin se deriva a +24 horas' do
      run_node(described_class, ctx,
               { 'title' => 'Feria', 'start' => '2026-09-01', 'allDay' => true })

      event = account.jabvox_calendar_events.last
      expect(event.all_day).to be(true)
      expect(event.end_at).to eq(event.start_at + 24.hours)
    end

    it 'respeta el fin explícito y el tipo y estado elegidos' do
      run_node(described_class, ctx,
               { 'title' => 'Cita', 'start' => '2026-09-01 09:00', 'end' => '2026-09-01 11:30',
                 'eventType' => 'appointment', 'status' => 'done' })

      event = account.jabvox_calendar_events.last
      expect(event.end_at).to eq(Time.zone.parse('2026-09-01 11:30'))
      expect(event.event_type).to eq('appointment')
      expect(event.status).to eq('done')
    end

    it 'falla si falta el título' do
      expect(run_node(described_class, ctx, { 'title' => '', 'start' => '2026-09-01 09:00' }).error)
        .to match(/Falta el título del evento/)
    end

    it 'falla si falta la fecha de inicio' do
      expect(run_node(described_class, ctx, { 'title' => 'Llamada', 'start' => '' }).error)
        .to match(/Falta la fecha de inicio/)
    end

    it 'FALLA con una fecha ilegible en vez de guardar nil' do
      result = run_node(described_class, ctx, { 'title' => 'Llamada', 'start' => 'mañana por la tarde' })

      expect(result.error).to match(/No se entiende la fecha de inicio/)
      expect(account.jabvox_calendar_events.count).to eq(0)
    end

    it 'rechaza un tipo de evento fuera de la lista' do
      expect(run_node(described_class, ctx,
                      { 'title' => 'x', 'start' => '2026-09-01 09:00', 'eventType' => 'boda' }).error)
        .to match(/Valor no válido para el tipo de evento/)
    end

    it 'no acepta un contacto de OTRA cuenta' do
      ajeno = create(:contact, account: create(:account))

      expect(run_node(described_class, ctx,
                      { 'title' => 'x', 'start' => '2026-09-01 09:00', 'contactId' => ajeno.id }).error)
        .to match(/no existe en esta cuenta/)
    end

    it 'adjunta participantes agentes y externos de la cuenta' do
      externo = account.jabvox_calendar_external_people.create!(name: 'Cliente', email: 'c@ej.com')

      result = run_node(described_class, ctx,
                        { 'title' => 'Cita', 'start' => '2026-09-01 09:00', 'note' => 'Traer contrato',
                          'attendeeUserIds' => [admin.id], 'attendeeExternalIds' => [externo.id] })

      expect(result.output['participants'].length).to eq(2)
      expect(result.output['participants'].map { |p| p['kind'] }).to contain_exactly('team', 'external')
    end

    it 'rechaza un participante externo de otra cuenta' do
      ajeno = create(:account).jabvox_calendar_external_people.create!(name: 'Otro')

      expect(run_node(described_class, ctx,
                      { 'title' => 'x', 'start' => '2026-09-01 09:00',
                        'attendeeExternalIds' => [ajeno.id] }).error)
        .to match(/no pertenecen a esta cuenta/)
    end

    it 'falla claro si la cuenta no tiene ningún administrador' do
      sin_admin = create(:account)

      expect(run_node(described_class, build_ctx(sin_admin),
                      { 'title' => 'x', 'start' => '2026-09-01 09:00' }).error)
        .to match(/no tiene ningún administrador/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::CalendarUpdateEventNode do
    let(:event) do
      account.jabvox_calendar_events.create!(
        user: admin, title: 'Original', start_at: Time.zone.parse('2026-09-01 09:00'),
        end_at: Time.zone.parse('2026-09-01 10:00'), note: 'nota'
      )
    end

    it 'actualiza SOLO lo configurado y no borra lo demás' do
      result = run_node(described_class, ctx, { 'eventId' => event.id, 'title' => 'Nuevo título' })

      expect(result).to be_ok
      expect(event.reload.title).to eq('Nuevo título')
      expect(event.start_at).to eq(Time.zone.parse('2026-09-01 09:00'))
    end

    it 'NO vacía los participantes cuando el usuario no elige ninguno' do
      event.jabvox_calendar_event_participants.create!(user_id: admin.id)

      run_node(described_class, ctx,
               { 'eventId' => event.id, 'title' => 'Otro', 'attendeeUserIds' => [],
                 'attendeeExternalIds' => '' })

      expect(event.reload.jabvox_calendar_event_participants.count).to eq(1)
    end

    it 'REEMPLAZA los participantes cuando sí se eligen' do
      otro = create(:user, account: account, role: :agent)
      event.jabvox_calendar_event_participants.create!(user_id: admin.id)

      run_node(described_class, ctx, { 'eventId' => event.id, 'attendeeUserIds' => [otro.id] })

      expect(event.reload.jabvox_calendar_event_participants.pluck(:user_id)).to eq([otro.id])
    end

    it 'falla si no se configuró nada que actualizar' do
      expect(run_node(described_class, ctx, { 'eventId' => event.id }).error)
        .to match(/ningún campo que actualizar/)
    end

    it 'no encuentra un evento de otra cuenta' do
      ajeno = create(:account)
      otro_admin = create(:user, account: ajeno, role: :administrator)
      evento_ajeno = ajeno.jabvox_calendar_events.create!(
        user: otro_admin, title: 'Ajeno', start_at: Time.zone.now, end_at: 1.hour.from_now
      )

      expect(run_node(described_class, ctx, { 'eventId' => evento_ajeno.id, 'title' => 'x' }).error)
        .to match(/no existe en esta cuenta/)
    end

    it 'FALLA con una fecha ilegible sin tocar el evento' do
      result = run_node(described_class, ctx, { 'eventId' => event.id, 'start' => 'la semana que viene' })

      expect(result.error).to match(/No se entiende la fecha de inicio/)
      expect(event.reload.title).to eq('Original')
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::CalendarDeleteEventNode do
    it 'borra el evento y publica su id' do
      event = account.jabvox_calendar_events.create!(
        user: admin, title: 'Borrable', start_at: Time.zone.now, end_at: 1.hour.from_now
      )

      result = run_node(described_class, ctx, { 'eventId' => event.id })

      expect(result.output).to include('deleted' => true, 'eventId' => event.id, 'title' => 'Borrable')
      expect(account.jabvox_calendar_events.count).to eq(0)
    end

    it 'falla si el ID del evento llega vacío' do
      expect(run_node(described_class, ctx, { 'eventId' => '' }).error)
        .to match(/Falta el ID del evento/)
    end
  end
end
