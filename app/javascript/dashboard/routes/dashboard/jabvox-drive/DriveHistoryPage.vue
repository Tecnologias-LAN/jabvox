<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import driveAPI from 'dashboard/api/jabvox/drive';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const logs = ref([]);
const isLoading = ref(false);
const page = ref(1);
const hasMore = ref(false);

// Filtros que viajan al backend (getAuditLogs los soporta).
const actionFilter = ref('');
const fromFilter = ref('');
const toFilter = ref('');

// Filtros client-side sobre los logs ya cargados.
const filenameFilter = ref('');
const userFilter = ref('');
const resultFilter = ref('');

// Iconos por tipo de acción (consistente con i-lucide del resto del dashboard).
const ACTION_ICON = {
  upload: 'i-lucide-upload',
  download: 'i-lucide-download',
  rename: 'i-lucide-pencil',
  move: 'i-lucide-folder-input',
  delete: 'i-lucide-trash-2',
  trash: 'i-lucide-trash-2',
  purge: 'i-lucide-trash',
  restore: 'i-lucide-rotate-ccw',
  create_folder: 'i-lucide-folder-plus',
  rename_folder: 'i-lucide-pencil',
  move_folder: 'i-lucide-folder-input',
  delete_folder: 'i-lucide-folder-x',
  overflow: 'i-lucide-alert-triangle',
  promote: 'i-lucide-arrow-up-circle',
  regularize: 'i-lucide-check-circle-2',
  reconcile: 'i-lucide-refresh-cw',
};

const ACTIONS = Object.keys(ACTION_ICON);

const RESULTS = ['success', 'failure', 'rejected'];

const actionLabel = action =>
  t(`JABVOX_DRIVE.HISTORY.ACTIONS.${action.toUpperCase()}`);

const resultClass = result => {
  if (result === 'failure') return 'text-n-ruby-11 bg-n-ruby-3';
  if (result === 'rejected') return 'text-n-amber-11 bg-n-amber-3';
  return 'text-n-teal-11 bg-n-teal-3';
};

const formatDateTime = value => {
  if (!value) return '';
  try {
    return new Date(value).toLocaleString();
  } catch (e) {
    return value;
  }
};

const fileName = log => log?.metadata?.filename || '';

const metadataSummary = meta => {
  if (!meta || typeof meta !== 'object') return '';
  return Object.entries(meta)
    .map(([k, v]) => `${k}: ${v}`)
    .join(' · ');
};

const fetchLogs = async (reset = true) => {
  if (reset) page.value = 1;
  isLoading.value = true;
  try {
    const { data } = await driveAPI.getAuditLogs({
      page: page.value,
      actionName: actionFilter.value || null,
      createdAfter: fromFilter.value || null,
      createdBefore: toFilter.value || null,
    });
    const items = Array.isArray(data?.payload) ? data.payload : [];
    logs.value = reset ? items : [...logs.value, ...items];
    hasMore.value = items.length >= (data?.meta?.per_page || 50);
  } catch (e) {
    useAlert(t('JABVOX_DRIVE.HISTORY.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const loadMore = () => {
  page.value += 1;
  fetchLogs(false);
};

// Lista de usuarios únicos presentes en los logs cargados (para el dropdown).
const userOptions = computed(() => {
  const names = logs.value.map(log => log.user_name).filter(name => !!name);
  return [...new Set(names)].sort((a, b) => a.localeCompare(b));
});

// Filtrado client-side (nombre de archivo, usuario, resultado).
const filteredLogs = computed(() => {
  const needle = filenameFilter.value.trim().toLowerCase();
  return logs.value.filter(log => {
    if (needle && !fileName(log).toLowerCase().includes(needle)) {
      return false;
    }
    if (userFilter.value && log.user_name !== userFilter.value) {
      return false;
    }
    if (resultFilter.value && log.result !== resultFilter.value) {
      return false;
    }
    return true;
  });
});

const goBack = () => {
  router.push({
    name: 'jabvox_drive_index',
    params: { accountId: accountId.value },
  });
};

const clearFilters = () => {
  actionFilter.value = '';
  fromFilter.value = '';
  toFilter.value = '';
  filenameFilter.value = '';
  userFilter.value = '';
  resultFilter.value = '';
  fetchLogs(true);
};

const isEmpty = computed(() => !isLoading.value && !filteredLogs.value.length);

onMounted(() => fetchLogs(true));
</script>

<template>
  <div class="h-full w-full overflow-y-auto">
    <div class="flex w-full flex-col gap-4 p-4">
      <!-- Encabezado -->
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div class="flex items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            icon="i-lucide-arrow-left"
            :aria-label="t('JABVOX_DRIVE.HISTORY.BACK')"
            @click="goBack"
          />
          <div>
            <h1 class="text-base font-medium text-n-slate-12">
              {{ t('JABVOX_DRIVE.HISTORY.TITLE') }}
            </h1>
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_DRIVE.HISTORY.SUBTITLE') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Filtros -->
      <div class="flex flex-wrap items-end gap-2">
        <!-- Búsqueda por nombre de archivo (client-side) -->
        <input
          v-model="filenameFilter"
          type="search"
          class="w-full sm:w-auto rounded-lg border border-n-weak bg-n-solid-1 py-2 px-3 text-sm text-n-slate-12 outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :placeholder="t('JABVOX_DRIVE.HISTORY.FILTER_FILENAME')"
          :aria-label="t('JABVOX_DRIVE.HISTORY.FILTER_FILENAME')"
        />
        <!-- Filtro por acción (backend) -->
        <select
          v-model="actionFilter"
          class="w-full sm:w-auto rounded-lg border border-n-weak bg-n-solid-1 py-2 px-3 text-sm text-n-slate-12 outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :aria-label="t('JABVOX_DRIVE.HISTORY.FILTER_ACTION')"
          @change="fetchLogs(true)"
        >
          <option value="">{{ t('JABVOX_DRIVE.HISTORY.ALL_ACTIONS') }}</option>
          <option v-for="a in ACTIONS" :key="a" :value="a">
            {{ actionLabel(a) }}
          </option>
        </select>
        <!-- Filtro por usuario (client-side) -->
        <select
          v-model="userFilter"
          class="w-full sm:w-auto rounded-lg border border-n-weak bg-n-solid-1 py-2 px-3 text-sm text-n-slate-12 outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :aria-label="t('JABVOX_DRIVE.HISTORY.FILTER_USER')"
        >
          <option value="">{{ t('JABVOX_DRIVE.HISTORY.ALL_USERS') }}</option>
          <option v-for="u in userOptions" :key="u" :value="u">
            {{ u }}
          </option>
        </select>
        <!-- Filtro por resultado (client-side) -->
        <select
          v-model="resultFilter"
          class="w-full sm:w-auto rounded-lg border border-n-weak bg-n-solid-1 py-2 px-3 text-sm text-n-slate-12 outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :aria-label="t('JABVOX_DRIVE.HISTORY.FILTER_STATUS')"
        >
          <option value="">{{ t('JABVOX_DRIVE.HISTORY.ALL_RESULTS') }}</option>
          <option v-for="r in RESULTS" :key="r" :value="r">
            {{ t(`JABVOX_DRIVE.HISTORY.RESULTS.${r.toUpperCase()}`) }}
          </option>
        </select>
        <!-- Rango de fechas (backend) -->
        <input
          v-model="fromFilter"
          type="date"
          class="w-full sm:w-auto rounded-lg border border-n-weak bg-n-solid-1 py-2 px-3 text-sm text-n-slate-12 outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :aria-label="t('JABVOX_DRIVE.HISTORY.FILTER_DATE_FROM')"
          @change="fetchLogs(true)"
        />
        <input
          v-model="toFilter"
          type="date"
          class="w-full sm:w-auto rounded-lg border border-n-weak bg-n-solid-1 py-2 px-3 text-sm text-n-slate-12 outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :aria-label="t('JABVOX_DRIVE.HISTORY.FILTER_DATE_TO')"
          @change="fetchLogs(true)"
        />
        <Button
          variant="ghost"
          size="sm"
          icon="i-lucide-x"
          :label="t('JABVOX_DRIVE.HISTORY.CLEAR_FILTERS')"
          @click="clearFilters"
        />
      </div>

      <!-- Carga -->
      <div v-if="isLoading && !logs.length" class="flex justify-center py-10">
        <Spinner />
      </div>

      <!-- Vacío -->
      <div
        v-else-if="isEmpty"
        class="flex flex-col items-center justify-center py-16 text-center text-n-slate-10"
      >
        <span class="i-lucide-history size-10 mb-3" aria-hidden="true" />
        <p class="text-sm">{{ t('JABVOX_DRIVE.HISTORY.EMPTY') }}</p>
      </div>

      <!-- Tabla -->
      <div v-else class="rounded-lg border border-n-weak overflow-x-auto">
        <table class="w-full min-w-[32rem] text-sm">
          <thead class="bg-n-solid-2 text-n-slate-11 text-left">
            <tr>
              <th class="py-2 px-3 font-medium">
                {{ t('JABVOX_DRIVE.HISTORY.COL_ACTION') }}
              </th>
              <th class="py-2 px-3 font-medium hidden sm:table-cell">
                {{ t('JABVOX_DRIVE.HISTORY.COL_USER') }}
              </th>
              <th class="py-2 px-3 font-medium hidden sm:table-cell">
                {{ t('JABVOX_DRIVE.HISTORY.COL_FILE') }}
              </th>
              <th class="py-2 px-3 font-medium hidden md:table-cell">
                {{ t('JABVOX_DRIVE.HISTORY.COL_DETAIL') }}
              </th>
              <th class="py-2 px-3 font-medium">
                {{ t('JABVOX_DRIVE.HISTORY.COL_RESULT') }}
              </th>
              <th class="py-2 px-3 font-medium hidden lg:table-cell">
                {{ t('JABVOX_DRIVE.HISTORY.COL_IP') }}
              </th>
              <th class="py-2 px-3 font-medium">
                {{ t('JABVOX_DRIVE.HISTORY.COL_DATE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="log in filteredLogs"
              :key="log.id"
              class="border-t border-n-weak hover:bg-n-solid-2"
            >
              <td class="py-2 px-3">
                <span class="inline-flex items-center gap-2 text-n-slate-12">
                  <span
                    :class="ACTION_ICON[log.action] || 'i-lucide-activity'"
                    class="size-4 text-n-slate-10"
                    aria-hidden="true"
                  />
                  {{ actionLabel(log.action) }}
                </span>
              </td>
              <td class="py-2 px-3 text-n-slate-11 hidden sm:table-cell">
                {{ log.user_name || t('JABVOX_DRIVE.HISTORY.SYSTEM') }}
              </td>
              <td
                class="py-2 px-3 text-n-slate-11 hidden sm:table-cell max-w-[12rem] truncate"
                :title="fileName(log)"
              >
                {{ fileName(log) }}
              </td>
              <td
                class="py-2 px-3 text-n-slate-10 hidden md:table-cell max-w-xs truncate"
                :title="metadataSummary(log.metadata)"
              >
                {{ metadataSummary(log.metadata) }}
              </td>
              <td class="py-2 px-3">
                <span
                  class="inline-block rounded px-2 py-0.5 text-xs font-medium"
                  :class="resultClass(log.result)"
                >
                  {{
                    t(
                      `JABVOX_DRIVE.HISTORY.RESULTS.${log.result.toUpperCase()}`
                    )
                  }}
                </span>
              </td>
              <td
                class="py-2 px-3 text-n-slate-10 hidden lg:table-cell whitespace-nowrap"
              >
                {{ log.ip_address || '—' }}
              </td>
              <td class="py-2 px-3 text-n-slate-10 whitespace-nowrap">
                {{ formatDateTime(log.created_at) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Cargar más -->
      <div v-if="hasMore && !isEmpty" class="flex justify-center">
        <Button
          variant="ghost"
          size="sm"
          :is-loading="isLoading"
          :label="t('JABVOX_DRIVE.HISTORY.LOAD_MORE')"
          @click="loadMore"
        />
      </div>
    </div>
  </div>
</template>
