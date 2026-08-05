<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TicketForm from './components/TicketForm.vue';
import TicketBadges from './components/TicketBadges.vue';
import SlaCountdown from './components/SlaCountdown.vue';
import NotificationPrefsDialog from './components/NotificationPrefsDialog.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const tickets = useMapGetter('jabvoxTickets/getTickets');
const meta = useMapGetter('jabvoxTickets/getMeta');
const uiFlags = useMapGetter('jabvoxTickets/getUIFlags');
const isStaff = useMapGetter('jabvoxTickets/isStaff');
const canResolve = useMapGetter('jabvoxTickets/canResolve');
const currentUserId = useMapGetter('getCurrentUserID');

const filters = ref({
  q: '',
  category_type: '',
  status: '',
  priority: '',
  overdue: false,
});
const page = ref(1);
const showForm = ref(false);
const showNotifPrefs = ref(false);
const activeView = ref('all');
const selectedIds = ref([]);

// Vistas rápidas: presets de filtro para operar. Cada una arma los params del fetch.
const QUICK_VIEWS = [
  { key: 'all', label: 'JABVOX_TICKETS.VIEWS.ALL' },
  { key: 'my_open', label: 'JABVOX_TICKETS.VIEWS.MY_OPEN' },
  { key: 'unassigned', label: 'JABVOX_TICKETS.VIEWS.UNASSIGNED' },
  { key: 'overdue', label: 'JABVOX_TICKETS.VIEWS.OVERDUE' },
  { key: 'due_today', label: 'JABVOX_TICKETS.VIEWS.DUE_TODAY' },
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

// Traduce la vista rápida activa a params adicionales del listado.
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
    useAlert(e?.response?.data?.error || 'Error');
  }
};

onMounted(fetch);
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <!-- Header -->
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-lg font-semibold text-n-slate-12">
          {{ t('JABVOX_TICKETS.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_TICKETS.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <Button
          v-if="isStaff"
          :label="t('JABVOX_TICKETS.METRICS.TITLE')"
          icon="i-lucide-bar-chart-3"
          size="sm"
          variant="outline"
          color="slate"
          @click="goToMetrics"
        />
        <Button
          v-if="isStaff"
          :label="t('JABVOX_TICKETS.CATEGORIES.TITLE')"
          icon="i-lucide-tags"
          size="sm"
          variant="outline"
          color="slate"
          @click="goToCategories"
        />
        <Button
          icon="i-lucide-bell"
          size="sm"
          variant="outline"
          color="slate"
          :aria-label="t('JABVOX_TICKETS.NOTIF_PREFS.TITLE')"
          @click="showNotifPrefs = true"
        />
        <Button
          :label="t('JABVOX_TICKETS.NEW')"
          icon="i-lucide-plus"
          size="sm"
          @click="showForm = true"
        />
      </div>
    </header>

    <!-- Filtros -->
    <div
      class="flex flex-wrap items-center gap-2 px-6 py-3 border-b border-n-weak"
    >
      <div class="relative flex-1 min-w-[200px]">
        <Input
          v-model="filters.q"
          :placeholder="t('JABVOX_TICKETS.FILTERS.SEARCH')"
          @keyup.enter="applyFilters"
        />
      </div>
      <select
        v-model="filters.category_type"
        class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
        @change="applyFilters"
      >
        <option value="">{{ t('JABVOX_TICKETS.FILTERS.ALL_TYPES') }}</option>
        <option v-for="ty in TYPES" :key="ty" :value="ty">
          {{ t(`JABVOX_TICKETS.TYPE.${ty.toUpperCase()}`) }}
        </option>
      </select>
      <select
        v-model="filters.status"
        class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
        @change="applyFilters"
      >
        <option value="">{{ t('JABVOX_TICKETS.FILTERS.ALL_STATUSES') }}</option>
        <option v-for="st in STATUSES" :key="st" :value="st">
          {{ t(`JABVOX_TICKETS.STATUS.${st.toUpperCase()}`) }}
        </option>
      </select>
      <select
        v-model="filters.priority"
        class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
        @change="applyFilters"
      >
        <option value="">
          {{ t('JABVOX_TICKETS.FILTERS.ALL_PRIORITIES') }}
        </option>
        <option v-for="pr in PRIORITIES" :key="pr" :value="pr">
          {{ t(`JABVOX_TICKETS.PRIORITY.${pr.toUpperCase()}`) }}
        </option>
      </select>
      <label class="flex items-center gap-1 text-sm text-n-slate-11">
        <input
          v-model="filters.overdue"
          type="checkbox"
          @change="applyFilters"
        />
        {{ t('JABVOX_TICKETS.FILTERS.OVERDUE') }}
      </label>
    </div>

    <!-- Vistas rápidas -->
    <div
      class="flex flex-wrap items-center gap-1 px-6 py-2 border-b border-n-weak"
      role="tablist"
      :aria-label="t('JABVOX_TICKETS.VIEWS.TITLE')"
    >
      <button
        v-for="view in QUICK_VIEWS"
        :key="view.key"
        role="tab"
        :aria-selected="activeView === view.key"
        class="text-xs px-3 py-1 rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-n-brand"
        :class="
          activeView === view.key
            ? 'bg-n-brand text-white'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="selectView(view.key)"
      >
        {{ t(view.label) }}
      </button>
    </div>

    <!-- Barra de acciones en lote -->
    <div
      v-if="canBulk && selectedIds.length"
      class="flex flex-wrap items-center gap-2 px-6 py-2 bg-n-brand/5 border-b border-n-weak"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_TICKETS.BULK.SELECTED', { count: selectedIds.length }) }}
      </span>
      <select
        class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-1 text-n-slate-12"
        @change="runBulk('change_status', $event.target.value)"
      >
        <option value="">{{ t('JABVOX_TICKETS.BULK.CHANGE_STATUS') }}</option>
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

    <!-- Lista -->
    <div class="flex-1 overflow-y-auto px-6 py-4">
      <!-- Skeleton de carga: evita el salto de layout -->
      <div
        v-if="uiFlags.isFetching"
        class="flex flex-col gap-2"
        aria-busy="true"
      >
        <div
          v-for="n in 6"
          :key="n"
          class="h-10 rounded-lg bg-n-alpha-1 animate-pulse"
        />
      </div>
      <div
        v-else-if="!rows.length"
        class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_TICKETS.EMPTY') }}
      </div>
      <div v-else class="overflow-x-auto">
        <table class="min-w-full text-sm">
          <thead
            class="text-left text-xs uppercase text-n-slate-10 border-b border-n-weak"
          >
            <tr>
              <th v-if="canBulk" class="py-2 px-3 w-8">
                <input
                  type="checkbox"
                  :checked="allSelected"
                  :aria-label="
                    t('JABVOX_TICKETS.BULK.SELECTED', {
                      count: selectedIds.length,
                    })
                  "
                  @change="toggleSelectAll"
                />
              </th>
              <th class="py-2 px-3">{{ '#' }}</th>
              <th class="py-2 px-3">{{ t('JABVOX_TICKETS.COLS.TITLE') }}</th>
              <th class="py-2 px-3">{{ t('JABVOX_TICKETS.COLS.TYPE') }}</th>
              <th class="py-2 px-3">{{ t('JABVOX_TICKETS.COLS.PRIORITY') }}</th>
              <th class="py-2 px-3">{{ t('JABVOX_TICKETS.COLS.STATUS') }}</th>
              <th class="py-2 px-3">{{ 'SLA' }}</th>
              <th class="py-2 px-3">
                {{ t('JABVOX_TICKETS.COLS.REQUESTER') }}
              </th>
              <th class="py-2 px-3">{{ t('JABVOX_TICKETS.COLS.ASSIGNEE') }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="ticket in rows"
              :key="ticket.id"
              class="cursor-pointer hover:bg-n-alpha-1"
              :class="ticket.overdue ? 'bg-n-ruby-2' : ''"
              @click="openTicket(ticket.id)"
            >
              <td v-if="canBulk" class="py-2 px-3" @click.stop>
                <input
                  type="checkbox"
                  :checked="isSelected(ticket.id)"
                  :aria-label="`#${ticket.display_id}`"
                  @change="toggleSelect(ticket.id)"
                />
              </td>
              <td class="py-2 px-3 text-n-slate-11">
                {{ `#${ticket.display_id}` }}
              </td>
              <td class="py-2 px-3 font-medium text-n-slate-12">
                {{ ticket.title }}
                <span v-if="ticket.overdue" class="ml-1 text-n-ruby-11 text-xs">
                  {{ t('JABVOX_TICKETS.OVERDUE_TAG') }}
                </span>
              </td>
              <td class="py-2 px-3">
                <TicketBadges kind="type" :value="ticket.category_type" />
              </td>
              <td class="py-2 px-3">
                <TicketBadges kind="priority" :value="ticket.priority" />
              </td>
              <td class="py-2 px-3">
                <TicketBadges kind="status" :value="ticket.status" />
              </td>
              <td class="py-2 px-3">
                <SlaCountdown
                  :status="ticket.sla_status"
                  :minutes="ticket.minutes_to_due"
                />
              </td>
              <td class="py-2 px-3 text-n-slate-11">
                {{ ticket.requester?.name }}
              </td>
              <td class="py-2 px-3 text-n-slate-11">
                {{ ticket.assignee?.name || '—' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Paginación -->
      <div
        v-if="meta.totalPages > 1"
        class="flex items-center justify-center gap-2 mt-4"
      >
        <Button
          :label="t('JABVOX_TICKETS.PREV')"
          size="xs"
          variant="outline"
          color="slate"
          :disabled="meta.currentPage <= 1"
          @click="goToPage(meta.currentPage - 1)"
        />
        <span class="text-sm text-n-slate-11">
          {{ meta.currentPage }} / {{ meta.totalPages }}
        </span>
        <Button
          :label="t('JABVOX_TICKETS.NEXT')"
          size="xs"
          variant="outline"
          color="slate"
          :disabled="meta.currentPage >= meta.totalPages"
          @click="goToPage(meta.currentPage + 1)"
        />
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
