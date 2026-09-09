module SuperAdmin::AccountFeaturesHelper
  def self.account_features
    YAML.safe_load(Rails.root.join('config/features.yml').read).freeze
  end

  def self.account_premium_features
    account_features.filter { |feature| feature['premium'] }.pluck('name')
  end

  # Returns a hash mapping feature names to their display names
  def self.feature_display_names
    account_features.each_with_object({}) do |feature, hash|
      hash[feature['name']] = feature['display_name']
    end
  end

  def self.filter_internal_features(features)
    return features if JabvoxApp.jabvox_cloud?

    internal_features = account_features.select { |f| f['jabvox_internal'] }.pluck('name')
    features.except(*internal_features)
  end

  def self.filter_deprecated_features(features)
    deprecated_features = account_features.select { |f| f['deprecated'] }.pluck('name')
    features.except(*deprecated_features)
  end

  # Sub-features de Jabvox IA (Captain): NO se muestran por separado en super admin. Se
  # gobiernan con la feature principal `captain_integration` ("Jabvox IA"): al activarla se
  # activan estas automáticamente (ver Account#sync_jabvox_ia_subfeatures). Así el admin ve
  # UN solo interruptor "Jabvox IA".
  JABVOX_IA_SUBFEATURES = %w[
    captain_integration_v2 captain_document_auto_sync captain_tasks captain_v1_action_classifier
  ].freeze

  def self.filter_jabvox_ia_subfeatures(features)
    features.except(*JABVOX_IA_SUBFEATURES)
  end

  def self.sort_and_transform_features(features, display_names)
    features.sort_by { |key, _| display_names[key] || key }
            .to_h
            .transform_keys { |key| [key, display_names[key]] }
  end

  def self.partition_features(features)
    filtered = filter_internal_features(features)
    filtered = filter_deprecated_features(filtered)
    filtered = filter_jabvox_ia_subfeatures(filtered)
    display_names = feature_display_names

    regular, premium = filtered.partition { |key, _value| account_premium_features.exclude?(key) }

    [
      sort_and_transform_features(regular, display_names),
      sort_and_transform_features(premium, display_names)
    ]
  end

  def self.filtered_features(features)
    regular, premium = partition_features(features)
    regular.merge(premium)
  end
end
