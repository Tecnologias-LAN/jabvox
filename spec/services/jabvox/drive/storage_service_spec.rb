# frozen_string_literal: true

require 'rails_helper'

# Specs del guardián de seguridad del Drive. Las pruebas de construcción de clave y
# aislamiento NO dependen de MinIO (son lógica pura). Las de I/O real corren solo si
# hay un MinIO disponible en JABVOX_DRIVE_ENDPOINT (se marcan como :minio y se saltan
# si no responde), para no acoplar CI a un servicio externo.
RSpec.describe Jabvox::Drive::StorageService do
  let(:account) { create(:account) }
  let(:other) { create(:account) }
  let(:service) { described_class.new(account) }

  describe '#account_prefix' do
    it 'deriva el prefijo del id de la cuenta' do
      expect(service.account_prefix).to eq("acct-#{account.id}/")
    end
  end

  describe '#object_key (anti path-traversal)' do
    it 'construye la clave con el prefijo de la cuenta' do
      expect(service.object_key('Contactos/5/foto.jpg')).to eq("acct-#{account.id}/Contactos/5/foto.jpg")
    end

    it 'rechaza rutas con ..' do
      expect { service.object_key('../otra/x.txt') }.to raise_error(described_class::InvalidKeyError)
      expect { service.object_key('Contactos/../../acct-999/x.txt') }.to raise_error(described_class::InvalidKeyError)
    end

    it 'rechaza rutas absolutas y bytes nulos' do
      expect { service.object_key('/etc/passwd') }.to raise_error(described_class::InvalidKeyError)
      expect { service.object_key("x\u0000y") }.to raise_error(described_class::InvalidKeyError)
    end

    it 'rechaza ruta vacía' do
      expect { service.object_key('') }.to raise_error(described_class::InvalidKeyError)
    end
  end

  describe '#owns_key? / #assert_owned! (aislamiento entre cuentas)' do
    it 'reconoce las claves propias' do
      expect(service.owns_key?("acct-#{account.id}/x.txt")).to be(true)
    end

    it 'rechaza la clave de otra cuenta' do
      foreign = "acct-#{other.id}/secreto.txt"
      expect(service.owns_key?(foreign)).to be(false)
      expect { service.assert_owned!(foreign) }.to raise_error(described_class::InvalidKeyError)
    end
  end

  # --- I/O real contra MinIO (opcional) ---
  describe 'I/O real', :minio do
    before do
      skip 'MinIO no disponible' unless described_class.configured? && service.available?
    end

    it 'sube, lee, head y borra respetando el prefijo' do
      key = "spec/#{SecureRandom.hex(6)}.txt"
      r = service.put(key, 'contenido spec', content_type: 'text/plain')
      expect(r[:key]).to start_with(service.account_prefix)
      expect(service.get(r[:key])).to eq('contenido spec')
      expect(service.head(r[:key])[:byte_size]).to eq(r[:byte_size])
      service.delete(r[:key])
      expect(service.head(r[:key])).to be_nil
    end

    it 'no permite leer el objeto de otra cuenta (prefijo ajeno)' do
      foreign_key = "acct-#{other.id}/robo.txt"
      expect { service.get(foreign_key) }.to raise_error(described_class::InvalidKeyError)
    end
  end
end
