<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  status: {
    type: String,
    default: 'untested',
    validator: value => ['ok', 'error', 'untested'].includes(value),
  },
});

const { t } = useI18n();

const config = computed(() => {
  switch (props.status) {
    case 'ok':
      return {
        dot: 'bg-n-teal-11',
        text: 'text-n-teal-11',
        label: t('JABVOX_ANALYTICS.DATA_SOURCES.TEST.CONNECTED'),
      };
    case 'error':
      return {
        dot: 'bg-n-ruby-9',
        text: 'text-n-ruby-11',
        label: t('JABVOX_ANALYTICS.DATA_SOURCES.TEST.ERROR'),
      };
    default:
      return {
        dot: 'bg-n-slate-9',
        text: 'text-n-slate-11',
        label: t('JABVOX_ANALYTICS.COMMON.NONE'),
      };
  }
});
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium"
    :class="config.text"
  >
    <span class="size-1.5 rounded-full" :class="config.dot" />
    {{ config.label }}
  </span>
</template>
