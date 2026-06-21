<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsEmptyState from '../components/AnalyticsEmptyState.vue';
import AnalyticsLoadingState from '../components/AnalyticsLoadingState.vue';
import DataSourceList from './DataSourceList.vue';
import DataSourceFormDialog from './DataSourceFormDialog.vue';

const { t } = useI18n();
const store = useAnalyticsDataSourcesStore();
const capabilities = useAnalyticsCapabilitiesStore();
const { showError } = useAnalyticsError();

const dialogOpen = ref(false);
const editing = ref(null);
const pendingDelete = ref(null);

const dataSources = computed(() => store.list);
const loading = computed(() => store.uiFlags.fetchingList);
const canManage = computed(() => capabilities.canManageDataSources);

const openCreate = () => {
  editing.value = null;
  dialogOpen.value = true;
};

const openEdit = ds => {
  editing.value = ds;
  dialogOpen.value = true;
};

const closeDialog = () => {
  dialogOpen.value = false;
  editing.value = null;
};

const onSaved = () => {
  closeDialog();
  store.fetch();
};

const requestDelete = ds => {
  pendingDelete.value = ds;
};

const confirmDelete = async () => {
  const ds = pendingDelete.value;
  if (!ds) return;
  try {
    await store.destroy(ds.id);
    useAlert(t('JABVOX_ANALYTICS.DATA_SOURCES.DELETE.SUCCESS'));
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.DATA_SOURCES.DELETE.ERROR');
  } finally {
    pendingDelete.value = null;
  }
};

const onSync = async ds => {
  try {
    await store.sync(ds.id);
    await store.fetch();
  } catch (error) {
    showError(error);
  }
};

onMounted(() => {
  store.fetch().catch(error => showError(error));
});
</script>

<template>
  <div>
    <AnalyticsPageHeader :title="t('JABVOX_ANALYTICS.DATA_SOURCES.TITLE')">
      <template #actions>
        <button
          v-if="canManage"
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white"
          @click="openCreate"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('JABVOX_ANALYTICS.DATA_SOURCES.NEW') }}
        </button>
      </template>
    </AnalyticsPageHeader>

    <AnalyticsLoadingState v-if="loading" />

    <AnalyticsEmptyState
      v-else-if="!dataSources.length"
      icon="i-lucide-database"
      :title="t('JABVOX_ANALYTICS.DATA_SOURCES.EMPTY_TITLE')"
      :body="t('JABVOX_ANALYTICS.DATA_SOURCES.EMPTY_BODY')"
    >
      <template #action>
        <button
          v-if="canManage"
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white"
          @click="openCreate"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('JABVOX_ANALYTICS.DATA_SOURCES.EMPTY_ACTION') }}
        </button>
      </template>
    </AnalyticsEmptyState>

    <DataSourceList
      v-else
      :data-sources="dataSources"
      @edit="openEdit"
      @delete="requestDelete"
      @sync="onSync"
    />

    <DataSourceFormDialog
      :open="dialogOpen"
      :data-source="editing"
      @close="closeDialog"
      @saved="onSaved"
    />

    <!-- Delete confirmation -->
    <div
      v-if="pendingDelete"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-3 p-4"
    >
      <div
        class="w-full max-w-md rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.DATA_SOURCES.DELETE.CONFIRM_TITLE') }}
        </h3>
        <p class="mt-2 text-sm text-n-slate-11">
          {{
            t('JABVOX_ANALYTICS.DATA_SOURCES.DELETE.CONFIRM_BODY', {
              name: pendingDelete.nameJabvox,
            })
          }}
        </p>
        <div class="mt-6 flex items-center justify-end gap-3">
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
            @click="pendingDelete = null"
          >
            {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-ruby-9 px-3 py-2 text-sm font-medium text-white"
            @click="confirmDelete"
          >
            {{ t('JABVOX_ANALYTICS.COMMON.DELETE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
