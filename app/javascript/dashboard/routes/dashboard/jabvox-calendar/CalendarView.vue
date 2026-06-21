<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ExternalPeopleTab from './ExternalPeopleTab.vue';
import EventModal from './EventModal.vue';

const { t } = useI18n();
const store = useStore();

const today = new Date();

function toDateKey(date) {
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

// ─── tabs ──────────────────────────────────────────────────────────────────
const activeTab = ref('calendar'); // calendar | settings

// ─── view / date state ───────────────────────────────────────────────────────
const viewMode = ref('month'); // month | week | day
const currentDate = ref(new Date(today.getFullYear(), today.getMonth(), 1));

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

const currentMonthLabel = computed(
  () =>
    `${MONTH_NAMES[currentDate.value.getMonth()]} ${currentDate.value.getFullYear()}`
);

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

function eventsForDate(date) {
  const key = toDateKey(date);
  return filteredEvents.value.filter(
    e => toDateKey(new Date(e.start_at)) === key
  );
}

function isToday(date) {
  return toDateKey(date) === toDateKey(today);
}

// ─── navigation ──────────────────────────────────────────────────────────────
function shift(dir) {
  const d = new Date(currentDate.value);
  if (viewMode.value === 'month') d.setMonth(d.getMonth() + dir);
  else if (viewMode.value === 'week') d.setDate(d.getDate() + 7 * dir);
  else d.setDate(d.getDate() + dir);
  currentDate.value = d;
}
function goToday() {
  currentDate.value = new Date(today.getFullYear(), today.getMonth(), 1);
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
onMounted(() => {
  fetchRange();
  store.dispatch('agents/get');
  store.dispatch('jabvoxCalendar/fetchExternalPeople');
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
        v-for="tab in ['calendar', 'settings']"
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

    <!-- ── Settings tab ── -->
    <ExternalPeopleTab v-if="activeTab === 'settings'" class="flex-1 min-h-0" />

    <!-- ── Calendar tab ── -->
    <div v-else class="flex flex-1 min-h-0 overflow-hidden">
      <!-- Left panel -->
      <aside
        class="w-64 shrink-0 border-r border-n-weak bg-n-surface-2 flex flex-col overflow-y-auto"
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
          <!-- Agent filter -->
          <select
            v-model="agentFilter"
            class="w-full h-8 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-xs text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          >
            <option :value="null">
              {{ t('JABVOX_CALENDAR.FILTERS.ALL_AGENTS') }}
            </option>
            <option v-for="a in agents" :key="a.id" :value="a.id">
              {{ a.name }}
            </option>
          </select>
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
      <main class="flex-1 flex flex-col overflow-hidden">
        <header
          class="flex items-center justify-between px-5 py-3 border-b border-n-weak shrink-0"
        >
          <div class="flex items-center gap-2">
            <button
              class="px-3 h-8 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-black2 transition-colors"
              @click="goToday"
            >
              {{ t('JABVOX_CALENDAR.TODAY') }}
            </button>
            <button
              class="p-1.5 rounded hover:bg-n-alpha-black2"
              @click="shift(-1)"
            >
              <span class="i-lucide-chevron-left size-4 text-n-slate-11" />
            </button>
            <button
              class="p-1.5 rounded hover:bg-n-alpha-black2"
              @click="shift(1)"
            >
              <span class="i-lucide-chevron-right size-4 text-n-slate-11" />
            </button>
            <h2 class="text-base font-semibold text-n-slate-12 ml-1">
              {{ currentMonthLabel }}
            </h2>
          </div>
          <div class="flex rounded-lg border border-n-weak overflow-hidden">
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
          class="flex-1 overflow-y-auto min-h-0"
        >
          <div class="grid grid-cols-7 border-b border-n-weak">
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
          <div class="grid grid-cols-7">
            <div
              v-for="day in weekDays"
              :key="day.toISOString()"
              class="border-r border-n-weak min-h-48 p-1 space-y-1"
            >
              <div
                v-for="ev in eventsForDate(day)"
                :key="ev.id"
                class="flex items-start gap-1 px-2 py-1 rounded text-xs text-white cursor-pointer hover:opacity-90"
                :style="{ background: ev.color }"
                @click="openEdit(ev)"
              >
                <span
                  class="size-3 shrink-0 mt-0.5"
                  :class="TYPE_ICONS[ev.event_type]"
                />
                <div class="min-w-0">
                  <p
                    class="truncate"
                    :class="
                      ev.status === 'done' ? 'line-through opacity-70' : ''
                    "
                  >
                    {{ ev.title }}
                  </p>
                  <p v-if="!ev.all_day" class="opacity-80 text-[10px]">
                    {{
                      new Date(ev.start_at).toLocaleTimeString('es', {
                        hour: '2-digit',
                        minute: '2-digit',
                      })
                    }}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Day view -->
        <div v-else class="flex-1 overflow-y-auto min-h-0 p-4">
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
          <div class="space-y-2">
            <div
              v-for="ev in eventsForDate(currentDate)"
              :key="ev.id"
              class="flex items-start gap-3 p-3 rounded-xl border border-n-weak bg-n-surface-2 cursor-pointer hover:border-n-brand/40 transition-colors group"
              @click="openEdit(ev)"
            >
              <span
                class="size-3 rounded-full mt-1 shrink-0"
                :style="{ background: ev.color }"
              />
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span
                    class="size-4 text-n-slate-10"
                    :class="TYPE_ICONS[ev.event_type]"
                  />
                  <p
                    class="font-medium text-n-slate-12 truncate"
                    :class="
                      ev.status === 'done' ? 'line-through text-n-slate-10' : ''
                    "
                  >
                    {{ ev.title }}
                  </p>
                  <span
                    class="text-[11px] px-1.5 py-0.5 rounded-full bg-n-alpha-black2 text-n-slate-10"
                  >
                    {{ t(`JABVOX_CALENDAR.TYPES.${ev.event_type}`) }}
                  </span>
                </div>
                <p
                  v-if="ev.description"
                  class="text-sm text-n-slate-10 mt-0.5 truncate"
                >
                  {{ ev.description }}
                </p>
                <p v-if="!ev.all_day" class="text-xs text-n-slate-10 mt-1">
                  {{
                    new Date(ev.start_at).toLocaleTimeString('es', {
                      hour: '2-digit',
                      minute: '2-digit',
                    })
                  }}
                  –
                  {{
                    new Date(ev.end_at).toLocaleTimeString('es', {
                      hour: '2-digit',
                      minute: '2-digit',
                    })
                  }}
                </p>
                <!-- participants chips -->
                <div
                  v-if="(ev.participants || []).length"
                  class="flex flex-wrap gap-1 mt-2"
                >
                  <span
                    v-for="p in ev.participants"
                    :key="p.id"
                    class="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full"
                    :class="
                      p.kind === 'team'
                        ? 'bg-n-brand/10 text-n-brand'
                        : 'bg-n-teal-3 text-n-teal-11'
                    "
                  >
                    <span
                      class="size-2.5"
                      :class="
                        p.kind === 'team'
                          ? 'i-lucide-user'
                          : 'i-lucide-user-plus'
                      "
                    />
                    {{ p.name }}
                  </span>
                </div>
              </div>
              <div
                class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <button
                  class="p-1.5 rounded hover:bg-n-alpha-black2"
                  @click.stop="toggleStatus(ev)"
                >
                  <span
                    class="size-4"
                    :class="
                      ev.status === 'done'
                        ? 'i-lucide-rotate-ccw text-n-slate-10'
                        : 'i-lucide-check text-n-brand'
                    "
                  />
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
