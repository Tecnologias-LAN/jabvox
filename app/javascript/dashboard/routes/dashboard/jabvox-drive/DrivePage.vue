<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import driveAPI from 'dashboard/api/jabvox/drive';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

import StorageBar from './components/StorageBar.vue';
import DriveToolbar from './components/DriveToolbar.vue';
import DriveItems from './components/DriveItems.vue';
import BulkActionsBar from './components/BulkActionsBar.vue';
import FilePreviewModal from './components/FilePreviewModal.vue';
import FolderFormDialog from './components/FolderFormDialog.vue';
import RenameFileDialog from './components/RenameFileDialog.vue';
import MoveFileDialog from './components/MoveFileDialog.vue';
import UploadDialog from './components/UploadDialog.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const accountId = useMapGetter('getCurrentAccountId');
const currentRole = useMapGetter('getCurrentRole');

// --- Estado de navegación ---
const currentFolderId = computed(() =>
  route.params.folderId ? Number(route.params.folderId) : null
);
const currentContactId = computed(() =>
  route.params.contactId ? Number(route.params.contactId) : null
);

// Pila de breadcrumb (label + params de ruta). Se mantiene en memoria al navegar.
const folderTrail = ref([]);

// --- Filtros ---
const query = ref('');
const typeFilter = ref('');
const fromFilter = ref('');
const toFilter = ref('');
const viewMode = ref('grid');
const page = ref(1);

// --- Selección múltiple ---
const selectedIds = ref([]);

// --- Getters del store ---
const folders = useMapGetter('jabvoxDrive/getFolders');
const files = useMapGetter('jabvoxDrive/getFiles');
const storage = useMapGetter('jabvoxDrive/getStorage');
const meta = useMapGetter('jabvoxDrive/getMeta');
const uiFlags = useMapGetter('jabvoxDrive/getUIFlags');

const isAdmin = computed(() => currentRole.value === 'administrator');
// RBAC: solo los administradores GESTIONAN el Drive (subir, eliminar, renombrar,
// mover, papelera, historial). Los agentes y roles personalizados solo ven y
// descargan. El backend lo exige igual (Pundit); esto oculta los controles para que
// no aparezcan acciones que el servidor va a rechazar.
const canManage = computed(() => isAdmin.value);

const goToHistory = () => {
  router.push({
    name: 'jabvox_drive_history',
    params: { accountId: accountId.value },
  });
};

const goToTrash = () => {
  router.push({
    name: 'jabvox_drive_trash',
    params: { accountId: accountId.value },
  });
};

const isLoading = computed(
  () => uiFlags.value.isFetchingFolders || uiFlags.value.isFetchingFiles
);

const isEmpty = computed(() => !folders.value.length && !files.value.length);
const hasActiveFilters = computed(
  () =>
    !!(query.value || typeFilter.value || fromFilter.value || toFilter.value)
);

// Las carpetas representan contactos cuando estamos dentro de "Contactos/".
const isContactsRoot = computed(() => !!currentContactId.value);

// Nombre del contacto para el breadcrumb de la carpeta "Contactos/<nombre>".
const contactGetter = useMapGetter('contacts/getContact');
const contactName = computed(() => {
  if (!currentContactId.value) return '';
  const contact = contactGetter.value?.(currentContactId.value);
  return contact?.name || `#${currentContactId.value}`;
});

// Breadcrumb visible.
const breadcrumb = computed(() => {
  const crumbs = [
    { label: t('JABVOX_DRIVE.ROOT'), routeName: 'jabvox_drive_index' },
  ];
  if (currentContactId.value) {
    crumbs.push({
      label: t('JABVOX_DRIVE.CONTACTS_FOLDER'),
      routeName: 'jabvox_drive_index',
    });
    crumbs.push({
      label: contactName.value,
      routeName: 'jabvox_drive_contact',
      params: { contactId: currentContactId.value },
    });
  } else {
    folderTrail.value.forEach(folder => {
      crumbs.push({
        label: folder.name,
        routeName: 'jabvox_drive_folder',
        params: { folderId: folder.id },
      });
    });
  }
  return crumbs;
});

// --- Dialog refs ---
const folderDialog = ref(null);
const renameFileDialog = ref(null);
const moveFileDialog = ref(null);
const uploadDialog = ref(null);
const deleteDialog = ref(null);

const editingFolder = ref(null);
const editingFile = ref(null);
const movingFile = ref(null); // archivo único o null (masivo)
const pendingDelete = ref(null); // { kind: 'file'|'folder'|'bulk', payload }
const uploadProgress = ref(0);
const previewFile = ref(null);

// --- Carga de datos ---
const fetchData = async () => {
  selectedIds.value = [];
  const folderParams = {
    parentId: currentFolderId.value,
    contactId: currentContactId.value,
    // Con texto de búsqueda, el backend filtra carpetas por nombre en toda la cuenta.
    query: query.value,
  };
  const fileParams = {
    folderId: currentFolderId.value,
    contactId: currentContactId.value,
    query: query.value,
    type: typeFilter.value,
    from: fromFilter.value,
    to: toFilter.value,
    page: page.value,
  };
  try {
    await Promise.all([
      store.dispatch('jabvoxDrive/fetchFolders', folderParams),
      store.dispatch('jabvoxDrive/fetchFiles', fileParams),
    ]);
  } catch {
    useAlert(t('JABVOX_DRIVE.ERROR'));
  }
};

const fetchStorage = async () => {
  try {
    await store.dispatch('jabvoxDrive/fetchStorage');
  } catch {
    // La cuota es informativa; un fallo no bloquea la UI.
  }
};

// Recarga cuando cambia la ruta (carpeta/contacto).
watch(
  () => [currentFolderId.value, currentContactId.value],
  () => {
    page.value = 1;
    fetchData();
  }
);

// Recarga con debounce ligero al cambiar filtros.
let filterTimer = null;
watch([query, typeFilter, fromFilter, toFilter], () => {
  page.value = 1;
  clearTimeout(filterTimer);
  filterTimer = setTimeout(fetchData, 300);
});

watch(page, fetchData);

// --- Navegación ---
const openFolder = folder => {
  folderTrail.value = [...folderTrail.value, folder];
  router.push({
    name: 'jabvox_drive_folder',
    params: { accountId: accountId.value, folderId: folder.id },
  });
};

const navigateCrumb = crumb => {
  if (crumb.routeName === 'jabvox_drive_index') {
    folderTrail.value = [];
    router.push({
      name: 'jabvox_drive_index',
      params: { accountId: accountId.value },
    });
    return;
  }
  // Recorta la pila hasta la carpeta pulsada.
  const idx = folderTrail.value.findIndex(f => f.id === crumb.params?.folderId);
  if (idx !== -1) {
    folderTrail.value = folderTrail.value.slice(0, idx + 1);
  }
  router.push({
    name: crumb.routeName,
    params: { accountId: accountId.value, ...crumb.params },
  });
};

const clearFilters = () => {
  typeFilter.value = '';
  fromFilter.value = '';
  toFilter.value = '';
};

// --- Selección ---
const toggleSelect = id => {
  const idx = selectedIds.value.indexOf(id);
  if (idx === -1) selectedIds.value.push(id);
  else selectedIds.value.splice(idx, 1);
};
// Alterna "seleccionar todo" sobre los archivos visibles del nivel actual.
const toggleSelectAll = () => {
  const allIds = files.value.map(f => f.id);
  const everySelected =
    allIds.length > 0 && allIds.every(id => selectedIds.value.includes(id));
  selectedIds.value = everySelected ? [] : allIds;
};
const clearSelection = () => {
  selectedIds.value = [];
};

// --- Preview / descarga ---
const openPreview = file => {
  previewFile.value = file;
};
const closePreview = () => {
  previewFile.value = null;
};
const downloadFile = file => {
  window.open(driveAPI.downloadUrl(file.id), '_blank');
};
const goToConversation = file => {
  if (!file.conversation_id) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: file.conversation_id,
    },
  });
};

// --- Carpetas: crear / renombrar / eliminar ---
const openCreateFolder = () => {
  editingFolder.value = null;
  folderDialog.value?.open();
};
const openRenameFolder = folder => {
  editingFolder.value = folder;
  folderDialog.value?.open();
};
const onFolderSubmit = async ({ name }) => {
  try {
    if (editingFolder.value) {
      await store.dispatch('jabvoxDrive/renameFolder', {
        id: editingFolder.value.id,
        name,
      });
      useAlert(t('JABVOX_DRIVE.FOLDER.RENAMED'));
    } else {
      await store.dispatch('jabvoxDrive/createFolder', {
        name,
        parentId: currentFolderId.value,
      });
      useAlert(t('JABVOX_DRIVE.FOLDER.CREATED'));
    }
    folderDialog.value?.close();
  } catch {
    useAlert(
      editingFolder.value
        ? t('JABVOX_DRIVE.FOLDER.RENAME_ERROR')
        : t('JABVOX_DRIVE.FOLDER.CREATE_ERROR')
    );
  }
};

const requestDeleteFolder = folder => {
  pendingDelete.value = { kind: 'folder', payload: folder };
  deleteDialog.value?.open();
};

// --- Archivos: renombrar / mover / eliminar ---
const openRenameFile = file => {
  editingFile.value = file;
  renameFileDialog.value?.open();
};
const onRenameFileSubmit = async ({ filename }) => {
  try {
    await store.dispatch('jabvoxDrive/updateFile', {
      id: editingFile.value.id,
      filename,
    });
    useAlert(t('JABVOX_DRIVE.FILE.RENAMED'));
    renameFileDialog.value?.close();
  } catch {
    useAlert(t('JABVOX_DRIVE.FILE.RENAME_ERROR'));
  }
};

const openMoveFile = file => {
  movingFile.value = file;
  moveFileDialog.value?.open();
};
const openBulkMove = () => {
  movingFile.value = null;
  moveFileDialog.value?.open();
};
const onMoveSubmit = async ({ folderId }) => {
  try {
    if (movingFile.value) {
      await store.dispatch('jabvoxDrive/updateFile', {
        id: movingFile.value.id,
        folderId,
      });
      useAlert(t('JABVOX_DRIVE.FILE.MOVED'));
    } else {
      await store.dispatch('jabvoxDrive/bulkMoveFiles', {
        ids: [...selectedIds.value],
        folderId,
      });
      useAlert(t('JABVOX_DRIVE.BULK.MOVED'));
      clearSelection();
    }
    moveFileDialog.value?.close();
  } catch {
    useAlert(
      movingFile.value
        ? t('JABVOX_DRIVE.FILE.MOVE_ERROR')
        : t('JABVOX_DRIVE.BULK.MOVE_ERROR')
    );
  }
};

const requestDeleteFile = file => {
  pendingDelete.value = { kind: 'file', payload: file };
  deleteDialog.value?.open();
};
const requestBulkDelete = () => {
  pendingDelete.value = { kind: 'bulk', payload: [...selectedIds.value] };
  deleteDialog.value?.open();
};

const deleteTitle = computed(() => {
  if (pendingDelete.value?.kind === 'folder')
    return t('JABVOX_DRIVE.FOLDER.DELETE_TITLE');
  if (pendingDelete.value?.kind === 'bulk')
    return t('JABVOX_DRIVE.BULK.DELETE_TITLE');
  return t('JABVOX_DRIVE.FILE.DELETE_TITLE');
});
const deleteDescription = computed(() => {
  const d = pendingDelete.value;
  if (!d) return '';
  if (d.kind === 'folder')
    return t('JABVOX_DRIVE.FOLDER.DELETE_CONFIRM', { name: d.payload.name });
  if (d.kind === 'bulk')
    return t('JABVOX_DRIVE.BULK.DELETE_CONFIRM', { count: d.payload.length });
  return t('JABVOX_DRIVE.FILE.DELETE_CONFIRM', { name: d.payload.filename });
});

const confirmDelete = async () => {
  const d = pendingDelete.value;
  if (!d) return;
  try {
    if (d.kind === 'folder') {
      await store.dispatch('jabvoxDrive/deleteFolder', d.payload.id);
      useAlert(t('JABVOX_DRIVE.FOLDER.DELETED'));
    } else if (d.kind === 'bulk') {
      await store.dispatch('jabvoxDrive/bulkDeleteFiles', d.payload);
      useAlert(t('JABVOX_DRIVE.BULK.DELETED'));
      clearSelection();
    } else {
      await store.dispatch('jabvoxDrive/deleteFile', d.payload.id);
      useAlert(t('JABVOX_DRIVE.FILE.DELETED'));
    }
    deleteDialog.value?.close();
    fetchStorage();
  } catch {
    const deleteErrorKeys = {
      folder: 'JABVOX_DRIVE.FOLDER.DELETE_ERROR',
      bulk: 'JABVOX_DRIVE.BULK.DELETE_ERROR',
      file: 'JABVOX_DRIVE.FILE.DELETE_ERROR',
    };
    useAlert(t(deleteErrorKeys[d.kind] || deleteErrorKeys.file));
  } finally {
    pendingDelete.value = null;
  }
};

// --- Subida ---
const openUpload = () => {
  uploadProgress.value = 0;
  uploadDialog.value?.open();
};
const uploadOne = file =>
  store.dispatch('jabvoxDrive/uploadFile', {
    payload: {
      file,
      folderId: currentFolderId.value,
      contactId: currentContactId.value,
    },
    onUploadProgress: evt => {
      uploadProgress.value = evt.total
        ? Math.round((evt.loaded * 100) / evt.total)
        : 0;
    },
  });

const onUploadSubmit = async filesToUpload => {
  try {
    // Subida en serie para no saturar el ancho de banda ni la cuota.
    await filesToUpload.reduce(
      (chain, file) => chain.then(() => uploadOne(file)),
      Promise.resolve()
    );
    useAlert(t('JABVOX_DRIVE.UPLOAD.SUCCESS'));
    uploadDialog.value?.close();
    fetchData();
    fetchStorage();
  } catch (error) {
    const msg = /quota|cuota|space|espacio/i.test(error?.message || '')
      ? t('JABVOX_DRIVE.UPLOAD.QUOTA_EXCEEDED')
      : t('JABVOX_DRIVE.UPLOAD.ERROR');
    useAlert(msg);
  }
};

// --- Drag & drop a nivel de página ---
const isPageDragging = ref(false);
let dragDepth = 0;
const hasFiles = evt =>
  Array.from(evt.dataTransfer?.types || []).includes('Files');
const onPageDragEnter = evt => {
  if (!canManage.value || !hasFiles(evt)) return;
  dragDepth += 1;
  isPageDragging.value = true;
};
const onPageDragLeave = () => {
  dragDepth = Math.max(0, dragDepth - 1);
  if (dragDepth === 0) isPageDragging.value = false;
};
const onPageDrop = evt => {
  dragDepth = 0;
  isPageDragging.value = false;
  if (!canManage.value) return;
  const dropped = Array.from(evt.dataTransfer?.files || []);
  if (dropped.length) onUploadSubmit(dropped);
};

onMounted(() => {
  fetchData();
  fetchStorage();
});
</script>

<template>
  <div
    class="relative flex h-full w-full flex-col gap-4 overflow-hidden p-4"
    @dragenter.prevent="onPageDragEnter"
    @dragover.prevent
    @dragleave.prevent="onPageDragLeave"
    @drop.prevent="onPageDrop"
  >
    <!-- Overlay de arrastre: soltar archivos para subirlos -->
    <div
      v-if="isPageDragging && canManage"
      class="pointer-events-none absolute inset-2 z-40 flex flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-n-brand bg-n-brand/5 text-center"
    >
      <span
        class="i-lucide-upload-cloud size-10 text-n-brand"
        aria-hidden="true"
      />
      <p class="text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_DRIVE.UPLOAD.DROP_TO_UPLOAD') }}
      </p>
    </div>

    <!-- Encabezado del módulo -->
    <div class="flex items-center gap-3">
      <span
        class="i-lucide-hard-drive size-6 text-n-brand shrink-0"
        aria-hidden="true"
      />
      <div class="min-w-0">
        <h1 class="text-base font-semibold text-n-slate-12 truncate">
          {{ t('JABVOX_DRIVE.BRAND') }}
        </h1>
        <p class="text-xs text-n-slate-10 truncate">
          {{ t('JABVOX_DRIVE.BRAND_SUB') }}
        </p>
      </div>
      <!-- Papelera (solo administradores). -->
      <Button
        v-if="isAdmin"
        variant="ghost"
        size="sm"
        icon="i-lucide-trash-2"
        :label="t('JABVOX_DRIVE.TRASH.TITLE')"
        class="ml-auto shrink-0"
        @click="goToTrash"
      />
      <!-- Historial de actividad (solo administradores). -->
      <Button
        v-if="isAdmin"
        variant="ghost"
        size="sm"
        icon="i-lucide-history"
        :label="t('JABVOX_DRIVE.HISTORY.TITLE')"
        class="shrink-0"
        @click="goToHistory"
      />
    </div>

    <StorageBar :storage="storage" />

    <DriveToolbar
      :breadcrumb="breadcrumb"
      :query="query"
      :type="typeFilter"
      :from="fromFilter"
      :to="toFilter"
      :view-mode="viewMode"
      :can-manage="canManage"
      @update:query="query = $event"
      @update:type="typeFilter = $event"
      @update:from="fromFilter = $event"
      @update:to="toFilter = $event"
      @update:view-mode="viewMode = $event"
      @clear-filters="clearFilters"
      @upload="openUpload"
      @new-folder="openCreateFolder"
      @navigate="navigateCrumb"
    />

    <BulkActionsBar
      v-if="selectedIds.length"
      :count="selectedIds.length"
      @move="openBulkMove"
      @delete="requestBulkDelete"
      @clear="clearSelection"
    />

    <!-- Área scrollable: solo el contenido (carpetas/archivos) hace scroll; el
         encabezado, la cuota y la toolbar quedan fijos arriba. -->
    <div class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto">
      <!-- Carga -->
      <div
        v-if="isLoading"
        class="flex flex-1 items-center justify-center py-16"
      >
        <Spinner />
      </div>

      <!-- Estado vacío -->
      <div
        v-else-if="isEmpty"
        class="flex flex-1 flex-col items-center justify-center gap-3 py-16 text-center"
      >
        <span
          :class="
            hasActiveFilters ? 'i-lucide-search-x' : 'i-lucide-folder-open'
          "
          class="size-12 text-n-slate-9"
          aria-hidden="true"
        />
        <div>
          <p class="text-sm font-medium text-n-slate-12">
            {{
              hasActiveFilters
                ? t('JABVOX_DRIVE.EMPTY.NO_RESULTS_TITLE')
                : t('JABVOX_DRIVE.EMPTY.TITLE')
            }}
          </p>
          <p class="mt-1 text-sm text-n-slate-10">
            {{
              hasActiveFilters
                ? t('JABVOX_DRIVE.EMPTY.NO_RESULTS_BODY')
                : t('JABVOX_DRIVE.EMPTY.BODY')
            }}
          </p>
        </div>
        <Button
          v-if="canManage && !hasActiveFilters"
          color="blue"
          size="sm"
          icon="i-lucide-upload"
          :label="t('JABVOX_DRIVE.TOOLBAR.UPLOAD')"
          @click="openUpload"
        />
      </div>

      <!-- Contenido -->
      <template v-else>
        <DriveItems
          :folders="folders"
          :files="files"
          :view-mode="viewMode"
          :selected-ids="selectedIds"
          :can-manage="canManage"
          :contact-folders="isContactsRoot"
          @open-folder="openFolder"
          @rename-folder="openRenameFolder"
          @delete-folder="requestDeleteFolder"
          @toggle-select="toggleSelect"
          @toggle-select-all="toggleSelectAll"
          @preview="openPreview"
          @download="downloadFile"
          @rename="openRenameFile"
          @move="openMoveFile"
          @delete="requestDeleteFile"
          @go-to-conversation="goToConversation"
        />

        <!-- Paginación -->
        <div
          v-if="meta.totalPages > 1"
          class="flex items-center justify-center gap-3 pt-2"
        >
          <Button
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-chevron-left"
            :aria-label="t('JABVOX_DRIVE.PAGINATION.PREVIOUS')"
            :disabled="page <= 1"
            @click="page = Math.max(1, page - 1)"
          />
          <span class="text-sm text-n-slate-11">
            {{
              t('JABVOX_DRIVE.PAGINATION.PAGE_OF', {
                page,
                total: meta.totalPages,
              })
            }}
          </span>
          <Button
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-chevron-right"
            :aria-label="t('JABVOX_DRIVE.PAGINATION.NEXT')"
            :disabled="page >= meta.totalPages"
            @click="page = Math.min(meta.totalPages, page + 1)"
          />
        </div>
      </template>
    </div>

    <!-- Modales y diálogos -->
    <FilePreviewModal
      :file="previewFile"
      @close="closePreview"
      @download="downloadFile"
    />
    <FolderFormDialog
      ref="folderDialog"
      :folder="editingFolder"
      :is-loading="uiFlags.isFetchingFolders"
      @submit="onFolderSubmit"
    />
    <RenameFileDialog
      ref="renameFileDialog"
      :file="editingFile"
      @submit="onRenameFileSubmit"
    />
    <MoveFileDialog
      ref="moveFileDialog"
      :folders="folders"
      :count="movingFile ? 1 : selectedIds.length"
      @submit="onMoveSubmit"
    />
    <UploadDialog
      ref="uploadDialog"
      :is-loading="uiFlags.isUploading"
      :progress="uploadProgress"
      @submit="onUploadSubmit"
    />
    <ConfirmDialog
      ref="deleteDialog"
      :title="deleteTitle"
      :description="deleteDescription"
      :confirm-label="t('JABVOX_DRIVE.FILE.DELETE')"
      @confirm="confirmDelete"
    />
  </div>
</template>
