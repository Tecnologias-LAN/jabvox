<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CalendarAPI from 'dashboard/api/jabvox/calendar';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SectionCard from 'dashboard/routes/dashboard/settings/jabvox-email/components/SectionCard.vue';
import SaveBar from 'dashboard/routes/dashboard/settings/jabvox-email/components/SaveBar.vue';

const { t } = useI18n();

// Días de la semana con day_of_week = Date#wday (0 domingo … 6 sábado).
const DAYS = computed(() =>
  [0, 1, 2, 3, 4, 5, 6].map(wday => ({
    wday,
    // Claves 0..6 declaradas explícitamente en el i18n; índice controlado.
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(`JABVOX_CALENDAR.AVAILABILITY.DAYS.${wday}`),
  }))
);

// Opciones de duración de cita ofrecidas al agendar.
const SLOT_OPTIONS = [15, 20, 30, 45, 60, 90, 120].map(m => ({
  value: m,
  label: `${m} min`,
}));

const agents = ref([]);
const selectedAgentId = ref(null);
const rows = ref([]); // una fila por día: { wday, active, start, end, slot }
const isLoading = ref(false);
const isSaving = ref(false);
const isDirty = ref(false);

const agentOptions = computed(() =>
  agents.value.map(a => ({
    value: a.id,
    label: a.availabilities_count > 0 ? `${a.name} ✓` : a.name,
  }))
);

const minutesToTime = minutes => {
  const h = String(Math.floor(minutes / 60)).padStart(2, '0');
  const m = String(minutes % 60).padStart(2, '0');
  return `${h}:${m}`;
};

const timeToMinutes = value => {
  const [h, m] = String(value || '00:00')
    .split(':')
    .map(n => parseInt(n, 10) || 0);
  return h * 60 + m;
};

// Fila por defecto: día laboral típico 9-18, cita de 30 min, desactivado.
const emptyRow = wday => ({
  wday,
  active: false,
  start: '09:00',
  end: '18:00',
  slot: 30,
});

const buildRows = availabilities => {
  const byDay = Object.fromEntries(
    (availabilities || []).map(a => [a.day_of_week, a])
  );
  return DAYS.value.map(({ wday }) => {
    const found = byDay[wday];
    if (!found) return emptyRow(wday);
    return {
      wday,
      active: found.active,
      start: minutesToTime(found.start_minute),
      end: minutesToTime(found.end_minute),
      slot: found.slot_minutes,
    };
  });
};

const fetchAgents = async () => {
  const { data } = await CalendarAPI.getAgentsAvailability();
  agents.value = data;
  if (!selectedAgentId.value && data.length) {
    selectedAgentId.value = data[0].id;
  }
};

const fetchAgentAvailability = async agentId => {
  if (!agentId) return;
  isLoading.value = true;
  try {
    const { data } = await CalendarAPI.getAgentAvailability(agentId);
    rows.value = buildRows(data.availabilities);
    await nextTick();
    isDirty.value = false;
  } finally {
    isLoading.value = false;
  }
};

watch(selectedAgentId, id => fetchAgentAvailability(id));
watch(
  rows,
  () => {
    isDirty.value = true;
  },
  { deep: true }
);

const validRow = row => timeToMinutes(row.end) > timeToMinutes(row.start);

const onSave = async () => {
  const active = rows.value.filter(r => r.active);
  if (active.some(r => !validRow(r))) {
    useAlert(t('JABVOX_CALENDAR.AVAILABILITY.SAVE_INVALID'));
    return;
  }
  isSaving.value = true;
  try {
    const payload = active.map(r => ({
      day_of_week: r.wday,
      start_minute: timeToMinutes(r.start),
      end_minute: timeToMinutes(r.end),
      slot_minutes: r.slot,
      active: true,
    }));
    await CalendarAPI.updateAgentAvailability(selectedAgentId.value, payload);
    await fetchAgents();
    isDirty.value = false;
    useAlert(t('JABVOX_CALENDAR.AVAILABILITY.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CALENDAR.AVAILABILITY.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const onDiscard = () => fetchAgentAvailability(selectedAgentId.value);

onMounted(fetchAgents);
</script>

<template>
  <div class="w-full flex flex-col gap-4">
    <SectionCard
      :title="t('JABVOX_CALENDAR.AVAILABILITY.TITLE')"
      :description="t('JABVOX_CALENDAR.AVAILABILITY.DESCRIPTION')"
      icon="i-lucide-calendar-check"
    >
      <div class="flex flex-col gap-5">
        <!-- Selector de agente -->
        <div class="flex flex-col gap-1.5 max-w-sm">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('JABVOX_CALENDAR.AVAILABILITY.AGENT_LABEL') }}
          </label>
          <Select v-model="selectedAgentId" :options="agentOptions" />
        </div>

        <!-- Tabla de días -->
        <div
          v-if="selectedAgentId && !isLoading"
          class="flex flex-col divide-y divide-n-weak rounded-xl border border-n-weak overflow-hidden"
        >
          <div
            v-for="row in rows"
            :key="row.wday"
            class="flex flex-wrap items-center gap-3 px-4 py-3"
            :class="row.active ? 'bg-n-alpha-1' : 'bg-n-background'"
          >
            <div class="flex items-center gap-2 w-32 shrink-0">
              <Switch v-model="row.active" />
              <span class="text-sm font-medium text-n-slate-12">
                {{ DAYS[row.wday].label }}
              </span>
            </div>

            <template v-if="row.active">
              <div class="flex items-center gap-1.5">
                <input
                  v-model="row.start"
                  type="time"
                  class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-sm text-n-slate-12"
                />
                <span
                  class="w-2 h-px bg-n-slate-8 shrink-0"
                  aria-hidden="true"
                />
                <input
                  v-model="row.end"
                  type="time"
                  class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-sm text-n-slate-12"
                />
              </div>
              <div class="w-32">
                <Select v-model="row.slot" :options="SLOT_OPTIONS" />
              </div>
            </template>
            <span v-else class="text-xs text-n-slate-10 italic">
              {{ t('JABVOX_CALENDAR.AVAILABILITY.DAY_OFF') }}
            </span>
          </div>
        </div>

        <p class="text-xs text-n-slate-10">
          {{ t('JABVOX_CALENDAR.AVAILABILITY.HELP') }}
        </p>
      </div>
    </SectionCard>

    <SaveBar
      :visible="isDirty"
      :is-saving="isSaving"
      @save="onSave"
      @discard="onDiscard"
    />
  </div>
</template>
