import { JABVOX_PERMISSION_GROUPS } from 'dashboard/constants/permissions.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// Mirrors the module->flag map and the filter logic in CustomRoleModal.vue.
// Guards the rule: only show permission groups for ENABLED modules; unmapped
// modules always show; keep a disabled group visible if the edited role already
// holds one of its permissions (so grants aren't silently dropped).
const MODULE_FEATURE_FLAG = {
  kanban: FEATURE_FLAGS.JABVOX_KANBAN,
  tasks: FEATURE_FLAGS.JABVOX_TASKS,
  cdr: FEATURE_FLAGS.JABVOX_CDR,
  audio: FEATURE_FLAGS.JABVOX_AUDIO_ANALYSIS,
  ai_chat: FEATURE_FLAGS.JABVOX_AI_CHAT,
  whatsapp_templates: FEATURE_FLAGS.JABVOX_WHATSAPP_TEMPLATES,
  analytics: FEATURE_FLAGS.JABVOX_ANALYTICS,
  lead_import: FEATURE_FLAGS.JABVOX_LEAD_IMPORT,
  data_export: FEATURE_FLAGS.JABVOX_DATA_EXPORT,
  bulk_whatsapp: FEATURE_FLAGS.JABVOX_BULK_WHATSAPP,
  custom_data: FEATURE_FLAGS.JABVOX_CUSTOMIZATION,
  dialer: FEATURE_FLAGS.JABVOX_DIALER,
  click_to_call: FEATURE_FLAGS.JABVOX_CLICK_TO_CALL,
  internal_chat: FEATURE_FLAGS.JABVOX_INTERNAL_CHAT,
  calendar: FEATURE_FLAGS.JABVOX_CALENDAR,
  forms: FEATURE_FLAGS.JABVOX_FORMS,
  sms: FEATURE_FLAGS.JABVOX_SMS,
  email: FEATURE_FLAGS.JABVOX_EMAIL,
  saldo: FEATURE_FLAGS.JABVOX_SALDO,
  voip: FEATURE_FLAGS.JABVOX_VOIP,
  products: FEATURE_FLAGS.JABVOX_PRODUCTS,
  management_states: FEATURE_FLAGS.JABVOX_MANAGEMENT_STATES,
};

const filterGroups = (enabledFlags, selectedPermissions = []) =>
  JABVOX_PERMISSION_GROUPS.filter(group => {
    const flag = MODULE_FEATURE_FLAG[group.module];
    if (!flag) return true;
    if (enabledFlags.includes(flag)) return true;
    return group.permissions.some(p => selectedPermissions.includes(p));
  });

const groupModules = groups => groups.map(g => g.module);

describe('CustomRole permission filtering by enabled modules', () => {
  it('shows nothing gated when NO jabvox modules are enabled (only unmapped groups)', () => {
    const groups = filterGroups([]);
    const modules = groupModules(groups);
    // Mapped modules must be hidden
    // 'contacts' no tiene flag de módulo: se muestra siempre.
    expect(modules).toContain('contacts');
    expect(modules).not.toContain('dialer');
    expect(modules).not.toContain('cdr');
    // Unmapped modules (no account toggle) always show
    expect(modules).toContain('integrations');
    expect(modules).toContain('ip_whitelist');
    expect(modules).toContain('typifications');
    expect(modules).toContain('campaigns');
  });

  it('shows only the enabled modules', () => {
    const groups = filterGroups([FEATURE_FLAGS.JABVOX_DIALER]);
    const modules = groupModules(groups);
    expect(modules).toContain('contacts');
    expect(modules).toContain('dialer');
    expect(modules).not.toContain('cdr');
    expect(modules).not.toContain('kanban');
    expect(modules).not.toContain('sms');
  });

  it('maps audio -> jabvox_audio_analysis and custom_data -> jabvox_customization correctly', () => {
    const audio = filterGroups([FEATURE_FLAGS.JABVOX_AUDIO_ANALYSIS]);
    expect(groupModules(audio)).toContain('audio');
    const custom = filterGroups([FEATURE_FLAGS.JABVOX_CUSTOMIZATION]);
    expect(groupModules(custom)).toContain('custom_data');
  });

  it('keeps a disabled module visible if the edited role already holds its permission', () => {
    // dialer disabled, but role already has jabvox_dialer_use → keep it visible
    const groups = filterGroups([], ['jabvox_dialer_use']);
    expect(groupModules(groups)).toContain('dialer');
    // a module the role does NOT hold stays hidden
    expect(groupModules(groups)).not.toContain('cdr');
  });

  it('shows all mapped modules when every flag is enabled', () => {
    const allFlags = Object.values(MODULE_FEATURE_FLAG);
    const groups = filterGroups(allFlags);
    // Every group in the catalog should be present
    expect(groups.length).toBe(JABVOX_PERMISSION_GROUPS.length);
  });

  it('every mapped flag resolves to a real feature flag string', () => {
    Object.values(MODULE_FEATURE_FLAG).forEach(flag => {
      expect(typeof flag).toBe('string');
      expect(flag.startsWith('jabvox_')).toBe(true);
    });
  });
});
