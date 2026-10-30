<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import dashboardAPI from 'dashboard/api/jabvox/dashboard';

const { t, locale } = useI18n();
const { accountScopedRoute, currentAccount } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const dateFrom = ref('');
const dateTo = ref('');
const summary = ref(null);
const isLoading = ref(false);
const errorMessage = ref('');
const lastUpdatedAt = ref(null);

const greeting = computed(() => {
  const hour = new Date().getHours();
  const name = currentUser.value?.name?.split(' ')[0] || '';
  if (!name) return t('JABVOX_DASHBOARD.GREETING.WELCOME');
  if (hour < 12) return t('JABVOX_DASHBOARD.GREETING.MORNING', { name });
  if (hour < 18) return t('JABVOX_DASHBOARD.GREETING.AFTERNOON', { name });
  return t('JABVOX_DASHBOARD.GREETING.EVENING', { name });
});
const canConfigureCdr = computed(
  () => currentAccount.value?.role === 'administrator'
);
const lastUpdatedLabel = computed(() => {
  if (!lastUpdatedAt.value) return '';
  const minutes = Math.floor((Date.now() - lastUpdatedAt.value) / 60000);
  return minutes < 1
    ? t('JABVOX_DASHBOARD.UPDATED_JUST_NOW')
    : t('JABVOX_DASHBOARD.UPDATED_MINUTES', { count: minutes });
});

function formatNumber(value) {
  if (typeof value !== 'number') return value ?? 0;
  return new Intl.NumberFormat(locale.value).format(value);
}

const chartLegends = [
  {
    key: 'messages',
    color: 'bg-sky-500',
    stroke: '#6b7fd7',
    label: () => t('JABVOX_DASHBOARD.CHART.MESSAGES'),
  },
  {
    key: 'calls',
    color: 'bg-violet-500',
    stroke: '#5679a8',
    label: () => t('JABVOX_DASHBOARD.CHART.CALLS'),
  },
  {
    key: 'tickets',
    color: 'bg-amber-500',
    stroke: '#d89a4a',
    label: () => t('JABVOX_DASHBOARD.CHART.TICKETS'),
  },
  {
    key: 'events',
    color: 'bg-emerald-500',
    stroke: '#0f8b83',
    label: () => t('JABVOX_DASHBOARD.CHART.EVENTS'),
  },
];

const moduleDefinitions = [
  {
    key: 'calls',
    icon: 'i-lucide-phone',
    iconTone: 'bg-sky-50 text-sky-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.CALLS'),
    metrics: [
      ['total', () => t('JABVOX_DASHBOARD.METRICS.CALLS_TOTAL')],
      ['answered', () => t('JABVOX_DASHBOARD.METRICS.CALLS_ANSWERED')],
    ],
  },
  {
    key: 'campaigns',
    icon: 'i-lucide-megaphone',
    iconTone: 'bg-violet-50 text-violet-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.CAMPAIGNS'),
    metrics: [
      ['active', () => t('JABVOX_DASHBOARD.METRICS.CAMPAIGNS_ACTIVE')],
      ['created', () => t('JABVOX_DASHBOARD.METRICS.CAMPAIGNS_CREATED')],
    ],
  },
  {
    key: 'whatsapp',
    icon: 'i-lucide-message-circle',
    iconTone: 'bg-emerald-50 text-emerald-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.WHATSAPP'),
    metrics: [
      ['batches', () => t('JABVOX_DASHBOARD.METRICS.WHATSAPP_BATCHES')],
      ['sent', () => t('JABVOX_DASHBOARD.METRICS.WHATSAPP_SENT')],
      ['failed', () => t('JABVOX_DASHBOARD.METRICS.WHATSAPP_FAILED')],
    ],
  },
  {
    key: 'tickets',
    icon: 'i-lucide-ticket',
    iconTone: 'bg-amber-50 text-amber-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.TICKETS'),
    metrics: [
      ['pending', () => t('JABVOX_DASHBOARD.METRICS.TICKETS_PENDING')],
      ['created', () => t('JABVOX_DASHBOARD.METRICS.TICKETS_CREATED')],
    ],
  },
  {
    key: 'events',
    icon: 'i-lucide-calendar-days',
    iconTone: 'bg-blue-50 text-blue-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.EVENTS'),
    metrics: [
      ['upcoming', () => t('JABVOX_DASHBOARD.METRICS.EVENTS_UPCOMING')],
      ['in_period', () => t('JABVOX_DASHBOARD.METRICS.EVENTS_IN_PERIOD')],
    ],
  },
  {
    key: 'messages',
    icon: 'i-lucide-messages-square',
    iconTone: 'bg-indigo-50 text-indigo-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.MESSAGES'),
    metrics: [
      ['incoming', () => t('JABVOX_DASHBOARD.METRICS.MESSAGES_INCOMING')],
      ['outgoing', () => t('JABVOX_DASHBOARD.METRICS.MESSAGES_OUTGOING')],
    ],
  },
  {
    key: 'tasks',
    icon: 'i-lucide-list-checks',
    iconTone: 'bg-teal-50 text-teal-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.TASKS'),
    metrics: [
      ['open', () => t('JABVOX_DASHBOARD.METRICS.TASKS_OPEN')],
      ['created', () => t('JABVOX_DASHBOARD.METRICS.TASKS_CREATED')],
    ],
  },
  {
    key: 'kanban',
    icon: 'i-lucide-columns-3',
    iconTone: 'bg-cyan-50 text-cyan-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.KANBAN'),
    metrics: [
      ['active', () => t('JABVOX_DASHBOARD.METRICS.KANBAN_ACTIVE')],
      ['moved', () => t('JABVOX_DASHBOARD.METRICS.KANBAN_MOVED')],
    ],
  },
  {
    key: 'orders',
    icon: 'i-lucide-shopping-bag',
    iconTone: 'bg-orange-50 text-orange-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.ORDERS'),
    metrics: [
      ['created', () => t('JABVOX_DASHBOARD.METRICS.ORDERS_CREATED')],
      ['total', () => t('JABVOX_DASHBOARD.METRICS.ORDERS_TOTAL')],
    ],
  },
  {
    key: 'sms',
    icon: 'i-lucide-message-square-text',
    iconTone: 'bg-sky-50 text-sky-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.SMS'),
    metrics: [
      ['sent', () => t('JABVOX_DASHBOARD.METRICS.SMS_SENT')],
      ['failed', () => t('JABVOX_DASHBOARD.METRICS.SMS_FAILED')],
    ],
  },
  {
    key: 'email',
    icon: 'i-lucide-mail',
    iconTone: 'bg-slate-100 text-slate-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.EMAIL'),
    metrics: [
      ['sent', () => t('JABVOX_DASHBOARD.METRICS.EMAIL_SENT')],
      ['failed', () => t('JABVOX_DASHBOARD.METRICS.EMAIL_FAILED')],
    ],
  },
  {
    key: 'forms',
    icon: 'i-lucide-clipboard-list',
    iconTone: 'bg-rose-50 text-rose-700',
    title: () => t('JABVOX_DASHBOARD.MODULES.FORMS'),
    metrics: [
      ['submissions', () => t('JABVOX_DASHBOARD.METRICS.FORMS_SUBMISSIONS')],
    ],
  },
];

const enabledCards = computed(() =>
  moduleDefinitions
    .filter(({ key }) => summary.value?.modules?.[key])
    .map(definition => ({
      ...definition,
      title: definition.title(),
      values: definition.metrics.map(([key, label]) => ({
        label: label(),
        value: summary.value.modules[definition.key][key],
        currency: definition.key === 'orders' && key === 'total',
      })),
    }))
);

const dailyRows = computed(() => summary.value?.daily || []);
const maxDailyValue = computed(() =>
  Math.max(
    1,
    ...chartLegends.flatMap(({ key }) =>
      dailyRows.value.map(row => Number(row[key] || 0))
    )
  )
);
const labelInterval = computed(() =>
  Math.max(1, Math.ceil(dailyRows.value.length / 10))
);
const chartDays = computed(() => {
  const width = 900;
  const height = 220;
  const padding = { x: 24, top: 16, bottom: 24 };
  const plotHeight = height - padding.top - padding.bottom;

  return dailyRows.value.map((row, index) => {
    const dateParts = row.date.split('-').map(Number);
    const date = new Date(dateParts[0], dateParts[1] - 1, dateParts[2]);
    const x =
      padding.x +
      (dailyRows.value.length < 2
        ? (width - padding.x * 2) / 2
        : (index / (dailyRows.value.length - 1)) * (width - padding.x * 2));
    const points = Object.fromEntries(
      chartLegends.map(({ key }) => [
        key,
        {
          x,
          y:
            padding.top +
            plotHeight -
            (Number(row[key] || 0) / maxDailyValue.value) * plotHeight,
        },
      ])
    );

    return {
      ...row,
      x,
      points,
      title: `${date.toLocaleDateString(locale.value)} · ${t(
        'JABVOX_DASHBOARD.CHART.TOTAL'
      )}: ${formatNumber(row.messages + row.calls + row.tickets + row.events)}`,
      label:
        index % labelInterval.value === 0 ||
        index === dailyRows.value.length - 1
          ? date.toLocaleDateString(locale.value, {
              day: 'numeric',
              month: 'short',
            })
          : '',
    };
  });
});
const chartSeries = computed(() =>
  chartLegends.map(legend => {
    const points = chartDays.value.map(day => day.points[legend.key]);
    const path = points.reduce((result, point, index) => {
      if (index === 0) return `M ${point.x} ${point.y}`;
      const previous = points[index - 1];
      const middleX = (previous.x + point.x) / 2;
      return `${result} Q ${middleX} ${previous.y} ${point.x} ${point.y}`;
    }, '');
    return { ...legend, path };
  })
);
const chartGridLines = computed(() =>
  [0, 0.5, 1].map((fraction, index) => ({
    y: 16 + fraction * 180,
    value: formatNumber(Math.round(maxDailyValue.value * (1 - fraction))),
    key: `grid-${index}`,
  }))
);
const sampledChartDays = computed(() =>
  chartDays.value.filter(
    (_, index) =>
      index % Math.max(1, Math.ceil(chartDays.value.length / 24)) === 0 ||
      index === chartDays.value.length - 1
  )
);

function formatMetric(value, currency) {
  if (currency) {
    return new Intl.NumberFormat(locale.value, {
      style: 'currency',
      currency: 'COP',
      maximumFractionDigits: 0,
    }).format(value || 0);
  }
  return formatNumber(value);
}

async function loadSummary() {
  isLoading.value = true;
  errorMessage.value = '';
  summary.value = null;
  try {
    const params = {};
    if (dateFrom.value) params.date_from = dateFrom.value;
    if (dateTo.value) params.date_to = dateTo.value;
    const response = await dashboardAPI.getSummary(params);
    summary.value = response.data;
    dateFrom.value = response.data.filters.date_from;
    dateTo.value = response.data.filters.date_to;
    lastUpdatedAt.value = Date.now();
  } catch (error) {
    errorMessage.value =
      error.response?.data?.error || t('JABVOX_DASHBOARD.ERROR');
  } finally {
    isLoading.value = false;
  }
}

onMounted(loadSummary);
</script>

<template>
  <main
    class="dashboard-page min-h-full overflow-y-auto px-4 py-6 sm:px-6 lg:px-8"
  >
    <div class="flex w-full flex-col gap-7">
      <header
        class="flex flex-col gap-6 xl:flex-row xl:items-end xl:justify-between"
      >
        <div class="min-w-0">
          <div
            class="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.16em] text-n-slate-10"
          >
            <span class="size-2 rounded-full bg-n-teal-9" />
            {{ t('JABVOX_DASHBOARD.EYEBROW') }}
          </div>
          <h1
            class="text-3xl font-semibold tracking-tight text-n-slate-12 sm:text-4xl"
          >
            {{ t('JABVOX_DASHBOARD.TITLE') }}
          </h1>
          <p class="mt-2 text-base font-medium text-n-slate-12">
            {{ greeting }}
          </p>
          <p class="mt-1 max-w-2xl text-sm text-n-slate-10">
            {{ t('JABVOX_DASHBOARD.DESCRIPTION') }}
          </p>
        </div>

        <form
          class="relative flex flex-wrap items-end gap-3 rounded-2xl border border-n-weak bg-n-surface-1 p-3 shadow-sm sm:p-4"
          @submit.prevent="loadSummary"
        >
          <label
            class="flex min-w-[145px] flex-1 flex-col gap-1.5 text-xs font-medium text-n-slate-11"
          >
            {{ t('JABVOX_DASHBOARD.FILTERS.FROM') }}
            <input
              v-model="dateFrom"
              class="jabvox-date-input h-10 w-full rounded-xl border border-n-weak bg-n-background px-3 text-sm font-medium text-n-slate-12 outline-none transition focus:border-n-brand"
              type="date"
              required
            />
          </label>
          <label
            class="flex min-w-[145px] flex-1 flex-col gap-1.5 text-xs font-medium text-n-slate-11"
          >
            {{ t('JABVOX_DASHBOARD.FILTERS.TO') }}
            <input
              v-model="dateTo"
              class="jabvox-date-input h-10 w-full rounded-xl border border-n-weak bg-n-background px-3 text-sm font-medium text-n-slate-12 outline-none transition focus:border-n-brand"
              type="date"
              required
            />
          </label>
          <button
            class="h-10 rounded-xl bg-n-brand px-5 text-sm font-semibold text-white shadow-sm transition hover:brightness-95 disabled:cursor-not-allowed disabled:opacity-60"
            type="submit"
            :disabled="isLoading"
          >
            {{
              isLoading
                ? t('JABVOX_DASHBOARD.FILTERS.LOADING')
                : t('JABVOX_DASHBOARD.FILTERS.APPLY')
            }}
          </button>
          <span
            v-if="lastUpdatedLabel"
            class="absolute -bottom-5 right-4 text-[11px] text-n-slate-9"
          >
            {{ lastUpdatedLabel }}
          </span>
        </form>
      </header>

      <div
        v-if="errorMessage"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-ruby-weak bg-n-ruby-weak/20 p-4 text-sm text-n-ruby-11"
        role="alert"
      >
        <span>{{ errorMessage }}</span>
        <button
          class="font-semibold underline"
          type="button"
          @click="loadSummary"
        >
          {{ t('JABVOX_DASHBOARD.RETRY') }}
        </button>
      </div>

      <div
        v-if="isLoading && !summary"
        class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"
        aria-live="polite"
      >
        <div
          v-for="skeleton in 8"
          :key="skeleton"
          class="dashboard-surface-card h-36 animate-pulse rounded-2xl border border-n-weak"
        />
      </div>

      <section
        v-else-if="summary"
        class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4"
        :aria-label="t('JABVOX_DASHBOARD.SECTION_SUMMARY')"
      >
        <article
          v-for="card in enabledCards"
          :key="card.key"
          class="dashboard-surface-card group min-h-[156px] rounded-2xl border border-n-weak p-5 shadow-[0_2px_12px_rgba(25,50,65,0.035)] transition duration-200 hover:-translate-y-0.5 hover:shadow-[0_8px_24px_rgba(25,50,65,0.08)]"
        >
          <div class="mb-5 flex items-center gap-3">
            <span
              class="flex size-11 shrink-0 items-center justify-center rounded-full text-lg transition-transform group-hover:scale-105"
              :class="card.iconTone"
              aria-hidden="true"
            >
              <span :class="card.icon" class="size-5" />
            </span>
            <h2
              class="min-w-0 flex-1 truncate text-sm font-semibold text-n-slate-12"
            >
              {{ card.title }}
            </h2>
          </div>
          <div
            class="grid gap-3"
            :class="card.values.length > 2 ? 'grid-cols-3' : 'grid-cols-2'"
          >
            <div
              v-for="(metric, index) in card.values"
              :key="metric.label"
              class="min-w-0"
              :class="index > 0 ? 'border-l border-n-weak pl-3' : ''"
            >
              <p class="truncate text-[11px] font-medium text-n-slate-10">
                {{ metric.label }}
              </p>
              <p
                class="mt-1 text-2xl font-semibold leading-none tracking-tight text-n-slate-12"
              >
                {{ formatMetric(metric.value, metric.currency) }}
              </p>
            </div>
          </div>
        </article>
      </section>

      <section
        v-if="summary"
        class="grid gap-4 xl:grid-cols-3"
        :aria-label="t('JABVOX_DASHBOARD.SECTION_ACTIVITY')"
      >
        <article v-if="summary.modules.calls" class="dashboard-feature-card">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="dashboard-card-eyebrow">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.CALLS_EYEBROW') }}
              </p>
              <h2 class="dashboard-card-title">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.CALLS_TITLE') }}
              </h2>
            </div>
            <span class="dashboard-feature-icon bg-sky-50 text-sky-700">
              <span class="i-lucide-phone-call size-5" />
            </span>
          </div>
          <template v-if="!summary.modules.calls.configured">
            <div class="dashboard-empty-state">
              <span class="i-lucide-phone-off size-5 text-sky-700" />
              <p>{{ t('JABVOX_DASHBOARD.ACTIVITY.CDR_NOT_CONFIGURED') }}</p>
            </div>
            <router-link
              v-if="canConfigureCdr"
              class="dashboard-text-link"
              :to="accountScopedRoute('jabvox_cdr_settings_index')"
            >
              {{ t('JABVOX_DASHBOARD.ACTIVITY.CONFIGURE_CDR') }}
              <span class="i-lucide-arrow-right size-4" />
            </router-link>
          </template>
          <template v-else>
            <div class="mt-7 flex items-end gap-3">
              <span
                class="text-4xl font-semibold tracking-tight text-n-slate-12"
                >{{ formatNumber(summary.modules.calls.total) }}</span
              >
              <span class="mb-1 text-sm text-n-slate-10">{{
                t('JABVOX_DASHBOARD.METRICS.CALLS_TOTAL')
              }}</span>
            </div>
            <p class="mt-2 text-sm text-n-slate-10">
              {{ formatNumber(summary.modules.calls.answered) }}
              {{ t('JABVOX_DASHBOARD.METRICS.CALLS_ANSWERED').toLowerCase() }}
            </p>
          </template>
        </article>

        <article
          v-if="summary.modules.campaigns"
          class="dashboard-feature-card"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="dashboard-card-eyebrow">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.CAMPAIGNS_EYEBROW') }}
              </p>
              <h2 class="dashboard-card-title">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.CAMPAIGNS_TITLE') }}
              </h2>
            </div>
            <span class="dashboard-feature-icon bg-violet-50 text-violet-700">
              <span class="i-lucide-megaphone size-5" />
            </span>
          </div>
          <div class="mt-7 flex items-end gap-3">
            <span
              class="text-4xl font-semibold tracking-tight text-n-slate-12"
              >{{ formatNumber(summary.modules.campaigns.active) }}</span
            >
            <span class="mb-1 text-sm text-n-slate-10">{{
              t('JABVOX_DASHBOARD.METRICS.CAMPAIGNS_ACTIVE').toLowerCase()
            }}</span>
          </div>
          <p class="mt-2 text-sm text-n-slate-10">
            {{
              summary.modules.campaigns.active > 0
                ? t('JABVOX_DASHBOARD.ACTIVITY.CAMPAIGNS_RUNNING')
                : t('JABVOX_DASHBOARD.ACTIVITY.CAMPAIGNS_EMPTY')
            }}
          </p>
          <router-link
            class="dashboard-text-link"
            :to="accountScopedRoute('jabvox_dialer_index')"
          >
            {{ t('JABVOX_DASHBOARD.ACTIVITY.VIEW_CAMPAIGNS') }}
            <span class="i-lucide-arrow-right size-4" />
          </router-link>
        </article>

        <article v-if="summary.modules.whatsapp" class="dashboard-feature-card">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="dashboard-card-eyebrow">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.BULK_EYEBROW') }}
              </p>
              <h2 class="dashboard-card-title">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.BULK_TITLE') }}
              </h2>
            </div>
            <span class="dashboard-feature-icon bg-emerald-50 text-emerald-700">
              <span class="i-lucide-send size-5" />
            </span>
          </div>
          <div class="mt-7 flex items-end gap-3">
            <span
              class="text-4xl font-semibold tracking-tight text-n-slate-12"
              >{{ formatNumber(summary.modules.whatsapp.batches) }}</span
            >
            <span class="mb-1 text-sm text-n-slate-10">{{
              t('JABVOX_DASHBOARD.METRICS.WHATSAPP_BATCHES').toLowerCase()
            }}</span>
          </div>
          <p class="mt-2 text-sm text-n-slate-10">
            {{
              summary.modules.whatsapp.batches > 0
                ? t('JABVOX_DASHBOARD.ACTIVITY.BULK_SENT', {
                    count: formatNumber(summary.modules.whatsapp.sent),
                  })
                : t('JABVOX_DASHBOARD.ACTIVITY.BULK_EMPTY')
            }}
          </p>
          <div class="mt-auto pt-5">
            <span class="text-xs font-medium text-n-slate-9">
              {{ t('JABVOX_DASHBOARD.ACTIVITY.PERIOD_LABEL') }}
            </span>
          </div>
        </article>
      </section>

      <section v-if="summary" class="grid gap-4 xl:grid-cols-3">
        <article v-if="summary.modules.events" class="dashboard-feature-card">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="dashboard-card-eyebrow">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.NEXT') }}
              </p>
              <h2 class="dashboard-card-title">
                {{ t('JABVOX_DASHBOARD.MODULES.EVENTS') }}
              </h2>
            </div>
            <span class="dashboard-feature-icon bg-blue-50 text-blue-700">
              <span class="i-lucide-calendar-days size-5" />
            </span>
          </div>
          <p class="mt-8 text-3xl font-semibold tracking-tight text-n-slate-12">
            {{ formatNumber(summary.modules.events.upcoming) }}
            <span class="text-sm font-normal text-n-slate-10">{{
              t('JABVOX_DASHBOARD.METRICS.EVENTS_UPCOMING').toLowerCase()
            }}</span>
          </p>
          <p
            v-if="summary.modules.events.upcoming === 0"
            class="mt-2 text-sm text-n-slate-10"
          >
            {{ t('JABVOX_DASHBOARD.ACTIVITY.EVENTS_EMPTY') }}
          </p>
          <router-link
            class="dashboard-text-link"
            :to="accountScopedRoute('jabvox_calendar_index')"
          >
            {{ t('JABVOX_DASHBOARD.ACTIVITY.VIEW_CALENDAR') }}
            <span class="i-lucide-arrow-right size-4" />
          </router-link>
        </article>

        <article v-if="summary.modules.tickets" class="dashboard-feature-card">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="dashboard-card-eyebrow">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.PERIOD_LABEL') }}
              </p>
              <h2 class="dashboard-card-title">
                {{ t('JABVOX_DASHBOARD.MODULES.TICKETS') }}
              </h2>
            </div>
            <span class="dashboard-feature-icon bg-amber-50 text-amber-700">
              <span class="i-lucide-ticket size-5" />
            </span>
          </div>
          <div class="mt-8 flex items-baseline gap-2">
            <span
              class="text-3xl font-semibold tracking-tight text-n-slate-12"
              >{{ formatNumber(summary.modules.tickets.created) }}</span
            >
            <span class="text-sm text-n-slate-10">{{
              t('JABVOX_DASHBOARD.METRICS.TICKETS_CREATED').toLowerCase()
            }}</span>
          </div>
          <div class="mt-5 flex h-2 items-center">
            <div class="h-px w-full bg-n-weak" />
          </div>
        </article>

        <article v-if="summary.modules.messages" class="dashboard-feature-card">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="dashboard-card-eyebrow">
                {{ t('JABVOX_DASHBOARD.ACTIVITY.PERIOD_LABEL') }}
              </p>
              <h2 class="dashboard-card-title">
                {{ t('JABVOX_DASHBOARD.MODULES.MESSAGES') }}
              </h2>
            </div>
            <span class="dashboard-feature-icon bg-indigo-50 text-indigo-700">
              <span class="i-lucide-messages-square size-5" />
            </span>
          </div>
          <div class="mt-8 flex items-baseline gap-2">
            <span
              class="text-3xl font-semibold tracking-tight text-n-slate-12"
              >{{
                formatNumber(
                  summary.modules.messages.incoming +
                    summary.modules.messages.outgoing
                )
              }}</span
            >
            <span class="text-sm text-n-slate-10">{{
              t('JABVOX_DASHBOARD.ACTIVITY.MESSAGES_TOTAL')
            }}</span>
          </div>
          <p class="mt-2 text-sm text-n-slate-10">
            {{ formatNumber(summary.modules.messages.incoming) }}
            {{ t('JABVOX_DASHBOARD.METRICS.MESSAGES_INCOMING').toLowerCase() }}
            <span class="mx-1 text-n-slate-8">·</span>
            {{ formatNumber(summary.modules.messages.outgoing) }}
            {{ t('JABVOX_DASHBOARD.METRICS.MESSAGES_OUTGOING').toLowerCase() }}
          </p>
        </article>
      </section>

      <section
        v-if="summary"
        class="dashboard-surface-card rounded-2xl border border-n-weak p-5 shadow-[0_2px_12px_rgba(25,50,65,0.035)] sm:p-6"
      >
        <div
          class="mb-5 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between"
        >
          <div>
            <p class="dashboard-card-eyebrow">
              {{ t('JABVOX_DASHBOARD.CHART.EYEBROW') }}
            </p>
            <h2 class="mt-1 text-lg font-semibold text-n-slate-12">
              {{ t('JABVOX_DASHBOARD.CHART.TITLE') }}
            </h2>
            <p class="mt-1 text-sm text-n-slate-10">
              {{ t('JABVOX_DASHBOARD.CHART.DESCRIPTION') }}
            </p>
          </div>
          <div class="flex flex-wrap gap-x-4 gap-y-2 text-xs text-n-slate-11">
            <span
              v-for="legend in chartLegends"
              :key="legend.key"
              class="flex items-center gap-2"
            >
              <i class="chart-legend" :class="legend.color" />
              {{ legend.label() }}
            </span>
          </div>
        </div>
        <div
          v-if="chartDays.length"
          class="chart-wrap"
          role="img"
          :aria-label="t('JABVOX_DASHBOARD.CHART.TITLE')"
        >
          <div class="chart-y-labels" aria-hidden="true">
            <span v-for="line in chartGridLines" :key="line.key">{{
              line.value
            }}</span>
          </div>
          <svg
            class="chart-svg"
            viewBox="0 0 900 220"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <defs>
              <linearGradient
                id="dashboardChartFill"
                x1="0"
                x2="0"
                y1="0"
                y2="1"
              >
                <stop offset="0%" stop-color="#0f766e" stop-opacity="0.14" />
                <stop offset="100%" stop-color="#0f766e" stop-opacity="0" />
              </linearGradient>
            </defs>
            <line
              v-for="line in chartGridLines"
              :key="line.key"
              x1="24"
              x2="876"
              :y1="line.y"
              :y2="line.y"
              class="chart-grid-line"
            />
            <path
              v-if="chartSeries[0]?.path"
              :d="`${chartSeries[0].path} L 876 196 L 24 196 Z`"
              fill="url(#dashboardChartFill)"
            />
            <path
              v-for="series in chartSeries"
              :key="series.key"
              :d="series.path"
              fill="none"
              :stroke="series.stroke"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2.5"
              vector-effect="non-scaling-stroke"
            />
            <g v-for="day in sampledChartDays" :key="day.date">
              <circle
                v-for="legend in chartLegends"
                :key="legend.key"
                :cx="day.points[legend.key].x"
                :cy="day.points[legend.key].y"
                r="3"
                :fill="legend.stroke"
                stroke="white"
                stroke-width="1.5"
              >
                <title>
                  {{ day.date }} · {{ legend.label() }}:
                  {{ formatNumber(day[legend.key]) }}
                </title>
              </circle>
            </g>
          </svg>
          <div class="chart-x-labels" aria-hidden="true">
            <span
              v-for="day in chartDays.filter(item => item.label)"
              :key="day.date"
              :style="{ left: `${(day.x / 900) * 100}%` }"
            >
              {{ day.label }}
            </span>
          </div>
        </div>
        <p v-else class="py-10 text-center text-sm text-n-slate-10">
          {{ t('JABVOX_DASHBOARD.CHART.EMPTY') }}
        </p>
      </section>
    </div>
  </main>
</template>

<style scoped>
.chart-legend {
  display: inline-block;
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 9999px;
}

.dashboard-page {
  color-scheme: light;
  background:
    radial-gradient(
      ellipse at 88% 0%,
      rgb(207 231 230 / 22%),
      transparent 32rem
    ),
    #f8fafb;
}

.dashboard-page :deep(.bg-n-background) {
  background-color: #fff;
}

.dashboard-surface-card {
  border-color: #cfdee2;
  background: linear-gradient(145deg, #e9f2f4 0%, #e3eef0 100%);
  box-shadow: 0 3px 14px rgb(33 67 79 / 7%);
}

.dashboard-surface-card:hover {
  border-color: #bdd3d8;
  background: linear-gradient(145deg, #e5f0f2 0%, #deeaed 100%);
  box-shadow: 0 10px 26px rgb(33 67 79 / 12%);
}

.dashboard-page :deep(.text-n-slate-12) {
  color: #28343d;
}

.dashboard-page :deep(.text-n-slate-11) {
  color: #5f6f79;
}

.dashboard-page :deep(.text-n-slate-10) {
  color: #71808a;
}

.dashboard-page :deep(.text-n-slate-9) {
  color: #84919a;
}

.dashboard-page :deep(.border-n-weak) {
  border-color: #e5eaed;
}

.dashboard-feature-card {
  display: flex;
  min-height: 220px;
  flex-direction: column;
  border: 1px solid #cfdee2;
  border-radius: 1rem;
  background: linear-gradient(145deg, #e9f2f4 0%, #e3eef0 100%);
  padding: 1.25rem;
  box-shadow: 0 3px 14px rgb(33 67 79 / 7%);
}

.dashboard-card-eyebrow {
  color: #82909a;
  font-size: 0.6875rem;
  font-weight: 600;
  letter-spacing: 0.11em;
  text-transform: uppercase;
}

.dashboard-card-title {
  margin-top: 0.25rem;
  color: #28343d;
  font-size: 1rem;
  font-weight: 600;
}

.dashboard-feature-icon {
  display: flex;
  width: 2.5rem;
  height: 2.5rem;
  flex: none;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
}

.dashboard-empty-state {
  display: flex;
  min-height: 4.5rem;
  align-items: center;
  gap: 0.75rem;
  margin-top: 1.5rem;
  border-radius: 0.75rem;
  background: #f5f8fa;
  padding: 0.75rem;
  color: #6f7f89;
  font-size: 0.8125rem;
  line-height: 1.4;
}

.dashboard-text-link {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  align-self: flex-start;
  margin-top: auto;
  padding-top: 1.25rem;
  color: #287b91;
  font-size: 0.8125rem;
  font-weight: 600;
}

.dashboard-text-link:hover {
  color: #165f75;
}

/* Input de fecha sin ningún ícono de calendario: ocultamos el indicador nativo del
   navegador (se solapaba con el valor y el usuario lo pidió sin iconos). El campo
   sigue abriendo el selector de fecha al hacer clic en cualquier parte del input. */
.jabvox-date-input::-webkit-calendar-picker-indicator {
  display: none;
  -webkit-appearance: none;
  appearance: none;
}

.jabvox-date-input::-webkit-inner-spin-button,
.jabvox-date-input::-webkit-clear-button {
  display: none;
  -webkit-appearance: none;
  appearance: none;
}

.jabvox-date-input {
  cursor: pointer;
}

.chart-wrap {
  position: relative;
  height: 260px;
  padding: 0 0 2rem 3.25rem;
}

.chart-y-labels {
  position: absolute;
  top: 0.6rem;
  bottom: 3rem;
  left: 0;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  color: #84919a;
  font-size: 0.6875rem;
  text-align: right;
}

.chart-svg {
  width: 100%;
  height: 100%;
  overflow: visible;
}

.chart-grid-line {
  stroke: #e9eef1;
  stroke-dasharray: 3 5;
  stroke-width: 1;
  vector-effect: non-scaling-stroke;
}

.chart-x-labels {
  position: absolute;
  right: 0;
  bottom: 0;
  left: 3.25rem;
  height: 1.5rem;
  color: #84919a;
  font-size: 0.6875rem;
}

.chart-x-labels span {
  position: absolute;
  transform: translateX(-50%);
  white-space: nowrap;
}

@media (max-width: 640px) {
  .chart-wrap {
    height: 220px;
    padding-left: 2.5rem;
  }

  .chart-x-labels {
    left: 2.5rem;
  }
}
</style>
