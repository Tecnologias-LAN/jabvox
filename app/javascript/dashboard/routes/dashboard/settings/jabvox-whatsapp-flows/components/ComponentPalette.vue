<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  COMPONENT_CATALOG,
  COMPONENT_CATEGORIES,
  isAtLimit,
  MAX_COMPONENTS_PER_SCREEN,
} from '../componentCatalog';

const props = defineProps({
  screenComponents: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['add']);

const { t } = useI18n();

const atScreenLimit = computed(
  () => props.screenComponents.length >= MAX_COMPONENTS_PER_SCREEN
);

const groupedTypes = computed(() =>
  COMPONENT_CATEGORIES.map(cat => ({
    ...cat,
    types: Object.entries(COMPONENT_CATALOG)
      .filter(([, meta]) => meta.category === cat.key)
      .map(([type, meta]) => ({ type, ...meta })),
  })).filter(group => group.types.length)
);

const isDisabled = type =>
  props.disabled ||
  atScreenLimit.value ||
  isAtLimit(props.screenComponents, type);

const limitLabel = type => {
  const meta = COMPONENT_CATALOG[type];
  if (!meta?.limitPerScreen) return '';
  const used = props.screenComponents.filter(c => c.type === type).length;
  return `${used}/${meta.limitPerScreen}`;
};
</script>

<template>
  <div class="flex flex-col h-full overflow-y-auto p-3 gap-4">
    <p v-if="atScreenLimit" class="text-xs text-n-amber-11">
      {{ t('JABVOX_WA_FLOWS.BUILDER.PALETTE.SCREEN_LIMIT_REACHED') }}
    </p>
    <div
      v-for="group in groupedTypes"
      :key="group.key"
      class="flex flex-col gap-1.5"
    >
      <h4
        class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-9"
      >
        {{ group.label }}
      </h4>
      <div class="grid grid-cols-2 gap-1.5">
        <button
          v-for="item in group.types"
          :key="item.type"
          type="button"
          class="wf-palette-btn"
          :disabled="isDisabled(item.type)"
          :title="item.label"
          @click="emit('add', item.type)"
        >
          <span :class="item.icon" class="size-4 shrink-0" aria-hidden="true" />
          <span class="truncate flex-1 text-left">{{ item.label }}</span>
          <span
            v-if="limitLabel(item.type)"
            class="text-[10px] text-n-slate-9 shrink-0"
          >
            {{ limitLabel(item.type) }}
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
