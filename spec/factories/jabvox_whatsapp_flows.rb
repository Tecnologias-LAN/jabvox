FactoryBot.define do
  factory :jabvox_whatsapp_flow do
    account
    inbox
    waba_id { '123456789' }
    name { 'Encuesta de satisfacción' }
    category { 'SURVEY' }
    status { 'draft' }
    screens_json do
      [
        {
          'id' => 'welcome', 'title' => 'Inicio', 'terminal' => false, 'order' => 0,
          'components' => [
            { 'id' => 'cmp_1', 'type' => 'TextHeading', 'props' => { 'text' => 'Encuesta' } },
            { 'id' => 'cmp_2', 'type' => 'Footer', 'props' => { 'label' => 'Comenzar', 'action' => { 'name' => 'navigate', 'next' => 'rating' } } }
          ]
        },
        {
          'id' => 'rating', 'title' => 'Calificación', 'terminal' => true, 'order' => 1,
          'components' => [
            { 'id' => 'cmp_3', 'type' => 'RadioButtonsGroup',
              'props' => { 'name' => 'calificacion', 'label' => '¿Cómo calificas el servicio?',
                           'data_source' => [{ 'id' => 'excelente', 'title' => 'Excelente' }, { 'id' => 'bueno', 'title' => 'Bueno' }] } },
            { 'id' => 'cmp_4', 'type' => 'Footer', 'props' => { 'label' => 'Enviar', 'action' => { 'name' => 'complete' } } }
          ]
        }
      ]
    end

    trait :published do
      status { 'published' }
      meta_flow_id { 'meta-flow-123' }
      meta_status { 'PUBLISHED' }
      published_at { Time.current }
    end
  end

  factory :jabvox_whatsapp_flow_submission do
    account
    jabvox_whatsapp_flow
    contact
    jabvox_whatsapp_flow_version { 1 }
    sequence(:flow_token) { |n| "flow-token-#{n}" }
    status { 'completed' }
    raw_response_json { { 'flow_token' => 'flow-token', 'screen_0_calificacion_0' => 'Excelente' } }
    completed_at { Time.current }
  end

  factory :jabvox_whatsapp_flow_answer do
    association :submission, factory: :jabvox_whatsapp_flow_submission
    screen_id { 'rating' }
    component_id { 'cmp_3' }
    component_name { 'calificacion' }
    component_type { 'RadioButtonsGroup' }
    value_text { 'Excelente' }
  end
end
