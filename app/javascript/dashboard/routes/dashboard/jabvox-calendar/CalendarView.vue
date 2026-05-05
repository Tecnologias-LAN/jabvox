<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

const { t } = useI18n();
const store = useStore();

// ─── helpers (defined first to avoid hoisting issues) ─────────────────────────
const today = new Date();

function toDateKey(date) {
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

function defaultForm(date = null) {
  const d = date || new Date();
  const pad = n => String(n).padStart(2, '0');
  const dateStr = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const timeStr = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return {
    title: '',
    description: '',
    date: dateStr,
    start_time: timeStr,
    end_time: `${pad(d.getHours() + 1)}:${pad(d.getMinutes())}`,
    all_day: false,
    event_type: 'reminder',
    status: 'pending',
    color: '#3B82F6',
  };
}

// ─── view / date state ────────────────────────────────────────────────────────
const viewMode = ref('month'); // month | week | day
const currentDate = ref(new Date(today.getFullYear(), today.getMonth(), 1));

// ─── modal state ─────────────────────────────────────────────────────────────
const showModal = ref(false);
const editingEvent = ref(null);
const form = ref(defaultForm());
const formError = ref('');
const isSaving = ref(false);

// ─── store ────────────────────────────────────────────────────────────────────
const events = computed(() => store.getters['jabvoxCalendar/getEvents']);
const uiFlags = computed(() => store.getters['jabvoxCalendar/getUIFlags']);

// ─── calendar grid (month view) ──────────────────────────────────────────────
const MONTH_NAMES = [
  t('JABVOX_CALENDAR.MONTHS.JAN'),
  t('JABVOX_CALENDAR.MONTHS.FEB'),
  t('JABVOX_CALENDAR.MONTHS.MAR'),
  t('JABVOX_CALENDAR.MONTHS.APR'),
  t('JABVOX_CALENDAR.MONTHS.MAY'),
  t('JABVOX_CALENDAR.MONTHS.JUN'),
  t('JABVOX_CALENDAR.MONTHS.JUL'),
  t('JABVOX_CALENDAR.MONTHS.AUG'),
  t('JABVOX_CALENDAR.MONTHS.SEP'),
  t('JABVOX_CALENDAR.MONTHS.OCT'),
  t('JABVOX_CALENDAR.MONTHS.NOV'),
  t('JABVOX_CALENDAR.MONTHS.DEC'),
];
const DAY_NAMES = [
  t('JABVOX_CALENDAR.DAYS.SUN'),
  t('JABVOX_CALENDAR.DAYS.MON'),
  t('JABVOX_CALENDAR.DAYS.TUE'),
  t('JABVOX_CALENDAR.DAYS.WED'),
  t('JABVOX_CALENDAR.DAYS.THU'),
  t('JABVOX_CALENDAR.DAYS.FRI'),
  t('JABVOX_CALENDAR.DAYS.SAT'),
];

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
  // leading cells from prev month
  Array.from({ length: firstDay }, (_, idx) =>
    cells.push({
      date: new Date(year, month - 1, daysInPrev - (firstDay - 1 - idx)),
      current: false,
    })
  );
  // current month
  Array.from({ length: daysInMonth }, (_, idx) =>
    cells.push({ date: new Date(year, month, idx + 1), current: true })
  );
  // trailing cells to complete grid rows
  const remaining = 42 - cells.length;
  Array.from({ length: remaining }, (_, idx) =>
    cells.push({ date: new Date(year, month + 1, idx + 1), current: false })
  );
  return cells;
});

// ─── week view days ───────────────────────────────────────────────────────────
const weekDays = computed(() => {
  const d = new Date(currentDate.value);
  const day = d.getDay();
  const sunday = new Date(d);
  sunday.setDate(d.getDate() - day);
  return Array.from({ length: 7 }, (_, i) => {
    const date = new Date(sunday);
    date.setDate(sunday.getDate() + i);
    return date;
  });
});

// ─── events per day ──────────────────────────────────────────────────────────
function eventsForDate(date) {
  const key = toDateKey(date);
  return events.value.filter(e => toDateKey(new Date(e.start_at)) === key);
}

function isToday(date) {
  return toDateKey(date) === toDateKey(today);
}

// ─── navigation ──────────────────────────────────────────────────────────────
function prev() {
  const d = new Date(currentDate.value);
  if (viewMode.value === 'month') d.setMonth(d.getMonth() - 1);
  else if (viewMode.value === 'week') d.setDate(d.getDate() - 7);
  else d.setDate(d.getDate() - 1);
  currentDate.value = d;
}
function next() {
  const d = new Date(currentDate.value);
  if (viewMode.value === 'month') d.setMonth(d.getMonth() + 1);
  else if (viewMode.value === 'week') d.setDate(d.getDate() + 7);
  else d.setDate(d.getDate() + 1);
  currentDate.value = d;
}
function goToday() {
  currentDate.value = new Date(today.getFullYear(), today.getMonth(), 1);
}

// ─── fetch ────────────────────────────────────────────────────────────────────
function fetchRange() {
  const year = currentDate.value.getFullYear();
  const month = currentDate.value.getMonth();
  const from = new Date(year, month - 1, 1).toISOString();
  const to = new Date(year, month + 2, 0).toISOString();
  store.dispatch('jabvoxCalendar/fetchEvents', { from, to });
}

watch(currentDate, fetchRange);
onMounted(fetchRange);

// ─── modal ────────────────────────────────────────────────────────────────────
function openCreate(date) {
  editingEvent.value = null;
  form.value = defaultForm(date);
  formError.value = '';
  showModal.value = true;
}

function openEdit(event) {
  editingEvent.value = event;
  const d = new Date(event.start_at);
  const de = new Date(event.end_at);
  const pad = n => String(n).padStart(2, '0');
  form.value = {
    title: event.title,
    description: event.description || '',
    date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    start_time: `${pad(d.getHours())}:${pad(d.getMinutes())}`,
    end_time: `${pad(de.getHours())}:${pad(de.getMinutes())}`,
    all_day: event.all_day,
    event_type: event.event_type,
    status: event.status,
    color: event.color,
  };
  formError.value = '';
  showModal.value = true;
}

function closeModal() {
  showModal.value = false;
  editingEvent.value = null;
}

async function saveEvent() {
  if (!form.value.title.trim()) {
    formError.value = t('JABVOX_CALENDAR.ERRORS.TITLE_REQUIRED');
    return;
  }
  formError.value = '';
  isSaving.value = true;
  try {
    const startAt = new Date(`${form.value.date}T${form.value.start_time}:00`);
    const endAt = form.value.all_day
      ? new Date(`${form.value.date}T23:59:00`)
      : new Date(`${form.value.date}T${form.value.end_time}:00`);

    const payload = {
      title: form.value.title.trim(),
      description: form.value.description,
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
      all_day: form.value.all_day,
      event_type: form.value.event_type,
      status: form.value.status,
      color: form.value.color,
    };

    if (editingEvent.value) {
      await store.dispatch('jabvoxCalendar/updateEvent', {
        id: editingEvent.value.id,
        ...payload,
      });
    } else {
      await store.dispatch('jabvoxCalendar/createEvent', payload);
    }
    closeModal();
  } catch {
    formError.value = t('JABVOX_CALENDAR.ERRORS.SAVE_FAILED');
  } finally {
    isSaving.value = false;
  }
}

const showDeleteConfirm = ref(false);
const pendingDeleteEvent = ref(null);

function requestDelete(event) {
  pendingDeleteEvent.value = event;
  showDeleteConfirm.value = true;
}

async function confirmDelete() {
  if (!pendingDeleteEvent.value) return;
  await store.dispatch(
    'jabvoxCalendar/deleteEvent',
    pendingDeleteEvent.value.id
  );
  showDeleteConfirm.value = false;
  pendingDeleteEvent.value = null;
  if (showModal.value) closeModal();
}

function cancelDelete() {
  showDeleteConfirm.value = false;
  pendingDeleteEvent.value = null;
}

function toggleStatus(event) {
  const nextStatus = event.status === 'done' ? 'pending' : 'done';
  store.dispatch('jabvoxCalendar/updateEvent', {
    id: event.id,
    status: nextStatus,
  });
}

// ─── colors ───────────────────────────────────────────────────────────────────
const COLOR_OPTIONS = [
  '#3B82F6',
  '#10B981',
  '#F59E0B',
  '#EF4444',
  '#8B5CF6',
  '#EC4899',
  '#06B6D4',
  '#84CC16',
];

const TYPE_ICONS = {
  reminder: 'i-lucide-bell',
  appointment: 'i-lucide-calendar-check',
  task: 'i-lucide-check-square',
};
</script>

<template>
  <div class="flex flex-1 h-full w-full min-h-0 bg-n-surface-1 overflow-hidden">
    <!-- ── Left panel: mini-calendar + upcoming ── -->
    <aside
      class="w-60 shrink-0 border-r border-n-weak bg-n-surface-2 flex flex-col overflow-y-auto"
    >
      <!-- New event button -->
      <div class="p-4">
        <button
          class="w-full flex items-center justify-center gap-2 h-10 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 transition-colors"
          @click="openCreate(new Date())"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('JABVOX_CALENDAR.NEW_EVENT') }}
        </button>
      </div>

      <!-- Mini month navigator -->
      <div class="px-3 pb-3">
        <div class="flex items-center justify-between mb-2">
          <button class="p-1 rounded hover:bg-n-alpha-black2" @click="prev">
            <span class="i-lucide-chevron-left size-4 text-n-slate-11" />
          </button>
          <span class="text-xs font-semibold text-n-slate-12">{{
            currentMonthLabel
          }}</span>
          <button class="p-1 rounded hover:bg-n-alpha-black2" @click="next">
            <span class="i-lucide-chevron-right size-4 text-n-slate-11" />
          </button>
        </div>
        <div class="grid grid-cols-7 gap-0.5">
          <div
            v-for="d in DAY_NAMES"
            :key="d"
            class="text-center text-[10px] font-medium text-n-slate-10 pb-1"
          >
            {{ d[0] }}
          </div>
          <button
            v-for="cell in calendarDays"
            :key="cell.date.toISOString()"
            class="aspect-square flex items-center justify-center rounded-full text-[11px] transition-colors"
            :class="[
              !cell.current ? 'text-n-slate-9' : 'text-n-slate-12',
              isToday(cell.date)
                ? 'bg-n-brand text-white font-bold'
                : 'hover:bg-n-alpha-black2',
            ]"
            @click="openCreate(cell.date)"
          >
            {{ cell.date.getDate() }}
          </button>
        </div>
      </div>

      <!-- Upcoming events -->
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
          v-for="ev in events
            .slice()
            .sort((a, b) => new Date(a.start_at) - new Date(b.start_at))
            .slice(0, 8)"
          :key="ev.id"
          class="mb-1.5 flex items-start gap-2 cursor-pointer group"
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
            </p>
          </div>
        </div>
        <p
          v-if="!uiFlags.isFetching && events.length === 0"
          class="text-xs text-n-slate-10"
        >
          {{ t('JABVOX_CALENDAR.EMPTY') }}
        </p>
      </div>
    </aside>

    <!-- ── Main calendar area ── -->
    <main class="flex-1 flex flex-col overflow-hidden">
      <!-- Toolbar -->
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
          <button class="p-1.5 rounded hover:bg-n-alpha-black2" @click="prev">
            <span class="i-lucide-chevron-left size-4 text-n-slate-11" />
          </button>
          <button class="p-1.5 rounded hover:bg-n-alpha-black2" @click="next">
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
        <!-- Day headers -->
        <div class="grid grid-cols-7 border-b border-n-weak shrink-0">
          <div
            v-for="day in DAY_NAMES"
            :key="day"
            class="py-2 text-center text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
          >
            {{ day }}
          </div>
        </div>
        <!-- Grid -->
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
                  :class="ev.status === 'done' ? 'line-through opacity-70' : ''"
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
                  :class="ev.status === 'done' ? 'line-through opacity-70' : ''"
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
            </div>
            <div
              class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
            >
              <button
                class="p-1.5 rounded hover:bg-n-alpha-black2"
                :title="
                  ev.status === 'done' ? 'Marcar pendiente' : 'Marcar completo'
                "
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
              <button
                class="p-1.5 rounded hover:bg-n-ruby-3"
                @click.stop="requestDelete(ev)"
              >
                <span class="i-lucide-trash-2 size-4 text-n-ruby-9" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </main>

    <!-- ── Event modal ── -->
    <Teleport to="body">
      <div
        v-if="showModal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4"
        @click.self="closeModal"
      >
        <div
          class="w-full max-w-md rounded-2xl bg-n-surface-2 border border-n-weak shadow-xl"
        >
          <div
            class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
          >
            <h2 class="font-semibold text-n-slate-12">
              {{
                editingEvent
                  ? t('JABVOX_CALENDAR.EDIT_EVENT')
                  : t('JABVOX_CALENDAR.NEW_EVENT')
              }}
            </h2>
            <button
              class="p-1.5 rounded hover:bg-n-alpha-black2"
              @click="closeModal"
            >
              <span class="i-lucide-x size-4 text-n-slate-11" />
            </button>
          </div>

          <form class="p-5 space-y-4" @submit.prevent="saveEvent">
            <!-- Title -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.FORM.TITLE_LABEL') }}
              </label>
              <input
                v-model="form.title"
                type="text"
                :placeholder="t('JABVOX_CALENDAR.FORM.TITLE_PLACEHOLDER')"
                class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>

            <!-- Type + Status row -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-n-slate-12 mb-1">
                  {{ t('JABVOX_CALENDAR.FORM.TYPE_LABEL') }}
                </label>
                <select
                  v-model="form.event_type"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option
                    v-for="(label, key) in {
                      reminder: t('JABVOX_CALENDAR.TYPES.reminder'),
                      appointment: t('JABVOX_CALENDAR.TYPES.appointment'),
                      task: t('JABVOX_CALENDAR.TYPES.task'),
                    }"
                    :key="key"
                    :value="key"
                  >
                    {{ label }}
                  </option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-n-slate-12 mb-1">
                  {{ t('JABVOX_CALENDAR.FORM.STATUS_LABEL') }}
                </label>
                <select
                  v-model="form.status"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option value="pending">
                    {{ t('JABVOX_CALENDAR.STATUS.pending') }}
                  </option>
                  <option value="done">
                    {{ t('JABVOX_CALENDAR.STATUS.done') }}
                  </option>
                  <option value="cancelled">
                    {{ t('JABVOX_CALENDAR.STATUS.cancelled') }}
                  </option>
                </select>
              </div>
            </div>

            <!-- Date -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.FORM.DATE_LABEL') }}
              </label>
              <input
                v-model="form.date"
                type="date"
                class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>

            <!-- All day toggle -->
            <label class="flex items-center gap-2 cursor-pointer">
              <input v-model="form.all_day" type="checkbox" class="rounded" />
              <span class="text-sm text-n-slate-12">{{
                t('JABVOX_CALENDAR.FORM.ALL_DAY')
              }}</span>
            </label>

            <!-- Time range (hidden if all_day) -->
            <div v-if="!form.all_day" class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-n-slate-12 mb-1">{{
                  t('JABVOX_CALENDAR.TIME_START')
                }}</label>
                <input
                  v-model="form.start_time"
                  type="time"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-n-slate-12 mb-1">{{
                  t('JABVOX_CALENDAR.TIME_END')
                }}</label>
                <input
                  v-model="form.end_time"
                  type="time"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                />
              </div>
            </div>

            <!-- Description -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.FORM.DESCRIPTION_LABEL') }}
              </label>
              <textarea
                v-model="form.description"
                rows="2"
                :placeholder="t('JABVOX_CALENDAR.FORM.DESCRIPTION_PLACEHOLDER')"
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 resize-none focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>

            <!-- Color -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-2">
                {{ t('JABVOX_CALENDAR.FORM.COLOR_LABEL') }}
              </label>
              <div class="flex gap-2 flex-wrap">
                <button
                  v-for="c in COLOR_OPTIONS"
                  :key="c"
                  type="button"
                  class="w-6 h-6 rounded-full ring-offset-1 transition-all"
                  :style="{ background: c }"
                  :class="form.color === c ? 'ring-2 ring-n-brand' : ''"
                  @click="form.color = c"
                />
              </div>
            </div>

            <!-- Error -->
            <p
              v-if="formError"
              class="text-sm text-n-ruby-9 rounded-lg bg-n-ruby-3 px-3 py-2"
            >
              {{ formError }}
            </p>

            <!-- Actions -->
            <div class="flex items-center justify-between pt-1">
              <button
                v-if="editingEvent"
                type="button"
                class="flex items-center gap-1.5 text-sm text-n-ruby-9 hover:text-n-ruby-10"
                @click="requestDelete(editingEvent)"
              >
                <span class="i-lucide-trash-2 size-4" />
                {{ t('JABVOX_CALENDAR.DELETE_EVENT') }}
              </button>
              <div v-else />
              <div class="flex gap-2">
                <button
                  type="button"
                  class="px-4 h-9 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-black2 transition-colors"
                  @click="closeModal"
                >
                  {{ t('JABVOX_CALENDAR.CANCEL') }}
                </button>
                <button
                  type="submit"
                  :disabled="isSaving"
                  class="px-4 h-9 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
                >
                  {{ isSaving ? '...' : t('JABVOX_CALENDAR.SAVE') }}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </Teleport>

    <!-- ── Delete confirmation ── -->
    <Teleport to="body">
      <div
        v-if="showDeleteConfirm"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4"
        @click.self="cancelDelete"
      >
        <div
          class="w-full max-w-sm rounded-2xl bg-n-surface-2 border border-n-weak shadow-xl p-6"
        >
          <h3 class="font-semibold text-n-slate-12 mb-2">
            {{ t('JABVOX_CALENDAR.DELETE_EVENT') }}
          </h3>
          <p class="text-sm text-n-slate-11 mb-5">
            {{ t('JABVOX_CALENDAR.DELETE_CONFIRM') }}
          </p>
          <div class="flex justify-end gap-2">
            <button
              class="px-4 h-9 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-black2 transition-colors"
              @click="cancelDelete"
            >
              {{ t('JABVOX_CALENDAR.CANCEL') }}
            </button>
            <button
              class="px-4 h-9 rounded-lg bg-n-ruby-9 text-white text-sm font-medium hover:bg-n-ruby-10 transition-colors"
              @click="confirmDelete"
            >
              {{ t('JABVOX_CALENDAR.DELETE_EVENT') }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
