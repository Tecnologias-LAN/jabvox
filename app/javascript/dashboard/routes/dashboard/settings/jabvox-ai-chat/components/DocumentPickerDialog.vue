<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Bucket-file picker for AI Chat documents. Lists the bucket contents so the
// user chooses exactly which files to use (checkboxes). The account-level max
// (`limit`, 0 = unlimited) is the cap on how many can be selected — the picker
// blocks selecting beyond it, and the backend enforces it again on save.
const emit = defineEmits(['saved']);

const store = useStore();
const { t } = useI18n();

const open = ref(false);
const loading = ref(false);
const saving = ref(false);
const folders = ref([]);
const files = ref([]);
const limit = ref(0);
const search = ref('');
// Current folder prefix ('' = bucket root).
const prefix = ref('');
// Set of selected S3 keys (persists across folder navigation).
const selected = ref(new Set());

const atLimit = computed(
  () => limit.value > 0 && selected.value.size >= limit.value
);

const filteredFiles = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return files.value;
  return files.value.filter(f => f.name?.toLowerCase().includes(q));
});

// Breadcrumb segments from the current prefix (each with its own prefix path).
const breadcrumbs = computed(() => {
  const parts = prefix.value.split('/').filter(Boolean);
  let acc = '';
  return parts.map(part => {
    acc += `${part}/`;
    return { name: part, prefix: acc };
  });
});

// Display name of a folder prefix: its last path segment.
const folderName = folderPrefix =>
  folderPrefix.replace(/\/$/, '').split('/').pop();

const isSelected = key => selected.value.has(key);

const load = async () => {
  loading.value = true;
  try {
    const data = await store.dispatch('jabvoxAiChat/fetchBucketObjects', {
      prefix: prefix.value,
      search: search.value.trim(),
    });
    folders.value = data.folders || [];
    files.value = data.files || [];
    limit.value = Number(data.limit) || 0;
    // Merge already-selected files from this listing into the running set.
    (data.files || [])
      .filter(f => f.selected)
      .forEach(f => selected.value.add(f.key));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
    open.value = false;
  } finally {
    loading.value = false;
  }
};

// Enter a folder / jump via breadcrumb, then reload its contents.
const openFolder = async folderPrefix => {
  prefix.value = folderPrefix;
  search.value = '';
  await load();
};

const toggle = key => {
  const next = new Set(selected.value);
  if (next.has(key)) {
    next.delete(key);
  } else if (limit.value > 0 && next.size >= limit.value) {
    // At the cap: refuse to add more and tell the user why.
    useAlert(
      t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.LIMIT_REACHED', { limit: limit.value })
    );
    return;
  } else {
    next.add(key);
  }
  selected.value = next;
};

const openDialog = async () => {
  open.value = true;
  prefix.value = '';
  search.value = '';
  selected.value = new Set();
  await load();
};

const close = () => {
  open.value = false;
};

// Server-side search within the current folder.
const submitSearch = () => load();

const save = async () => {
  saving.value = true;
  try {
    await store.dispatch('jabvoxAiChat/saveDocuments', [...selected.value]);
    useAlert(t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.SAVED'));
    open.value = false;
    emit('saved');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  } finally {
    saving.value = false;
  }
};

// Reset search when reopened.
watch(open, isOpen => {
  if (!isOpen) search.value = '';
});

defineExpose({ openDialog });
</script>

<template>
  <teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      @click.self="close"
    >
      <div
        class="flex flex-col w-full max-w-2xl max-h-[85vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
      >
        <!-- Header -->
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <div class="min-w-0">
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{
                limit > 0
                  ? t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.SUBTITLE_LIMITED', {
                      selected: selected.size,
                      limit,
                    })
                  : t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.SUBTITLE', {
                      selected: selected.size,
                    })
              }}
            </p>
          </div>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            @click="close"
          />
        </div>

        <!-- Search + breadcrumb -->
        <div class="px-5 pt-4 flex flex-col gap-3">
          <div class="relative w-full">
            <Input
              v-model="search"
              :placeholder="t('JABVOX_AI_CHAT.DOCUMENTS.SEARCH_PLACEHOLDER')"
              custom-input-class="!pl-9"
              @keyup.enter="submitSearch"
            >
              <template #prefix>
                <span
                  class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                />
              </template>
            </Input>
          </div>
          <!-- Breadcrumb -->
          <div
            class="flex items-center gap-1 flex-wrap text-xs text-n-slate-11"
          >
            <button
              type="button"
              class="hover:text-n-slate-12 flex items-center gap-1"
              @click="openFolder('')"
            >
              <span class="i-lucide-hard-drive size-3.5" />
              {{ t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.ROOT') }}
            </button>
            <template v-for="crumb in breadcrumbs" :key="crumb.prefix">
              <span class="i-lucide-chevron-right size-3.5 text-n-slate-9" />
              <button
                type="button"
                class="hover:text-n-slate-12"
                @click="openFolder(crumb.prefix)"
              >
                {{ crumb.name }}
              </button>
            </template>
          </div>
        </div>

        <!-- Body -->
        <div class="flex-1 overflow-y-auto px-5 py-4">
          <div v-if="loading" class="flex items-center justify-center py-16">
            <Spinner :size="24" />
          </div>
          <div
            v-else-if="!folders.length && !filteredFiles.length"
            class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.EMPTY') }}
          </div>
          <div
            v-else
            class="rounded-xl border border-n-weak divide-y divide-n-weak overflow-hidden"
          >
            <!-- Folders -->
            <button
              v-for="folder in folders"
              :key="folder"
              type="button"
              class="w-full flex items-center gap-3 px-4 py-2.5 text-left hover:bg-n-alpha-1"
              @click="openFolder(folder)"
            >
              <span class="i-lucide-folder size-4 text-n-amber-9 shrink-0" />
              <span class="flex-1 min-w-0 text-sm text-n-slate-12 truncate">
                {{ folderName(folder) }}
              </span>
              <span
                class="i-lucide-chevron-right size-4 text-n-slate-9 shrink-0"
              />
            </button>
            <!-- Files -->
            <label
              v-for="file in filteredFiles"
              :key="file.key"
              class="flex items-center gap-3 px-4 py-2.5 cursor-pointer hover:bg-n-alpha-1"
              :class="{
                'opacity-50': atLimit && !isSelected(file.key),
              }"
            >
              <input
                type="checkbox"
                class="size-4 shrink-0 accent-n-brand"
                :checked="isSelected(file.key)"
                :disabled="atLimit && !isSelected(file.key)"
                @change="toggle(file.key)"
              />
              <span
                class="i-lucide-file-text size-4 text-n-slate-10 shrink-0"
              />
              <span class="flex-1 min-w-0 text-sm text-n-slate-12 truncate">
                {{ file.name }}
              </span>
            </label>
          </div>
        </div>

        <!-- Footer -->
        <div
          class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak"
        >
          <Button
            :label="t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.CANCEL')"
            variant="outline"
            color="slate"
            size="sm"
            @click="close"
          />
          <Button
            :label="t('JABVOX_AI_CHAT.DOCUMENTS.PICKER.SAVE')"
            size="sm"
            :is-loading="saving"
            :disabled="loading"
            @click="save"
          />
        </div>
      </div>
    </div>
  </teleport>
</template>
