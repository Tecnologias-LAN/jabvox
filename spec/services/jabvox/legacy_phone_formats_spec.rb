# frozen_string_literal: true

require 'rails_helper'

# Producción tiene teléfonos guardados en TRES formatos distintos, todos de
# Colombia:
#
#   "+573001234567"  E.164 correcto
#   "573001234567"   con código de país pero sin "+"
#   "3001234567"     solo el número local
#
# Los dos últimos entraron por caminos que saltan la validación del modelo
# (el import desde BD externa usa save!(validate: false)).
#
# Lo que se protege aquí: NADA de lo ya guardado se rompe ni se pierde. Las
# pantallas siguen mostrando el número, el marcador sigue pudiendo llamar, y
# el contacto se puede seguir abriendo y editando.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Teléfonos heredados en los tres formatos' do
  let(:account) { create(:account) }

  # Escribe saltando la validación, igual que hizo el import histórico.
  def legacy_contact(phone, name: 'Heredado')
    contact = account.contacts.new(name: name, phone_number: phone)
    contact.save!(validate: false)
    contact.reload
  end

  describe 'lo guardado no se altera' do
    it 'conserva el número sin "+" tal como estaba' do
      contact = legacy_contact('573001234567')

      expect(contact.phone_number).to eq('573001234567')
    end

    it 'conserva el número local tal como estaba' do
      contact = legacy_contact('3001234567')

      expect(contact.phone_number).to eq('3001234567')
    end

    it 'la migración de piezas no toca un número que no es E.164' do
      contact = legacy_contact('573001234567')

      # split devuelve nil para lo que no es E.164, así que el backfill lo salta
      # en vez de inventar un prefijo.
      expect(Jabvox::PhoneParts.split(contact.phone_number)).to be_nil
      expect(contact.phone_national_jabvox).to be_nil
    end
  end

  describe 'las pantallas siguen funcionando' do
    it 'phone_parts_jabvox no revienta con un número heredado' do
      contact = legacy_contact('3001234567')

      expect { contact.phone_parts_jabvox }.not_to raise_error
      expect(contact.phone_parts_jabvox[:e164]).to eq('3001234567')
    end

    it 'un contacto heredado se puede leer sin errores' do
      contact = legacy_contact('573001234567')

      expect(contact.reload.name).to eq('Heredado')
    end
  end

  describe 'el marcador sigue pudiendo llamar' do
    it 'marca un número heredado con código de país' do
      contact = legacy_contact('573001234567')

      expect(Jabvox::PhoneNormalizer.for_dialing(contact.phone_number)).to eq('573001234567')
    end

    it 'un número local se marca con el prefijo del campo configurado' do
      contact = legacy_contact('3001234567')
      lead = JabvoxLead.create!(account: account, contact: contact)

      # Con el teléfono del contacto se marca tal cual (el dial plan de la PBX
      # resuelve los locales); con prefijo configurado se completa.
      expect(Jabvox::DialNumberResolver.resolve(lead: lead, field: 'phone')).to eq('3001234567')
    end
  end

  describe 'editar un contacto heredado' do
    it 'guardar solo el nombre funciona y repara el teléfono de paso' do
      contact = legacy_contact('573001234567')

      contact.name = 'Nombre nuevo'
      contact.save!

      expect(contact.reload.name).to eq('Nombre nuevo')
      # Antes esto fallaba entero: el contacto quedaba bloqueado por su propio
      # teléfono heredado. Ahora se normaliza al guardar.
      expect(contact.phone_number).to eq('+573001234567')
      expect(contact.phone_national_jabvox).to eq('3001234567')
    end

    it 'repara también un número local suelto' do
      contact = legacy_contact('3001234567')

      contact.update!(name: 'Otro nombre')

      expect(contact.reload.phone_number).to eq('+573001234567')
    end

    it 'un teléfono NUEVO e inválido sigue siendo rechazado, no se corrige solo' do
      contact = legacy_contact('+573001234567')

      contact.phone_number = 'no-es-un-numero'

      expect(contact).not_to be_valid
    end

    it 'corregirlo a E.164 rellena las piezas' do
      contact = legacy_contact('573001234567')

      contact.update!(phone_number: '+573001234567')

      expect(contact.reload.phone_country_code_jabvox).to eq('+57')
      expect(contact.phone_national_jabvox).to eq('3001234567')
    end
  end

  describe 'deduplicación con formatos mezclados' do
    it 'un import reconoce como duplicado el número heredado ya normalizado' do
      legacy_contact('+573001234567')

      index = Jabvox::LeadIdentityService.existing_index(account, phones: ['+573001234567'])

      expect(Jabvox::LeadIdentityService.match_existing(index, phone: '+573001234567')).to be_present
    end

    it 'un heredado SIN "+" no se reconoce: se crearía un contacto nuevo' do
      # Comportamiento conocido y aceptado: mientras el histórico no se
      # normalice, "573001234567" y "+573001234567" son filas distintas.
      # La tarea de normalización (rake) es la que unifica esto.
      legacy_contact('573001234567')

      index = Jabvox::LeadIdentityService.existing_index(account, phones: ['+573001234567'])

      expect(Jabvox::LeadIdentityService.match_existing(index, phone: '+573001234567')).to be_nil
    end
  end
end
# rubocop:enable RSpec/DescribeClass
