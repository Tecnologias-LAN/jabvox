# frozen_string_literal: true

# Anti-replay: registra cada nonce visto. Un nonce repetido dentro de la ventana = replay →
# se rechaza. El índice único hace la deduplicación atómica (dos peticiones con el mismo
# nonce: solo una inserta, la otra choca y se bloquea).
# == Schema Information
#
# Table name: jabvox_provisioner_nonces
#
class JabvoxProvisionerNonce < ApplicationRecord
  WINDOW = 300 # segundos: ventana de validez del timestamp firmado

  # Intenta registrar el nonce. Devuelve true si es nuevo (petición legítima), false si ya
  # existía (replay). Nunca lanza por la colisión de unicidad.
  def self.register(nonce)
    return false if nonce.blank?

    create!(nonce_jabvox: nonce.to_s, seen_at_jabvox: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Purga nonces más viejos que la ventana (ya no pueden replayearse por el chequeo de tiempo).
  def self.purge_expired!
    where(seen_at_jabvox: ..WINDOW.seconds.ago).delete_all
  end
end
