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

// Folder creation
const showFolderForm = ref(false);
const folderName = ref('');
const creatingFolder = ref(false);

const openFolderForm = () => {
  folderName.value = '';
  showFolderForm.value = true;
};

// Internal reports picker — user chooses which built-in reports to create.
const showReportsPicker = ref(false);
const reportCatalog = ref([]);
const selectedReportKeys = ref([]);
const creatingReports = ref(false);

const openReportsPicker = async () => {
  selectedReportKeys.value = [];
  try {
    reportCatalog.value = await store.fetchInternalReports();
    showReportsPicker.value = true;
  } catch (error) {
    showError(error);
  }
};

const toggleReportKey = key => {
  const i = selectedReportKeys.value.indexOf(key);
  if (i === -1) selectedReportKeys.value.push(key);
  else selectedReportKeys.value.splice(i, 1);
};

const createSelectedReports = async () => {
  if (!selectedReportKeys.value.length || creatingReports.value) return;
  creatingReports.value = true;
  try {
    await store.createInternalReports(selectedReportKeys.value);
    useAlert(t('JABVOX_ANALYTICS.DASHBOARDS.REPORTS_CREATED'));
    showReportsPicker.value = false;
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.DASHBOARDS.REPORTS_ERROR');
  } finally {
    creatingReports.value = false;
  }
};

const createFolder = async () => {
  const name = folderName.value.trim();
  if (!name || creatingFolder.value) return;
  creatingFolder.value = true;
  try {
    await store.createFolder({ name_jabvox: name });
    useAlert(t('JABVOX_ANALYTICS.DASHBOARDS.FOLDER_CREATED'));
    showFolderForm.value = false;
    folderName.value = '';
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.DASHBOARDS.FOLDER_ERROR');
  } finally {
    creatingFolder.value = false;
  }
};

// Borrado de carpeta (los dashboards dentro NO se borran: quedan sin carpeta).
const pendingFolderDelete = ref(null);
const deletingFolder = ref(false);

const onDeleteFolder = folder => {
  pendingFolderDelete.value = folder;
};

const confirmDeleteFolder = async () => {
  if (!pendingFolderDelete.value) return;
  deletingFolder.value = true;
  try {
    await store.destroyFolder(pendingFolderDelete.value.id);
    useAlert(t('JABVOX_ANALYTICS.FOLDERS.DELETE_SUCCESS'));
    // Si estabas filtrando por esa carpeta, vuelve a "todas".
    if (selectedFolderId.value === pendingFolderDelete.value.id) {
      selectedFolderId.value = null;
    }
    pendingFolderDelete.value = null;
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.FOLDERS.DELETE_ERROR');
  } finally {
    deletingFolder.value = false;
  }
};

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
          class="inline-flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1"
          @click="openReportsPicker"
        >
          <span class="i-lucide-layout-list size-4" />
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.INTERNAL_REPORTS') }}
        </button>
        <button
          v-if="capabilities.canCreate"
          type="button"
          class="inline-flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1"
          @click="openFolderForm"
        >
          <span class="i-lucide-folder-plus size-4" />
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.NEW_FOLDER') }}
        </button>
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

    <div class="flex flex-col gap-6 md:flex-row">
      <aside class="w-full shrink-0 md:w-56">
        <p
          class="mb-2 px-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.FOLDERS_TITLE') }}
        </p>
        <FolderTree
          :selected-id="selectedFolderId"
          @select="selectedFolderId = $event"
          @delete="onDeleteFolder"
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

    <!-- Internal reports picker dialog -->
    <div
      v-if="showReportsPicker"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-16"
    >
      <div
        class="w-full max-w-lg rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <div class="mb-1 flex items-center justify-between">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.DASHBOARDS.INTERNAL_REPORTS') }}
          </h3>
          <button
            type="button"
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
            @click="showReportsPicker = false"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>
        <p class="mb-4 text-sm text-n-slate-11">
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.INTERNAL_REPORTS_HELP') }}
        </p>

        <div
          class="grid max-h-80 grid-cols-1 gap-2 overflow-y-auto sm:grid-cols-2"
        >
          <label
            v-for="r in reportCatalog"
            :key="r.key"
            class="flex cursor-pointer items-center gap-3 rounded-lg border px-3 py-2.5 transition-colors"
            :class="
              selectedReportKeys.includes(r.key)
                ? 'border-n-brand/40 bg-n-alpha-2'
                : 'border-n-weak hover:bg-n-alpha-1'
            "
          >
            <input
              type="checkbox"
              class="size-4 rounded accent-n-brand"
              :checked="selectedReportKeys.includes(r.key)"
              @change="toggleReportKey(r.key)"
            />
            <span :class="r.icon" class="size-4 shrink-0 text-n-slate-11" />
            <span class="text-sm text-n-slate-12">{{ r.label }}</span>
          </label>
        </div>

        <div class="mt-6 flex items-center justify-end gap-3">
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
            @click="showReportsPicker = false"
          >
            {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="creatingReports || !selectedReportKeys.length"
            @click="createSelectedReports"
          >
            <span
              v-if="creatingReports"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            {{
              t('JABVOX_ANALYTICS.DASHBOARDS.CREATE_SELECTED', {
                count: selectedReportKeys.length,
              })
            }}
          </button>
        </div>
      </div>
    </div>

    <!-- New folder dialog -->
    <div
      v-if="showFolderForm"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-24"
    >
      <div
        class="w-full max-w-md rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <div class="mb-4 flex items-center justify-between">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.DASHBOARDS.NEW_FOLDER') }}
          </h3>
          <button
            type="button"
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
            @click="showFolderForm = false"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>
        <label class="mb-1 block text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.FOLDER_NAME') }}
        </label>
        <input
          v-model="folderName"
          type="text"
          class="block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong"
          :placeholder="
            t('JABVOX_ANALYTICS.DASHBOARDS.FOLDER_NAME_PLACEHOLDER')
          "
          autofocus
          @keydown.enter="createFolder"
        />
        <div class="mt-6 flex items-center justify-end gap-3">
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
            @click="showFolderForm = false"
          >
            {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="creatingFolder || !folderName.trim()"
            @click="createFolder"
          >
            <span
              v-if="creatingFolder"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            {{ t('JABVOX_ANALYTICS.COMMON.CREATE') }}
          </button>
        </div>
      </div>
    </div>

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

    <!-- Folder delete confirmation -->
    <div
      v-if="pendingFolderDelete"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-24"
    >
      <div
        class="w-full max-w-md rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.FOLDERS.DELETE_CONFIRM_TITLE') }}
        </h3>
        <p class="mt-2 text-sm text-n-slate-11">
          {{
            t('JABVOX_ANALYTICS.FOLDERS.DELETE_CONFIRM_BODY', {
              name: pendingFolderDelete.nameJabvox || pendingFolderDelete.name,
            })
          }}
        </p>
        <div class="mt-6 flex items-center justify-end gap-3">
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
            @click="pendingFolderDelete = null"
          >
            {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-ruby-9 px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="deletingFolder"
            @click="confirmDeleteFolder"
          >
            <span
              v-if="deletingFolder"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            {{ t('JABVOX_ANALYTICS.COMMON.DELETE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
