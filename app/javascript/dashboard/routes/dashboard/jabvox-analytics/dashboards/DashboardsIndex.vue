<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { storeToRefs } from 'pinia';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsEmptyState from '../components/AnalyticsEmptyState.vue';
import AnalyticsLoadingState from '../components/AnalyticsLoadingState.vue';
import FolderTree from './FolderTree.vue';
import DashboardCard from './DashboardCard.vue';
import DashboardFormDialog from './DashboardFormDialog.vue';

const { t } = useI18n();
const store = useAnalyticsDashboardsStore();
const dsStore = useAnalyticsDataSourcesStore();
const capabilities = useAnalyticsCapabilitiesStore();
const { showError } = useAnalyticsError();

const { list } = storeToRefs(store);

const selectedFolderId = ref(null);
const showForm = ref(false);
const pendingDelete = ref(null);
const deleting = ref(false);

const fetchingList = computed(() => store.uiFlags.fetchingList);

const filteredDashboards = computed(() => {
  if (selectedFolderId.value === null) return list.value;
  return list.value.filter(d => d.folderId === selectedFolderId.value);
});

onMounted(async () => {
  try {
    await Promise.all([store.fetchFolders(), store.fetchDashboards()]);
    if (!dsStore.list.length) dsStore.fetch().catch(() => {});
  } catch (error) {
    showError(error);
  }
});

const onSaved = () => {
  showForm.value = false;
};

const confirmDelete = async () => {
  if (!pendingDelete.value) return;
  deleting.value = true;
  try {
    await store.destroy(pendingDelete.value.id);
    useAlert(t('JABVOX_ANALYTICS.DASHBOARDS.DELETE.SUCCESS'));
    pendingDelete.value = null;
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.DASHBOARDS.DELETE.ERROR');
  } finally {
    deleting.value = false;
  }
};
</script>

<template>
  <div>
    <AnalyticsPageHeader :title="t('JABVOX_ANALYTICS.DASHBOARDS.TITLE')">
      <template #actions>
        <button
          v-if="capabilities.canCreate"
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white"
          @click="showForm = true"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.NEW') }}
        </button>
      </template>
    </AnalyticsPageHeader>

    <div class="flex gap-6">
      <aside class="w-56 shrink-0">
        <FolderTree
          :selected-id="selectedFolderId"
          @select="selectedFolderId = $event"
        />
      </aside>

      <main class="min-w-0 flex-1">
        <AnalyticsLoadingState v-if="fetchingList" />
        <AnalyticsEmptyState
          v-else-if="!filteredDashboards.length"
          icon="i-lucide-layout-dashboard"
          :title="t('JABVOX_ANALYTICS.DASHBOARDS.EMPTY_TITLE')"
          :body="t('JABVOX_ANALYTICS.DASHBOARDS.EMPTY_BODY')"
        >
          <template #action>
            <button
              v-if="capabilities.canCreate"
              type="button"
              class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white"
              @click="showForm = true"
            >
              <span class="i-lucide-plus size-4" />
              {{ t('JABVOX_ANALYTICS.DASHBOARDS.NEW') }}
            </button>
          </template>
        </AnalyticsEmptyState>
        <div
          v-else
          class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
        >
          <DashboardCard
            v-for="dashboard in filteredDashboards"
            :key="dashboard.id"
            :dashboard="dashboard"
            @delete="pendingDelete = $event"
          />
        </div>
      </main>
    </div>

    <DashboardFormDialog
      :open="showForm"
      :folder-id="selectedFolderId"
      @close="showForm = false"
      @saved="onSaved"
    />

    <!-- Delete confirmation -->
    <div
      v-if="pendingDelete"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-24"
    >
      <div
        class="w-full max-w-md rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.DELETE.CONFIRM_TITLE') }}
        </h3>
        <p class="mt-2 text-sm text-n-slate-11">
          {{
            t('JABVOX_ANALYTICS.DASHBOARDS.DELETE.CONFIRM_BODY', {
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
            class="inline-flex items-center gap-2 rounded-lg bg-n-ruby-9 px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="deleting"
            @click="confirmDelete"
          >
            <span
              v-if="deleting"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            {{ t('JABVOX_ANALYTICS.COMMON.DELETE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
