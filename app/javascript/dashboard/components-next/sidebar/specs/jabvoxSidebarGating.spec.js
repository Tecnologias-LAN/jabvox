import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

// Static guard: the Jabvox sidebar gating must match the product spec so a plain
// agent never sees config pestañas / restricted reports. We assert directly on the
// Sidebar source: for each menu item we look at the ~16 lines preceding its `name:`
// and check whether the enclosing spread includes a permission gate.
const here = dirname(fileURLToPath(import.meta.url));
const sidebarSrc = readFileSync(resolve(here, '../Sidebar.vue'), 'utf8');
const lines = sidebarSrc.split('\n');

const contextBefore = (needle, span = 16) => {
  const i = lines.findIndex(l => l.includes(needle));
  if (i === -1) return null;
  return lines.slice(Math.max(0, i - span), i).join('\n');
};

const hasPermGate = ctx =>
  /jabvoxCan\(|checkPermissions\(|canViewJabvoxReports/.test(ctx);

// CONFIG items ("no" or config-only): MUST require a permission (admin/custom).
const CONFIG_ITEMS = [
  "name: 'Settings Jabvox Kanban'",
  "name: 'Settings Jabvox Products'",
  "name: 'Settings Jabvox VoIP'",
  "name: 'Settings Jabvox CDR'",
  "name: 'Settings Jabvox WA Templates'",
  "name: 'Settings Jabvox Bulk WhatsApp'",
  "name: 'Settings Jabvox Audio Analysis'",
  "name: 'Settings Jabvox Lead Import'",
  "name: 'Settings Jabvox Data Export'",
  "name: 'Settings Jabvox Typifications'",
  "name: 'Settings Jabvox Saldo'",
  "name: 'Settings Jabvox SMS'",
  "name: 'Settings Jabvox AI Chat'",
  "name: 'Settings Jabvox Dialer'",
  "name: 'Settings Jabvox Affiliates'",
  "name: 'Settings Jabvox Response Bot'",
  "name: 'Settings Jabvox Email'",
  "name: 'Settings Jabvox Forms'",
  "name: 'Settings Jabvox Customization'",
];

// Reports that only admin / custom-role-with-permission may see.
const REPORT_ITEMS = [
  "name: 'Jabvox Reports'",
  "name: 'Jabvox CDR Reports'",
  "name: 'Jabvox Audio Reports'",
  "name: 'Jabvox Custom Data'",
];

// USAGE items an agent may see when the module is active (flag-only, NO perm gate).
const USAGE_FLAG_ONLY = [
  "name: 'Jabvox Kanban'",
  "name: 'Leads'",
  "name: 'Jabvox AI Chat'",
  "name: 'Jabvox Dialer'",
];

describe('Jabvox sidebar gating matches the permission spec', () => {
  it.each(CONFIG_ITEMS)('config item requires a permission: %s', item => {
    const ctx = contextBefore(item);
    expect(ctx, `menu item not found: ${item}`).not.toBeNull();
    expect(hasPermGate(ctx), `${item} must be permission-gated`).toBe(true);
  });

  it.each(REPORT_ITEMS)('report item requires a permission: %s', item => {
    const ctx = contextBefore(item);
    expect(ctx).not.toBeNull();
    expect(hasPermGate(ctx)).toBe(true);
  });

  it.each(USAGE_FLAG_ONLY)(
    'usage item is flag-only (no perm gate): %s',
    item => {
      const ctx = contextBefore(item);
      expect(ctx).not.toBeNull();
      expect(hasPermGate(ctx), `${item} should NOT be permission-gated`).toBe(
        false
      );
    }
  );

  // Captain se unificó dentro del Chat IA (Hermes): ya no tiene entrada propia en el
  // sidebar. El único módulo de IA de la cuenta es "Jabvox AI Chat" (ver USAGE_FLAG_ONLY).
  it('Captain no longer has its own sidebar entry', () => {
    expect(contextBefore("name: 'Captain'")).toBeNull();
  });

  it('Help Center (Portals) is gated by its feature flag', () => {
    const ctx = contextBefore("name: 'Portals'");
    expect(ctx).not.toBeNull();
    expect(/FEATURE_FLAGS\.HELP_CENTER\b/.test(ctx)).toBe(true);
  });
});
