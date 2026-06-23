<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import {
  aiChatModelsAPI,
  aiChatDocumentsAPI,
} from 'dashboard/api/jabvox/aiChat';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SectionCard from './components/SectionCard.vue';
import ModelFormDialog from './components/ModelFormDialog.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();
const { markDirty, markClean } = useUnsavedChanges();

const ACTIVE_TAB_KEY = 'jabvox_ai_chat_active_tab';
const BUCKET_FORM_KEY = 'jabvox_ai_chat_bucket_form';
const activeTab = ref(sessionStorage.getItem(ACTIVE_TAB_KEY) || 'models');

const tabs = [
  { key: 'models', icon: 'i-lucide-cpu' },
  { key: 'documents', icon: 'i-lucide-file-text' },
  { key: 'config', icon: 'i-lucide-settings-2' },
  { key: 'permissions', icon: 'i-lucide-shield-check' },
];

watch(activeTab, val => sessionStorage.setItem(ACTIVE_TAB_KEY, val), {
  flush: 'sync',
});

// ─── store ───
const models = computed(() => store.getters['jabvoxAiChat/getModels']);
const config = computed(() => store.getters['jabvoxAiChat/getConfig']);
const documents = computed(() => store.getters['jabvoxAiChat/getDocuments']);
const permissions = computed(
  () => store.getters['jabvoxAiChat/getPermissions']
);
const uiFlags = computed(() => store.getters['jabvoxAiChat/getUIFlags']);

// ─── models ───
const modelDialog = ref(null);
const deleteDialog = ref(null);
const testResults = ref({});
const testingId = ref(null);
const modelSearch = ref('');

const filteredModels = computed(() => {
  const q = modelSearch.value.trim().toLowerCase();
  if (!q) return models.value;
  return models.value.filter(
    m =>
      m.name_jabvox?.toLowerCase().includes(q) ||
      m.model_jabvox?.toLowerCase().includes(q) ||
      m.provider_jabvox?.toLowerCase().includes(q)
  );
});

const setDefault = id => store.dispatch('jabvoxAiChat/setDefaultModel', id);

const testConnection = async model => {
  testingId.value = model.id;
  testResults.value = { ...testResults.value, [model.id]: null };
  try {
    const { data } = await aiChatModelsAPI.testConnection(model.id);
    testResults.value = {
      ...testResults.value,
      [model.id]: { success: true, latency: data.latency_ms },
    };
  } catch (e) {
    const errorMessage =
      e?.response?.data?.error || e?.message || t('JABVOX_AI_CHAT.ERROR');
    testResults.value = {
      ...testResults.value,
      [model.id]: { success: false, error: errorMessage },
    };
  } finally {
    testingId.value = null;
  }
};

const askDeleteModel = model => {
  deleteDialog.value?.open({
    title: t('JABVOX_AI_CHAT.MODELS.DELETE_TITLE'),
    description: t('JABVOX_AI_CHAT.MODELS.DELETE_BODY', {
      name: model.name_jabvox,
    }),
    data: { kind: 'model', id: model.id },
  });
};

// ─── documents (bucket config + list) ───
const loadBucketFormFromStorage = () => {
  try {
    const saved = sessionStorage.getItem(BUCKET_FORM_KEY);
    return saved ? JSON.parse(saved) : null;
  } catch {
    return null;
  }
};
const savedBucket = loadBucketFormFromStorage();
const bucketForm = ref({
  bucket_url_jabvox: savedBucket?.bucket_url_jabvox || '',
  bucket_access_key_jabvox: savedBucket?.bucket_access_key_jabvox || '',
  bucket_secret_key_jabvox: '',
  bucket_region_jabvox: savedBucket?.bucket_region_jabvox || 'us-east-1',
  bucket_name_jabvox: savedBucket?.bucket_name_jabvox || '',
});
const showSecretKey = ref(false);
const docSearch = ref('');

watch(
  bucketForm,
  val => {
    markDirty();
    sessionStorage.setItem(
      BUCKET_FORM_KEY,
      JSON.stringify({
        bucket_url_jabvox: val.bucket_url_jabvox,
        bucket_access_key_jabvox: val.bucket_access_key_jabvox,
        bucket_region_jabvox: val.bucket_region_jabvox,
        bucket_name_jabvox: val.bucket_name_jabvox,
      })
    );
  },
  { deep: true, flush: 'sync' }
);

const filteredDocuments = computed(() => {
  const q = docSearch.value.trim().toLowerCase();
  if (!q) return documents.value;
  return documents.value.filter(d => d.name_jabvox?.toLowerCase().includes(q));
});

const saveBucketConfig = async () => {
  await store.dispatch('jabvoxAiChat/updateConfig', { ...bucketForm.value });
  sessionStorage.removeItem(BUCKET_FORM_KEY);
  await nextTick();
  markClean();
  useAlert(t('JABVOX_AI_CHAT.DOCUMENTS.SAVE_CONFIG'));
};

// Whether a bucket is configured (sync would fail without one).
const hasBucket = computed(() => !!config.value?.bucket_name_jabvox);

// Manual sync: surfaces errors and warns when the bucket has more files than
// the document limit allows (only the first N are imported).
const syncDocuments = async () => {
  try {
    const res = await store.dispatch('jabvoxAiChat/syncDocuments');
    if (res?.skipped > 0) {
      useAlert(
        t('JABVOX_AI_CHAT.DOCUMENTS.SYNC_TRUNCATED', {
          shown: res.limit,
          total: res.total_in_bucket,
        })
      );
    }
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  }
};

// Auto-sync the live bucket contents every time the Documents tab is opened,
// so the list reflects the real bucket instead of stale DB rows. Silently
// ignores errors (e.g. transient bucket issues) — the manual Sync button
// surfaces them. Only runs when a bucket is configured.
const autoSyncDocuments = async () => {
  if (!hasBucket.value) return;
  try {
    await store.dispatch('jabvoxAiChat/syncDocuments');
  } catch {
    // keep whatever is in the list; manual sync reports the error
  }
};

watch(activeTab, tab => {
  if (tab === 'documents') autoSyncDocuments();
});

const toggleDocument = doc =>
  store.dispatch('jabvoxAiChat/toggleDocument', {
    id: doc.id,
    is_enabled_jabvox: !doc.is_enabled_jabvox,
  });

const askDeleteDocument = doc => {
  deleteDialog.value?.open({
    title: t('JABVOX_AI_CHAT.DOCUMENTS.DELETE_TITLE'),
    description: t('JABVOX_AI_CHAT.DOCUMENTS.DELETE_BODY', {
      name: doc.name_jabvox,
    }),
    data: { kind: 'document', id: doc.id },
  });
};

// ─── config ───
const configForm = ref({ web_search_enabled_jabvox: false });
watch(configForm, () => markDirty(), { deep: true });

const saveConfig = async () => {
  await store.dispatch('jabvoxAiChat/updateConfig', { ...configForm.value });
  await nextTick();
  markClean();
  useAlert(t('JABVOX_AI_CHAT.CONFIG.SAVE'));
};

// ─── permissions ───
const localPermissions = ref([]);
const permSearch = ref('');
const permDirty = ref(false);

watch(
  permissions,
  async val => {
    localPermissions.value = val.map(p => ({ ...p }));
    permDirty.value = false;
    await nextTick();
    markClean();
  },
  { immediate: true }
);

const filteredPermissions = computed(() => {
  const q = permSearch.value.trim().toLowerCase();
  if (!q) return localPermissions.value;
  return localPermissions.value.filter(
    p => p.name?.toLowerCase().includes(q) || p.email?.toLowerCase().includes(q)
  );
});

const onPermissionChange = () => {
  permDirty.value = true;
  markDirty();
};

const savePermissions = async () => {
  await store.dispatch('jabvoxAiChat/savePermissions', localPermissions.value);
  permDirty.value = false;
  await nextTick();
  markClean();
  useAlert(t('JABVOX_AI_CHAT.PERMISSIONS.SAVED'));
};

// ─── shared delete handler ───
const onConfirmDelete = async ({ kind, id }) => {
  try {
    if (kind === 'model') {
      await store.dispatch('jabvoxAiChat/deleteModel', id);
    } else {
      // Documents have no store action — call the API directly then refetch.
      await aiChatDocumentsAPI.destroy(id);
      await store.dispatch('jabvoxAiChat/fetchDocuments');
    }
  } catch {
    useAlert(t('JABVOX_AI_CHAT.ERROR'));
  }
};

// ─── helpers ───
const formatBytes = bytes => {
  if (!bytes) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  let val = bytes;
  while (val >= 1024 && i < units.length - 1) {
    val /= 1024;
    i += 1;
  }
  return `${val.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
};

onMounted(async () => {
  store.dispatch('jabvoxAiChat/fetchModels');
  store.dispatch('jabvoxAiChat/fetchDocuments');
  store.dispatch('jabvoxAiChat/fetchPermissions');
  await store.dispatch('jabvoxAiChat/fetchConfig');
  if (!config.value) return;
  if (!savedBucket) {
    bucketForm.value.bucket_url_jabvox = config.value.bucket_url_jabvox || '';
    bucketForm.value.bucket_access_key_jabvox =
      config.value.bucket_access_key_jabvox || '';
    bucketForm.value.bucket_name_jabvox = config.value.bucket_name_jabvox || '';
    bucketForm.value.bucket_region_jabvox =
      config.value.bucket_region_jabvox || 'us-east-1';
  }
  configForm.value.web_search_enabled_jabvox =
    config.value.web_search_enabled_jabvox;
  await nextTick();
  markClean();
  // Live-sync the bucket if we land directly on the Documents tab.
  if (activeTab.value === 'documents') autoSyncDocuments();
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-sparkles size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_AI_CHAT.SUBTITLE') }}
            </p>
          </div>
        </div>
        <Button
          v-if="activeTab === 'models'"
          :label="t('JABVOX_AI_CHAT.MODELS.ADD')"
          icon="i-lucide-plus"
          class="shrink-0"
          @click="modelDialog?.openCreate()"
        />
      </div>

      <!-- Tabs -->
      <div
        class="flex items-center gap-1 p-1 rounded-xl bg-n-alpha-1 border border-n-weak w-full sm:w-fit overflow-x-auto"
      >
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition-colors flex-1 sm:flex-none focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            activeTab === tab.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          <span :class="tab.icon" class="size-4 shrink-0" />
          {{ t(`JABVOX_AI_CHAT.TABS.${tab.key.toUpperCase()}`) }}
        </button>
      </div>

      <!-- ── MODELS ── -->
      <div v-if="activeTab === 'models'" class="flex flex-col gap-5">
        <div
          v-if="uiFlags.isFetchingModels"
          class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
        >
          <Spinner :size="18" />
        </div>

        <EmptyStateLayout
          v-else-if="!models.length"
          :title="t('JABVOX_AI_CHAT.MODELS.EMPTY_TITLE')"
          :subtitle="t('JABVOX_AI_CHAT.MODELS.EMPTY')"
        >
          <template #actions>
            <Button
              icon="i-lucide-plus"
              :label="t('JABVOX_AI_CHAT.MODELS.ADD')"
              size="sm"
              @click="modelDialog?.openCreate()"
            />
          </template>
        </EmptyStateLayout>

        <template v-else>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="relative w-full sm:w-64">
              <Input
                v-model="modelSearch"
                :placeholder="t('JABVOX_AI_CHAT.MODELS.SEARCH_PLACEHOLDER')"
                custom-input-class="!pl-9"
              >
                <template #prefix>
                  <span
                    class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                  />
                </template>
              </Input>
            </div>
            <span class="text-xs text-n-slate-10">
              {{ t('JABVOX_AI_CHAT.MODELS.COUNT', { count: models.length }) }}
            </span>
          </div>

          <div
            v-if="!filteredModels.length"
            class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_AI_CHAT.MODELS.NO_RESULTS') }}
          </div>

          <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div
              v-for="model in filteredModels"
              :key="model.id"
              class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm transition-shadow hover:shadow-md"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="flex items-center gap-2 min-w-0">
                  <span class="i-lucide-cpu size-4 text-n-slate-10 shrink-0" />
                  <p class="text-sm font-semibold text-n-slate-12 truncate">
                    {{ model.name_jabvox }}
                  </p>
                </div>
                <Label
                  v-if="model.is_default_jabvox"
                  :label="t('JABVOX_AI_CHAT.MODELS.DEFAULT_BADGE')"
                  color="teal"
                  compact
                />
              </div>

              <p
                class="flex items-center gap-1.5 text-xs text-n-slate-11 font-mono truncate"
              >
                <span v-if="model.provider_jabvox" class="text-n-slate-12">
                  {{ model.provider_jabvox }}
                </span>
                <span
                  v-if="model.provider_jabvox"
                  class="size-1 rounded-full bg-n-slate-8 shrink-0"
                />
                <span class="truncate">{{ model.model_jabvox }}</span>
              </p>

              <!-- Test result -->
              <div
                v-if="testResults[model.id]"
                class="text-xs"
                :class="
                  testResults[model.id].success
                    ? 'text-n-teal-11'
                    : 'text-n-ruby-11'
                "
              >
                <span
                  v-if="testResults[model.id].success"
                  class="inline-flex items-center gap-1"
                >
                  <span class="i-lucide-check size-3.5" />
                  {{
                    t('JABVOX_AI_CHAT.MODELS.TEST_LATENCY', {
                      ms: testResults[model.id].latency,
                    })
                  }}
                </span>
                <span v-else class="inline-flex items-center gap-1">
                  <span class="i-lucide-circle-x size-3.5" />
                  {{ testResults[model.id].error }}
                </span>
              </div>

              <div class="flex items-center gap-1 pt-2 border-t border-n-weak">
                <Button
                  :label="
                    testingId === model.id
                      ? t('JABVOX_AI_CHAT.MODELS.TESTING')
                      : t('JABVOX_AI_CHAT.MODELS.TEST')
                  "
                  icon="i-lucide-plug-zap"
                  variant="outline"
                  color="slate"
                  size="sm"
                  :is-loading="testingId === model.id"
                  @click="testConnection(model)"
                />
                <Button
                  v-if="!model.is_default_jabvox"
                  :label="t('JABVOX_AI_CHAT.MODELS.SET_DEFAULT')"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="setDefault(model.id)"
                />
                <div class="flex-1" />
                <Button
                  icon="i-lucide-pencil"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  :title="t('JABVOX_AI_CHAT.MODELS.EDIT')"
                  @click="modelDialog?.openEdit(model)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  :title="t('JABVOX_AI_CHAT.COMMON.DELETE')"
                  @click="askDeleteModel(model)"
                />
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- ── DOCUMENTS ── -->
      <div v-else-if="activeTab === 'documents'" class="flex flex-col gap-6">
        <!-- Bucket config -->
        <SectionCard
          :title="t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_CONFIG')"
          :description="t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_SECTION_DESC')"
          icon="i-lucide-database"
        >
          <div class="flex flex-col gap-4">
            <Input
              v-model="bucketForm.bucket_url_jabvox"
              :label="t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_URL')"
              :placeholder="
                t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_URL_PLACEHOLDER')
              "
            />
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Input
                v-model="bucketForm.bucket_access_key_jabvox"
                :label="t('JABVOX_AI_CHAT.DOCUMENTS.ACCESS_KEY')"
                custom-input-class="font-mono"
              />
              <div class="flex flex-col gap-1.5">
                <label class="text-sm font-medium text-n-slate-12">
                  {{ t('JABVOX_AI_CHAT.DOCUMENTS.SECRET_KEY') }}
                </label>
                <div class="relative">
                  <Input
                    v-model="bucketForm.bucket_secret_key_jabvox"
                    :type="showSecretKey ? 'text' : 'password'"
                    custom-input-class="!pr-10 font-mono"
                    :placeholder="
                      t('JABVOX_AI_CHAT.DOCUMENTS.SECRET_KEY_PLACEHOLDER')
                    "
                  />
                  <button
                    type="button"
                    class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
                    @click="showSecretKey = !showSecretKey"
                  >
                    <span
                      :class="
                        showSecretKey ? 'i-lucide-eye-off' : 'i-lucide-eye'
                      "
                      class="size-4"
                    />
                  </button>
                </div>
              </div>
              <Input
                v-model="bucketForm.bucket_region_jabvox"
                :label="t('JABVOX_AI_CHAT.DOCUMENTS.REGION')"
              />
              <Input
                v-model="bucketForm.bucket_name_jabvox"
                :label="t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_NAME')"
              />
            </div>
          </div>
          <template #footer>
            <div class="flex flex-wrap items-center justify-end gap-2">
              <Button
                :label="
                  uiFlags.isSyncingDocuments
                    ? t('JABVOX_AI_CHAT.DOCUMENTS.SYNCING')
                    : t('JABVOX_AI_CHAT.DOCUMENTS.SYNC')
                "
                icon="i-lucide-refresh-cw"
                variant="outline"
                color="slate"
                size="sm"
                :is-loading="uiFlags.isSyncingDocuments"
                @click="syncDocuments"
              />
              <Button
                :label="t('JABVOX_AI_CHAT.DOCUMENTS.SAVE_CONFIG')"
                size="sm"
                :is-loading="uiFlags.isSavingConfig"
                @click="saveBucketConfig"
              />
            </div>
          </template>
        </SectionCard>

        <!-- Document list -->
        <div class="flex flex-col gap-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-2 min-w-0">
              <h2 class="text-base font-semibold text-n-slate-12">
                {{ t('JABVOX_AI_CHAT.DOCUMENTS.DOCUMENT_LIST') }}
              </h2>
              <span
                v-if="uiFlags.isSyncingDocuments"
                class="inline-flex items-center gap-1.5 text-xs text-n-slate-11"
              >
                <Spinner :size="14" />
                {{ t('JABVOX_AI_CHAT.DOCUMENTS.SYNCING') }}
              </span>
            </div>
            <span class="text-xs text-n-slate-10">
              {{
                t('JABVOX_AI_CHAT.DOCUMENTS.COUNT', { count: documents.length })
              }}
            </span>
          </div>

          <div v-if="documents.length" class="relative w-full sm:w-64">
            <Input
              v-model="docSearch"
              :placeholder="t('JABVOX_AI_CHAT.DOCUMENTS.SEARCH_PLACEHOLDER')"
              custom-input-class="!pl-9"
            >
              <template #prefix>
                <span
                  class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                />
              </template>
            </Input>
          </div>

          <div
            v-if="!documents.length"
            class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_AI_CHAT.DOCUMENTS.EMPTY') }}
          </div>
          <div
            v-else-if="!filteredDocuments.length"
            class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_AI_CHAT.DOCUMENTS.NO_RESULTS') }}
          </div>

          <div
            v-else
            class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm divide-y divide-n-weak overflow-hidden"
          >
            <div
              v-for="doc in filteredDocuments"
              :key="doc.id"
              class="flex items-center gap-3 px-4 py-3"
            >
              <span
                class="i-lucide-file-text size-5 text-n-slate-10 shrink-0"
              />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-n-slate-12 truncate">
                  {{ doc.name_jabvox }}
                </p>
                <p class="text-xs text-n-slate-10">
                  {{ formatBytes(doc.size_jabvox) }}
                </p>
              </div>
              <label
                class="flex items-center gap-2 cursor-pointer shrink-0"
                :title="
                  doc.is_enabled_jabvox
                    ? t('JABVOX_AI_CHAT.DOCUMENTS.DISABLE')
                    : t('JABVOX_AI_CHAT.DOCUMENTS.ENABLE')
                "
              >
                <Switch
                  :model-value="doc.is_enabled_jabvox"
                  @update:model-value="toggleDocument(doc)"
                />
              </label>
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="askDeleteDocument(doc)"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- ── CONFIG ── -->
      <div v-else-if="activeTab === 'config'" class="w-full max-w-2xl">
        <SectionCard
          :title="t('JABVOX_AI_CHAT.CONFIG.TITLE')"
          :description="t('JABVOX_AI_CHAT.CONFIG.SECTION_DESC')"
          icon="i-lucide-settings-2"
        >
          <div
            class="flex items-center justify-between gap-4 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
          >
            <div class="flex flex-col">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_AI_CHAT.CONFIG.WEB_SEARCH') }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t('JABVOX_AI_CHAT.CONFIG.WEB_SEARCH_DESC') }}
              </span>
            </div>
            <Switch v-model="configForm.web_search_enabled_jabvox" />
          </div>
          <template #footer>
            <div class="flex justify-end">
              <Button
                :label="t('JABVOX_AI_CHAT.CONFIG.SAVE')"
                size="sm"
                :is-loading="uiFlags.isSavingConfig"
                @click="saveConfig"
              />
            </div>
          </template>
        </SectionCard>
      </div>

      <!-- ── PERMISSIONS ── -->
      <div v-else class="flex flex-col gap-5">
        <div
          class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
        >
          <div>
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.PERMISSIONS.TITLE') }}
            </h2>
            <p class="mt-1 text-sm text-n-slate-11 max-w-2xl">
              {{ t('JABVOX_AI_CHAT.PERMISSIONS.DESC') }}
            </p>
          </div>
          <Button
            :label="t('JABVOX_AI_CHAT.PERMISSIONS.SAVE')"
            icon="i-lucide-save"
            size="sm"
            class="shrink-0"
            :disabled="!permDirty"
            :is-loading="uiFlags.isSavingPermissions"
            @click="savePermissions"
          />
        </div>

        <div class="relative w-full sm:w-64">
          <Input
            v-model="permSearch"
            :placeholder="t('JABVOX_AI_CHAT.PERMISSIONS.SEARCH_PLACEHOLDER')"
            custom-input-class="!pl-9"
          >
            <template #prefix>
              <span
                class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
              />
            </template>
          </Input>
        </div>

        <div
          v-if="!filteredPermissions.length"
          class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_AI_CHAT.PERMISSIONS.NO_RESULTS') }}
        </div>

        <!-- Desktop table -->
        <div
          v-else
          class="hidden md:block rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden overflow-x-auto"
        >
          <table class="min-w-full text-sm">
            <thead
              class="bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
            >
              <tr>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_AI_CHAT.PERMISSIONS.USER') }}
                </th>
                <th class="text-center px-4 py-2.5">
                  {{ t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE') }}
                </th>
                <th class="text-center px-4 py-2.5">
                  {{ t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE_MODELS') }}
                </th>
                <th class="text-center px-4 py-2.5">
                  {{ t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE_DOCUMENTS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="perm in filteredPermissions"
                :key="perm.user_id ?? perm.id"
                class="hover:bg-n-alpha-1 transition-colors"
              >
                <td class="px-4 py-3">
                  <div class="flex items-center gap-3 min-w-0">
                    <Avatar
                      :name="perm.name"
                      :src="perm.thumbnail"
                      :size="32"
                      rounded-full
                    />
                    <div class="min-w-0">
                      <p class="font-medium text-n-slate-12 truncate">
                        {{ perm.name }}
                      </p>
                      <p class="text-xs text-n-slate-10 truncate">
                        {{ perm.email }}
                      </p>
                    </div>
                  </div>
                </td>
                <td class="px-4 py-3">
                  <div class="flex justify-center">
                    <Switch
                      v-model="perm.can_use"
                      @update:model-value="onPermissionChange"
                    />
                  </div>
                </td>
                <td class="px-4 py-3">
                  <div class="flex justify-center">
                    <Switch
                      v-model="perm.can_use_models"
                      @update:model-value="onPermissionChange"
                    />
                  </div>
                </td>
                <td class="px-4 py-3">
                  <div class="flex justify-center">
                    <Switch
                      v-model="perm.can_use_documents"
                      @update:model-value="onPermissionChange"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Mobile cards -->
        <div
          v-if="filteredPermissions.length"
          class="flex flex-col gap-3 md:hidden"
        >
          <div
            v-for="perm in filteredPermissions"
            :key="perm.user_id ?? perm.id"
            class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <div class="flex items-center gap-3 min-w-0">
              <Avatar
                :name="perm.name"
                :src="perm.thumbnail"
                :size="36"
                rounded-full
              />
              <div class="min-w-0">
                <p class="text-sm font-medium text-n-slate-12 truncate">
                  {{ perm.name }}
                </p>
                <p class="text-xs text-n-slate-10 truncate">{{ perm.email }}</p>
              </div>
            </div>
            <div class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-3">
              <label class="flex items-center justify-between gap-2">
                <span class="text-sm text-n-slate-12">{{
                  t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE')
                }}</span>
                <Switch
                  v-model="perm.can_use"
                  @update:model-value="onPermissionChange"
                />
              </label>
              <label class="flex items-center justify-between gap-2">
                <span class="text-sm text-n-slate-12">{{
                  t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE_MODELS')
                }}</span>
                <Switch
                  v-model="perm.can_use_models"
                  @update:model-value="onPermissionChange"
                />
              </label>
              <label class="flex items-center justify-between gap-2">
                <span class="text-sm text-n-slate-12">{{
                  t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE_DOCUMENTS')
                }}</span>
                <Switch
                  v-model="perm.can_use_documents"
                  @update:model-value="onPermissionChange"
                />
              </label>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Dialogs -->
    <ModelFormDialog ref="modelDialog" :is-saving="uiFlags.isSavingModel" />
    <ConfirmDialog ref="deleteDialog" @confirm="onConfirmDelete" />
  </div>
</template>
