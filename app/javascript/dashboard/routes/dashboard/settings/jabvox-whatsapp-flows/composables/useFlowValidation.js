import { ref, computed } from 'vue';
import { wfFlowsAPI } from 'dashboard/api/jabvox/whatsappFlows';

/**
 * Llama al endpoint POST /flows/:id/validate (Validator local del backend,
 * sección 5.1 de docs/whatsapp-flows/architecture.md) y expone los errores
 * de forma reactiva para que ValidationPanel.vue los liste y el builder
 * pueda resaltar el screen/componente afectado.
 *
 * `errors`: [{ screen_id, component_id, field, message }]
 */
export function useFlowValidation() {
  const errors = ref([]);
  const validating = ref(false);
  const validated = ref(false);

  const isValid = computed(() => validated.value && errors.value.length === 0);

  const errorsForScreen = screenId =>
    errors.value.filter(e => e.screen_id === screenId);

  const errorsForComponent = (screenId, componentId) =>
    errors.value.filter(
      e => e.screen_id === screenId && e.component_id === componentId
    );

  const validate = async flowId => {
    validating.value = true;
    try {
      const { data } = await wfFlowsAPI.validate(flowId);
      errors.value = data.errors || [];
      validated.value = true;
      return data.valid ?? errors.value.length === 0;
    } catch (err) {
      // Un error de red/servidor no es lo mismo que "flow inválido": se
      // expone como un error genérico en vez de fingir que el flow es válido.
      errors.value = [
        {
          screen_id: null,
          component_id: null,
          field: null,
          message:
            err?.response?.data?.error ||
            'No se pudo validar el Flow. Intenta de nuevo.',
        },
      ];
      validated.value = true;
      return false;
    } finally {
      validating.value = false;
    }
  };

  const reset = () => {
    errors.value = [];
    validated.value = false;
  };

  return {
    errors,
    validating,
    validated,
    isValid,
    validate,
    reset,
    errorsForScreen,
    errorsForComponent,
  };
}
