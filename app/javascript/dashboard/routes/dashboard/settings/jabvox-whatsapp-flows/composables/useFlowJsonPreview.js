import { computed } from 'vue';
import { compileFlowJson } from '../flowJsonCompiler';

/**
 * Arma el preview del Flow JSON en el cliente, para feedback inmediato sin
 * round-trip al backend. El compilado AUTORITATIVO (el que se manda a Meta)
 * sigue siendo el de `Jabvox::WhatsappFlows::JsonCompiler` en el backend —
 * este preview puede quedar desalineado en detalles finos y no debe usarse
 * para publicar, solo para que el usuario vea la forma del JSON mientras
 * construye el Flow (FlowJsonView.vue).
 *
 * @param {import('vue').Ref<Array>} screensJsonRef
 */
export function useFlowJsonPreview(screensJsonRef) {
  const compiledJson = computed(() =>
    compileFlowJson(screensJsonRef.value || [])
  );

  const compiledJsonString = computed(() =>
    JSON.stringify(compiledJson.value, null, 2)
  );

  // Checklist básico local (regla 13 del encargo): no reemplaza al Validator
  // del backend, solo da una señal temprana de "forma" del JSON mientras se
  // edita, antes de gastar una llamada de red.
  const localChecks = computed(() => {
    const screens = screensJsonRef.value || [];
    return {
      hasScreens: screens.length > 0,
      hasTerminalScreen: screens.some(s => s.terminal),
      allScreensHaveIds: screens.every(s => !!s.id),
      allScreensHaveFooter: screens.every(s =>
        (s.components || []).some(c => c.type === 'Footer')
      ),
    };
  });

  return { compiledJson, compiledJsonString, localChecks };
}
