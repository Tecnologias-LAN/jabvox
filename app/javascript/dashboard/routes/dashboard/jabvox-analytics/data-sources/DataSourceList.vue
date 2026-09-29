<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import StatusBadge from './StatusBadge.vue';

const props = defineProps({
  dataSources: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['edit', 'delete', 'sync']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const openMenuId = ref(null);
const dsStore = useAnalyticsDataSourcesStore();

// Conteo de tablas/vistas por fuente, para mostrarlo en la tarjeta sin abrir el explorador.
// Se pide una vez por fuente y falla en silencio: es informativo.
watch(
  () => props.dataSources,
  list => {
    (list || []).forEach(ds => {
      if (!dsStore.statsFor(ds.id)) dsStore.fetchStats(ds.id);
    });
  },
  { immediate: true, deep: true }
);

const statsFor = id => dsStore.statsFor(id);

const toggleMenu = id => {
  openMenuId.value = openMenuId.value === id ? null : id;
};

const closeMenu = () => {
  openMenuId.value = null;
};

const normalizeStatus = status => {
  if (status === 'ok' || status === 'connected') return 'ok';
  if (status === 'error' || status === 'failed') return 'error';
  return 'untested';
};

// Icon + accent per supported engine (backend supports these four).
const ENGINE_META = {
  postgresql: {
    icon: 'i-lucide-database',
    label: 'PostgreSQL',
    tone: 'bg-n-blue-3 text-n-blue-11',
  },
  mysql: {
    icon: 'i-lucide-database',
    label: 'MySQL',
    tone: 'bg-n-amber-3 text-n-amber-11',
  },
  mariadb: {
    icon: 'i-lucide-database',
    label: 'MariaDB',
    tone: 'bg-n-amber-3 text-n-amber-11',
  },
  sqlite: {
    icon: 'i-lucide-file-box',
    label: 'SQLite',
    tone: 'bg-n-teal-3 text-n-teal-11',
  },
};
const engineMeta = engine =>
  ENGINE_META[engine] || {
    icon: 'i-lucide-database',
    label: engine,
    tone: 'bg-n-alpha-2 text-n-slate-11',
  };

const formatDate = value => {
  if (!value) return '—';
  return new Date(value).toLocaleString();
};

const viewTables = ds => {
  closeMenu();
  router.push({
    name: 'jabvox_analytics_ds_tables',
    params: { accountId: route.params.accountId, dataSourceId: ds.id },
  });
};

const onEdit = ds => {
  closeMenu();
  emit('edit', ds);
};

const onDelete = ds => {
  closeMenu();
  emit('delete', ds);
};

const onSync = ds => {
  closeMenu();
  emit('sync', ds);
};
</script>

<template>
  <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <div
      v-for="ds in dataSources"
      :key="ds.id"
      class="group flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm transition-all hover:shadow-md hover:-translate-y-0.5"
    >
      <!-- Header: engine icon + name + menu -->
      <div class="flex items-start gap-3">
        <span
          class="flex items-center justify-center size-10 rounded-xl shrink-0"
          :class="engineMeta(ds.engineJabvox).tone"
        >
          <span :class="engineMeta(ds.engineJabvox).icon" class="size-5" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="text-sm font-semibold text-n-slate-12 truncate">
            {{ ds.nameJabvox }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ engineMeta(ds.engineJabvox).label }}
          </p>
        </div>
        <div class="relative shrink-0">
          <button
            type="button"
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
            @click="toggleMenu(ds.id)"
          >
            <span class="i-lucide-ellipsis-vertical size-5" />
          </button>
          <div
            v-if="openMenuId === ds.id"
            class="absolute right-0 top-10 z-10 w-44 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 py-1 shadow-lg"
          >
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
              @click="viewTables(ds)"
            >
              <span class="i-lucide-table-2 size-4 text-n-slate-11" />
              {{ t('JABVOX_ANALYTICS.DATA_SOURCES.LIST.VIEW_TABLES') }}
            </button>
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
              @click="onSync(ds)"
            >
              <span class="i-lucide-refresh-cw size-4 text-n-slate-11" />
              {{ t('JABVOX_ANALYTICS.DATA_SOURCES.LIST.SYNC') }}
            </button>
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
              @click="onEdit(ds)"
            >
              <span class="i-lucide-pencil size-4 text-n-slate-11" />
              {{ t('JABVOX_ANALYTICS.COMMON.EDIT') }}
            </button>
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-ruby-11 hover:bg-n-alpha-2"
              @click="onDelete(ds)"
            >
              <span class="i-lucide-trash-2 size-4" />
              {{ t('JABVOX_ANALYTICS.COMMON.DELETE') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Status + host -->
      <div class="flex items-center justify-between gap-2">
        <StatusBadge :status="normalizeStatus(ds.statusJabvox)" />
        <span class="text-xs text-n-slate-10 truncate font-mono">
          {{ ds.hostJabvox || ds.sqlitePathJabvox || '—' }}
        </span>
      </div>

      <!-- Meta footer -->
      <div
        class="flex items-center justify-between gap-2 pt-2 border-t border-n-weak text-xs text-n-slate-10"
      >
        <span class="inline-flex items-center gap-1">
          <span class="i-lucide-calendar-plus size-3" />
          {{ formatDate(ds.createdAt) }}
        </span>
        <span class="inline-flex items-center gap-1">
          <span class="i-lucide-plug size-3" />
          {{ formatDate(ds.lastTestedAtJabvox) }}
        </span>
      </div>

      <!-- Quick action -->
      <button
        type="button"
        class="mt-1 flex items-center justify-center gap-1.5 rounded-lg bg-n-alpha-1 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
        @click="viewTables(ds)"
      >
        <span class="i-lucide-table-2 size-3.5" />
        {{ t('JABVOX_ANALYTICS.DATA_SOURCES.LIST.VIEW_TABLES') }}
        <span
          v-if="statsFor(ds.id)"
          class="rounded-full bg-n-alpha-2 px-1.5 text-[11px] tabular-nums"
        >
          {{ statsFor(ds.id).total }}
        </span>
      </button>
    </div>
  </div>
</template>
