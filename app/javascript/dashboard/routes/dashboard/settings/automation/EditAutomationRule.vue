<script setup>
import { ref, watch, nextTick, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAutomation } from 'dashboard/composables/useAutomation';
import { useEditableAutomation } from 'dashboard/composables/useEditableAutomation';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
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
const { isCloudFeatureEnabled } = useAccount();
const companiesStore = useCompaniesStore();

onMounted(() => {
  // Precarga de empresas para resolver el nombre de un company_id ya guardado en la
  // regla. Solo si el módulo está activo (endpoint enterprise, 403 si no).
  if (isCloudFeatureEnabled(FEATURE_FLAGS.COMPANIES)) {
    companiesStore.get({});
  }
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
