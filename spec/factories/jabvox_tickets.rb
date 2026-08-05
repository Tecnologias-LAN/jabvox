FactoryBot.define do
  factory :jabvox_ticket_helpdesk_config do
    account
    auto_assign_mode_jabvox { :manual }
    resolver_visibility_jabvox { :assigned_only }
    active_jabvox { true }
  end

  factory :jabvox_ticket_category do
    account
    sequence(:name_jabvox) { |n| "Categoría #{n}" }
    category_type_jabvox { :incident }
    color_jabvox { '#1F93FF' }
    sla_response_minutes_jabvox { 60 }
    sla_resolution_minutes_jabvox { 1440 }
  end

  factory :jabvox_ticket do
    account
    sequence(:title_jabvox) { |n| "Ticket #{n}" }
    description_jabvox { 'Descripción del ticket' }
    priority_jabvox { :medium }
    requester { association :user, account: account }
  end

  factory :jabvox_ticket_comment do
    association :ticket, factory: :jabvox_ticket
    user
    body_jabvox { 'Comentario de prueba' }
    private_jabvox { false }
  end
end
