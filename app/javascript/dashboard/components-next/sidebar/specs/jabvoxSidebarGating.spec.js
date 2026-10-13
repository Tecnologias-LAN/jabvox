import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

// Static guard: the Jabvox sidebar gating must match the product spec so a plain
// agent never sees config pestañas / restricted reports. We assert directly on the
// Sidebar source: for each menu item we look at the ~16 lines preceding its `name:`
// and check whether the enclosing spread includes a permission gate.
const here = dirname(fileURLToPath(import.meta.url));
const sidebarSrc = readFileSync(resolve(here, '../Sidebar.vue'), 'utf8');
const navigationSrc = readFileSync(
  resolve(here, '../jabvoxModuleNavigation.js'),
  'utf8'
);
const dashboardRoutesSrc = readFileSync(
  resolve(here, '../../../routes/dashboard/dashboard.routes.js'),
  'utf8'
);
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
  "name: 'Settings Jabvox Email'",
  "name: 'Settings Jabvox Forms'",
  "name: 'Settings Jabvox Customization'",
];

describe('Jabvox sidebar gating matches the permission spec', () => {
  it.each(CONFIG_ITEMS)('config item requires a permission: %s', item => {
    const ctx = contextBefore(item);
    expect(ctx, `menu item not found: ${item}`).not.toBeNull();
    expect(hasPermGate(ctx), `${item} must be permission-gated`).toBe(true);
  });

  it('filters module tabs through the destination route policy', () => {
    expect(navigationSrc).toContain(
      'tab.permissionRoutes.some(isRouteAllowed)'
    );
    expect(sidebarSrc).toContain(
      'isJabvoxNavigationRouteAllowed(router, shouldShow, to)'
    );
  });

  it('keeps the requested modules in their consolidated navigation groups', () => {
    expect(navigationSrc).toContain("'jabvox_kanban_index'");
    expect(navigationSrc).toContain("'jabvox_calendar_index'");
    expect(navigationSrc).toContain("'jabvox_tasks_index'");
    expect(navigationSrc).toContain("'jabvox_internal_chat_index'");
    expect(navigationSrc).toContain("'jabvox_tickets_index'");
    expect(navigationSrc).toContain("'jabvox_custom_data_index'");
    expect(navigationSrc).toContain("'jabvox_ai_chat_index'");
    expect(navigationSrc).toContain("'jabvox_provisioning_chat_index'");
    expect(navigationSrc).toContain("'jabvox_reports_index'");
    expect(navigationSrc).toContain("'calls_dashboard_index'");
    expect(navigationSrc).toContain("'jabvox_audio_analysis_reports_index'");
    expect(navigationSrc).toContain("'jabvox_cdr_reports_index'");
    expect(navigationSrc).toContain("'jabvox_analytics_index'");
    expect(navigationSrc).toContain("'jabvox_dialer_index'");
  });

  // Captain se unificó dentro del Chat IA (Hermes): ya no tiene entrada propia en el
  // sidebar. El único módulo de IA de la cuenta es "Jabvox AI Chat" (ver USAGE_FLAG_ONLY).
  it('Captain no longer has its own sidebar entry', () => {
    expect(contextBefore("name: 'Captain'")).toBeNull();
  });

  // El centro de ayuda se retiro del producto: ni entrada de sidebar ni feature flag.
  it('Help Center (Portals) no longer has a sidebar entry', () => {
    expect(contextBefore("name: 'Portals'")).toBeNull();
    expect(sidebarSrc).not.toContain('HELP_CENTER');
  });

  it('does not expose standard Campaigns navigation', () => {
    expect(sidebarSrc).not.toContain("name: 'Campaigns'");
    expect(navigationSrc).not.toContain('campaigns_livechat_index');
    expect(dashboardRoutesSrc).not.toContain('campaignsRoutes');
  });
});
