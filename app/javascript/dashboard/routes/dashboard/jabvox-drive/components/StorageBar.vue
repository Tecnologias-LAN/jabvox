<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { humanSize } from '../helper';

const props = defineProps({
  storage: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

const unlimited = computed(() => props.storage?.unlimited === true);
const percent = computed(() => {
  const p = Number(props.storage?.percent_used || 0);
  return Math.min(Math.max(Math.round(p), 0), 100);
});
const overflowBytes = computed(() =>
  Number(props.storage?.overflow_bytes || 0)
);
const hasOverflow = computed(() => overflowBytes.value > 0);
const almostFull = computed(() => !unlimited.value && percent.value >= 90);

// Color de la barra según uso.
const barColorClass = computed(() => {
  if (hasOverflow.value) return 'bg-n-ruby-9';
  if (almostFull.value) return 'bg-n-amber-9';
  return 'bg-n-brand';
});
</script>

<template>
  <div
    v-if="storage"
    class="flex flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-3"
  >
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="i-lucide-hard-drive size-4 text-n-slate-11 shrink-0"
          aria-hidden="true"
        />
        <span class="text-sm font-medium text-n-slate-12 truncate">
          {{ t('JABVOX_DRIVE.STORAGE.TITLE') }}
        </span>
      </div>
      <span v-if="unlimited" class="text-xs font-medium text-n-teal-11">
        {{ t('JABVOX_DRIVE.STORAGE.UNLIMITED') }}
      </span>
      <span v-else class="text-xs text-n-slate-11 whitespace-nowrap">
        {{
          t('JABVOX_DRIVE.STORAGE.USED_OF', {
            used: humanSize(storage.used_bytes),
            quota: humanSize(storage.quota_bytes),
          })
        }}
      </span>
    </div>

    <template v-if="!unlimited">
      <div class="h-2 w-full overflow-hidden rounded-full bg-n-alpha-1">
        <div
          class="h-full rounded-full transition-all"
          :class="barColorClass"
          :style="{ width: `${percent}%` }"
        />
      </div>
      <div
        class="flex items-center justify-between text-[11px] text-n-slate-10"
      >
        <span>{{ t('JABVOX_DRIVE.STORAGE.PERCENT_USED', { percent }) }}</span>
        <span>
          {{
            t('JABVOX_DRIVE.STORAGE.AVAILABLE', {
              available: humanSize(storage.available_bytes),
            })
          }}
        </span>
      </div>
    </template>

    <p
      v-if="hasOverflow"
      class="flex items-start gap-1.5 text-xs text-n-ruby-11"
    >
      <span
        class="i-lucide-triangle-alert size-3.5 shrink-0 mt-0.5"
        aria-hidden="true"
      />
      {{
        t('JABVOX_DRIVE.STORAGE.OVERFLOW_WARNING', {
          overflow: humanSize(overflowBytes),
        })
      }}
    </p>
    <p
      v-else-if="almostFull"
      class="flex items-start gap-1.5 text-xs text-n-amber-11"
    >
      <span
        class="i-lucide-triangle-alert size-3.5 shrink-0 mt-0.5"
        aria-hidden="true"
      />
      {{ t('JABVOX_DRIVE.STORAGE.ALMOST_FULL') }}
    </p>
  </div>
</template>
