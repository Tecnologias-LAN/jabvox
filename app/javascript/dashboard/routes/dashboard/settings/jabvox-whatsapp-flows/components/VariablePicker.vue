<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import {
  availableVariablesForScreen,
  SYSTEM_VARIABLES,
} from '../screenHelpers';

const props = defineProps({
  screens: { type: Array, default: () => [] },
  currentScreenId: { type: String, default: '' },
  // Solo la primera pantalla puede usar variables de sistema del contacto
  // (sección 4.4: se inyectan al enviar vía flow_action_data).
  isFirstScreen: { type: Boolean, default: false },
});

const emit = defineEmits(['pick']);

const { t } = useI18n();

const open = ref(false);
const rootRef = ref(null);
onClickOutside(rootRef, () => {
  open.value = false;
});

const screenVariables = computed(() =>
  availableVariablesForScreen(props.screens, props.currentScreenId)
);

const hasAnyVariables = computed(
  () => screenVariables.value.length > 0 || props.isFirstScreen
);

const pick = reference => {
  emit('pick', reference);
  open.value = false;
};
</script>

<template>
  <div ref="rootRef" class="relative inline-block">
    <button
      type="button"
      class="wf-icon-btn-xs"
      :disabled="!hasAnyVariables"
      :title="t('JABVOX_WA_FLOWS.BUILDER.VARIABLES.PICKER_TITLE')"
      @click="open = !open"
    >
      <span class="i-lucide-braces size-3.5" aria-hidden="true" />
    </button>

    <div
      v-if="open"
      class="absolute z-30 mt-1 w-64 max-h-64 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 shadow-lg p-2"
    >
      <div v-if="isFirstScreen" class="mb-2">
        <p
          class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-9 px-1.5 mb-1"
        >
          {{ t('JABVOX_WA_FLOWS.BUILDER.VARIABLES.SYSTEM_GROUP') }}
        </p>
        <button
          v-for="sysVar in SYSTEM_VARIABLES"
          :key="sysVar.key"
          type="button"
          class="wf-variable-item"
          @click="pick(sysVar.reference)"
        >
          <span class="truncate">{{ sysVar.label }}</span>
          <code class="text-[10px] text-n-slate-9 shrink-0">{{
            sysVar.reference
          }}</code>
        </button>
      </div>

      <div v-if="screenVariables.length">
        <p
          class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-9 px-1.5 mb-1"
        >
          {{ t('JABVOX_WA_FLOWS.BUILDER.VARIABLES.SCREENS_GROUP') }}
        </p>
        <button
          v-for="sv in screenVariables"
          :key="`${sv.screenId}_${sv.name}`"
          type="button"
          class="wf-variable-item"
          @click="pick(sv.reference)"
        >
          <span class="truncate">{{ sv.screenTitle }} · {{ sv.name }}</span>
          <code class="text-[10px] text-n-slate-9 shrink-0">{{
            sv.reference
          }}</code>
        </button>
      </div>

      <p v-if="!hasAnyVariables" class="text-xs text-n-slate-10 px-1.5 py-1">
        {{ t('JABVOX_WA_FLOWS.BUILDER.VARIABLES.NONE_AVAILABLE') }}
      </p>
    </div>
  </div>
</template>
