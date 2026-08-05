<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import TicketForm from './components/TicketForm.vue';
import TicketBadges from './components/TicketBadges.vue';
import SlaCountdown from './components/SlaCountdown.vue';
import TicketsKanban from './components/TicketsKanban.vue';
import NotificationPrefsDialog from './components/NotificationPrefsDialog.vue';
import { humanizeMinutes, minutesSince } from './helper/ticketTime';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const tickets = useMapGetter('jabvoxTickets/getTickets');
const meta = useMapGetter('jabvoxTickets/getMeta');
const uiFlags = useMapGetter('jabvoxTickets/getUIFlags');
const isStaff = useMapGetter('jabvoxTickets/isStaff');
const canResolve = useMapGetter('jabvoxTickets/canResolve');
const categories = useMapGetter('jabvoxTickets/getCategories');
const currentUserId = useMapGetter('getCurrentUserID');

const filters = ref({
  q: '',
  category_type: '',
  ticket_category_id: '',
  status: '',
  priority: '',
  assignee_id: '',
  date_from: '',
  date_to: '',
  overdue: false,
});
const page = ref(1);
const showForm = ref(false);
const showNotifPrefs = ref(false);
const showFilters = ref(false);
const activeView = ref('all');
const selectedIds = ref([]);
const viewMode = ref('list'); // list | board
const density = ref('comfortable'); // comfortable | compact
const sortBy = ref('created_at');
const sortDir = ref('desc');

const QUICK_VIEWS = [
  { key: 'all', label: 'JABVOX_TICKETS.VIEWS.ALL', icon: 'i-lucide-inbox' },
  {
    key: 'my_open',
    label: 'JABVOX_TICKETS.VIEWS.MY_OPEN',
    icon: 'i-lucide-user',
  },
  {
    key: 'unassigned',
    label: 'JABVOX_TICKETS.VIEWS.UNASSIGNED',
    icon: 'i-lucide-user-x',
  },
  {
    key: 'overdue',
    label: 'JABVOX_TICKETS.VIEWS.OVERDUE',
    icon: 'i-lucide-alarm-clock',
  },
  {
    key: 'due_today',
    label: 'JABVOX_TICKETS.VIEWS.DUE_TODAY',
    icon: 'i-lucide-calendar-clock',
  },
];

const STATUSES = [
  'new_ticket',
  'assigned',
  'in_progress',
  'on_hold',
  'resolved',
  'closed',
  'reopened',
];
const TYPES = ['incident', 'requirement', 'request'];
const PRIORITIES = ['low', 'medium', 'high', 'urgent'];

// Temas (categorías raíz) para el filtro por tema.
const topicOptions = computed(() =>
  (categories.value || []).filter(c => !c.parent_id)
);

// Agentes presentes en los tickets cargados (para el filtro por asignado).
const agentOptions = computed(() => {
  const seen = new Map();
  (tickets.value || []).forEach(tk => {
    if (tk.assignee?.id && !seen.has(tk.assignee.id))
      seen.set(tk.assignee.id, tk.assignee);
  });
  return Array.from(seen.values());
});

const viewParams = () => {
  switch (activeView.value) {
    case 'my_open':
      return { assignee_id: currentUserId.value, status: 'open' };
    case 'unassigned':
      return { unassigned: true };
    case 'overdue':
      return { overdue: true };
    case 'due_today':
      return { due_today: true };
    default:
      return {};
  }
};

const fetch = () => {
  store.dispatch('jabvoxTickets/fetchTickets', {
    ...filters.value,
    overdue: filters.value.overdue || undefined,
    ...viewParams(),
    sort_by: sortBy.value,
    sort_dir: sortDir.value,
    page: page.value,
  });
};

const applyFilters = () => {
  page.value = 1;
  selectedIds.value = [];
  fetch();
};

const selectView = key => {
  activeView.value = key;
  applyFilters();
};

const resetFilters = () => {
  filters.value = {
    q: '',
    category_type: '',
    ticket_category_id: '',
    status: '',
    priority: '',
    assignee_id: '',
    date_from: '',
    date_to: '',
    overdue: false,
  };
  applyFilters();
};

const goToPage = p => {
  page.value = p;
  fetch();
};

const openTicket = id => {
  router.push({ name: 'jabvox_tickets_detail', params: { ticketId: id } });
};

const onCreated = ticket => {
  showForm.value = false;
  fetch();
  if (ticket?.id) openTicket(ticket.id);
};

const goToMetrics = () => router.push({ name: 'jabvox_tickets_metrics' });
const goToCategories = () => router.push({ name: 'jabvox_tickets_categories' });

const rows = computed(() => tickets.value || []);
const activeFilterCount = computed(
  () =>
    Object.entries(filters.value).filter(
      ([k, v]) => k !== 'q' && v !== '' && v !== false
    ).length
);

// --- Ordenamiento por columna ---
const setSort = column => {
  if (sortBy.value === column) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc';
  } else {
    sortBy.value = column;
    sortDir.value = 'desc';
  }
  fetch();
};
const sortIcon = column => {
  if (sortBy.value !== column) return 'i-lucide-chevrons-up-down';
  return sortDir.value === 'asc'
    ? 'i-lucide-chevron-up'
    : 'i-lucide-chevron-down';
};

// --- Tiempos por fila ---
const elapsedFor = tk => humanizeMinutes(minutesSince(tk.created_at) ?? 0);

// --- Selección múltiple + acciones en lote ---
const canBulk = computed(() => isStaff.value || canResolve.value);
const isSelected = id => selectedIds.value.includes(id);
const toggleSelect = id => {
  selectedIds.value = isSelected(id)
    ? selectedIds.value.filter(x => x !== id)
    : [...selectedIds.value, id];
};
const allSelected = computed(
  () => rows.value.length > 0 && selectedIds.value.length === rows.value.length
);
const toggleSelectAll = () => {
  selectedIds.value = allSelected.value ? [] : rows.value.map(r => r.id);
};
const clearSelection = () => {
  selectedIds.value = [];
};

const runBulk = async (type, value = null) => {
  if (!selectedIds.value.length) return;
  if (
    type === 'archive' &&
    !window.confirm(t('JABVOX_TICKETS.BULK.CONFIRM_ARCHIVE'))
  )
    return;
  try {
    const result = await store.dispatch('jabvoxTickets/bulkAction', {
      type,
      ids: selectedIds.value,
      value,
    });
    useAlert(
      t('JABVOX_TICKETS.BULK.DONE', {
        processed: result.processed?.length ?? 0,
        failed: result.failed?.length ?? 0,
      })
    );
    clearSelection();
    fetch();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_TICKETS.DETAIL.ERROR'));
  }
};

// --- Kanban: cambio de estado por drag & drop ---
const onKanbanStatusChange = async ({ id, status }) => {
  try {
    await store.dispatch('jabvoxTickets/runAction', {
      type: 'changeStatus',
      id,
      args: [status],
    });
    fetch();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_TICKETS.DETAIL.ERROR'));
    fetch(); // revierte la vista al estado real
  }
};

const rowPad = computed(() =>
  density.value === 'compact' ? 'py-1.5' : 'py-3'
);

onMounted(() => {
  if (!categories.value?.length)
    store.dispatch('jabvoxTickets/fetchCategories');
  fetch();
});
</script>

<template>
  <div class="flex h-full overflow-hidden bg-n-background">
    <!-- ===== Sidebar de vistas rápidas ===== -->
    <aside
      class="hidden md:flex flex-col w-52 shrink-0 border-r border-n-weak px-3 py-4 gap-1 overflow-y-auto"
    >
      <p
        class="px-2 pb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
      >
        {{ t('JABVOX_TICKETS.VIEWS.TITLE') }}
      </p>
      <button
        v-for="view in QUICK_VIEWS"
        :key="view.key"
        class="flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-sm transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          activeView === view.key
            ? 'bg-n-brand/10 text-n-slate-12 font-medium'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        :aria-current="activeView === view.key ? 'true' : undefined"
        @click="selectView(view.key)"
      >
        <span
          :class="`${view.icon} w-4 h-4`"
          :style="
            activeView === view.key
              ? { color: 'var(--color-woot, currentColor)' }
              : {}
          "
          aria-hidden="true"
        />
        <span class="flex-1 text-left">{{ t(view.label) }}</span>
        <span
          v-if="activeView === view.key && meta.total"
          class="text-xs tabular-nums px-1.5 py-0.5 rounded-full bg-n-brand/15 text-n-slate-12"
        >
          {{ meta.total }}
        </span>
      </button>

      <div class="mt-auto pt-4 flex flex-col gap-1">
        <button
          v-if="isStaff"
          class="flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-sm text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
          @click="goToMetrics"
        >
          <span class="i-lucide-bar-chart-3 w-4 h-4" aria-hidden="true" />
          {{ t('JABVOX_TICKETS.METRICS.TITLE') }}
        </button>
        <button
          v-if="isStaff"
          class="flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-sm text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
          @click="goToCategories"
        >
          <span class="i-lucide-tags w-4 h-4" aria-hidden="true" />
          {{ t('JABVOX_TICKETS.CATEGORIES.TITLE') }}
        </button>
        <button
          class="flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-sm text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
          @click="showNotifPrefs = true"
        >
          <span class="i-lucide-bell w-4 h-4" aria-hidden="true" />
          {{ t('JABVOX_TICKETS.NOTIF_PREFS.TITLE') }}
        </button>
      </div>
    </aside>

    <!-- ===== Panel principal ===== -->
    <div class="flex flex-col flex-1 min-w-0 overflow-hidden">
      <!-- Cabecera -->
      <header
        class="flex flex-col gap-3 px-4 sm:px-6 py-4 border-b border-n-weak"
      >
        <div class="flex items-center justify-between gap-3">
          <div class="min-w-0">
            <h1 class="text-lg font-semibold text-n-slate-12 truncate">
              {{ t('JABVOX_TICKETS.TITLE') }}
            </h1>
            <p class="text-sm text-n-slate-11 hidden sm:block">
              {{ t('JABVOX_TICKETS.SUBTITLE') }}
            </p>
          </div>
          <Button
            :label="t('JABVOX_TICKETS.NEW')"
            icon="i-lucide-plus"
            size="sm"
            @click="showForm = true"
          />
        </div>

        <!-- Barra de búsqueda + controles -->
        <div class="flex flex-wrap items-center gap-2">
          <div class="relative flex-1 min-w-[180px]">
            <Input
              v-model="filters.q"
              :placeholder="t('JABVOX_TICKETS.FILTERS.SEARCH')"
              @keyup.enter="applyFilters"
            />
          </div>
          <Button
            :label="t('JABVOX_TICKETS.FILTERS.TITLE')"
            icon="i-lucide-sliders-horizontal"
            size="sm"
            variant="outline"
            color="slate"
            @click="showFilters = !showFilters"
          />
          <span
            v-if="activeFilterCount"
            class="text-xs px-2 py-0.5 rounded-full bg-n-brand/15 text-n-slate-12 tabular-nums"
          >
            {{ activeFilterCount }}
          </span>

          <!-- Toggle Lista / Tablero -->
          <div
            class="flex items-center rounded-lg border border-n-weak overflow-hidden"
          >
            <button
              class="px-2.5 py-1.5 text-xs flex items-center gap-1 transition-colors"
              :class="
                viewMode === 'list'
                  ? 'bg-n-brand/10 text-n-slate-12'
                  : 'text-n-slate-11 hover:bg-n-alpha-1'
              "
              :aria-pressed="viewMode === 'list'"
              @click="viewMode = 'list'"
            >
              <span class="i-lucide-list w-3.5 h-3.5" aria-hidden="true" />
              {{ t('JABVOX_TICKETS.VIEW.LIST') }}
            </button>
            <button
              class="px-2.5 py-1.5 text-xs flex items-center gap-1 transition-colors border-l border-n-weak"
              :class="
                viewMode === 'board'
                  ? 'bg-n-brand/10 text-n-slate-12'
                  : 'text-n-slate-11 hover:bg-n-alpha-1'
              "
              :aria-pressed="viewMode === 'board'"
              @click="viewMode = 'board'"
            >
              <span
                class="i-lucide-layout-grid w-3.5 h-3.5"
                aria-hidden="true"
              />
              {{ t('JABVOX_TICKETS.VIEW.BOARD') }}
            </button>
          </div>

          <!-- Densidad (solo lista) -->
          <button
            v-if="viewMode === 'list'"
            class="px-2 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
            :title="t('JABVOX_TICKETS.VIEW.DENSITY')"
            :aria-label="t('JABVOX_TICKETS.VIEW.DENSITY')"
            @click="
              density = density === 'comfortable' ? 'compact' : 'comfortable'
            "
          >
            <span
              :class="
                density === 'compact'
                  ? 'i-lucide-rows-3 w-4 h-4'
                  : 'i-lucide-rows-2 w-4 h-4'
              "
              aria-hidden="true"
            />
          </button>
        </div>

        <!-- Filtros combinables (desplegable) -->
        <div
          v-if="showFilters"
          class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2 tk-fade"
        >
          <select
            v-model="filters.category_type"
            class="tk-select"
            @change="applyFilters"
          >
            <option value="">
              {{ t('JABVOX_TICKETS.FILTERS.ALL_TYPES') }}
            </option>
            <option v-for="ty in TYPES" :key="ty" :value="ty">
              {{ t(`JABVOX_TICKETS.TYPE.${ty.toUpperCase()}`) }}
            </option>
          </select>
          <select
            v-model="filters.ticket_category_id"
            class="tk-select"
            @change="applyFilters"
          >
            <option value="">
              {{ t('JABVOX_TICKETS.FILTERS.ALL_TOPICS') }}
            </option>
            <option v-for="c in topicOptions" :key="c.id" :value="c.id">
              {{ c.name }}
            </option>
          </select>
          <select
            v-model="filters.status"
            class="tk-select"
            @change="applyFilters"
          >
            <option value="">
              {{ t('JABVOX_TICKETS.FILTERS.ALL_STATUSES') }}
            </option>
            <option v-for="st in STATUSES" :key="st" :value="st">
              {{ t(`JABVOX_TICKETS.STATUS.${st.toUpperCase()}`) }}
            </option>
          </select>
          <select
            v-model="filters.priority"
            class="tk-select"
            @change="applyFilters"
          >
            <option value="">
              {{ t('JABVOX_TICKETS.FILTERS.ALL_PRIORITIES') }}
            </option>
            <option v-for="pr in PRIORITIES" :key="pr" :value="pr">
              {{ t(`JABVOX_TICKETS.PRIORITY.${pr.toUpperCase()}`) }}
            </option>
          </select>
          <select
            v-model="filters.assignee_id"
            class="tk-select"
            @change="applyFilters"
          >
            <option value="">
              {{ t('JABVOX_TICKETS.FILTERS.ALL_AGENTS') }}
            </option>
            <option v-for="ag in agentOptions" :key="ag.id" :value="ag.id">
              {{ ag.name }}
            </option>
          </select>
          <button
            class="tk-select text-n-slate-11 hover:text-n-slate-12 flex items-center justify-center gap-1"
            @click="resetFilters"
          >
            <span class="i-lucide-rotate-ccw w-3.5 h-3.5" aria-hidden="true" />
            {{ t('JABVOX_TICKETS.FILTERS.RESET') }}
          </button>
          <input
            v-model="filters.date_from"
            type="date"
            class="tk-select"
            :aria-label="t('JABVOX_TICKETS.FILTERS.DATE_FROM')"
            @change="applyFilters"
          />
          <input
            v-model="filters.date_to"
            type="date"
            class="tk-select"
            :aria-label="t('JABVOX_TICKETS.FILTERS.DATE_TO')"
            @change="applyFilters"
          />
        </div>
      </header>

      <!-- Barra de acciones en lote -->
      <transition name="tk-slide">
        <div
          v-if="canBulk && selectedIds.length"
          class="flex flex-wrap items-center gap-2 px-4 sm:px-6 py-2 bg-n-brand/5 border-b border-n-weak"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{
              t('JABVOX_TICKETS.BULK.SELECTED', { count: selectedIds.length })
            }}
          </span>
          <select
            class="tk-select !py-1"
            @change="runBulk('change_status', $event.target.value)"
          >
            <option value="">
              {{ t('JABVOX_TICKETS.BULK.CHANGE_STATUS') }}
            </option>
            <option v-for="st in STATUSES" :key="st" :value="st">
              {{ t(`JABVOX_TICKETS.STATUS.${st.toUpperCase()}`) }}
            </option>
          </select>
          <Button
            :label="t('JABVOX_TICKETS.BULK.ARCHIVE')"
            icon="i-lucide-archive"
            size="xs"
            variant="outline"
            color="ruby"
            @click="runBulk('archive')"
          />
          <Button
            :label="t('JABVOX_TICKETS.BULK.CLEAR')"
            size="xs"
            variant="ghost"
            color="slate"
            @click="clearSelection"
          />
        </div>
      </transition>

      <!-- ===== Contenido ===== -->
      <!-- Skeleton -->
      <div
        v-if="uiFlags.isFetching"
        class="flex-1 overflow-y-auto px-4 sm:px-6 py-4 flex flex-col gap-2"
        aria-busy="true"
      >
        <div
          v-for="n in 8"
          :key="n"
          class="h-12 rounded-xl bg-n-alpha-1 animate-pulse"
        />
      </div>

      <!-- Vacío -->
      <div
        v-else-if="!rows.length"
        class="flex-1 flex flex-col items-center justify-center gap-3 text-center px-6"
      >
        <span
          class="flex items-center justify-center w-16 h-16 rounded-2xl bg-n-alpha-1"
          aria-hidden="true"
        >
          <span class="i-lucide-ticket w-7 h-7 text-n-slate-9" />
        </span>
        <p class="text-sm text-n-slate-11 max-w-xs">
          {{ t('JABVOX_TICKETS.EMPTY') }}
        </p>
      </div>

      <!-- Tablero Kanban -->
      <TicketsKanban
        v-else-if="viewMode === 'board'"
        :tickets="rows"
        @open="openTicket"
        @change-status="onKanbanStatusChange"
      />

      <!-- Lista -->
      <div v-else class="flex-1 overflow-auto px-4 sm:px-6 py-4">
        <table class="min-w-full text-sm">
          <thead
            class="text-left text-xs uppercase text-n-slate-10 border-b border-n-weak"
          >
            <tr>
              <th v-if="canBulk" class="py-2 px-3 w-8">
                <input
                  type="checkbox"
                  :checked="allSelected"
                  :aria-label="t('JABVOX_TICKETS.BULK.SELECT_ALL')"
                  @change="toggleSelectAll"
                />
              </th>
              <th class="py-2 px-3">{{ '#' }}</th>
              <th class="py-2 px-3">{{ t('JABVOX_TICKETS.COLS.TITLE') }}</th>
              <th class="py-2 px-3">{{ t('JABVOX_TICKETS.COLS.TYPE') }}</th>
              <th class="py-2 px-3">
                <button
                  class="flex items-center gap-1 hover:text-n-slate-12"
                  @click="setSort('priority_jabvox')"
                >
                  {{ t('JABVOX_TICKETS.COLS.PRIORITY') }}
                  <span :class="`${sortIcon('priority_jabvox')} w-3 h-3`" />
                </button>
              </th>
              <th class="py-2 px-3">
                <button
                  class="flex items-center gap-1 hover:text-n-slate-12"
                  @click="setSort('status_jabvox')"
                >
                  {{ t('JABVOX_TICKETS.COLS.STATUS') }}
                  <span :class="`${sortIcon('status_jabvox')} w-3 h-3`" />
                </button>
              </th>
              <th class="py-2 px-3">
                <button
                  class="flex items-center gap-1 hover:text-n-slate-12"
                  @click="setSort('due_at_jabvox')"
                >
                  {{ 'SLA' }}
                  <span :class="`${sortIcon('due_at_jabvox')} w-3 h-3`" />
                </button>
              </th>
              <th class="py-2 px-3 hidden lg:table-cell">
                {{ t('JABVOX_TICKETS.COLS.ELAPSED') }}
              </th>
              <th class="py-2 px-3 hidden md:table-cell">
                {{ t('JABVOX_TICKETS.COLS.REQUESTER') }}
              </th>
              <th class="py-2 px-3">{{ t('JABVOX_TICKETS.COLS.ASSIGNEE') }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="ticket in rows"
              :key="ticket.id"
              class="cursor-pointer transition-colors hover:bg-n-alpha-1"
              :class="ticket.overdue ? 'bg-n-ruby-2/40' : ''"
              @click="openTicket(ticket.id)"
            >
              <td v-if="canBulk" class="px-3" :class="rowPad" @click.stop>
                <input
                  type="checkbox"
                  :checked="isSelected(ticket.id)"
                  :aria-label="`#${ticket.display_id}`"
                  @change="toggleSelect(ticket.id)"
                />
              </td>
              <td class="px-3 text-n-slate-11 tabular-nums" :class="rowPad">
                {{ `#${ticket.display_id}` }}
              </td>
              <td class="px-3 font-medium text-n-slate-12" :class="rowPad">
                <div class="flex items-center gap-2">
                  <span class="truncate max-w-[22rem]">{{ ticket.title }}</span>
                  <span
                    v-if="ticket.category?.name"
                    class="hidden xl:inline text-xs px-1.5 py-0.5 rounded-md bg-n-alpha-1 text-n-slate-10 shrink-0"
                  >
                    {{ ticket.category.name }}
                  </span>
                </div>
              </td>
              <td class="px-3" :class="rowPad">
                <TicketBadges kind="type" :value="ticket.category_type" />
              </td>
              <td class="px-3" :class="rowPad">
                <TicketBadges kind="priority" :value="ticket.priority" />
              </td>
              <td class="px-3" :class="rowPad">
                <TicketBadges kind="status" :value="ticket.status" />
              </td>
              <td class="px-3" :class="rowPad">
                <SlaCountdown
                  :status="ticket.sla_status"
                  :minutes="ticket.minutes_to_due"
                />
              </td>
              <td
                class="px-3 text-n-slate-11 hidden lg:table-cell whitespace-nowrap"
                :class="rowPad"
              >
                {{ elapsedFor(ticket) }}
              </td>
              <td class="px-3 hidden md:table-cell" :class="rowPad">
                <div class="flex items-center gap-2 min-w-0">
                  <Avatar
                    :name="ticket.requester?.name || '?'"
                    :src="ticket.requester?.avatar_url"
                    :size="22"
                  />
                  <div class="min-w-0 leading-tight">
                    <p class="text-n-slate-12 truncate max-w-[9rem]">
                      {{ ticket.requester?.name }}
                    </p>
                    <p
                      v-if="ticket.account?.name"
                      class="text-[11px] text-n-slate-9 truncate max-w-[9rem]"
                    >
                      {{ ticket.account.name }}
                    </p>
                  </div>
                </div>
              </td>
              <td class="px-3" :class="rowPad">
                <div v-if="ticket.assignee" class="flex items-center gap-2">
                  <Avatar
                    :name="ticket.assignee.name"
                    :src="ticket.assignee.avatar_url"
                    :size="22"
                  />
                  <span
                    class="text-n-slate-11 hidden xl:inline truncate max-w-[8rem]"
                  >
                    {{ ticket.assignee.name }}
                  </span>
                </div>
                <span v-else class="text-n-slate-9 text-xs">
                  {{ t('JABVOX_TICKETS.UNASSIGNED') }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>

        <!-- Paginación -->
        <div
          v-if="meta.totalPages > 1"
          class="flex items-center justify-center gap-2 mt-4"
        >
          <Button
            :label="t('JABVOX_TICKETS.PREV')"
            icon="i-lucide-chevron-left"
            size="xs"
            variant="outline"
            color="slate"
            :disabled="meta.currentPage <= 1"
            @click="goToPage(meta.currentPage - 1)"
          />
          <span class="text-sm text-n-slate-11 tabular-nums">
            {{ meta.currentPage }} / {{ meta.totalPages }}
          </span>
          <Button
            :label="t('JABVOX_TICKETS.NEXT')"
            trailing-icon="i-lucide-chevron-right"
            size="xs"
            variant="outline"
            color="slate"
            :disabled="meta.currentPage >= meta.totalPages"
            @click="goToPage(meta.currentPage + 1)"
          />
        </div>
      </div>
    </div>

    <TicketForm
      v-if="showForm"
      @close="showForm = false"
      @created="onCreated"
    />
    <NotificationPrefsDialog
      v-if="showNotifPrefs"
      @close="showNotifPrefs = false"
    />
  </div>
</template>

<style scoped>
.tk-select {
  @apply text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand/40;
}
.tk-fade {
  animation: tk-fade 0.2s ease-out;
}
@keyframes tk-fade {
  from {
    opacity: 0;
    transform: translateY(-4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
.tk-slide-enter-active,
.tk-slide-leave-active {
  transition: all 0.18s ease;
}
.tk-slide-enter-from,
.tk-slide-leave-to {
  opacity: 0;
  transform: translateY(-6px);
}
</style>
