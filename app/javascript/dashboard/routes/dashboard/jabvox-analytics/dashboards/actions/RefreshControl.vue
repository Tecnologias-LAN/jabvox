<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';

const emit = defineEmits(['refresh']);

const { t } = useI18n();

const interval = ref(0);
let timer = null;

const INTERVALS = [0, 30, 60];

// Labels resolved with static literal keys so the template binds plain strings.
const intervalLabels = computed(() => ({
  0: t('JABVOX_ANALYTICS.REFRESH_CONTROL.OFF'),
  30: t('JABVOX_ANALYTICS.REFRESH_CONTROL.30S'),
  60: t('JABVOX_ANALYTICS.REFRESH_CONTROL.60S'),
}));

const clearTimer = () => {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
};

const onIntervalChange = value => {
  interval.value = Number(value);
  clearTimer();
  if (interval.value > 0) {
    timer = setInterval(() => emit('refresh'), interval.value * 1000);
  }
};

onBeforeUnmount(clearTimer);

const inputClass =
  'rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div class="flex items-center gap-2">
    <button
      type="button"
      class="inline-flex items-center gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
      @click="emit('refresh')"
    >
      <span class="i-lucide-refresh-cw size-4" />
      {{ t('JABVOX_ANALYTICS.REFRESH_CONTROL.REFRESH') }}
    </button>
    <select
      :value="interval"
      :class="inputClass"
      :title="t('JABVOX_ANALYTICS.REFRESH_CONTROL.AUTO')"
      @change="onIntervalChange($event.target.value)"
    >
      <option v-for="item in INTERVALS" :key="item" :value="item">
        {{ intervalLabels[item] }}
      </option>
    </select>
  </div>
</template>
