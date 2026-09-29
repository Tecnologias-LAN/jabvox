import { createI18n } from 'vue-i18n';
import es from '../locale/es/jabvoxKanban.json';

describe('traducciones del panel de automatizaciones', () => {
  const i18n = createI18n({ legacy: false, locale: 'es', messages: { es } });
  const t = i18n.global.t;

  // El error real: {{...}} sin escapar hace que vue-i18n lo lea como placeholder
  // anidado y lance "Not allowed nest placeholder" al abrir el formulario.
  it('renderiza el placeholder del mensaje sin lanzar', () => {
    const out = t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.MESSAGE_PLACEHOLDER');
    expect(out).toContain('{{contact_name}}');
    expect(out).toContain('{{stage_name}}');
  });

  it('renderiza la lista de variables sin lanzar', () => {
    const out = t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.VARIABLES_LIST');
    expect(out).toBe('{{contact_name}}, {{stage_name}}');
  });
});
