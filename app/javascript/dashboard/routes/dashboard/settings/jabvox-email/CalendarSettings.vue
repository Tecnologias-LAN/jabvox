<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SectionCard from './components/SectionCard.vue';
import SaveBar from './components/SaveBar.vue';

const store = useStore();
const { t } = useI18n();
const { isDirty, markDirty, markClean } = useUnsavedChanges();

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

const applySetting = setting => {
  enabled.value = setting.reminders_enabled ?? false;
  intervals.value = (setting.reminder_minutes || []).map(minutesToDisplay);
};

watch(
  calendarSetting,
  async setting => {
    if (setting) {
      applySetting(setting);
      await nextTick();
      markClean();
    }
  },
  { immediate: true }
);

watch([enabled, intervals], () => markDirty(), { deep: true });

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
    await nextTick();
    markClean();
    useAlert(t('JABVOX_EMAIL.CALENDAR.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_EMAIL.CALENDAR.SAVE_ERROR'));
  }
};

const onDiscard = async () => {
  if (calendarSetting.value) applySetting(calendarSetting.value);
  await nextTick();
  markClean();
};
</script>

<template>
  <div class="w-full flex flex-col gap-4">
    <SectionCard
      :title="t('JABVOX_EMAIL.CALENDAR.TITLE')"
      :description="t('JABVOX_EMAIL.CALENDAR.DESCRIPTION')"
      icon="i-lucide-calendar-clock"
    >
      <div class="flex flex-col gap-5">
        <!-- Enable toggle -->
        <div
          class="flex items-center justify-between gap-4 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <div>
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_EMAIL.CALENDAR.ENABLED_LABEL') }}
            </p>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{ t('JABVOX_EMAIL.CALENDAR.ENABLED_HELP') }}
            </p>
          </div>
          <Switch v-model="enabled" />
        </div>

        <template v-if="enabled">
          <!-- Interval list -->
          <div class="flex flex-col gap-2">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_EMAIL.CALENDAR.INTERVALS_LABEL') }}
            </p>

            <div
              v-if="!intervals.length"
              class="text-xs text-n-slate-10 italic py-1"
            >
              {{ t('JABVOX_EMAIL.CALENDAR.INTERVALS_EMPTY') }}
            </div>

            <div v-else class="flex flex-wrap gap-2">
              <span
                v-for="(interval, idx) in intervals"
                :key="idx"
                class="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-n-alpha-2 text-n-slate-12 text-sm"
              >
                {{ intervalLabel(interval) }}
                <button
                  class="text-n-slate-10 hover:text-n-ruby-11"
                  :aria-label="t('JABVOX_EMAIL.CALENDAR.REMOVE_INTERVAL')"
                  @click="removeInterval(idx)"
                >
                  <span class="i-lucide-x size-3" />
                </button>
              </span>
            </div>

            <!-- Add interval form -->
            <div class="flex flex-wrap items-end gap-2 pt-1">
              <div class="w-24">
                <Input v-model.number="newValue" type="number" min="1" />
              </div>
              <div class="w-32">
                <Select v-model="newUnit" :options="UNITS" />
              </div>
              <Button
                icon="i-lucide-plus"
                :label="t('JABVOX_EMAIL.CALENDAR.ADD_INTERVAL')"
                variant="outline"
                color="slate"
                size="sm"
                @click="addInterval"
              />
            </div>
          </div>
        </template>
      </div>
    </SectionCard>

    <SaveBar
      :visible="isDirty"
      :is-saving="uiFlags.isSavingCalendar"
      @save="onSave"
      @discard="onDiscard"
    />
  </div>
</template>
