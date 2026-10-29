<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import driveAPI from 'dashboard/api/jabvox/drive';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { iconForFile, humanSize } from './helper';

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const items = ref([]);
const isLoading = ref(false);
const page = ref(1);
const hasMore = ref(false);
// Ids de archivos con una acción en curso (restaurar/purgar), para deshabilitar botones.
const busyIds = ref(new Set());

const isBusy = id => busyIds.value.has(id);

const setBusy = (id, value) => {
  const next = new Set(busyIds.value);
  if (value) next.add(id);
  else next.delete(id);
  busyIds.value = next;
};

const formatDateTime = value => {
  if (!value) return '';
  try {
    return new Date(value).toLocaleString();
  } catch (e) {
    return value;
  }
};

// Aviso tipo "en X días" a partir de la fecha de auto-purga.
const purgeHint = value => {
  if (!value) return '';
  const target = new Date(value).getTime();
  if (Number.isNaN(target)) return '';
  const diffMs = target - Date.now();
  if (diffMs <= 0) return t('JABVOX_DRIVE.TRASH.PURGE_SOON');
  const days = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
  if (days <= 0) return t('JABVOX_DRIVE.TRASH.PURGE_TODAY');
  if (days === 1) return t('JABVOX_DRIVE.TRASH.PURGE_IN_DAY');
  return t('JABVOX_DRIVE.TRASH.PURGE_IN_DAYS', { days });
};

const fetchTrash = async (reset = true) => {
  if (reset) page.value = 1;
  isLoading.value = true;
  try {
    const { data } = await driveAPI.getTrash({ page: page.value });
    const list = Array.isArray(data?.payload) ? data.payload : [];
    items.value = reset ? list : [...items.value, ...list];
    hasMore.value = list.length >= (data?.meta?.per_page || 50);
  } catch (e) {
    useAlert(t('JABVOX_DRIVE.TRASH.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const loadMore = () => {
  page.value += 1;
  fetchTrash(false);
};

const removeItem = id => {
  items.value = items.value.filter(file => file.id !== id);
};

const onRestore = async file => {
  if (isBusy(file.id)) return;
  setBusy(file.id, true);
  try {
    await driveAPI.restoreFile(file.id);
    removeItem(file.id);
    useAlert(t('JABVOX_DRIVE.TRASH.RESTORED'));
  } catch (e) {
    useAlert(t('JABVOX_DRIVE.TRASH.RESTORE_ERROR'));
  } finally {
    setBusy(file.id, false);
  }
};

const onPurge = async file => {
  if (isBusy(file.id)) return;
  // eslint-disable-next-line no-alert
  const confirmed = window.confirm(
    t('JABVOX_DRIVE.TRASH.DELETE_CONFIRM', { name: file.filename })
  );
  if (!confirmed) return;
  setBusy(file.id, true);
  try {
    await driveAPI.purgeFile(file.id);
    removeItem(file.id);
    useAlert(t('JABVOX_DRIVE.TRASH.PURGED'));
  } catch (e) {
    useAlert(t('JABVOX_DRIVE.TRASH.PURGE_ERROR'));
  } finally {
    setBusy(file.id, false);
  }
};

const goBack = () => {
  router.push({
    name: 'jabvox_drive_index',
    params: { accountId: accountId.value },
  });
};

const isEmpty = computed(() => !isLoading.value && !items.value.length);

onMounted(() => fetchTrash(true));
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
            :aria-label="t('JABVOX_DRIVE.TRASH.BACK')"
            @click="goBack"
          />
          <div>
            <h1 class="text-base font-medium text-n-slate-12">
              {{ t('JABVOX_DRIVE.TRASH.TITLE') }}
            </h1>
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_DRIVE.TRASH.SUBTITLE') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Aviso de auto-eliminación -->
      <div
        class="flex items-start gap-2 rounded-lg border border-n-amber-5 bg-n-amber-2 py-2 px-3 text-xs text-n-amber-11"
      >
        <span class="i-lucide-info size-4 shrink-0 mt-0.5" aria-hidden="true" />
        <span>{{ t('JABVOX_DRIVE.TRASH.AUTO_DELETE_NOTICE') }}</span>
      </div>

      <!-- Carga -->
      <div v-if="isLoading && !items.length" class="flex justify-center py-10">
        <Spinner />
      </div>

      <!-- Vacío -->
      <div
        v-else-if="isEmpty"
        class="flex flex-col items-center justify-center py-16 text-center text-n-slate-10"
      >
        <span class="i-lucide-trash-2 size-10 mb-3" aria-hidden="true" />
        <p class="text-sm">{{ t('JABVOX_DRIVE.TRASH.EMPTY') }}</p>
      </div>

      <!-- Tabla -->
      <div v-else class="rounded-lg border border-n-weak overflow-x-auto">
        <table class="w-full min-w-[32rem] text-sm">
          <thead class="bg-n-solid-2 text-n-slate-11 text-left">
            <tr>
              <th class="py-2 px-3 font-medium">
                {{ t('JABVOX_DRIVE.TRASH.COL_NAME') }}
              </th>
              <th class="py-2 px-3 font-medium hidden sm:table-cell">
                {{ t('JABVOX_DRIVE.TRASH.COL_SIZE') }}
              </th>
              <th class="py-2 px-3 font-medium hidden md:table-cell">
                {{ t('JABVOX_DRIVE.TRASH.COL_DELETED_BY') }}
              </th>
              <th class="py-2 px-3 font-medium hidden md:table-cell">
                {{ t('JABVOX_DRIVE.TRASH.COL_DELETED_AT') }}
              </th>
              <th class="py-2 px-3 font-medium hidden sm:table-cell">
                {{ t('JABVOX_DRIVE.TRASH.COL_PURGE_AT') }}
              </th>
              <th class="py-2 px-3 font-medium text-right">
                {{ t('JABVOX_DRIVE.TRASH.COL_ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="file in items"
              :key="file.id"
              class="border-t border-n-weak hover:bg-n-solid-2"
            >
              <td class="py-2 px-3">
                <span
                  class="inline-flex items-center gap-2 text-n-slate-12 min-w-0"
                >
                  <span
                    :class="iconForFile(file)"
                    class="size-4 shrink-0 text-n-slate-10"
                    aria-hidden="true"
                  />
                  <span class="truncate max-w-[14rem]" :title="file.filename">
                    {{ file.filename }}
                  </span>
                </span>
              </td>
              <td
                class="py-2 px-3 text-n-slate-11 hidden sm:table-cell whitespace-nowrap"
              >
                {{ humanSize(file.byte_size) }}
              </td>
              <td
                class="py-2 px-3 text-n-slate-11 hidden md:table-cell truncate max-w-[12rem]"
                :title="file.trashed_by_name || '—'"
              >
                {{ file.trashed_by_name || '—' }}
              </td>
              <td
                class="py-2 px-3 text-n-slate-10 hidden md:table-cell whitespace-nowrap"
              >
                {{ formatDateTime(file.deleted_at) }}
              </td>
              <td
                class="py-2 px-3 text-n-slate-10 hidden sm:table-cell whitespace-nowrap"
              >
                <span>{{ formatDateTime(file.purge_at) }}</span>
                <span v-if="purgeHint(file.purge_at)" class="text-n-amber-11">
                  ({{ purgeHint(file.purge_at) }})
                </span>
              </td>
              <td class="py-2 px-3">
                <div class="flex items-center justify-end gap-1">
                  <Button
                    variant="ghost"
                    size="sm"
                    icon="i-lucide-rotate-ccw"
                    :label="t('JABVOX_DRIVE.TRASH.RESTORE')"
                    :disabled="isBusy(file.id)"
                    @click="onRestore(file)"
                  />
                  <Button
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    icon="i-lucide-trash"
                    :label="t('JABVOX_DRIVE.TRASH.DELETE_FOREVER')"
                    :disabled="isBusy(file.id)"
                    @click="onPurge(file)"
                  />
                </div>
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
          :label="t('JABVOX_DRIVE.TRASH.LOAD_MORE')"
          @click="loadMore"
        />
      </div>
    </div>
  </div>
</template>
