<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  result: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

const isSuccess = computed(() => Boolean(props.result?.success));
</script>

<template>
  <div>
    <div
      v-if="result"
      class="flex items-start gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm"
    >
      <span
        class="mt-0.5 size-4 shrink-0"
        :class="
          isSuccess
            ? 'i-lucide-circle-check text-n-teal-11'
            : 'i-lucide-circle-x text-n-ruby-11'
        "
      />
      <div class="min-w-0">
        <p
          class="font-medium"
          :class="isSuccess ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          {{
            isSuccess
              ? t('JABVOX_ANALYTICS.DATA_SOURCES.TEST.CONNECTED')
              : t('JABVOX_ANALYTICS.DATA_SOURCES.TEST.ERROR')
          }}
        </p>
        <p
          v-if="isSuccess && result.latencyMs != null"
          class="mt-0.5 text-n-slate-11"
        >
          {{
            t('JABVOX_ANALYTICS.DATA_SOURCES.TEST.LATENCY', {
              ms: result.latencyMs,
            })
          }}
        </p>
        <p
          v-else-if="!isSuccess && result.message"
          class="mt-0.5 break-words text-n-slate-11"
        >
          {{ result.message }}
        </p>
      </div>
    </div>
  </div>
</template>
