FactoryBot.define do
  factory :data_import do
    data_type { 'contacts' }
    import_file { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/contacts.csv'), 'text/csv') }
    account
    # País del import: de él sale el prefijo telefónico. Los fixtures traen
    # números de India (+91), ya con prefijo.
    source_metadata { { 'country' => 'IN', 'duplicate_policy' => 'update' } }

    # Política por defecto del producto: un lead que ya existe NO se toca.
    trait :skip_duplicates do
      source_metadata { { 'country' => 'IN', 'duplicate_policy' => 'skip' } }
    end

    trait :intercom do
      data_type { 'intercom' }
      source_type { 'api' }
      source_provider { 'intercom' }
      import_types { %w[contacts conversations] }
      access_token { 'intercom-token' }
      import_file { nil }
    end
  end
end
