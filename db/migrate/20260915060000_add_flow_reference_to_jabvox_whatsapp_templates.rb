class AddFlowReferenceToJabvoxWhatsappTemplates < ActiveRecord::Migration[7.1]
  def change
    # Enlace con el Flow que abre el botón de la plantilla, cuando se creó desde
    # el mismo wizard. Nullable: las plantillas que referencian un Flow hecho
    # aparte (o creado directamente en Meta) no lo tienen.
    add_reference :jabvox_whatsapp_templates, :jabvox_whatsapp_flow,
                  foreign_key: true, null: true, index: true
  end
end
