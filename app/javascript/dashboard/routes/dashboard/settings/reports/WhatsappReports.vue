<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';

const { t } = useI18n();

const summary = ref(null);
const agents = ref([]);
const labelDurations = ref([]);
const loading = ref(false);
// Filtro de fechas (epoch segundos) + horario laboral, igual que Informes core.
const range = ref({ from: null, to: null, businessHours: false });

const fetchAll = async () => {
  loading.value = true;
  try {
    const [s, a, l] = await Promise.all([
      ReportsAPI.getWhatsappSummary(range.value),
      ReportsAPI.getWhatsappAgents(range.value),
      ReportsAPI.getWhatsappLabelDurations(range.value),
    ]);
    summary.value = s.data;
    agents.value = a.data || [];
    labelDurations.value = l.data || [];
  } finally {
    loading.value = false;
  }
};

const onFilterChange = ({ from, to, businessHours }) => {
  range.value = { from, to, businessHours };
  fetchAll();
};

// ── Formatters ──────────────────────────────────────────────────────────────
const fmtInt = v => (v == null ? '—' : Number(v).toLocaleString());
const fmtPct = v => (v == null ? '—' : `${v}%`);
const fmtSeconds = secs => {
  if (secs == null) return '—';
  const s = Math.round(secs);
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`;
  if (s < 86400)
    return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
  return `${Math.floor(s / 86400)}d ${Math.floor((s % 86400) / 3600)}h`;
};
// time_stats hash → median seconds (the headline value)
const median = stat => fmtSeconds(stat?.median);

const summaryCards = computed(() => {
  const s = summary.value;
  if (!s) return [];
  return [
    { label: t('WHATSAPP_REPORTS.SUMMARY.SENT'), value: fmtInt(s.sent) },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.DELIVERED'),
      value: fmtInt(s.delivered),
    },
    { label: t('WHATSAPP_REPORTS.SUMMARY.READ'), value: fmtInt(s.read) },
    { label: t('WHATSAPP_REPORTS.SUMMARY.FAILED'), value: fmtInt(s.failed) },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.RECEIVED'),
      value: fmtInt(s.received),
    },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.TEMPLATES'),
      value: fmtInt(s.templates),
    },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.MEDIA_SENT'),
      value: fmtInt(s.media_sent),
    },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.DELIVERY_RATE'),
      value: fmtPct(s.delivery_rate),
    },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.READ_RATE'),
      value: fmtPct(s.read_rate),
    },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.TIME_TO_DELIVER'),
      value: median(s.time_to_deliver),
    },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.TIME_TO_READ'),
      value: median(s.time_to_read),
    },
    {
      label: t('WHATSAPP_REPORTS.SUMMARY.FIRST_RESPONSE'),
      value: median(s.first_response),
    },
  ];
});

const typeRows = computed(() => {
  const s = summary.value;
  if (!s) return [];
  const inc = s.incoming_by_type || {};
  const out = s.outgoing_by_type || {};
  const keys = [
    'text',
    'image',
    'video',
    'audio',
    'document',
    'location',
    'total',
  ];
  return keys.map(k => ({
    key: k,
    label: t(`WHATSAPP_REPORTS.TYPES.${k.toUpperCase()}`),
    incoming: inc[k] || 0,
    outgoing: out[k] || 0,
  }));
});

onMounted(fetchAll);
</script>

<template>
  <ReportHeader :header-title="t('WHATSAPP_REPORTS.HEADER_TITLE')" />

  <div class="flex flex-col gap-6">
    <OverviewReportFilters @filter-change="onFilterChange" />

    <!-- Resumen general -->
    <section>
      <h3 class="text-sm font-medium text-n-slate-12 mb-2">
        {{ t('WHATSAPP_REPORTS.SUMMARY.TITLE') }}
      </h3>
      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <ReportMetricCard
          v-for="card in summaryCards"
          :key="card.label"
          :label="card.label"
          :value="card.value"
          :info-text="card.label"
        />
      </div>
      <p v-if="!summary && !loading" class="text-sm text-n-slate-10 mt-2">
        {{ t('WHATSAPP_REPORTS.EMPTY') }}
      </p>
    </section>

    <!-- Desglose por tipo de mensaje -->
    <section
      v-if="summary"
      class="overflow-x-auto rounded-lg border border-n-weak"
    >
      <table class="w-full text-sm">
        <thead class="bg-n-alpha-1 text-n-slate-11">
          <tr>
            <th class="text-left px-3 py-2 font-medium">
              {{ t('WHATSAPP_REPORTS.TYPES.TITLE_OUT') }} /
              {{ t('WHATSAPP_REPORTS.TYPES.TITLE_IN') }}
            </th>
            <th class="text-right px-3 py-2 font-medium">
              {{ t('WHATSAPP_REPORTS.TYPES.TITLE_IN') }}
            </th>
            <th class="text-right px-3 py-2 font-medium">
              {{ t('WHATSAPP_REPORTS.TYPES.TITLE_OUT') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in typeRows"
            :key="row.key"
            class="border-t border-n-weak text-n-slate-12"
          >
            <td class="px-3 py-1.5">{{ row.label }}</td>
            <td class="px-3 py-1.5 text-right">{{ fmtInt(row.incoming) }}</td>
            <td class="px-3 py-1.5 text-right">{{ fmtInt(row.outgoing) }}</td>
          </tr>
        </tbody>
      </table>
    </section>

    <!-- Por agente -->
    <section>
      <h3 class="text-sm font-medium text-n-slate-12 mb-2">
        {{ t('WHATSAPP_REPORTS.AGENTS.TITLE') }}
      </h3>
      <div class="overflow-x-auto rounded-lg border border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11">
            <tr>
              <th class="text-left px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.AGENT') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.SENT') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.RECEIVED') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.DELIVERED') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.READ') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.FAILED') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.READ_RATE') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.TIME_TO_DELIVER') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.TIME_TO_READ') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.MEDIA') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="a in agents"
              :key="a.id"
              class="border-t border-n-weak text-n-slate-12"
            >
              <td class="px-3 py-1.5">{{ a.name }}</td>
              <td class="px-3 py-1.5 text-right">{{ fmtInt(a.sent) }}</td>
              <td class="px-3 py-1.5 text-right">{{ fmtInt(a.received) }}</td>
              <td class="px-3 py-1.5 text-right">{{ fmtInt(a.delivered) }}</td>
              <td class="px-3 py-1.5 text-right">{{ fmtInt(a.read) }}</td>
              <td class="px-3 py-1.5 text-right">{{ fmtInt(a.failed) }}</td>
              <td class="px-3 py-1.5 text-right">{{ fmtPct(a.read_rate) }}</td>
              <td class="px-3 py-1.5 text-right">
                {{ median(a.time_to_deliver) }}
              </td>
              <td class="px-3 py-1.5 text-right">
                {{ median(a.time_to_read) }}
              </td>
              <td class="px-3 py-1.5 text-right">{{ fmtInt(a.media_sent) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Tiempo por etiqueta -->
    <section v-if="labelDurations.length">
      <h3 class="text-sm font-medium text-n-slate-12 mb-1">
        {{ t('WHATSAPP_REPORTS.LABELS.TITLE') }}
      </h3>
      <p class="text-[11px] text-n-slate-9 mb-2">
        {{ t('WHATSAPP_REPORTS.LABELS.NOTE') }}
      </p>
      <div class="overflow-x-auto rounded-lg border border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11">
            <tr>
              <th class="text-left px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.LABELS.LABEL') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.LABELS.TOTAL') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.LABELS.AVG') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.LABELS.OCCURRENCES') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in labelDurations"
              :key="row.label"
              class="border-t border-n-weak text-n-slate-12"
            >
              <td class="px-3 py-1.5">{{ row.label }}</td>
              <td class="px-3 py-1.5 text-right">
                {{ fmtSeconds(row.total_seconds) }}
              </td>
              <td class="px-3 py-1.5 text-right">
                {{ fmtSeconds(row.avg_seconds) }}
              </td>
              <td class="px-3 py-1.5 text-right">
                {{ fmtInt(row.occurrences) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
