<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ExternalPeopleTab from './ExternalPeopleTab.vue';
import AgentAvailabilityTab from './AgentAvailabilityTab.vue';
import BranchesTab from './BranchesTab.vue';
import EventModal from './EventModal.vue';
import calendarAPI from 'dashboard/api/jabvox/calendar';
import {
  HOURS,
  HOUR_HEIGHT,
  DAY_HEIGHT,
  positionedEvents,
  allDayEvents,
  nowOffset,
  formatHour,
} from 'dashboard/helper/jabvox/calendarGrid';

const { t } = useI18n();
const store = useStore();

const today = new Date();

function toDateKey(date) {
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

// ─── tabs ──────────────────────────────────────────────────────────────────
const activeTab = ref('calendar'); // calendar | settings
const showSidebar = ref(false); // mobile drawer

// ─── view / date state ───────────────────────────────────────────────────────
// Se abre en DÍA: es la vista con horas, que es a lo que se entra a diario. Mes y semana
// siguen disponibles y parten siempre de la fecha del selector.
const viewMode = ref('day'); // month | week | day
// Arranca en HOY (no en el día 1 del mes): así al cambiar a semana/día sin pulsar "Hoy" se
// muestra la semana/día actual. La vista mes igual sale bien porque hoy cae dentro del mes.
const currentDate = ref(
  new Date(today.getFullYear(), today.getMonth(), today.getDate())
);

// ─── modal state ─────────────────────────────────────────────────────────────
const showModal = ref(false);
const editingEvent = ref(null);
const modalDate = ref(new Date());

// ─── store ─────────────────────────────────────────────────────────────────
const events = useMapGetter('jabvoxCalendar/getEvents');
const uiFlags = useMapGetter('jabvoxCalendar/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

// ─── calendar filter (mine / team / by agent) ───────────────────────────────
const calendarFilter = ref('team'); // team | mine
const agentFilter = ref(null); // null = all agents, or a user id
// Varios agentes a la vez: es lo que permite superponer agendas y ver los huecos comunes.
// Lista vacía = todos, que es lo que espera quien no ha tocado el filtro.
const selectedAgentIds = ref([]);
const branchFilter = ref(null);
const branches = ref([]);

// Un color estable por agente para distinguir sus citas al superponerlas. Se deriva del
// id en vez de guardarse: así un agente nuevo ya tiene color sin configurar nada.
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
// Color de la sede elegida, para el punto del selector. Sin sede, gris neutro.
const activeBranchColor = computed(() => {
  const active = branches.value.find(b => b.id === branchFilter.value);
  return active?.color_jabvox || '#94A3B8';
});

const agentColor = id =>
  AGENT_COLORS[Math.abs(Number(id)) % AGENT_COLORS.length];

const toggleAgent = id => {
  const idx = selectedAgentIds.value.indexOf(id);
  if (idx === -1) selectedAgentIds.value.push(id);
  else selectedAgentIds.value.splice(idx, 1);
};

const filteredEvents = computed(() => {
  let list = events.value;
  if (calendarFilter.value === 'mine') {
    const uid = currentUser.value?.id;
    list = list.filter(
      e =>
        e.user_id === uid || (e.participants || []).some(p => p.user_id === uid)
    );
  }
  if (agentFilter.value) {
    list = list.filter(
      e =>
        e.user_id === agentFilter.value ||
        (e.participants || []).some(p => p.user_id === agentFilter.value)
    );
  }
  if (selectedAgentIds.value.length) {
    list = list.filter(
      e =>
        selectedAgentIds.value.includes(e.user_id) ||
        (e.participants || []).some(p =>
          selectedAgentIds.value.includes(p.user_id)
        )
    );
  }
  if (branchFilter.value) {
    list = list.filter(e => e.branch_id === branchFilter.value);
  }
  return list;
});

// ─── calendar labels ─────────────────────────────────────────────────────────
const MONTH_NAMES = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
].map(k => t(`JABVOX_CALENDAR.MONTHS.${k}`));
const DAY_NAMES = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'].map(k =>
  t(`JABVOX_CALENDAR.DAYS.${k}`)
);

// Los 7 días de la semana de currentDate (de domingo a sábado). Definido antes que
// currentMonthLabel porque el label de la vista semana lo usa.
const weekDays = computed(() => {
  const d = new Date(currentDate.value);
  const sunday = new Date(d);
  sunday.setDate(d.getDate() - d.getDay());
  return Array.from({ length: 7 }, (_, i) => {
    const date = new Date(sunday);
    date.setDate(sunday.getDate() + i);
    return date;
  });
});

// Etiqueta del período según la vista activa: mes ("Septiembre 2026"), semana ("14 – 20 sep
// 2026") o día ("martes, 16 sep 2026"). Antes SIEMPRE mostraba "Mes Año", así que en semana/
// día no reflejaba dónde estabas.
const currentMonthLabel = computed(() => {
  const d = currentDate.value;
  if (viewMode.value === 'day') {
    return d.toLocaleDateString('es', {
      weekday: 'long',
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    });
  }
  if (viewMode.value === 'week') {
    const days = weekDays.value;
    const start = days[0];
    const end = days[6];
    const fmt = (dt, withYear) =>
      dt.toLocaleDateString('es', {
        day: 'numeric',
        month: 'short',
        ...(withYear ? { year: 'numeric' } : {}),
      });
    return `${fmt(start, start.getFullYear() !== end.getFullYear())} – ${fmt(end, true)}`;
  }
  return `${MONTH_NAMES[d.getMonth()]} ${d.getFullYear()}`;
});

const calendarDays = computed(() => {
  const year = currentDate.value.getFullYear();
  const month = currentDate.value.getMonth();
  const firstDay = new Date(year, month, 1).getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const daysInPrev = new Date(year, month, 0).getDate();

  const cells = [];
  Array.from({ length: firstDay }, (_, idx) =>
    cells.push({
      date: new Date(year, month - 1, daysInPrev - (firstDay - 1 - idx)),
      current: false,
    })
  );
  Array.from({ length: daysInMonth }, (_, idx) =>
    cells.push({ date: new Date(year, month, idx + 1), current: true })
  );
  const remaining = 42 - cells.length;
  Array.from({ length: remaining }, (_, idx) =>
    cells.push({ date: new Date(year, month + 1, idx + 1), current: false })
  );
  return cells;
});

function eventsForDate(date) {
  const key = toDateKey(date);
  return filteredEvents.value.filter(
    e => toDateKey(new Date(e.start_at)) === key
  );
}

// Fecha del selector, en el formato que espera un input de tipo date. Se arma con los
// componentes locales y no con toISOString(), que convierte a UTC y puede devolver el día
// anterior según la hora.
const currentDateInput = computed(() => {
  const d = currentDate.value;
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate()
  ).padStart(2, '0')}`;
});

// Saltar a un día concreto. Se construye la fecha a mano porque `new Date('2026-09-28')`
// se interpreta como UTC y en husos negativos cae en el día anterior.
const pickDate = value => {
  if (!value) return;
  const [y, m, d] = value.split('-').map(Number);
  currentDate.value = new Date(y, m - 1, d);
};

// ─── rejilla horaria ─────────────────────────────────────────────────────────
// Las vistas de semana y día sitúan cada evento por su hora; los de todo el día van en un
// carril aparte. El cálculo vive en el helper para poder probarlo sin montar el componente.
const positionedFor = day => positionedEvents(eventsForDate(day), day);
const allDayFor = day => allDayEvents(eventsForDate(day));

const weekHasAllDay = computed(() =>
  weekDays.value.some(day => allDayFor(day).length > 0)
);

// Franjas de horario comercial de la sede activa para un día. Fuera de ellas la agenda se
// sombrea: se ve de un vistazo cuándo no hay nadie. Sin sede elegida no se sombrea nada,
// porque cada sede puede abrir a horas distintas.
const businessHoursFor = day => {
  if (!branchFilter.value) return [];
  const branch = branches.value.find(b => b.id === branchFilter.value);
  if (!branch) return [];

  return (branch.hours || [])
    .filter(h => h.day_of_week === day.getDay())
    .map(h => ({
      top: `${(h.open_minute / 1440) * DAY_HEIGHT}px`,
      height: `${((h.close_minute - h.open_minute) / 1440) * DAY_HEIGHT}px`,
    }));
};

// Al abrir la agenda interesa ver la hora actual, no las 00:00: de madrugada nunca hay
// nada y obligaba a bajar a mano cada vez. Se deja un margen arriba para que se vea algo
// de lo anterior y quede claro que hay más.
const weekScroll = ref(null);
const dayScroll = ref(null);

const scrollToNow = () => {
  const offset = Math.max((nowOffset(new Date()) ?? 0) - HOUR_HEIGHT * 1.5, 0);
  [weekScroll.value, dayScroll.value].forEach(el => {
    if (el) el.scrollTop = offset;
  });
};

// Tras pintar la vista y cada vez que se cambia de modo o de día.
watch(
  [viewMode, currentDate],
  () => {
    nextTick(scrollToNow);
  },
  { immediate: true }
);

// Hora de inicio–fin tal como la ve el usuario, en su horario local.
const timeLabel = event => {
  const opts = { hour: '2-digit', minute: '2-digit' };
  const from = new Date(event.start_at).toLocaleTimeString('es', opts);
  const to = new Date(event.end_at).toLocaleTimeString('es', opts);
  return `${from} – ${to}`;
};

function isToday(date) {
  return toDateKey(date) === toDateKey(today);
}

// ─── navigation ──────────────────────────────────────────────────────────────
function shift(dir) {
  const d = new Date(currentDate.value);
  if (viewMode.value === 'month') {
    // Navegar por meses desde el día 1 evita el desborde de setMonth cuando el día actual
    // (p. ej. 31) no existe en el mes destino.
    currentDate.value = new Date(d.getFullYear(), d.getMonth() + dir, 1);
    return;
  }
  if (viewMode.value === 'week') d.setDate(d.getDate() + 7 * dir);
  else d.setDate(d.getDate() + dir);
  currentDate.value = d;
}
function goToday() {
  // Ir al DÍA de hoy real (no al día 1 del mes): en vista día/semana debe posicionarse en
  // hoy y su semana. La vista mes igual muestra el mes correcto porque cae dentro de él.
  currentDate.value = new Date(
    today.getFullYear(),
    today.getMonth(),
    today.getDate()
  );
}

// ─── fetch ─────────────────────────────────────────────────────────────────
function fetchRange() {
  const year = currentDate.value.getFullYear();
  const month = currentDate.value.getMonth();
  const from = new Date(year, month - 1, 1).toISOString();
  const to = new Date(year, month + 2, 0).toISOString();
  store.dispatch('jabvoxCalendar/fetchEvents', { from, to });
}

watch(currentDate, fetchRange);
onMounted(async () => {
  fetchRange();
  store.dispatch('agents/get');
  store.dispatch('jabvoxCalendar/fetchExternalPeople');
  try {
    const { data } = await calendarAPI.getBranches();
    branches.value = data;
  } catch {
    // Sin sedes el calendario funciona igual: no se sombrea horario y no hay filtro.
  }
});

// ─── modal open/close ──────────────────────────────────────────────────────
function openCreate(date) {
  editingEvent.value = null;
  modalDate.value = date || new Date();
  showModal.value = true;
}
function openEdit(event) {
  editingEvent.value = event;
  showModal.value = true;
}
function closeModal() {
  showModal.value = false;
  editingEvent.value = null;
}

// Doble clic sobre un evento lo marca como hecho (o lo reabre) sin abrir el modal: en la
// vista de día se van cerrando citas de una en una y abrir el formulario para eso sobra.
function toggleStatus(event) {
  store.dispatch('jabvoxCalendar/updateEvent', {
    id: event.id,
    status: event.status === 'done' ? 'pending' : 'done',
  });
}

const TYPE_ICONS = {
  reminder: 'i-lucide-bell',
  appointment: 'i-lucide-calendar-check',
  task: 'i-lucide-check-square',
};
</script>

<template>
  <div class="flex flex-col flex-1 h-full w-full min-h-0 bg-n-surface-1">
    <!-- ── Top tabs ── -->
    <div
      class="flex items-center gap-1 px-5 pt-3 border-b border-n-weak shrink-0"
    >
      <button
        v-for="tab in ['calendar', 'branches', 'settings', 'availability']"
        :key="tab"
        class="px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors"
        :class="
          activeTab === tab
            ? 'border-n-brand text-n-brand'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="activeTab = tab"
      >
        {{ t(`JABVOX_CALENDAR.TABS.${tab.toUpperCase()}`) }}
      </button>
    </div>

    <!-- ── Sedes: dónde se atiende, con su zona y su horario comercial ── -->
    <BranchesTab v-if="activeTab === 'branches'" class="flex-1 min-h-0" />

    <!-- ── Settings tab (personas externas) ── -->
    <ExternalPeopleTab
      v-else-if="activeTab === 'settings'"
      class="flex-1 min-h-0"
    />

    <!-- ── Availability tab (horario laboral por agente para Jabvox IA) ── -->
    <div
      v-else-if="activeTab === 'availability'"
      class="flex-1 min-h-0 overflow-y-auto p-5"
    >
      <AgentAvailabilityTab />
    </div>

    <!-- ── Calendar tab ── -->
    <div v-else class="flex flex-1 min-h-0 overflow-hidden relative">
      <!-- Mobile drawer backdrop -->
      <div
        v-if="showSidebar"
        class="fixed inset-0 z-30 bg-n-alpha-black2 lg:hidden"
        @click="showSidebar = false"
      />
      <!-- Left panel (drawer on mobile) -->
      <aside
        class="w-64 shrink-0 border-r border-n-weak bg-n-surface-2 flex-col overflow-y-auto z-40 lg:flex lg:static"
        :class="
          showSidebar
            ? 'flex fixed inset-y-0 left-0 shadow-xl'
            : 'hidden lg:flex'
        "
      >
        <div class="p-4">
          <button
            class="w-full flex items-center justify-center gap-2 h-10 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 transition-colors"
            @click="openCreate(new Date())"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('JABVOX_CALENDAR.NEW_EVENT') }}
          </button>
        </div>

        <!-- Calendar filters (mine / team) -->
        <div class="px-4 pb-3">
          <p
            class="text-xs font-semibold text-n-slate-11 mb-2 uppercase tracking-wide"
          >
            {{ t('JABVOX_CALENDAR.FILTERS.CALENDARS') }}
          </p>
          <div
            class="flex rounded-lg border border-n-weak overflow-hidden mb-3"
          >
            <button
              v-for="f in ['team', 'mine']"
              :key="f"
              class="flex-1 px-2 h-8 text-xs transition-colors"
              :class="
                calendarFilter === f
                  ? 'bg-n-brand text-white font-medium'
                  : 'text-n-slate-11 hover:bg-n-alpha-black2'
              "
              @click="calendarFilter = f"
            >
              {{ t(`JABVOX_CALENDAR.FILTERS.${f.toUpperCase()}`) }}
            </button>
          </div>
          <!-- Agentes: varios a la vez, para superponer agendas y ver los huecos comunes.
               Sin ninguno marcado se ven todos. -->
          <div class="space-y-1 max-h-40 overflow-y-auto">
            <label
              v-for="a in agents"
              :key="a.id"
              class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer px-1 py-0.5 rounded hover:bg-n-alpha-black2"
            >
              <input
                type="checkbox"
                class="rounded accent-n-brand"
                :checked="selectedAgentIds.includes(a.id)"
                @change="toggleAgent(a.id)"
              />
              <span
                class="size-2.5 rounded-full shrink-0"
                :style="{ background: agentColor(a.id) }"
              />
              <span class="truncate">{{ a.name }}</span>
            </label>
          </div>
        </div>

        <!-- Upcoming -->
        <div class="border-t border-n-weak p-3 flex-1">
          <p
            class="text-xs font-semibold text-n-slate-11 mb-2 uppercase tracking-wide"
          >
            {{ t('JABVOX_CALENDAR.UPCOMING') }}
          </p>
          <div v-if="uiFlags.isFetching" class="text-xs text-n-slate-10">
            {{ t('JABVOX_CALENDAR.LOADING') }}
          </div>
          <div
            v-for="ev in filteredEvents
              .slice()
              .sort((a, b) => new Date(a.start_at) - new Date(b.start_at))
              .slice(0, 8)"
            :key="ev.id"
            class="mb-1.5 flex items-start gap-2 cursor-pointer"
            @click="openEdit(ev)"
          >
            <span
              class="mt-0.5 size-2 rounded-full shrink-0"
              :style="{ background: ev.color }"
            />
            <div class="min-w-0">
              <p
                class="text-xs text-n-slate-12 truncate leading-snug"
                :class="
                  ev.status === 'done' ? 'line-through text-n-slate-10' : ''
                "
              >
                {{ ev.title }}
              </p>
              <p class="text-[10px] text-n-slate-10">
                {{
                  new Date(ev.start_at).toLocaleDateString('es', {
                    month: 'short',
                    day: 'numeric',
                  })
                }}
                <span v-if="(ev.participants || []).length">
                  · {{ ev.participants.length }}
                  <span class="i-lucide-users size-2.5 inline-block" />
                </span>
              </p>
            </div>
          </div>
          <p
            v-if="!uiFlags.isFetching && filteredEvents.length === 0"
            class="text-xs text-n-slate-10"
          >
            {{ t('JABVOX_CALENDAR.EMPTY') }}
          </p>
        </div>
      </aside>

      <!-- Main area -->
      <main class="flex-1 flex flex-col overflow-hidden min-w-0">
        <header
          class="flex flex-wrap items-center justify-between gap-2 px-3 sm:px-5 py-3 border-b border-n-weak shrink-0"
        >
          <div class="flex items-center gap-1.5 sm:gap-2 min-w-0">
            <!-- Mobile: open sidebar drawer -->
            <button
              class="lg:hidden p-1.5 rounded-lg text-n-slate-11 hover:bg-n-alpha-black2 transition-colors shrink-0"
              :title="t('JABVOX_CALENDAR.FILTERS.CALENDARS')"
              @click="showSidebar = true"
            >
              <span class="i-lucide-panel-left size-5" />
            </button>
            <button
              class="px-3 h-8 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-black2 transition-colors shrink-0"
              @click="goToday"
            >
              {{ t('JABVOX_CALENDAR.TODAY') }}
            </button>
            <button
              class="p-1.5 rounded hover:bg-n-alpha-black2 shrink-0"
              @click="shift(-1)"
            >
              <span class="i-lucide-chevron-left size-4 text-n-slate-11" />
            </button>
            <button
              class="p-1.5 rounded hover:bg-n-alpha-black2 shrink-0"
              @click="shift(1)"
            >
              <span class="i-lucide-chevron-right size-4 text-n-slate-11" />
            </button>
            <!-- Selector de fecha: despliega el calendario del sistema y lleva a
                 cualquier día. Las tres vistas arrancan de la fecha que marque, así que
                 cambiar a semana o mes muestra la que contiene ese día. -->
            <input
              :value="currentDateInput"
              type="date"
              class="h-8 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2 shrink-0"
              @input="pickDate($event.target.value)"
            />
            <h2
              class="hidden lg:block text-sm sm:text-base font-semibold text-n-slate-12 ml-1 truncate"
            >
              {{ currentMonthLabel }}
            </h2>
          </div>
          <!-- Sede, en la barra superior y no en el panel lateral: en móvil ese panel
               es un cajón oculto, así que el filtro quedaba invisible. El punto de color
               dice de un vistazo cuál está activa. -->
          <div
            v-if="branches.length"
            class="flex items-center gap-1.5 shrink-0 rounded-lg border border-n-weak px-2 h-8"
            :class="branchFilter ? 'bg-n-brand/5 border-n-brand/40' : ''"
          >
            <span
              class="size-2.5 rounded-full shrink-0"
              :style="{ background: activeBranchColor }"
            />
            <select
              v-model="branchFilter"
              class="bg-transparent text-sm text-n-slate-12 focus:outline-none max-w-[9rem] truncate"
              :title="t('JABVOX_CALENDAR.FILTERS.ALL_BRANCHES')"
            >
              <option :value="null">
                {{ t('JABVOX_CALENDAR.FILTERS.ALL_BRANCHES') }}
              </option>
              <option v-for="b in branches" :key="b.id" :value="b.id">
                {{ b.name_jabvox }}
              </option>
            </select>
          </div>

          <div
            class="flex rounded-lg border border-n-weak overflow-hidden shrink-0"
          >
            <button
              v-for="mode in ['month', 'week', 'day']"
              :key="mode"
              class="px-3 h-8 text-sm transition-colors"
              :class="
                viewMode === mode
                  ? 'bg-n-brand text-white font-medium'
                  : 'text-n-slate-11 hover:bg-n-alpha-black2'
              "
              @click="viewMode = mode"
            >
              {{ t(`JABVOX_CALENDAR.VIEWS.${mode.toUpperCase()}`) }}
            </button>
          </div>
        </header>

        <!-- Month view -->
        <div
          v-if="viewMode === 'month'"
          class="flex-1 flex flex-col overflow-hidden"
        >
          <div class="grid grid-cols-7 border-b border-n-weak shrink-0">
            <div
              v-for="day in DAY_NAMES"
              :key="day"
              class="py-2 text-center text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
            >
              {{ day }}
            </div>
          </div>
          <div
            class="grid grid-cols-7 flex-1 min-h-0 [grid-template-rows:repeat(6,minmax(0,1fr))]"
          >
            <div
              v-for="cell in calendarDays"
              :key="cell.date.toISOString()"
              class="border-r border-b border-n-weak p-1 cursor-pointer hover:bg-n-alpha-black2/50 transition-colors"
              :class="!cell.current ? 'bg-n-alpha-black2/30' : ''"
              @click="openCreate(cell.date)"
            >
              <div class="flex items-center justify-between mb-1">
                <span
                  class="text-xs font-medium w-6 h-6 flex items-center justify-center rounded-full"
                  :class="[
                    !cell.current ? 'text-n-slate-9' : 'text-n-slate-12',
                    isToday(cell.date) ? 'bg-n-brand text-white' : '',
                  ]"
                >
                  {{ cell.date.getDate() }}
                </span>
              </div>
              <div class="space-y-0.5">
                <div
                  v-for="ev in eventsForDate(cell.date).slice(0, 3)"
                  :key="ev.id"
                  class="flex items-center gap-1 px-1.5 py-0.5 rounded text-[11px] text-white truncate cursor-pointer hover:opacity-90"
                  :style="{ background: ev.color }"
                  @click.stop="openEdit(ev)"
                >
                  <span
                    class="size-3 shrink-0"
                    :class="TYPE_ICONS[ev.event_type]"
                  />
                  <span
                    class="truncate"
                    :class="
                      ev.status === 'done' ? 'line-through opacity-70' : ''
                    "
                  >
                    {{ ev.title }}
                  </span>
                </div>
                <div
                  v-if="eventsForDate(cell.date).length > 3"
                  class="text-[10px] text-n-slate-10 pl-1"
                >
                  {{
                    t('JABVOX_CALENDAR.MORE', {
                      count: eventsForDate(cell.date).length - 3,
                    })
                  }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Week view -->
        <div
          v-else-if="viewMode === 'week'"
          class="flex-1 flex flex-col min-h-0 overflow-hidden"
        >
          <!-- La cabecera usa EXACTAMENTE la misma rejilla que el cuerpo, con su hueco
               para el eje de horas: con `grid-cols-7` a secas los días quedaban corridos
               respecto a las columnas de abajo. -->
          <div
            class="grid grid-cols-[2.5rem_repeat(7,1fr)] sm:grid-cols-[4rem_repeat(7,1fr)] border-b border-n-weak shrink-0"
          >
            <div class="border-r border-n-weak" />
            <div
              v-for="day in weekDays"
              :key="day.toISOString()"
              class="py-3 text-center border-r border-n-weak cursor-pointer hover:bg-n-alpha-black2"
              @click="openCreate(day)"
            >
              <p class="text-xs text-n-slate-10 uppercase">
                {{ DAY_NAMES[day.getDay()] }}
              </p>
              <p
                class="text-lg font-semibold mx-auto mt-1 w-9 h-9 flex items-center justify-center rounded-full"
                :class="
                  isToday(day) ? 'bg-n-brand text-white' : 'text-n-slate-12'
                "
              >
                {{ day.getDate() }}
              </p>
            </div>
          </div>
          <!-- Carril de "todo el día": va sobre la rejilla, no dentro, porque no
               ocupa una hora concreta. -->
          <div
            v-if="weekHasAllDay"
            class="grid grid-cols-[2.5rem_repeat(7,1fr)] sm:grid-cols-[4rem_repeat(7,1fr)] border-b border-n-weak"
          >
            <div
              class="text-[10px] text-n-slate-10 px-1 py-1 border-r border-n-weak"
            >
              {{ t('JABVOX_CALENDAR.GRID.ALL_DAY') }}
            </div>
            <div
              v-for="day in weekDays"
              :key="`allday-${day.toISOString()}`"
              class="border-r border-n-weak p-1 space-y-1 min-h-8"
            >
              <button
                v-for="ev in allDayFor(day)"
                :key="ev.id"
                type="button"
                class="w-full truncate px-1.5 py-0.5 rounded text-[11px] text-white text-left"
                :style="{ background: ev.color }"
                @click="openEdit(ev)"
              >
                {{ ev.title }}
              </button>
            </div>
          </div>

          <!-- Rejilla horaria. Cada evento se sitúa por su hora de inicio y mide lo que
               dura; los que coinciden se reparten el ancho en vez de taparse. -->
          <!-- La rejilla se queda con todo el alto que sobra y lleva ella el scroll: con
               un `max-h` fijo se cortaba a media pantalla y dejaba un hueco muerto. -->
          <div ref="weekScroll" class="flex-1 min-h-0 overflow-y-auto">
            <div
              class="grid grid-cols-[2.5rem_repeat(7,1fr)] sm:grid-cols-[4rem_repeat(7,1fr)] relative"
            >
              <!-- Eje de horas -->
              <div class="border-r border-n-weak">
                <div
                  v-for="hour in HOURS"
                  :key="hour"
                  class="relative text-[10px] sm:text-xs text-n-slate-10 text-right pr-1 sm:pr-2 tabular-nums"
                  :style="{ height: `${HOUR_HEIGHT}px` }"
                >
                  <!-- La etiqueta se ancla a la línea que separa esta hora de la
                       anterior, centrada sobre ella. Antes se subía con un translate fijo
                       y quedaba dentro de su franja, desalineada con la rejilla; la de
                       las 00:00 además se salía por arriba, por eso no se veía. -->
                  <span
                    class="absolute right-1 sm:right-2 leading-none"
                    :class="hour === 0 ? 'top-0.5' : '-top-1.5'"
                  >
                    {{ formatHour(hour) }}
                  </span>
                </div>
              </div>

              <div
                v-for="day in weekDays"
                :key="day.toISOString()"
                class="relative border-r border-n-weak"
                :style="{ height: `${DAY_HEIGHT}px` }"
              >
                <div
                  v-for="hour in HOURS"
                  :key="hour"
                  class="border-b border-n-weak/50"
                  :style="{ height: `${HOUR_HEIGHT}px` }"
                />

                <!-- Horario comercial de la sede: lo que queda fuera se ve apagado,
                     así se distingue de un vistazo cuándo no hay nadie. -->
                <div
                  v-for="(franja, i) in businessHoursFor(day)"
                  :key="`bh-${i}`"
                  class="absolute inset-x-0 bg-n-brand/5 pointer-events-none"
                  :style="franja"
                />

                <div
                  v-if="nowOffset(day) !== null"
                  class="absolute left-0 right-0 border-t-2 border-n-ruby-9 z-20 pointer-events-none"
                  :style="{ top: `${nowOffset(day)}px` }"
                />

                <button
                  v-for="item in positionedFor(day)"
                  :key="item.event.id"
                  type="button"
                  class="absolute px-1.5 py-1 rounded-md text-[11px] leading-tight text-white text-left overflow-hidden border border-white/25 shadow-sm hover:brightness-110 transition z-10"
                  :style="{ ...item.style, background: item.event.color }"
                  :title="item.event.title"
                  @click="openEdit(item.event)"
                >
                  <span
                    class="block truncate font-medium"
                    :class="
                      item.event.status === 'done'
                        ? 'line-through opacity-70'
                        : ''
                    "
                  >
                    {{ item.event.title }}
                  </span>
                  <span
                    v-if="item.height > 34"
                    class="block truncate opacity-80"
                  >
                    {{ timeLabel(item.event) }}
                  </span>
                  <span
                    v-if="item.height > 68 && item.event.branch_name"
                    class="flex items-center gap-0.5 truncate opacity-80"
                  >
                    <span class="i-lucide-map-pin size-3 shrink-0" />
                    {{ item.event.branch_name }}
                  </span>
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Day view -->
        <div v-else class="flex-1 flex flex-col min-h-0 overflow-hidden p-4">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-n-slate-12">
              {{
                currentDate.toLocaleDateString('es', {
                  weekday: 'long',
                  year: 'numeric',
                  month: 'long',
                  day: 'numeric',
                })
              }}
            </h3>
            <button
              class="flex items-center gap-2 px-3 h-8 rounded-lg bg-n-brand/10 text-n-brand text-sm hover:bg-n-brand/20 transition-colors"
              @click="openCreate(currentDate)"
            >
              <span class="i-lucide-plus size-4" />
              {{ t('JABVOX_CALENDAR.ADD') }}
            </button>
          </div>
          <div
            v-if="eventsForDate(currentDate).length === 0"
            class="text-sm text-n-slate-10 text-center py-12"
          >
            {{ t('JABVOX_CALENDAR.EMPTY') }}
          </div>
          <!-- Carril de "todo el día" -->
          <div
            v-if="allDayFor(currentDate).length"
            class="flex gap-2 mb-2 pb-2 border-b border-n-weak"
          >
            <span class="text-[11px] text-n-slate-10 w-14 shrink-0 pt-1">
              {{ t('JABVOX_CALENDAR.GRID.ALL_DAY') }}
            </span>
            <div class="flex-1 space-y-1">
              <button
                v-for="ev in allDayFor(currentDate)"
                :key="ev.id"
                type="button"
                class="w-full truncate px-2 py-1 rounded text-xs text-white text-left"
                :style="{ background: ev.color }"
                @click="openEdit(ev)"
              >
                {{ ev.title }}
              </button>
            </div>
          </div>

          <!-- Rejilla horaria del día -->
          <div ref="dayScroll" class="flex-1 min-h-0 overflow-y-auto">
            <div class="flex">
              <div class="w-10 sm:w-16 shrink-0 border-r border-n-weak">
                <div
                  v-for="hour in HOURS"
                  :key="hour"
                  class="relative text-[10px] sm:text-xs text-n-slate-10 text-right pr-1 sm:pr-2 tabular-nums"
                  :style="{ height: `${HOUR_HEIGHT}px` }"
                >
                  <!-- La etiqueta se ancla a la línea que separa esta hora de la
                       anterior, centrada sobre ella. Antes se subía con un translate fijo
                       y quedaba dentro de su franja, desalineada con la rejilla; la de
                       las 00:00 además se salía por arriba, por eso no se veía. -->
                  <span
                    class="absolute right-1 sm:right-2 leading-none"
                    :class="hour === 0 ? 'top-0.5' : '-top-1.5'"
                  >
                    {{ formatHour(hour) }}
                  </span>
                </div>
              </div>

              <div
                class="relative flex-1"
                :style="{ height: `${DAY_HEIGHT}px` }"
              >
                <div
                  v-for="hour in HOURS"
                  :key="hour"
                  class="border-b border-n-weak/50"
                  :style="{ height: `${HOUR_HEIGHT}px` }"
                />

                <!-- Horario comercial de la sede: lo que queda fuera se ve apagado,
                     así se distingue de un vistazo cuándo no hay nadie. -->
                <div
                  v-for="(franja, i) in businessHoursFor(currentDate)"
                  :key="`bh-${i}`"
                  class="absolute inset-x-0 bg-n-brand/5 pointer-events-none"
                  :style="franja"
                />

                <div
                  v-if="nowOffset(currentDate) !== null"
                  class="absolute left-0 right-0 border-t-2 border-n-ruby-9 z-20 pointer-events-none"
                  :style="{ top: `${nowOffset(currentDate)}px` }"
                >
                  <span
                    class="absolute -left-1 -top-1 size-2 rounded-full bg-n-ruby-9"
                  />
                </div>

                <button
                  v-for="item in positionedFor(currentDate)"
                  :key="item.event.id"
                  type="button"
                  class="absolute px-2.5 py-1.5 rounded-lg text-xs leading-snug text-white text-left overflow-hidden border border-white/25 shadow-sm hover:brightness-110 transition z-10"
                  :style="{ ...item.style, background: item.event.color }"
                  @click="openEdit(item.event)"
                  @dblclick.stop="toggleStatus(item.event)"
                >
                  <span
                    class="flex items-center gap-1 font-medium truncate"
                    :class="
                      item.event.status === 'done'
                        ? 'line-through opacity-70'
                        : ''
                    "
                  >
                    <span
                      class="size-3 shrink-0"
                      :class="TYPE_ICONS[item.event.event_type]"
                    />
                    {{ item.event.title }}
                  </span>
                  <span
                    v-if="item.height > 34"
                    class="block truncate opacity-80"
                  >
                    {{ timeLabel(item.event) }}
                  </span>
                  <span
                    v-if="item.height > 68 && item.event.contact_name"
                    class="block truncate opacity-80"
                  >
                    {{ item.event.contact_name }}
                  </span>
                  <span
                    v-if="item.event.branch_name"
                    class="flex items-center gap-0.5 truncate opacity-80"
                  >
                    <span class="i-lucide-map-pin size-3 shrink-0" />
                    {{ item.event.branch_name }}
                  </span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>

    <!-- ── Event modal ── -->
    <EventModal
      v-if="showModal"
      :event="editingEvent"
      :initial-date="modalDate"
      :agents="agents"
      @close="closeModal"
    />
  </div>
</template>
