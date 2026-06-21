# Resolves human-readable labels for raw CDR data:
#  - extension -> agent/user name (VoIP user extensions are the source of truth, with the
#    CDR-specific extension mappings as a fallback);
#  - PBX call uniqueid -> a full enrichment (medium, real origin/destination, agent name and
#    typification) by joining the internal click-to-call AND dialer call logs.
# All scoped to a single account.
class Jabvox::CdrLabelResolver
  # Asterisk placeholders the dialer leaves in src/dst — meaningless, must be replaced.
  PLACEHOLDER_SRC = %w[0000 s].freeze
  PLACEHOLDER_DST = %w[s 0000].freeze

  def initialize(account)
    @account = account
  end

  # Name for a raw extension, or nil if unknown.
  def user_name_for(extension)
    extension_lookup.dig(extension.to_s, :name)
  end

  # user_id for a raw extension, or nil.
  def user_id_for(extension)
    extension_lookup.dig(extension.to_s, :user_id)
  end

  # Maps the given PBX uniqueids => enrichment hash:
  #   { medium:, typification_id:, typification:, origin:, destination:, agent_name: }
  # joining the click-to-call and dialer call logs. One query per source.
  def enrichment_lookup(uniqueids)
    ids = uniqueids.compact.map(&:to_s).uniq
    return {} if @account.nil? || ids.empty?

    lookup = {}
    add_click_to_call(lookup, ids)
    add_dialer(lookup, ids)
    lookup
  end

  # Resolves the displayed origin/destination for a CDR row, replacing Asterisk placeholders
  # with the enriched values when available.
  def origin_for(row, enrichment)
    src = row['src'].to_s
    return enrichment[:origin] if PLACEHOLDER_SRC.include?(src) && enrichment&.dig(:origin).present?

    user_name_for(src) || src.presence
  end

  def destination_for(row, enrichment)
    dst = row['dst'].to_s
    return enrichment[:destination] if PLACEHOLDER_DST.include?(dst) && enrichment&.dig(:destination).present?

    user_name_for(dst) || dst.presence
  end

  private

  def add_click_to_call(lookup, ids)
    @account.jabvox_call_logs
            .where(uniqueid: ids)
            .includes(:typification, :user)
            .find_each do |log|
      lookup[log.uniqueid.to_s] = {
        medium: 'click_to_call',
        typification_id: log.typification_id,
        typification: log.typification&.name,
        origin: log.user&.name || log.extension.presence,
        destination: log.phone_number.presence,
        agent_name: log.user&.name
      }
    end
  end

  def add_dialer(lookup, ids)
    @account.jabvox_dialer_call_logs
            .where(uniqueid_jabvox: ids)
            .includes(:typification)
            .find_each do |log|
      lookup[log.uniqueid_jabvox.to_s] ||= {
        medium: 'dialer',
        typification_id: log.typification_id,
        typification: log.typification&.name,
        origin: dialer_agent_name(log),
        destination: log.phone_jabvox.presence,
        agent_name: dialer_agent_name(log)
      }
    end
  end

  def dialer_agent_name(log)
    return nil if log.agent_id_jabvox.blank?

    @agent_names ||= {}
    @agent_names[log.agent_id_jabvox] ||= User.where(id: log.agent_id_jabvox).pick(:name)
  end

  # "extension" => { name:, user_id: }. Built once.
  def extension_lookup
    @extension_lookup ||= build_extension_lookup
  end

  def build_extension_lookup
    return {} if @account.nil?

    lookup = {}
    # CDR-specific labels/users first (lower priority), so VoIP can override below.
    @account.jabvox_cdr_extension_mappings.includes(:user).find_each do |mapping|
      name = mapping.user&.name || mapping.label.presence
      lookup[mapping.extension.to_s] = { name: name, user_id: mapping.user_id } if name
    end
    # VoIP user extensions are the authoritative source of truth.
    @account.jabvox_user_extensions.includes(:user).find_each do |ext|
      lookup[ext.extension_jabvox.to_s] = { name: ext.user&.name, user_id: ext.user_id }
    end
    lookup
  end
end
