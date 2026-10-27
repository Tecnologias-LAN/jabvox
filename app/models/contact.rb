# rubocop:disable Layout/LineLength

# == Schema Information
#
# Table name: contacts
#
#  id                        :integer          not null, primary key
#  additional_attributes     :jsonb
#  became_lead_at_jabvox     :datetime
#  blocked                   :boolean          default(FALSE), not null
#  contact_type              :integer          default("visitor")
#  country_code              :string           default("")
#  custom_attributes         :jsonb
#  custom_fields_jabvox      :jsonb            not null
#  email                     :string
#  identifier                :string
#  is_sold_jabvox            :boolean          default(FALSE), not null
#  last_activity_at          :datetime
#  last_name                 :string           default("")
#  lifecycle_stage_jabvox    :string           default("prospecto"), not null
#  location                  :string           default("")
#  middle_name               :string           default("")
#  name                      :string           default("")
#  phone_country_code_jabvox :string
#  phone_national_jabvox     :string
#  phone_number              :string
#  username                  :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :integer          not null
#  assignee_id               :bigint
#  company_id                :bigint
#  jabvox_affiliate_id       :bigint
#  jabvox_campaign_id        :bigint
#
# Indexes
#
#  index_contacts_on_account_id                             (account_id)
#  index_contacts_on_account_id_and_contact_type            (account_id,contact_type)
#  index_contacts_on_account_id_and_jabvox_affiliate_id     (account_id,jabvox_affiliate_id)
#  index_contacts_on_account_id_and_jabvox_campaign_id      (account_id,jabvox_campaign_id)
#  index_contacts_on_account_id_and_last_activity_at        (account_id,last_activity_at DESC NULLS LAST)
#  index_contacts_on_account_id_and_lifecycle_stage_jabvox  (account_id,lifecycle_stage_jabvox)
#  index_contacts_on_assignee_id                            (assignee_id)
#  index_contacts_on_blocked                                (blocked)
#  index_contacts_on_company_id                             (company_id)
#  index_contacts_on_custom_fields_jabvox                   (custom_fields_jabvox) USING gin
#  index_contacts_on_is_sold_jabvox                         (is_sold_jabvox)
#  index_contacts_on_lower_email_account_id                 (lower((email)::text), account_id)
#  index_contacts_on_name_email_phone_number_identifier     (name,email,phone_number,identifier) USING gin
#  index_contacts_on_nonempty_fields                        (account_id,email,phone_number,identifier) WHERE (((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))
#  index_contacts_on_phone_number_and_account_id            (phone_number,account_id)
#  index_resolved_contact_account_id                        (account_id) WHERE (((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))
#  uniq_email_per_account_contact                           (email,account_id) UNIQUE
#  uniq_identifier_per_account_contact                      (identifier,account_id) UNIQUE
#

# rubocop:enable Layout/LineLength

# rubocop:disable Metrics/ClassLength
class Contact < ApplicationRecord
  include Avatarable
  include AvailabilityStatusable

  def avatar_url = ''
  include Labelable
  include LlmFormattable
  include ContactAgentVisibility
  # Mantiene phone_country_code_jabvox / phone_national_jabvox derivados del E.164
  # de phone_number, que sigue siendo la identidad del contacto.
  include Jabvox::ContactPhoneParts
  include Jabvox::ContactLifecycle

  validates :account_id, presence: true
  validates :email, allow_blank: true, uniqueness: { scope: [:account_id], case_sensitive: false },
                    format: { with: Devise.email_regexp, message: I18n.t('errors.contacts.email.invalid') }
  validates :identifier, allow_blank: true, uniqueness: { scope: [:account_id] }
  validates :phone_number,
            allow_blank: true, uniqueness: { scope: [:account_id] },
            format: { with: /\+[1-9]\d{1,14}\z/, message: I18n.t('errors.contacts.phone_number.invalid') }
  # Username de WhatsApp: el "@usuario" que Meta entrega cuando el cliente no comparte
  # número. Se guarda sin la arroba y no puede repetirse dentro de la cuenta.
  validates :username, allow_blank: true, uniqueness: { scope: [:account_id], case_sensitive: false }

  belongs_to :account
  has_many :conversations, dependent: :destroy_async
  has_many :contact_inboxes, dependent: :destroy_async
  has_many :csat_survey_responses, dependent: :destroy_async
  has_many :inboxes, through: :contact_inboxes
  has_many :messages, as: :sender, dependent: :destroy_async
  has_many :notes, dependent: :destroy_async
  # Contact-linked custom rows go away with the contact (the FK is also
  # ON DELETE CASCADE, so a bulk delete_all can't be blocked either).
  has_many :jabvox_custom_table_rows, dependent: :delete_all
  # Enlace anti-duplicados con la importación desde base de datos externa (external_id).
  has_many :jabvox_lead_source_records, class_name: 'JabvoxLeadSourceRecord', dependent: :delete_all
  # Estas tres tienen clave foránea SIN on_delete, así que una fila cualquiera impedía
  # borrar el contacto con un ForeignKeyViolation. El controlador ya limpiaba calendario y
  # SMS a mano, pero no llamadas ni formularios de WhatsApp: el borrado fallaba en cuanto
  # el contacto tenía una llamada registrada. Declararlo aquí lo cubre venga de donde venga
  # el borrado, no solo desde esa acción del controlador.
  has_many :jabvox_call_logs, class_name: 'JabvoxCallLog', dependent: :delete_all
  has_many :jabvox_whatsapp_flow_submissions, class_name: 'JabvoxWhatsappFlowSubmission', dependent: :delete_all
  has_many :jabvox_calendar_events, class_name: 'JabvoxCalendarEvent', dependent: :delete_all
  before_validation :prepare_contact_attributes
  after_create_commit :dispatch_create_event, :ip_lookup
  after_update_commit :dispatch_update_event
  # El responsable del contacto arrastra a sus conversaciones ABIERTAS: si el comercial
  # cambia, quien atiende lo que está vivo cambia con él. Las resueltas se dejan como
  # están —son historial de quién atendió qué— y va en el modelo, no en el controlador,
  # para que valga igual desde la ficha que desde la asignación masiva.
  after_update_commit :sync_assignee_to_open_conversations, if: :saved_change_to_assignee_id?
  after_destroy_commit :dispatch_destroy_event
  before_save :sync_contact_attributes

  enum contact_type: { visitor: 0, lead: 1, customer: 2 }

  scope :order_on_last_activity_at, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order("\"contacts\".\"last_activity_at\" #{direction}
          NULLS LAST")
      )
    )
  }
  scope :order_on_created_at, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order("\"contacts\".\"created_at\" #{direction}
          NULLS LAST")
      )
    )
  }
  scope :order_on_company_name, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "\"contacts\".\"additional_attributes\"->>'company_name' #{direction}
          NULLS LAST"
        )
      )
    )
  }
  scope :order_on_city, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "\"contacts\".\"additional_attributes\"->>'city' #{direction}
          NULLS LAST"
        )
      )
    )
  }
  scope :order_on_country_name, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "\"contacts\".\"additional_attributes\"->>'country' #{direction}
          NULLS LAST"
        )
      )
    )
  }

  scope :order_on_name, lambda { |direction|
    order(
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "CASE
           WHEN \"contacts\".\"name\" ~~* '^+\d*' THEN 'z'
           WHEN \"contacts\".\"name\"  ~~*  '^\b*' THEN 'z'
           ELSE LOWER(\"contacts\".\"name\")
           END #{direction}"
        )
      )
    )
  }

  # Find contacts that:
  # 1. Have no identification (email, phone_number, and identifier are NULL or empty string)
  # 2. Have no conversations
  # 3. Are older than the specified time period
  scope :stale_without_conversations, lambda { |time_period|
    where('contacts.email IS NULL OR contacts.email = ?', '')
      .where('contacts.phone_number IS NULL OR contacts.phone_number = ?', '')
      .where('contacts.identifier IS NULL OR contacts.identifier = ?', '')
      .where('contacts.created_at < ?', time_period)
      .where.missing(:conversations)
  }

  def get_source_id(inbox_id)
    contact_inboxes.find_by!(inbox_id: inbox_id).source_id
  end

  # ¿Se puede INICIAR/ENVIAR WhatsApp a este contacto en este inbox?
  # Regla: necesita número de teléfono O un contact_inbox con BSUID (el identificador
  # que entrega Meta cuando la persona no comparte número). Si solo tiene username
  # (sin número ni BSUID) NO es direccionable: hay que esperar a que escriba o cargar
  # su número. Es independiente de la ventana de 24h (eso lo mide can_reply?).
  def whatsapp_addressable?(inbox)
    return true if phone_number.present?
    return false if inbox.blank?

    inbox.contact_inboxes
         .where(contact_id: id)
         .where('source_id ~ ?', RegexHelper::WHATSAPP_BSUID_SQL_PATTERN)
         .exists?
  end

  def push_event_data
    data = {
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      email: email,
      id: id,
      identifier: identifier,
      name: name,
      phone_number: phone_number,
      username: username,
      thumbnail: avatar_url,
      blocked: blocked,
      type: 'contact'
    }
    data[:company_id] = company_id if account.feature_enabled?('companies')
    data
  end

  def webhook_data
    {
      account: account.webhook_data,
      additional_attributes: additional_attributes,
      avatar: avatar_url,
      custom_attributes: custom_attributes,
      email: email,
      id: id,
      identifier: identifier,
      name: name,
      phone_number: phone_number,
      username: username,
      thumbnail: avatar_url,
      blocked: blocked
    }
  end

  def discard_invalid_attrs
    phone_number_format
    email_format
  end

  def self.from_email(email)
    find_by(email: email&.downcase)
  end

  private

  # `update_all` a propósito: puede tocar decenas de conversaciones y cargarlas una a una
  # para disparar callbacks dejaría la petición colgada. Es un solo campo ya validado.
  def sync_assignee_to_open_conversations
    conversations.where(status: :open)
                 .update_all(assignee_id: assignee_id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def ip_lookup
    return unless account.feature_enabled?('ip_lookup')

    ContactIpLookupJob.perform_later(self)
  end

  def phone_number_format
    return if phone_number.blank?

    self.phone_number = phone_number_was unless phone_number.match?(/\+[1-9]\d{1,14}\z/)
  end

  def email_format
    return if email.blank?

    self.email = email_was unless email.match(Devise.email_regexp)
  end

  def prepare_contact_attributes
    prepare_email_attribute
    prepare_username_attribute
    prepare_jsonb_attributes
  end

  # El username de WhatsApp se guarda SIN arroba y normalizado; '' pasa a nil para que
  # el índice único parcial por cuenta no choque entre contactos sin username.
  def prepare_username_attribute
    self.username = username.to_s.sub(/\A@+/, '').strip.presence
  end

  def prepare_email_attribute
    # So that the db unique constraint won't throw error when email is ''
    self.email = email.present? ? email.downcase : nil
  end

  def prepare_jsonb_attributes
    self.additional_attributes = {} if additional_attributes.blank?
    self.custom_attributes = {} if custom_attributes.blank?
  end

  def sync_contact_attributes
    ::Contacts::SyncAttributes.new(self).perform
  end

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(CONTACT_CREATED, Time.zone.now, contact: self)
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(CONTACT_UPDATED, Time.zone.now, contact: self, changed_attributes: previous_changes)
  end

  def dispatch_destroy_event
    # Pass serialized data instead of ActiveRecord object to avoid DeserializationError
    # when the async EventDispatcherJob runs after the contact has been deleted
    Rails.configuration.dispatcher.dispatch(
      CONTACT_DELETED,
      Time.zone.now,
      contact_data: push_event_data.merge(account_id: account_id)
    )
  end
end
# rubocop:enable Metrics/ClassLength
Contact.include_mod_with('Concerns::Contact')
