# frozen_string_literal: true

# Deja pasar solo los invitados que son de la cuenta.
#
# Los ids llegan del formulario, y sin cruzarlos con la cuenta se podía invitar a un
# usuario o a una persona externa de OTRA cuenta: el evento se guardaba y el serializador
# devolvía su nombre y su email. Lo que no encaja se descarta en silencio, que es lo que
# hace un formulario con una opción que ya no existe.
class Jabvox::CalendarParticipantsFilter
  def initialize(account)
    @account = account
  end

  def call(rows)
    return [] if rows.blank?

    rows.select { |row| allowed?(row) }
  end

  private

  def allowed?(row)
    user_ok?(row['user_id']) && person_ok?(row['external_person_id'])
  end

  def user_ok?(id)
    id.blank? || account_user_ids.include?(id.to_i)
  end

  def person_ok?(id)
    id.blank? || external_person_ids.include?(id.to_i)
  end

  def account_user_ids
    @account_user_ids ||= @account.users.pluck(:id)
  end

  def external_person_ids
    @external_person_ids ||= @account.jabvox_calendar_external_people.pluck(:id)
  end
end
