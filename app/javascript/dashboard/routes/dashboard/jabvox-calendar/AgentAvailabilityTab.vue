<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CalendarAPI from 'dashboard/api/jabvox/calendar';

// Horario laboral por agente. Sirve para que Jabvox IA ofrezca huecos y para sombrear la
// agenda.
//
// La lista de agentes va a la derecha y se marcan los que interesan: los horarios se
// despliegan en el centro, uno debajo de otro. Antes había un desplegable de un solo
// agente, así que comparar dos turnos obligaba a ir y volver perdiendo lo escrito.
const { t } = useI18n();

const DAYS = computed(() =>
  [0, 1, 2, 3, 4, 5, 6].map(wday => ({
    wday,
    // Claves 0..6 declaradas explícitamente en el i18n; índice controlado.
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(`JABVOX_CALENDAR.AVAILABILITY.DAYS.${wday}`),
  }))
);

const SLOT_OPTIONS = [15, 20, 30, 45, 60, 90, 120];

// La semana empieza en lunes, como se lee un horario laboral; el domingo va al final.
// Los índices siguen siendo Date#wday (0 = domingo).
const WEEK_ORDER = [1, 2, 3, 4, 5, 6, 0];

// Un color estable por agente, derivado de su id: al superponer varios en la misma semana
// es lo que permite distinguir de quién es cada turno sin leer el nombre.
const AGENT_COLORS = [
  '#3B82F6',
  '#10B981',
  '#F59E0B',
  '#EF4444',
  '#8B5CF6',
  '#EC4899',
  '#14B8A6',
  '#F97316',
];
const agentColor = id =>
  id === 'company'
    ? '#64748B'
    : AGENT_COLORS[Math.abs(Number(id)) % AGENT_COLORS.length];

const agents = ref([]);
// Varios a la vez: cada uno con sus filas y su estado de guardado propio.
const openAgentIds = ref([]);
const schedules = ref({});
const savingIds = ref([]);
const isLoading = ref(false);

const minutesToTime = minutes =>
  `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(
    minutes % 60
  ).padStart(2, '0')}`;

const timeToMinutes = value => {
  const [h, m] = String(value || '00:00')
    .split(':')
    .map(n => parseInt(n, 10) || 0);
  return h * 60 + m;
};

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
  isLoading.value = true;
  try {
    const { data } = await CalendarAPI.getAgentsAvailability();
    agents.value = data;
  } catch {
    useAlert(t('JABVOX_CALENDAR.AVAILABILITY.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const loadSchedule = async agentId => {
  if (schedules.value[agentId]) return;
  try {
    const { data } = await CalendarAPI.getAgentAvailability(agentId);
    schedules.value = {
      ...schedules.value,
      [agentId]: buildRows(data.availabilities),
    };
  } catch {
    useAlert(t('JABVOX_CALENDAR.AVAILABILITY.LOAD_ERROR'));
  }
};

const toggleAgent = async agentId => {
  const idx = openAgentIds.value.indexOf(agentId);
  if (idx === -1) {
    openAgentIds.value.push(agentId);
    await loadSchedule(agentId);
  } else {
    openAgentIds.value.splice(idx, 1);
  }
};

// Se abre el primero para no dejar el centro vacío al entrar.
onMounted(async () => {
  await fetchAgents();
  if (agents.value.length) toggleAgent(agents.value[0].id);
});

const openAgents = computed(() =>
  openAgentIds.value
    .map(id => agents.value.find(a => a.id === id))
    .filter(Boolean)
);

const agentName = agent =>
  agent.id === 'company'
    ? t('JABVOX_CALENDAR.AVAILABILITY.COMPANY')
    : agent.name;

const validRow = row => timeToMinutes(row.end) > timeToMinutes(row.start);

const save = async agentId => {
  const rows = schedules.value[agentId] || [];
  const active = rows.filter(r => r.active);
  if (active.some(r => !validRow(r))) {
    useAlert(t('JABVOX_CALENDAR.AVAILABILITY.SAVE_INVALID'));
    return;
  }
  savingIds.value.push(agentId);
  try {
    await CalendarAPI.updateAgentAvailability(
      agentId,
      active.map(r => ({
        day_of_week: r.wday,
        start_minute: timeToMinutes(r.start),
        end_minute: timeToMinutes(r.end),
        slot_minutes: r.slot,
        active: true,
      }))
    );
    await fetchAgents();
    useAlert(t('JABVOX_CALENDAR.AVAILABILITY.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CALENDAR.AVAILABILITY.SAVE_ERROR'));
  } finally {
    savingIds.value = savingIds.value.filter(id => id !== agentId);
  }
};

// Copiar el primer día activo al resto: configurar siete días uno a uno es tedioso y casi
// siempre son iguales.
const applyToAll = agentId => {
  const rows = schedules.value[agentId] || [];
  const source = rows.find(r => r.active);
  if (!source) return;

  schedules.value = {
    ...schedules.value,
    [agentId]: rows.map(r =>
      // El domingo se deja como está: rara vez se trabaja y sorprendería activarlo.
      r.wday === 0
        ? r
        : {
            ...r,
            active: true,
            start: source.start,
            end: source.end,
            slot: source.slot,
          }
    ),
  };
};

// Fila de un agente en un día concreto. Devuelve siempre un objeto —creándolo vacío si
// aún no existe— para que el `v-model` de la casilla y las horas tenga dónde escribir.
const rowFor = (agentId, wday) => {
  const rows = schedules.value[agentId];
  if (!rows) return emptyRow(wday);

  return rows.find(r => r.wday === wday) || emptyRow(wday);
};

const daysCount = agent => agent.availabilities_count || 0;
</script>

<template>
  <div class="flex flex-col lg:flex-row h-full min-h-0 gap-4">
    <!-- Semana de lunes a domingo: cada día una columna con los turnos de los agentes
         marcados, cada uno con su color. Antes era una lista de siete filas por agente y
         no se veía quién cubría qué franja. -->
    <div class="flex-1 min-w-0 overflow-auto order-2 lg:order-1">
      <p v-if="isLoading" class="text-sm text-n-slate-10">
        {{ t('JABVOX_CALENDAR.AVAILABILITY.LOADING') }}
      </p>

      <div
        v-else-if="!openAgents.length"
        class="flex flex-col items-center justify-center py-12 text-center gap-2"
      >
        <span class="i-lucide-users size-8 text-n-slate-8" aria-hidden="true" />
        <p class="text-sm text-n-slate-10">
          {{ t('JABVOX_CALENDAR.AVAILABILITY.PICK_AGENT') }}
        </p>
      </div>

      <div v-else class="min-w-[44rem]">
        <div class="grid grid-cols-7 gap-2">
          <div
            v-for="day in WEEK_ORDER"
            :key="day"
            class="rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden"
          >
            <p
              class="text-xs font-semibold text-n-slate-11 text-center py-2 border-b border-n-weak"
            >
              {{ DAYS[day].label }}
            </p>

            <div class="p-1.5 space-y-1.5 min-h-24">
              <!-- Un bloque por agente: se edita aquí mismo, en el día que toca. -->
              <div
                v-for="agent in openAgents"
                :key="`${agent.id}-${day}`"
                class="rounded-lg px-1.5 py-1 text-[11px]"
                :style="{
                  background: `${agentColor(agent.id)}1a`,
                  borderLeft: `3px solid ${agentColor(agent.id)}`,
                }"
              >
                <label
                  class="flex items-center gap-1 cursor-pointer text-n-slate-12"
                >
                  <input
                    v-model="rowFor(agent.id, day).active"
                    type="checkbox"
                    class="rounded accent-n-brand size-3"
                  />
                  <span class="truncate">{{ agentName(agent) }}</span>
                </label>

                <div v-if="rowFor(agent.id, day).active" class="mt-1 space-y-1">
                  <input
                    v-model="rowFor(agent.id, day).start"
                    type="time"
                    class="w-full h-7 rounded border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-[11px] text-n-slate-12 px-1"
                  />
                  <input
                    v-model="rowFor(agent.id, day).end"
                    type="time"
                    class="w-full h-7 rounded border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-[11px] text-n-slate-12 px-1"
                  />
                  <select
                    v-model.number="rowFor(agent.id, day).slot"
                    class="w-full h-7 rounded border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-[11px] text-n-slate-12 px-1"
                  >
                    <option v-for="m in SLOT_OPTIONS" :key="m" :value="m">
                      {{
                        t('JABVOX_CALENDAR.AVAILABILITY.MINUTES', { count: m })
                      }}
                    </option>
                  </select>
                  <p
                    v-if="!validRow(rowFor(agent.id, day))"
                    class="text-[10px] text-n-ruby-11"
                  >
                    {{ t('JABVOX_CALENDAR.AVAILABILITY.INVALID_RANGE') }}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Guardar por agente: cada uno con su botón, para no pisar el horario de otro
             al tocar el propio. -->
        <div class="flex flex-wrap items-center gap-2 mt-3">
          <div
            v-for="agent in openAgents"
            :key="`save-${agent.id}`"
            class="flex items-center gap-1.5"
          >
            <span
              class="size-2.5 rounded-full"
              :style="{ background: agentColor(agent.id) }"
            />
            <button
              type="button"
              class="px-3 h-8 rounded-lg bg-n-brand text-white text-xs font-medium disabled:opacity-50"
              :disabled="savingIds.includes(agent.id)"
              @click="save(agent.id)"
            >
              {{
                savingIds.includes(agent.id)
                  ? '…'
                  : t('JABVOX_CALENDAR.AVAILABILITY.SAVE_FOR', {
                      name: agentName(agent),
                    })
              }}
            </button>
            <button
              type="button"
              class="text-[11px] text-n-brand hover:underline"
              @click="applyToAll(agent.id)"
            >
              {{ t('JABVOX_CALENDAR.AVAILABILITY.APPLY_TO_ALL') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Lista de agentes: se marcan los que se quieren ver en la semana -->
    <aside
      class="w-full lg:w-56 shrink-0 order-1 lg:order-2 lg:border-l border-n-weak lg:pl-4"
    >
      <p
        class="text-xs font-semibold text-n-slate-11 uppercase tracking-wide mb-2"
      >
        {{ t('JABVOX_CALENDAR.AVAILABILITY.AGENTS') }}
      </p>
      <div class="space-y-0.5 max-h-40 lg:max-h-none overflow-y-auto">
        <label
          v-for="agent in agents"
          :key="agent.id"
          class="flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm cursor-pointer hover:bg-n-alpha-1"
          :class="
            openAgentIds.includes(agent.id)
              ? 'bg-n-brand/10 text-n-slate-12'
              : 'text-n-slate-11'
          "
        >
          <input
            type="checkbox"
            class="rounded accent-n-brand"
            :checked="openAgentIds.includes(agent.id)"
            @change="toggleAgent(agent.id)"
          />
          <span
            class="size-2.5 rounded-full shrink-0"
            :style="{ background: agentColor(agent.id) }"
          />
          <span class="truncate flex-1">{{ agentName(agent) }}</span>
          <span
            v-if="daysCount(agent)"
            class="text-[10px] px-1.5 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11 shrink-0"
          >
            {{ daysCount(agent) }}
          </span>
        </label>
      </div>
    </aside>
  </div>
</template>
