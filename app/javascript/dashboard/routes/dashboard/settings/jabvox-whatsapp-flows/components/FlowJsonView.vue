<script setup>
import { useI18n } from 'vue-i18n';
import Code from 'dashboard/components/Code.vue';
import { useFlowJsonPreview } from '../composables/useFlowJsonPreview';

const props = defineProps({
  screens: { type: Array, default: () => [] },
});

const { t } = useI18n();

const screensRef = { value: props.screens };
const { compiledJsonString, localChecks } = useFlowJsonPreview(screensRef);

const checklistItems = [
  {
    key: 'hasScreens',
    label: 'JABVOX_WA_FLOWS.BUILDER.JSON_VIEW.CHECK_HAS_SCREENS',
  },
  {
    key: 'hasTerminalScreen',
    label: 'JABVOX_WA_FLOWS.BUILDER.JSON_VIEW.CHECK_TERMINAL',
  },
  {
    key: 'allScreensHaveIds',
    label: 'JABVOX_WA_FLOWS.BUILDER.JSON_VIEW.CHECK_IDS',
  },
  {
    key: 'allScreensHaveFooter',
    label: 'JABVOX_WA_FLOWS.BUILDER.JSON_VIEW.CHECK_FOOTER',
  },
];
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <div class="px-3 py-2 border-b border-n-weak shrink-0">
      <h3 class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
        {{ t('JABVOX_WA_FLOWS.BUILDER.JSON_VIEW.TITLE') }}
      </h3>
      <p class="text-[11px] text-n-slate-9 mt-0.5">
        {{ t('JABVOX_WA_FLOWS.BUILDER.JSON_VIEW.HINT') }}
      </p>
    </div>

    <div class="px-3 py-2 border-b border-n-weak shrink-0 flex flex-col gap-1">
      <div
        v-for="item in checklistItems"
        :key="item.key"
        class="flex items-center gap-1.5 text-xs"
      >
        <span
          :class="
            localChecks[item.key]
              ? 'i-lucide-check-circle-2 text-n-teal-11'
              : 'i-lucide-circle text-n-slate-8'
          "
          class="size-3.5 shrink-0"
          aria-hidden="true"
        />
        <span
          :class="localChecks[item.key] ? 'text-n-slate-11' : 'text-n-slate-9'"
        >
          {{ t(item.label) }}
        </span>
      </div>
    </div>

    <div class="flex-1 overflow-auto p-3">
      <Code :script="compiledJsonString" lang="json" />
    </div>
  </div>
</template>
