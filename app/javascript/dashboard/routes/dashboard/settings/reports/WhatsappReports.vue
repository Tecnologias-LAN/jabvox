<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';

const { t } = useI18n();

const summary = ref(null);
const agents = ref([]);
const labelDurations = ref([]);
const templates = ref([]);
const selectedTemplate = ref('');
const loading = ref(false);
// Filtro de fechas (epoch segundos) + horario laboral, igual que Informes core.
const range = ref({ from: null, to: null, businessHours: false });

const queryParams = () => ({
  ...range.value,
  templateName: selectedTemplate.value || undefined,
});

const fetchAll = async () => {
  loading.value = true;
  try {
    const [s, a, l] = await Promise.all([
      ReportsAPI.getWhatsappSummary(queryParams()),
      ReportsAPI.getWhatsappAgents(queryParams()),
      ReportsAPI.getWhatsappLabelDurations(range.value),
    ]);
    summary.value = s.data;
    agents.value = a.data || [];
    labelDurations.value = l.data || [];
  } finally {
    loading.value = false;
  }
};

const loadTemplates = async () => {
  try {
    const { data } = await ReportsAPI.getWhatsappTemplates();
    templates.value = Array.isArray(data) ? data : [];
  } catch {
    templates.value = [];
  }
};

const onFilterChange = ({ from, to, businessHours }) => {
  range.value = { from, to, businessHours };
  fetchAll();
};

const onTemplateChange = () => fetchAll();

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

// Textos de ayuda (tooltip) en lenguaje simple para cada métrica.
const TIP = key => t(`WHATSAPP_REPORTS.HINTS.${key}`);

// Grupo de volumen (conteos). tone: 'neutral' | 'danger-if-positive'.
const volumeCards = computed(() => {
  const s = summary.value;
  if (!s) return [];
  return [
    {
      key: 'SENT',
      label: t('WHATSAPP_REPORTS.SUMMARY.SENT'),
      value: fmtInt(s.sent),
      tip: TIP('SENT'),
    },
    {
      key: 'RECEIVED',
      label: t('WHATSAPP_REPORTS.SUMMARY.RECEIVED'),
      value: fmtInt(s.received),
      tip: TIP('RECEIVED'),
    },
    {
      key: 'DELIVERED',
      label: t('WHATSAPP_REPORTS.SUMMARY.DELIVERED'),
      value: fmtInt(s.delivered),
      tip: TIP('DELIVERED'),
    },
    {
      key: 'READ',
      label: t('WHATSAPP_REPORTS.SUMMARY.READ'),
      value: fmtInt(s.read),
      tip: TIP('READ'),
    },
    {
      key: 'FAILED',
      label: t('WHATSAPP_REPORTS.SUMMARY.FAILED'),
      value: fmtInt(s.failed),
      tip: TIP('FAILED'),
      danger: (s.failed || 0) > 0,
    },
    {
      key: 'TEMPLATES',
      label: t('WHATSAPP_REPORTS.SUMMARY.TEMPLATES'),
      value: fmtInt(s.templates),
      tip: TIP('TEMPLATES'),
    },
    {
      key: 'MEDIA_SENT',
      label: t('WHATSAPP_REPORTS.SUMMARY.MEDIA_SENT'),
      value: fmtInt(s.media_sent),
      tip: TIP('MEDIA_SENT'),
    },
  ];
});

const rateCards = computed(() => {
  const s = summary.value;
  if (!s) return [];
  return [
    {
      key: 'DELIVERY_RATE',
      label: t('WHATSAPP_REPORTS.SUMMARY.DELIVERY_RATE'),
      value: fmtPct(s.delivery_rate),
      tip: TIP('DELIVERY_RATE'),
      positive: true,
    },
    {
      key: 'READ_RATE',
      label: t('WHATSAPP_REPORTS.SUMMARY.READ_RATE'),
      value: fmtPct(s.read_rate),
      tip: TIP('READ_RATE'),
      positive: true,
    },
  ];
});

const timeCards = computed(() => {
  const s = summary.value;
  if (!s) return [];
  return [
    {
      key: 'TIME_TO_DELIVER',
      label: t('WHATSAPP_REPORTS.SUMMARY.TIME_TO_DELIVER'),
      value: median(s.time_to_deliver),
      tip: TIP('TIME_TO_DELIVER'),
    },
    {
      key: 'TIME_TO_READ',
      label: t('WHATSAPP_REPORTS.SUMMARY.TIME_TO_READ'),
      value: median(s.time_to_read),
      tip: TIP('TIME_TO_READ'),
    },
    {
      key: 'FIRST_RESPONSE',
      label: t('WHATSAPP_REPORTS.SUMMARY.FIRST_RESPONSE'),
      value: median(s.first_response),
      tip: TIP('FIRST_RESPONSE'),
    },
  ];
});

// Columnas de la tabla por agente con su tooltip ("de este agente").
const agentColumns = computed(() => [
  {
    key: 'sent',
    label: t('WHATSAPP_REPORTS.AGENTS.SENT'),
    tip: TIP('AGENT_SENT'),
  },
  {
    key: 'received',
    label: t('WHATSAPP_REPORTS.AGENTS.RECEIVED'),
    tip: TIP('AGENT_RECEIVED'),
  },
  {
    key: 'delivered',
    label: t('WHATSAPP_REPORTS.AGENTS.DELIVERED'),
    tip: TIP('AGENT_DELIVERED'),
  },
  {
    key: 'read',
    label: t('WHATSAPP_REPORTS.AGENTS.READ'),
    tip: TIP('AGENT_READ'),
  },
  {
    key: 'failed',
    label: t('WHATSAPP_REPORTS.AGENTS.FAILED'),
    tip: TIP('AGENT_FAILED'),
  },
  {
    key: 'delivery_rate',
    label: t('WHATSAPP_REPORTS.AGENTS.DELIVERY_RATE'),
    tip: TIP('AGENT_DELIVERY_RATE'),
  },
  {
    key: 'read_rate',
    label: t('WHATSAPP_REPORTS.AGENTS.READ_RATE'),
    tip: TIP('AGENT_READ_RATE'),
  },
  {
    key: 'ttd',
    label: t('WHATSAPP_REPORTS.AGENTS.TIME_TO_DELIVER'),
    tip: TIP('AGENT_TIME_TO_DELIVER'),
  },
  {
    key: 'ttr',
    label: t('WHATSAPP_REPORTS.AGENTS.TIME_TO_READ'),
    tip: TIP('AGENT_TIME_TO_READ'),
  },
  {
    key: 'media',
    label: t('WHATSAPP_REPORTS.AGENTS.MEDIA'),
    tip: TIP('AGENT_MEDIA'),
  },
]);

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

onMounted(() => {
  loadTemplates();
  fetchAll();
});
</script>

<template>
  <ReportHeader :header-title="t('WHATSAPP_REPORTS.HEADER_TITLE')" />

  <div class="flex flex-col gap-6">
    <OverviewReportFilters @filter-change="onFilterChange" />

    <!-- Filtro por plantilla de WhatsApp (lista desplegable) -->
    <div
      v-if="templates.length"
      class="flex flex-wrap items-center gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
    >
      <label class="text-sm font-medium text-n-slate-11">
        {{ t('WHATSAPP_REPORTS.FILTERS.TEMPLATE') }}
      </label>
      <select
        v-model="selectedTemplate"
        class="text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-n-slate-12"
        @change="onTemplateChange"
      >
        <option value="">
          {{ t('WHATSAPP_REPORTS.FILTERS.ALL_TEMPLATES') }}
        </option>
        <option v-for="name in templates" :key="name" :value="name">
          {{ name }}
        </option>
      </select>
    </div>

    <p v-if="!summary && !loading" class="text-sm text-n-slate-10">
      {{ t('WHATSAPP_REPORTS.EMPTY') }}
    </p>

    <!-- Resumen general: volumen -->
    <section v-if="summary">
      <h3 class="text-sm font-medium text-n-slate-12 mb-2">
        {{ t('WHATSAPP_REPORTS.SUMMARY.TITLE') }}
      </h3>
      <div
        class="grid gap-3 grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5"
      >
        <div
          v-for="card in volumeCards"
          :key="card.key"
          v-tooltip="card.tip"
          :aria-label="`${card.label}: ${card.value}`"
          tabindex="0"
          class="group rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 shadow-sm transition-colors hover:border-n-slate-6 focus:outline-none focus:ring-2 focus:ring-n-brand"
        >
          <div class="flex items-center gap-1 text-xs text-n-slate-11">
            <span>{{ card.label }}</span>
            <span class="i-lucide-info w-3 h-3 text-n-slate-9" />
          </div>
          <div
            class="text-2xl font-semibold mt-1"
            :class="card.danger ? 'text-n-ruby-11' : 'text-n-slate-12'"
          >
            {{ card.value }}
          </div>
        </div>
      </div>
    </section>

    <!-- Porcentajes + tiempos -->
    <section v-if="summary" class="grid gap-4 md:grid-cols-2">
      <div>
        <h3 class="text-sm font-medium text-n-slate-12 mb-2">
          {{ t('WHATSAPP_REPORTS.SUMMARY.RATES_TITLE') }}
        </h3>
        <div class="grid grid-cols-2 gap-3">
          <div
            v-for="card in rateCards"
            :key="card.key"
            v-tooltip="card.tip"
            :aria-label="`${card.label}: ${card.value}`"
            tabindex="0"
            class="rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 shadow-sm focus:outline-none focus:ring-2 focus:ring-n-brand"
          >
            <div class="flex items-center gap-1 text-xs text-n-slate-11">
              <span>{{ card.label }}</span>
              <span class="i-lucide-info w-3 h-3 text-n-slate-9" />
            </div>
            <div class="text-2xl font-semibold mt-1 text-n-teal-11">
              {{ card.value }}
            </div>
          </div>
        </div>
      </div>
      <div>
        <h3 class="text-sm font-medium text-n-slate-12 mb-2">
          {{ t('WHATSAPP_REPORTS.SUMMARY.TIMES_TITLE') }}
        </h3>
        <div class="grid grid-cols-3 gap-3">
          <div
            v-for="card in timeCards"
            :key="card.key"
            v-tooltip="card.tip"
            :aria-label="`${card.label}: ${card.value}`"
            tabindex="0"
            class="rounded-xl border border-n-weak bg-n-solid-1 px-3 py-3 shadow-sm focus:outline-none focus:ring-2 focus:ring-n-brand"
          >
            <div class="flex items-center gap-1 text-xs text-n-slate-11">
              <span class="truncate">{{ card.label }}</span>
              <span class="i-lucide-info w-3 h-3 shrink-0 text-n-slate-9" />
            </div>
            <div class="text-xl font-semibold mt-1 text-n-slate-12">
              {{ card.value }}
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Desglose por tipo de mensaje -->
    <section v-if="summary">
      <h3 class="text-sm font-medium text-n-slate-12 mb-2">
        {{ t('WHATSAPP_REPORTS.TYPES.TITLE') }}
      </h3>
      <div class="overflow-x-auto rounded-lg border border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11 sticky top-0 z-[1]">
            <tr>
              <th class="text-left px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.TYPES.TYPE') }}
              </th>
              <th
                v-tooltip="t('WHATSAPP_REPORTS.HINTS.RECEIVED_BY_TYPE')"
                class="text-right px-3 py-2 font-medium cursor-help"
              >
                {{ t('WHATSAPP_REPORTS.TYPES.TITLE_IN') }}
              </th>
              <th
                v-tooltip="t('WHATSAPP_REPORTS.HINTS.SENT_BY_TYPE')"
                class="text-right px-3 py-2 font-medium cursor-help"
              >
                {{ t('WHATSAPP_REPORTS.TYPES.TITLE_OUT') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in typeRows"
              :key="row.key"
              class="border-t border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
              :class="[row.key === 'total' ? 'font-semibold bg-n-alpha-1' : '']"
            >
              <td class="px-3 py-1.5">{{ row.label }}</td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ fmtInt(row.incoming) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ fmtInt(row.outgoing) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Por agente -->
    <section>
      <h3 class="text-sm font-medium text-n-slate-12 mb-2">
        {{ t('WHATSAPP_REPORTS.AGENTS.TITLE') }}
      </h3>
      <div class="overflow-x-auto rounded-lg border border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11 sticky top-0 z-[1]">
            <tr>
              <th class="text-left px-3 py-2 font-medium">
                {{ t('WHATSAPP_REPORTS.AGENTS.AGENT') }}
              </th>
              <th
                v-for="col in agentColumns"
                :key="col.key"
                v-tooltip="col.tip"
                class="text-right px-3 py-2 font-medium cursor-help whitespace-nowrap"
              >
                {{ col.label }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="a in agents"
              :key="a.id"
              class="border-t border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            >
              <td class="px-3 py-1.5 whitespace-nowrap">{{ a.name }}</td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ fmtInt(a.sent) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ fmtInt(a.received) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ fmtInt(a.delivered) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ fmtInt(a.read) }}
              </td>
              <td
                class="px-3 py-1.5 text-right tabular-nums"
                :class="a.failed > 0 ? 'text-n-ruby-11' : ''"
              >
                {{ fmtInt(a.failed) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums text-n-teal-11">
                {{ fmtPct(a.delivery_rate) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums text-n-teal-11">
                {{ fmtPct(a.read_rate) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ median(a.time_to_deliver) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ median(a.time_to_read) }}
              </td>
              <td class="px-3 py-1.5 text-right tabular-nums">
                {{ fmtInt(a.media_sent) }}
              </td>
            </tr>
            <tr v-if="!agents.length">
              <td colspan="11" class="px-3 py-8 text-center text-n-slate-10">
                {{ t('WHATSAPP_REPORTS.AGENTS.EMPTY') }}
              </td>
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
