<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  iconForFile,
  humanSize,
  resolveCategory,
  isOverflow,
  isPending,
  isQuarantined,
} from '../helper';
import FileActionsMenu from './FileActionsMenu.vue';
import FolderActionsMenu from './FolderActionsMenu.vue';

const props = defineProps({
  folders: { type: Array, default: () => [] },
  files: { type: Array, default: () => [] },
  viewMode: { type: String, default: 'grid' },
  selectedIds: { type: Array, default: () => [] },
  canManage: { type: Boolean, default: true },
  // Marca las carpetas como "contactos" (icono persona) cuando aplica.
  contactFolders: { type: Boolean, default: false },
});

const emit = defineEmits([
  'openFolder',
  'renameFolder',
  'deleteFolder',
  'toggleSelect',
  'toggleSelectAll',
  'preview',
  'download',
  'rename',
  'move',
  'delete',
  'goToConversation',
]);

const { t } = useI18n();

const isSelected = id => props.selectedIds.includes(id);

// Selección global ("seleccionar todo") sobre los archivos del nivel actual.
const allSelected = computed(
  () => props.files.length > 0 && props.files.every(f => isSelected(f.id))
);
const someSelected = computed(
  () => props.selectedIds.length > 0 && !allSelected.value
);

const formatDate = value => {
  if (!value) return '';
  try {
    return new Date(value).toLocaleDateString();
  } catch {
    return '';
  }
};

const categoryLabel = file =>
  t(`JABVOX_DRIVE.TYPES.${resolveCategory(file).toUpperCase()}`);

// Etiqueta de estado para archivos que no están disponibles (pero existen):
// overflow (sin espacio), pending (procesando) o quarantined (retenido).
const statusBadge = file => {
  if (isOverflow(file)) {
    return { label: t('JABVOX_DRIVE.FILE.OVERFLOW_BADGE'), tone: 'amber' };
  }
  if (isPending(file)) {
    return { label: t('JABVOX_DRIVE.FILE.PENDING_BADGE'), tone: 'slate' };
  }
  if (isQuarantined(file)) {
    return { label: t('JABVOX_DRIVE.FILE.QUARANTINED_BADGE'), tone: 'red' };
  }
  return null;
};
</script>

<template>
  <!-- Vista de cuadrícula -->
  <div v-if="viewMode === 'grid'" class="flex flex-col gap-3">
    <!-- Seleccionar todo -->
    <label
      v-if="canManage && files.length"
      class="flex w-fit cursor-pointer items-center gap-2 text-xs text-n-slate-11"
    >
      <input
        type="checkbox"
        class="size-4 rounded border-n-weak accent-n-brand"
        :checked="allSelected"
        :indeterminate="someSelected"
        @change="emit('toggleSelectAll')"
      />
      {{ t('JABVOX_DRIVE.BULK.SELECT_ALL') }}
    </label>

    <div
      class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-5"
    >
      <!-- Carpetas -->
      <button
        v-for="folder in folders"
        :key="`folder-${folder.id}`"
        type="button"
        class="group relative flex flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-3 text-left transition-colors hover:border-n-brand/40 hover:bg-n-alpha-1"
        @click="emit('openFolder', folder)"
      >
        <div class="flex items-center justify-between">
          <span
            :class="contactFolders ? 'i-lucide-user-round' : 'i-lucide-folder'"
            class="size-8 text-n-brand"
            aria-hidden="true"
          />
          <FolderActionsMenu
            v-if="canManage && !folder.system_folder"
            :folder="folder"
            @rename="emit('renameFolder', $event)"
            @delete="emit('deleteFolder', $event)"
          />
        </div>
        <span class="flex items-center gap-1 min-w-0">
          <span
            v-if="folder.system_folder"
            class="i-lucide-star size-3.5 shrink-0 text-amber-500"
            :title="t('JABVOX_DRIVE.FOLDER.SYSTEM_FOLDER')"
            aria-hidden="true"
          />
          <span
            v-if="folder.source_alive === true"
            class="size-2 shrink-0 rounded-full bg-n-teal-9"
            :title="t('JABVOX_DRIVE.FOLDER.SOURCE_ALIVE')"
            aria-hidden="true"
          />
          <span
            v-else-if="folder.source_alive === false"
            class="size-2 shrink-0 rounded-full bg-n-ruby-9"
            :title="t('JABVOX_DRIVE.FOLDER.SOURCE_GONE')"
            aria-hidden="true"
          />
          <span class="truncate text-sm font-medium text-n-slate-12">
            {{ folder.name }}
          </span>
        </span>
      </button>

      <!-- Archivos -->
      <div
        v-for="file in files"
        :key="`file-${file.id}`"
        class="group relative flex flex-col gap-2 rounded-xl border p-3 transition-colors"
        :class="
          isSelected(file.id)
            ? 'border-n-brand bg-n-brand/5'
            : 'border-n-weak bg-n-solid-1 hover:border-n-brand/40 hover:bg-n-alpha-1'
        "
      >
        <div class="flex items-center justify-between">
          <input
            v-if="canManage"
            type="checkbox"
            class="size-4 rounded border-n-weak accent-n-brand"
            :checked="isSelected(file.id)"
            :aria-label="
              t('JABVOX_DRIVE.BULK.SELECT_FILE', { name: file.filename })
            "
            @change="emit('toggleSelect', file.id)"
          />
          <FileActionsMenu
            :file="file"
            :can-manage="canManage"
            @preview="emit('preview', $event)"
            @download="emit('download', $event)"
            @rename="emit('rename', $event)"
            @move="emit('move', $event)"
            @delete="emit('delete', $event)"
            @go-to-conversation="emit('goToConversation', $event)"
          />
        </div>
        <button
          type="button"
          class="relative flex flex-1 flex-col items-center gap-2 py-2 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :aria-label="t('JABVOX_DRIVE.FILE.PREVIEW')"
          @click="emit('preview', file)"
        >
          <span
            class="size-9 text-n-slate-11"
            :class="[iconForFile(file), statusBadge(file) ? 'opacity-40' : '']"
            aria-hidden="true"
          />
          <span
            v-if="statusBadge(file)"
            class="i-lucide-cloud-off absolute right-1 top-1 size-4 text-amber-500"
            aria-hidden="true"
          />
        </button>
        <div class="min-w-0">
          <p
            class="truncate text-sm font-medium text-n-slate-12"
            :title="file.filename"
          >
            {{ file.filename }}
          </p>
          <p class="truncate text-[11px] text-n-slate-10">
            {{ humanSize(file.byte_size) }} · {{ formatDate(file.created_at) }}
          </p>
          <span
            v-if="statusBadge(file)"
            class="mt-1 inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-medium"
            :class="
              statusBadge(file).tone === 'amber'
                ? 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-400'
                : statusBadge(file).tone === 'red'
                  ? 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-400'
                  : 'bg-n-alpha-2 text-n-slate-11'
            "
          >
            {{ statusBadge(file).label }}
          </span>
        </div>
      </div>
    </div>
  </div>

  <!-- Vista de lista -->
  <div
    v-else
    class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1"
  >
    <table class="w-full text-sm sm:min-w-[36rem]">
      <thead>
        <tr class="border-b border-n-weak text-left text-xs text-n-slate-10">
          <th class="w-10 px-3 py-2">
            <input
              v-if="canManage && files.length"
              type="checkbox"
              class="size-4 rounded border-n-weak accent-n-brand align-middle"
              :checked="allSelected"
              :indeterminate="someSelected"
              :aria-label="t('JABVOX_DRIVE.BULK.SELECT_ALL')"
              @change="emit('toggleSelectAll')"
            />
          </th>
          <th class="px-3 py-2 font-medium">
            {{ t('JABVOX_DRIVE.COLUMNS.NAME') }}
          </th>
          <th class="hidden px-3 py-2 font-medium sm:table-cell">
            {{ t('JABVOX_DRIVE.COLUMNS.TYPE') }}
          </th>
          <th class="hidden px-3 py-2 font-medium sm:table-cell">
            {{ t('JABVOX_DRIVE.COLUMNS.SIZE') }}
          </th>
          <th class="hidden px-3 py-2 font-medium md:table-cell">
            {{ t('JABVOX_DRIVE.COLUMNS.DATE') }}
          </th>
          <th class="w-10 px-3 py-2" />
        </tr>
      </thead>
      <tbody>
        <!-- Carpetas -->
        <tr
          v-for="folder in folders"
          :key="`rowfolder-${folder.id}`"
          class="cursor-pointer border-b border-n-weak transition-colors hover:bg-n-alpha-1"
          @click="emit('openFolder', folder)"
        >
          <td class="px-3 py-2">
            <span
              :class="
                contactFolders ? 'i-lucide-user-round' : 'i-lucide-folder'
              "
              class="size-5 text-n-brand"
              aria-hidden="true"
            />
          </td>
          <td class="px-3 py-2 font-medium text-n-slate-12">
            <span class="flex items-center gap-1 min-w-0">
              <span
                v-if="folder.system_folder"
                class="i-lucide-star size-3.5 shrink-0 text-amber-500"
                :title="t('JABVOX_DRIVE.FOLDER.SYSTEM_FOLDER')"
                aria-hidden="true"
              />
              <span
                v-if="folder.source_alive === true"
                class="size-2 shrink-0 rounded-full bg-n-teal-9"
                :title="t('JABVOX_DRIVE.FOLDER.SOURCE_ALIVE')"
                aria-hidden="true"
              />
              <span
                v-else-if="folder.source_alive === false"
                class="size-2 shrink-0 rounded-full bg-n-ruby-9"
                :title="t('JABVOX_DRIVE.FOLDER.SOURCE_GONE')"
                aria-hidden="true"
              />
              <span class="truncate">{{ folder.name }}</span>
            </span>
          </td>
          <td class="hidden px-3 py-2 text-n-slate-10 sm:table-cell">—</td>
          <td class="hidden px-3 py-2 text-n-slate-10 sm:table-cell">—</td>
          <td class="hidden px-3 py-2 text-n-slate-10 md:table-cell">—</td>
          <td class="px-3 py-2" @click.stop>
            <FolderActionsMenu
              v-if="canManage && !folder.system_folder"
              :folder="folder"
              @rename="emit('renameFolder', $event)"
              @delete="emit('deleteFolder', $event)"
            />
          </td>
        </tr>

        <!-- Archivos -->
        <tr
          v-for="file in files"
          :key="`rowfile-${file.id}`"
          class="border-b border-n-weak transition-colors"
          :class="isSelected(file.id) ? 'bg-n-brand/5' : 'hover:bg-n-alpha-1'"
        >
          <td class="px-3 py-2">
            <input
              v-if="canManage"
              type="checkbox"
              class="size-4 rounded border-n-weak accent-n-brand"
              :checked="isSelected(file.id)"
              :aria-label="
                t('JABVOX_DRIVE.BULK.SELECT_FILE', { name: file.filename })
              "
              @change="emit('toggleSelect', file.id)"
            />
          </td>
          <td class="px-3 py-2">
            <button
              type="button"
              class="flex items-center gap-2 text-left rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
              @click="emit('preview', file)"
            >
              <span
                :class="iconForFile(file)"
                class="size-5 text-n-slate-11 shrink-0"
                aria-hidden="true"
              />
              <span class="truncate font-medium text-n-slate-12">
                {{ file.filename }}
              </span>
            </button>
          </td>
          <td class="hidden px-3 py-2 text-n-slate-11 sm:table-cell">
            {{ categoryLabel(file) }}
          </td>
          <td class="hidden px-3 py-2 text-n-slate-11 sm:table-cell">
            {{ humanSize(file.byte_size) }}
          </td>
          <td class="hidden px-3 py-2 text-n-slate-11 md:table-cell">
            {{ formatDate(file.created_at) }}
          </td>
          <td class="px-3 py-2">
            <FileActionsMenu
              :file="file"
              :can-manage="canManage"
              @preview="emit('preview', $event)"
              @download="emit('download', $event)"
              @rename="emit('rename', $event)"
              @move="emit('move', $event)"
              @delete="emit('delete', $event)"
              @go-to-conversation="emit('goToConversation', $event)"
            />
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
