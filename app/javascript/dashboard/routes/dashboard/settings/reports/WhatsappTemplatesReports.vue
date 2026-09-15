<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import bulkWhatsappAPI from 'dashboard/api/jabvox/bulkWhatsapp';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RecipientsTable from '../jabvox-bulk-whatsapp/components/RecipientsTable.vue';

// Informes → Plantillas: read-only, cross-batch history of every WhatsApp
// template send for the account — every recipient, every batch, one table,
// with the same delivered/read/replied/reply-text columns as the per-batch
// report (BatchReportDialog → RecipientsTable), filterable by date range,
// template, inbox, delivery/reply status, and free-text search, paginated
// and exportable to CSV. Never mutates anything — no send/reuse actions
// here, that stays in Settings → Bulk WhatsApp.
const { t } = useI18n();

const loading = ref(false);
const recipients = ref([]);
const total = ref(0);
const page = ref(1);
const perPage = ref(50);
const deliverySummary = ref({ delivered: 0, read: 0, replied: 0 });
const templateOptions = ref([]);
const inboxOptions = ref([]);

const range = ref({ from: null, to: null, businessHours: false });
const selectedTemplate = ref('');
const selectedInbox = ref('');
const statusFilter = ref('');
const search = ref('');

const totalPages = computed(() =>
  Math.max(1, Math.ceil(total.value / perPage.value))
);

const filterParams = () => ({
  from: range.value.from || undefined,
  to: range.value.to || undefined,
  template: selectedTemplate.value || undefined,
  inboxId: selectedInbox.value || undefined,
  status: statusFilter.value || undefined,
  q: search.value.trim() || undefined,
});

const load = async () => {
  loading.value = true;
  try {
    const { data } = await bulkWhatsappAPI.getTemplatesReport({
      ...filterParams(),
      page: page.value,
    });
    recipients.value = data.recipients || [];
    total.value = data.total || 0;
    perPage.value = data.per_page || perPage.value;
    deliverySummary.value = data.delivery_summary || {
      delivered: 0,
      read: 0,
      replied: 0,
    };
    // Solo se refrescan las opciones de filtro cuando llegan (evita perder la
    // lista completa si un filtro estrecho deja el bloque de resultados vacío).
    if (data.templates) templateOptions.value = data.templates;
    if (data.inboxes) inboxOptions.value = data.inboxes;
  } catch (e) {
    useAlert(e?.response?.data?.error || t('WHATSAPP_TEMPLATES_REPORTS.ERROR'));
  } finally {
    loading.value = false;
  }
};

const onFilterChange = ({ from, to, businessHours }) => {
  range.value = { from, to, businessHours };
  page.value = 1;
  load();
};

const applyStatusFilter = value => {
  statusFilter.value = value;
  page.value = 1;
  load();
};

const onDropdownFilterChange = () => {
  page.value = 1;
  load();
};

const submitSearch = () => {
  page.value = 1;
  load();
};

const goToPage = p => {
  if (p < 1 || p > totalPages.value) return;
  page.value = p;
  load();
};

const exportCsv = async () => {
  try {
    const { data: blob } =
      await bulkWhatsappAPI.downloadTemplatesReportCsv(filterParams());
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'plantillas_whatsapp.csv';
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  } catch (e) {
    useAlert(e?.response?.data?.error || t('WHATSAPP_TEMPLATES_REPORTS.ERROR'));
  }
};

const STATUS_FILTERS = [
  { v: '', l: 'FILTER_ALL' },
  { v: 'sent', l: 'FILTER_SENT' },
  { v: 'delivered', l: 'FILTER_DELIVERED' },
  { v: 'read', l: 'FILTER_READ' },
  { v: 'replied', l: 'FILTER_REPLIED' },
  { v: 'not_replied', l: 'FILTER_NOT_REPLIED' },
  { v: 'failed', l: 'FILTER_FAILED' },
  { v: 'pending', l: 'FILTER_PENDING' },
];

onMounted(load);
</script>

<template>
  <ReportHeader :header-title="t('WHATSAPP_TEMPLATES_REPORTS.HEADER_TITLE')" />

  <div class="flex flex-col gap-4">
    <OverviewReportFilters @filter-change="onFilterChange" />

    <!-- Resumen -->
    <div
      class="flex flex-wrap items-center gap-4 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm"
    >
      <span class="text-n-slate-11">
        {{ t('WHATSAPP_TEMPLATES_REPORTS.TOTAL', { total }) }}
      </span>
      <span class="text-n-teal-11">
        {{
          t('WHATSAPP_TEMPLATES_REPORTS.DELIVERY', {
            delivered: deliverySummary.delivered || 0,
            read: deliverySummary.read || 0,
          })
        }}
      </span>
      <span class="text-n-blue-11">
        {{
          t('WHATSAPP_TEMPLATES_REPORTS.REPLIED', {
            replied: deliverySummary.replied || 0,
          })
        }}
      </span>
    </div>

    <!-- Filtros por plantilla / bandeja / estado / búsqueda -->
    <div
      class="flex flex-wrap items-end gap-3 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-3"
    >
      <div class="flex flex-col gap-1">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('WHATSAPP_TEMPLATES_REPORTS.FILTERS.TEMPLATE') }}
        </label>
        <select
          v-model="selectedTemplate"
          class="text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-n-slate-12 min-w-[10rem]"
          @change="onDropdownFilterChange"
        >
          <option value="">
            {{ t('WHATSAPP_TEMPLATES_REPORTS.FILTERS.ALL_TEMPLATES') }}
          </option>
          <option v-for="name in templateOptions" :key="name" :value="name">
            {{ name }}
          </option>
        </select>
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('WHATSAPP_TEMPLATES_REPORTS.FILTERS.INBOX') }}
        </label>
        <select
          v-model="selectedInbox"
          class="text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-n-slate-12 min-w-[10rem]"
          @change="onDropdownFilterChange"
        >
          <option value="">
            {{ t('WHATSAPP_TEMPLATES_REPORTS.FILTERS.ALL_INBOXES') }}
          </option>
          <option v-for="ib in inboxOptions" :key="ib.id" :value="ib.id">
            {{ ib.name }}
          </option>
        </select>
      </div>
      <div class="flex-1 min-w-[180px]">
        <label class="text-xs font-medium text-n-slate-11 block mb-1">
          {{ t('WHATSAPP_TEMPLATES_REPORTS.FILTERS.SEARCH') }}
        </label>
        <Input
          v-model="search"
          :placeholder="
            t('WHATSAPP_TEMPLATES_REPORTS.FILTERS.SEARCH_PLACEHOLDER')
          "
          @keyup.enter="submitSearch"
        />
      </div>
      <Button
        :label="t('WHATSAPP_TEMPLATES_REPORTS.EXPORT_CSV')"
        icon="i-lucide-download"
        variant="outline"
        color="slate"
        size="sm"
        @click="exportCsv"
      />
    </div>

    <!-- Chips de estado -->
    <div class="flex flex-wrap items-center gap-1">
      <Button
        v-for="opt in STATUS_FILTERS"
        :key="opt.l"
        :label="t(`WHATSAPP_TEMPLATES_REPORTS.${opt.l}`)"
        size="xs"
        :variant="statusFilter === opt.v ? 'solid' : 'outline'"
        color="slate"
        @click="applyStatusFilter(opt.v)"
      />
    </div>

    <RecipientsTable
      :recipients="recipients"
      :loading="loading"
      show-template
      show-origin
    />

    <!-- Paginación -->
    <div v-if="total > 0" class="flex items-center justify-between text-sm">
      <span class="text-n-slate-10">
        {{ t('WHATSAPP_TEMPLATES_REPORTS.PAGE_INFO', { page, totalPages }) }}
      </span>
      <div class="flex items-center gap-2">
        <Button
          icon="i-lucide-chevron-left"
          variant="outline"
          color="slate"
          size="sm"
          :disabled="page <= 1"
          @click="goToPage(page - 1)"
        />
        <Button
          icon="i-lucide-chevron-right"
          variant="outline"
          color="slate"
          size="sm"
          :disabled="page >= totalPages"
          @click="goToPage(page + 1)"
        />
      </div>
    </div>
  </div>
</template>
