<script setup>
import { ref, watch, nextTick, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAutomation } from 'dashboard/composables/useAutomation';
import { useEditableAutomation } from 'dashboard/composables/useEditableAutomation';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import { useCompaniesStore } from 'dashboard/stores/companies';
import AutomationRuleForm from './AutomationRuleForm.vue';
import { AUTOMATION_ACTION_TYPES } from './constants';

const props = defineProps({
  selectedResponse: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['saveAutomation']);

const allCustomAttributes = useMapGetter('attributes/getAttributes');
const formRef = ref(null);
const companiesStore = useCompaniesStore();

onMounted(() => {
  // Precarga de empresas para poblar el desplegable de la condición "Empresa" y
  // resolver el nombre de un company_id ya guardado. El endpoint degrada a lista
  // vacía si el módulo no aplica, así que no dependemos del feature-check (que
  // puede no estar resuelto al montar y dejaba el desplegable vacío).
  companiesStore.get({}).catch(() => {});
});

const {
  automation,
  automationTypes,
  onEventChange,
  getConditionDropdownValues,
  appendNewCondition,
  appendNewGroup,
  appendNewAction,
  removeFilter,
  removeAction,
  resetAction,
  getActionDropdownValues,
  manifestCustomAttributes,
} = useAutomation();

const { formatAutomation } = useEditableAutomation();

const { markDirty, markClean } = useUnsavedChanges();

const open = () => formRef.value?.open();
const close = () => {
  markClean();
  formRef.value?.close();
};

const onSave = (payload, mode) => {
  markClean();
  emit('saveAutomation', payload, mode);
};

watch(automation, () => markDirty(), { deep: true });

watch(
  () => props.selectedResponse,
  async value => {
    if (!value?.conditions) return;

    manifestCustomAttributes();

    automation.value = formatAutomation(
      value,
      allCustomAttributes.value,
      automationTypes,
      AUTOMATION_ACTION_TYPES
    );
    await nextTick();
    markClean();
  },
  { immediate: true }
);

defineExpose({ open, close });
</script>

<template>
  <AutomationRuleForm
    ref="formRef"
    v-model:automation="automation"
    mode="edit"
    :automation-types="automationTypes"
    :get-condition-dropdown-values="getConditionDropdownValues"
    :get-action-dropdown-values="getActionDropdownValues"
    :append-new-condition="appendNewCondition"
    :append-new-group="appendNewGroup"
    :append-new-action="appendNewAction"
    :remove-filter="removeFilter"
    :remove-action="removeAction"
    :reset-action="resetAction"
    :on-event-change="onEventChange"
    @save="onSave"
    @close="markClean"
  />
</template>
