# frozen_string_literal: true

# Expone en el payload del adjunto (push_event_data → dashboard y webhook) si su
# copia en el Drive está RETENIDA por falta de espacio (overflow) o aún procesándose.
#
# Modelo de control de espacio por cuenta: el adjunto SIEMPRE se guarda (no se pierde),
# pero solo se MUESTRA si la cuenta tiene espacio. Si no hay espacio, el chat y el Drive
# muestran "no se puede ver por falta de espacio" hasta que se amplíe el plan o se
# liberen archivos (entonces se promueve y se vuelve visible).
#
# Aditivo y seguro:
#   - Solo con el feature flag jabvox_drive. Sin él, comportamiento intacto.
#   - Una sola query puntual por attachment (por object_key del blob), memoizada.
#   - Si algo falla, se considera NO bloqueado (se muestra): nunca oculta por error.
module Jabvox::AttachmentDriveState
  extend ActiveSupport::Concern

  # Estados del Drive que impiden ver el adjunto todavía.
  BLOCKING_STATES = %w[restricted pending quarantined].freeze

  # Fila del Drive asociada a este adjunto (por la object_key de su blob), si existe.
  def jabvox_drive_file
    return @jabvox_drive_file if defined?(@jabvox_drive_file)

    @jabvox_drive_file = begin
      account.jabvox_drive_files.kept.find_by(object_key: file.blob.key) if jabvox_drive_state_enabled? && file.attached?
    rescue StandardError
      nil
    end
  end

  # ¿El adjunto está retenido (no visible) por el estado del Drive?
  def jabvox_drive_blocked?
    state = jabvox_drive_file&.status
    state.present? && BLOCKING_STATES.include?(state.to_s)
  end

  # Estado legible para el frontend: 'overflow' (sin espacio), 'pending', 'quarantined'.
  def jabvox_drive_state
    return nil unless jabvox_drive_blocked?

    jabvox_drive_file.status == 'restricted' ? 'overflow' : jabvox_drive_file.status
  end

  # Envuelve el file_metadata original: si el adjunto está retenido por falta de
  # espacio, NO se expone la URL real (ni al dashboard ni al webhook) y se marca
  # storage_blocked + storage_state para que el chat muestre el aviso. Cuando se
  # promueve (ampliar/liberar), vuelve a exponer la URL normal.
  def file_metadata
    data = super
    return data unless jabvox_drive_blocked?

    data.merge(
      data_url: '',
      thumb_url: '',
      storage_blocked: true,
      storage_state: jabvox_drive_state
    )
  end

  private

  def jabvox_drive_state_enabled?
    account&.feature_enabled?('jabvox_drive')
  rescue StandardError
    false
  end
end
