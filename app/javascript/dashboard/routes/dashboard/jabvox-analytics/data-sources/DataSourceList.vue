<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import StatusBadge from './StatusBadge.vue';

defineProps({
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
  <div class="overflow-x-auto rounded-lg border border-n-weak">
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-n-weak text-left text-n-slate-11">
          <th class="px-4 py-3 font-medium">
            {{ t('JABVOX_ANALYTICS.COMMON.NAME') }}
          </th>
          <th class="px-4 py-3 font-medium">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.LIST.ENGINE') }}
          </th>
          <th class="px-4 py-3 font-medium">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.LIST.HOST') }}
          </th>
          <th class="px-4 py-3 font-medium">
            {{ t('JABVOX_ANALYTICS.COMMON.STATUS') }}
          </th>
          <th class="px-4 py-3 font-medium">
            {{ t('JABVOX_ANALYTICS.COMMON.CREATED_AT') }}
          </th>
          <th class="px-4 py-3 font-medium">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.LIST.LAST_CONNECTION') }}
          </th>
          <th class="px-4 py-3 text-right font-medium">
            {{ t('JABVOX_ANALYTICS.COMMON.ACTIONS') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="ds in dataSources"
          :key="ds.id"
          class="border-b border-n-weak last:border-b-0"
        >
          <td class="px-4 py-3 font-medium text-n-slate-12">
            {{ ds.nameJabvox }}
          </td>
          <td class="px-4 py-3 text-n-slate-11">{{ ds.engineJabvox }}</td>
          <td class="px-4 py-3 text-n-slate-11">
            {{ ds.hostJabvox || ds.sqlitePathJabvox || '—' }}
          </td>
          <td class="px-4 py-3">
            <StatusBadge :status="normalizeStatus(ds.statusJabvox)" />
          </td>
          <td class="px-4 py-3 text-n-slate-11">
            {{ formatDate(ds.createdAt) }}
          </td>
          <td class="px-4 py-3 text-n-slate-11">
            {{ formatDate(ds.lastTestedAtJabvox) }}
          </td>
          <td class="relative px-4 py-3 text-right">
            <button
              type="button"
              class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
              @click="toggleMenu(ds.id)"
            >
              <span class="i-lucide-ellipsis-vertical size-5" />
            </button>
            <div
              v-if="openMenuId === ds.id"
              class="absolute right-4 top-12 z-10 w-44 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 py-1 shadow-lg"
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
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
