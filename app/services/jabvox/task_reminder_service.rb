# frozen_string_literal: true

# Avisa de una tarea que vence, por todos los canales que la cuenta tenga disponibles.
#
# "Todos los canales" es literal pero no ciego: se intenta cada uno y el que no esté
# configurado se salta sin romper los demás. Una cuenta sin SMTP sigue recibiendo el aviso
# interno; una sin proveedor de SMS, el correo. Así el recordatorio llega por donde se
# pueda en vez de no llegar porque falte una pieza.
#
# Avisa al RESPONSABLE, no al contacto: el recordatorio es para quien tiene que hacer el
# trabajo. Avisar al contacto de una tarea interna sería filtrarle gestión ajena.
class Jabvox::TaskReminderService
  Result = Struct.new(:delivered, :skipped, keyword_init: true)

  # Orden deliberado: el aviso interno primero, que es el único que no depende de que la
  # cuenta tenga nada configurado.
  CHANNELS = %i[notification email sms].freeze

  def initialize(task)
    @task = task
    @account = task.account
  end

  def call
    return Result.new(delivered: [], skipped: ['task_deleted']) if @task.deleted_at_jabvox.present?

    delivered = []
    skipped = []

    recipients.each do |user|
      CHANNELS.each do |channel|
        send(:"deliver_#{channel}", user)
        delivered << "#{channel}:#{user.id}"
      rescue StandardError => e
        skipped << "#{channel}:#{user.id}:#{e.message}"
      end
    end

    # update_column a propósito: es una marca de control para no repetir el aviso, no un
    # cambio de la tarea. Validar o disparar callbacks aquí solo añadiría ruido.
    @task.update_column(:reminder_sent_at_jabvox, Time.current) if delivered.any? # rubocop:disable Rails/SkipsModelValidations
    Result.new(delivered: delivered, skipped: skipped)
  end

  private

  # Los responsables de la tarea. `assignees` es la lista nueva; `assignee` el campo
  # histórico de un solo responsable, que se mantiene sincronizado.
  def recipients
    users = @task.assignees.to_a
    users << @task.assignee if users.empty? && @task.assignee
    users.compact.uniq
  end

  def subject
    "Recordatorio: #{@task.title_jabvox}"
  end

  def body
    vence = @task.due_at_jabvox ? I18n.l(@task.due_at_jabvox, format: :long) : 'sin fecha'
    "La tarea «#{@task.title_jabvox}» vence el #{vence}."
  end

  # Aviso dentro de Jabvox: la campanita del panel. Es el único que no depende de que la
  # cuenta tenga nada configurado, así que es el que siempre llega.
  def deliver_notification(user)
    Jabvox::ModuleNotificationService.create!(
      account: @account,
      user: user,
      type: :jabvox_task_reminder,
      actor: @task,
      title: 'Recordatorio de tarea',
      body: body,
      path: "/app/accounts/#{@account.id}/jabvox/tasks/view/#{@task.id}"
    )
  end

  def deliver_email(user)
    raise 'sin_email' if user.email.blank?

    smtp = @account.jabvox_smtp_config
    raise 'sin_smtp' unless smtp

    Jabvox::EmailSenderService.new(
      account: @account, config: smtp, to: user.email,
      subject: subject, html_body: body, source: 'task_reminder', user: user
    ).deliver!
  end

  def deliver_sms(user)
    phone = user.try(:phone_number).presence
    raise 'sin_telefono' if phone.blank?

    provider = @account.jabvox_sms_providers.find_by(active_jabvox: true)
    raise 'sin_proveedor_sms' unless provider

    Jabvox::SmsSenderService.new(provider).send_sms(
      phone: phone, message: body, account: @account, contact: nil
    )
  end
end
