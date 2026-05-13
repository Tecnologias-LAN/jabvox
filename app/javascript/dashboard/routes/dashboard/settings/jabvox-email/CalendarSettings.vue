<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const store = useStore();
const { t } = useI18n();

const calendarSetting = computed(
  () => store.getters['jabvoxEmail/getCalendarSetting']
);
const uiFlags = computed(() => store.getters['jabvoxEmail/getUIFlags']);

const enabled = ref(false);
const intervals = ref([]);

const minutesToDisplay = minutes => {
  if (minutes >= 1440 && minutes % 1440 === 0)
    return { value: minutes / 1440, unit: 'days' };
  if (minutes >= 60 && minutes % 60 === 0)
    return { value: minutes / 60, unit: 'hours' };
  return { value: minutes, unit: 'minutes' };
};

const displayToMinutes = (value, unit) => {
  const v = parseInt(value, 10);
  if (unit === 'days') return v * 1440;
  if (unit === 'hours') return v * 60;
  return v;
};

watch(
  calendarSetting,
  setting => {
    if (setting) {
      enabled.value = setting.reminders_enabled ?? false;
      intervals.value = (setting.reminder_minutes || []).map(minutesToDisplay);
    }
  },
  { immediate: true }
);

const newValue = ref(1);
const newUnit = ref('days');

const UNITS = computed(() => [
  { value: 'minutes', label: t('JABVOX_EMAIL.CALENDAR.UNIT_MINUTES') },
  { value: 'hours', label: t('JABVOX_EMAIL.CALENDAR.UNIT_HOURS') },
  { value: 'days', label: t('JABVOX_EMAIL.CALENDAR.UNIT_DAYS') },
]);

const addInterval = () => {
  const minutes = displayToMinutes(newValue.value, newUnit.value);
  if (minutes <= 0) return;
  if (intervals.value.some(i => displayToMinutes(i.value, i.unit) === minutes))
    return;
  intervals.value = [
    ...intervals.value,
    { value: parseInt(newValue.value, 10), unit: newUnit.value },
  ];
  newValue.value = 1;
  newUnit.value = 'days';
};

const removeInterval = index => {
  intervals.value = intervals.value.filter((_, i) => i !== index);
};

const intervalLabel = interval =>
  `${interval.value} ${t(`JABVOX_EMAIL.CALENDAR.UNIT_${interval.unit.toUpperCase()}`)}`;

const onSave = async () => {
  const minutesList = intervals.value.map(i =>
    displayToMinutes(i.value, i.unit)
  );
  try {
    await store.dispatch('jabvoxEmail/saveCalendarSetting', {
      reminders_enabled: enabled.value,
      reminder_minutes: minutesList,
    });
    useAlert(t('JABVOX_EMAIL.CALENDAR.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_EMAIL.CALENDAR.SAVE_ERROR'));
  }
};
</script>

<template>
  <div class="space-y-6 max-w-xl">
    <div>
      <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_EMAIL.CALENDAR.TITLE') }}
      </h2>
      <p class="text-xs text-slate-500 mt-0.5">
        {{ $t('JABVOX_EMAIL.CALENDAR.DESCRIPTION') }}
      </p>
    </div>

    <div
      class="rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-5 space-y-5"
    >
      <!-- Enable toggle -->
      <label class="flex items-center justify-between gap-4 cursor-pointer">
        <div>
          <p class="text-sm font-medium text-slate-700 dark:text-slate-200">
            {{ $t('JABVOX_EMAIL.CALENDAR.ENABLED_LABEL') }}
          </p>
          <p class="text-xs text-slate-500 mt-0.5">
            {{ $t('JABVOX_EMAIL.CALENDAR.ENABLED_HELP') }}
          </p>
        </div>
        <button
          role="switch"
          :aria-checked="enabled"
          class="relative w-11 h-6 rounded-full transition-colors shrink-0 focus:outline-none focus:ring-2 focus:ring-woot-500"
          :class="enabled ? 'bg-woot-500' : 'bg-slate-300 dark:bg-slate-600'"
          @click="enabled = !enabled"
        >
          <span
            class="absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform"
            :class="enabled ? 'translate-x-5' : 'translate-x-0'"
          />
        </button>
      </label>

      <template v-if="enabled">
        <hr class="border-slate-200 dark:border-slate-700" />

        <!-- Interval list -->
        <div class="space-y-2">
          <p class="text-xs font-medium text-slate-600 dark:text-slate-400">
            {{ $t('JABVOX_EMAIL.CALENDAR.INTERVALS_LABEL') }}
          </p>

          <div
            v-if="!intervals.length"
            class="text-xs text-slate-400 italic py-1"
          >
            {{ $t('JABVOX_EMAIL.CALENDAR.INTERVALS_EMPTY') }}
          </div>

          <div class="flex flex-wrap gap-2">
            <span
              v-for="(interval, idx) in intervals"
              :key="idx"
              class="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-woot-50 dark:bg-woot-900/20 text-woot-700 dark:text-woot-400 text-sm"
            >
              {{ intervalLabel(interval) }}
              <button
                class="text-woot-400 hover:text-woot-600 dark:hover:text-woot-300"
                :aria-label="$t('JABVOX_EMAIL.CALENDAR.REMOVE_INTERVAL')"
                @click="removeInterval(idx)"
              >
                <span class="i-lucide-x size-3" />
              </button>
            </span>
          </div>

          <!-- Add interval form -->
          <div class="flex items-center gap-2 pt-1">
            <input
              v-model.number="newValue"
              type="number"
              min="1"
              class="w-20 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
            />
            <select
              v-model="newUnit"
              class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
            >
              <option v-for="u in UNITS" :key="u.value" :value="u.value">
                {{ u.label }}
              </option>
            </select>
            <button
              class="px-3 py-2 bg-slate-100 hover:bg-slate-200 dark:bg-slate-700 dark:hover:bg-slate-600 text-slate-700 dark:text-slate-200 text-sm font-medium rounded-lg transition-colors"
              @click="addInterval"
            >
              {{ $t('JABVOX_EMAIL.CALENDAR.ADD_INTERVAL') }}
            </button>
          </div>
        </div>
      </template>
    </div>

    <button
      :disabled="uiFlags.isSavingCalendar"
      class="px-5 py-2 bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium rounded-lg transition-colors disabled:opacity-50"
      @click="onSave"
    >
      {{
        uiFlags.isSavingCalendar
          ? $t('JABVOX_EMAIL.CALENDAR.SAVING')
          : $t('JABVOX_EMAIL.CALENDAR.SAVE')
      }}
    </button>
  </div>
</template>
