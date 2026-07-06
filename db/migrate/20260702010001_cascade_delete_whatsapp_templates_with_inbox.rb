class CascadeDeleteWhatsappTemplatesWithInbox < ActiveRecord::Migration[7.1]
  # When a WhatsApp inbox is removed, its stored templates should go with it instead of
  # leaving orphaned rows (or blocking the inbox deletion via a foreign-key violation).
  # Rebuild the FK with ON DELETE CASCADE.
  def up
    remove_foreign_key :jabvox_whatsapp_templates, :inboxes if foreign_key_exists?(:jabvox_whatsapp_templates, :inboxes)
    add_foreign_key :jabvox_whatsapp_templates, :inboxes, on_delete: :cascade
  end

  def down
    remove_foreign_key :jabvox_whatsapp_templates, :inboxes if foreign_key_exists?(:jabvox_whatsapp_templates, :inboxes)
    add_foreign_key :jabvox_whatsapp_templates, :inboxes
  end
end
