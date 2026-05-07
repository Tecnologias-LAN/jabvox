<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import {
  aiChatModelsAPI,
  aiChatDocumentsAPI,
} from 'dashboard/api/jabvox/aiChat';

const store = useStore();
const { t } = useI18n();

const ACTIVE_TAB_KEY = 'jabvox_ai_chat_active_tab';
const BUCKET_FORM_KEY = 'jabvox_ai_chat_bucket_form';
const activeTab = ref(sessionStorage.getItem(ACTIVE_TAB_KEY) || 'models');
const tabs = ['models', 'documents', 'config', 'permissions'];

watch(activeTab, val => sessionStorage.setItem(ACTIVE_TAB_KEY, val), {
  flush: 'sync',
});

// Models
const showModelModal = ref(false);
const editingModel = ref(null);
const modelForm = ref({
  name_jabvox: '',
  provider_jabvox: '',
  model_jabvox: '',
  api_key_jabvox: '',
  base_url_jabvox: '',
  is_default_jabvox: false,
});
const testResults = ref({});
const testingId = ref(null);

// Documents
function loadBucketFormFromStorage() {
  try {
    const saved = sessionStorage.getItem(BUCKET_FORM_KEY);
    return saved ? JSON.parse(saved) : null;
  } catch {
    return null;
  }
}

const savedBucket = loadBucketFormFromStorage();
const bucketForm = ref({
  bucket_url_jabvox: savedBucket?.bucket_url_jabvox || '',
  bucket_access_key_jabvox: savedBucket?.bucket_access_key_jabvox || '',
  bucket_secret_key_jabvox: '',
  bucket_region_jabvox: savedBucket?.bucket_region_jabvox || 'us-east-1',
  bucket_name_jabvox: savedBucket?.bucket_name_jabvox || '',
});
const showSecretKey = ref(false);

watch(
  bucketForm,
  val => {
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

// Config
const configForm = ref({ web_search_enabled_jabvox: false });

// Permissions - local copy for editing
const localPermissions = ref([]);

const models = computed(() => store.getters['jabvoxAiChat/getModels']);
const config = computed(() => store.getters['jabvoxAiChat/getConfig']);
const documents = computed(() => store.getters['jabvoxAiChat/getDocuments']);
const permissions = computed(
  () => store.getters['jabvoxAiChat/getPermissions']
);
const uiFlags = computed(() => store.getters['jabvoxAiChat/getUIFlags']);

onMounted(async () => {
  store.dispatch('jabvoxAiChat/fetchModels');
  store.dispatch('jabvoxAiChat/fetchDocuments');
  store.dispatch('jabvoxAiChat/fetchPermissions');
  await store.dispatch('jabvoxAiChat/fetchConfig');
  if (!config.value) return;
  // Only fill from API when sessionStorage has no draft for this field
  const hasDraft = !!savedBucket;
  if (!hasDraft) {
    bucketForm.value.bucket_url_jabvox = config.value.bucket_url_jabvox || '';
    bucketForm.value.bucket_access_key_jabvox =
      config.value.bucket_access_key_jabvox || '';
    bucketForm.value.bucket_name_jabvox = config.value.bucket_name_jabvox || '';
    bucketForm.value.bucket_region_jabvox =
      config.value.bucket_region_jabvox || 'us-east-1';
  }
  configForm.value.web_search_enabled_jabvox =
    config.value.web_search_enabled_jabvox;
});

watch(
  permissions,
  val => {
    localPermissions.value = val.map(p => ({ ...p }));
  },
  { immediate: true }
);

function openAddModel() {
  editingModel.value = null;
  modelForm.value = {
    name_jabvox: '',
    provider_jabvox: '',
    model_jabvox: '',
    api_key_jabvox: '',
    base_url_jabvox: '',
    is_default_jabvox: false,
  };
  showModelModal.value = true;
}

function openEditModel(model) {
  editingModel.value = model;
  modelForm.value = {
    name_jabvox: model.name_jabvox,
    provider_jabvox: model.provider_jabvox || '',
    model_jabvox: model.model_jabvox,
    api_key_jabvox: '',
    base_url_jabvox: model.base_url_jabvox || '',
    is_default_jabvox: model.is_default_jabvox,
  };
  showModelModal.value = true;
}

function closeModelModal() {
  showModelModal.value = false;
}

async function saveModel() {
  const payload = { ...modelForm.value };
  if (!payload.api_key_jabvox) delete payload.api_key_jabvox;
  if (!payload.provider_jabvox) delete payload.provider_jabvox;
  if (editingModel.value) {
    await store.dispatch('jabvoxAiChat/updateModel', {
      id: editingModel.value.id,
      ...payload,
    });
  } else {
    await store.dispatch('jabvoxAiChat/createModel', payload);
  }
  closeModelModal();
}

async function deleteModel(id) {
  if (!window.confirm(t('JABVOX_AI_CHAT.MODELS.DELETE_CONFIRM'))) return;
  await store.dispatch('jabvoxAiChat/deleteModel', id);
}

async function setDefault(id) {
  await store.dispatch('jabvoxAiChat/setDefaultModel', id);
}

async function testConnection(model) {
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
}

async function saveBucketConfig() {
  const payload = { ...bucketForm.value };
  if (!payload.bucket_secret_key_jabvox)
    delete payload.bucket_secret_key_jabvox;
  await store.dispatch('jabvoxAiChat/updateConfig', payload);
  sessionStorage.removeItem(BUCKET_FORM_KEY);
}

async function syncDocuments() {
  await store.dispatch('jabvoxAiChat/syncDocuments');
}

async function toggleDocument(doc) {
  await store.dispatch('jabvoxAiChat/toggleDocument', {
    id: doc.id,
    is_enabled_jabvox: !doc.is_enabled_jabvox,
  });
}

async function deleteDocument(id) {
  if (!window.confirm(t('JABVOX_AI_CHAT.DOCUMENTS.DELETE_CONFIRM'))) return;
  await aiChatDocumentsAPI.destroy(id);
  await store.dispatch('jabvoxAiChat/fetchDocuments');
}

async function saveConfig() {
  await store.dispatch('jabvoxAiChat/updateConfig', configForm.value);
}

async function savePermissions() {
  await store.dispatch('jabvoxAiChat/savePermissions', localPermissions.value);
}

function formatBytes(bytes) {
  if (!bytes) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / k ** i).toFixed(1))} ${sizes[i]}`;
}
</script>

<template>
  <div class="flex-1 overflow-y-auto">
    <div class="max-w-5xl mx-auto p-8">
      <h1 class="text-2xl font-bold text-slate-800 mb-6">
        {{ t('JABVOX_AI_CHAT.TITLE') }} —
        {{ t('JABVOX_AI_CHAT.CONFIG_SIDEBAR_LABEL') }}
      </h1>

      <!-- Tabs -->
      <div class="border-b border-slate-200 mb-8">
        <nav class="flex gap-1">
          <button
            v-for="tab in tabs"
            :key="tab"
            class="px-4 py-2.5 text-sm font-medium border-b-2 transition-colors capitalize"
            :class="
              activeTab === tab
                ? 'border-violet-600 text-violet-600'
                : 'border-transparent text-slate-500 hover:text-slate-700'
            "
            @click="activeTab = tab"
          >
            {{ t(`JABVOX_AI_CHAT.TABS.${tab.toUpperCase()}`) }}
          </button>
        </nav>
      </div>

      <!-- MODELS TAB -->
      <div v-show="activeTab === 'models'">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-slate-700">
            {{ t('JABVOX_AI_CHAT.MODELS.TITLE') }}
          </h2>
          <button
            class="bg-violet-600 hover:bg-violet-700 text-white px-4 py-2 rounded-lg text-sm font-medium flex items-center gap-2 transition-colors"
            @click="openAddModel"
          >
            <span class="i-ri-add-line" />
            {{ t('JABVOX_AI_CHAT.MODELS.ADD') }}
          </button>
        </div>
        <div
          v-if="models.length === 0"
          class="text-center py-12 text-slate-400 text-sm"
        >
          {{ t('JABVOX_AI_CHAT.MODELS.EMPTY') }}
        </div>
        <div v-else class="space-y-3">
          <div
            v-for="model in models"
            :key="model.id"
            class="bg-white border border-slate-200 rounded-xl p-4 flex items-center justify-between shadow-sm"
          >
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="font-medium text-slate-800 text-sm">{{
                  model.name_jabvox
                }}</span>
                <span
                  v-if="model.is_default_jabvox"
                  class="bg-violet-100 text-violet-700 text-xs px-2 py-0.5 rounded-full font-medium"
                  >{{ t('JABVOX_AI_CHAT.MODELS.DEFAULT_BADGE') }}</span
                >
              </div>
              <div class="text-xs text-slate-500 mt-0.5">
                {{ model.provider_jabvox }} · {{ model.model_jabvox }}
              </div>
              <div v-if="testResults[model.id]" class="mt-1">
                <span
                  v-if="testResults[model.id].success"
                  class="text-xs text-green-600"
                >
                  {{
                    t('JABVOX_AI_CHAT.MODELS.TEST_SUCCESS', {
                      ms: testResults[model.id].latency,
                    })
                  }}
                </span>
                <span v-else class="text-xs text-red-500">
                  {{
                    t('JABVOX_AI_CHAT.MODELS.TEST_ERROR', {
                      error: testResults[model.id].error,
                    })
                  }}
                </span>
              </div>
            </div>
            <div class="flex items-center gap-2 ml-4">
              <button
                class="text-xs text-slate-500 hover:text-violet-600 px-2 py-1 rounded border border-slate-200 hover:border-violet-300 transition-colors disabled:opacity-50"
                :disabled="testingId === model.id"
                @click="testConnection(model)"
              >
                {{
                  testingId === model.id
                    ? t('JABVOX_AI_CHAT.MODELS.TESTING')
                    : t('JABVOX_AI_CHAT.MODELS.TEST')
                }}
              </button>
              <button
                v-if="!model.is_default_jabvox"
                class="text-xs text-slate-500 hover:text-violet-600 px-2 py-1 rounded border border-slate-200 hover:border-violet-300 transition-colors"
                @click="setDefault(model.id)"
              >
                {{ t('JABVOX_AI_CHAT.MODELS.SET_DEFAULT') }}
              </button>
              <button
                class="text-xs text-slate-500 hover:text-violet-600 p-1.5 rounded hover:bg-slate-100 transition-colors"
                @click="openEditModel(model)"
              >
                <span class="i-ri-edit-line" />
              </button>
              <button
                class="text-xs text-slate-500 hover:text-red-500 p-1.5 rounded hover:bg-red-50 transition-colors"
                @click="deleteModel(model.id)"
              >
                <span class="i-ri-delete-bin-line" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- DOCUMENTS TAB -->
      <div v-show="activeTab === 'documents'" class="space-y-8">
        <!-- Bucket config -->
        <div class="bg-white border border-slate-200 rounded-xl p-6">
          <h2 class="text-base font-semibold text-slate-700 mb-4">
            {{ t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_CONFIG') }}
          </h2>
          <div class="grid grid-cols-2 gap-4">
            <div class="col-span-2">
              <label class="block text-xs font-medium text-slate-600 mb-1">
                {{ t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_URL') }}
              </label>
              <input
                v-model="bucketForm.bucket_url_jabvox"
                type="text"
                class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
                :placeholder="
                  t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_URL_PLACEHOLDER')
                "
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">
                {{ t('JABVOX_AI_CHAT.DOCUMENTS.ACCESS_KEY') }}
              </label>
              <input
                v-model="bucketForm.bucket_access_key_jabvox"
                type="text"
                class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">
                {{ t('JABVOX_AI_CHAT.DOCUMENTS.SECRET_KEY') }}
              </label>
              <div class="relative">
                <input
                  v-model="bucketForm.bucket_secret_key_jabvox"
                  :type="showSecretKey ? 'text' : 'password'"
                  class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500 pr-10"
                  :placeholder="
                    t('JABVOX_AI_CHAT.DOCUMENTS.SECRET_KEY_PLACEHOLDER')
                  "
                />
                <button
                  class="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                  @click="showSecretKey = !showSecretKey"
                >
                  <span
                    :class="
                      showSecretKey ? 'i-ri-eye-off-line' : 'i-ri-eye-line'
                    "
                  />
                </button>
              </div>
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">
                {{ t('JABVOX_AI_CHAT.DOCUMENTS.REGION') }}
              </label>
              <input
                v-model="bucketForm.bucket_region_jabvox"
                type="text"
                class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
                :placeholder="t('JABVOX_AI_CHAT.DOCUMENTS.REGION_DEFAULT')"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">
                {{ t('JABVOX_AI_CHAT.DOCUMENTS.BUCKET_NAME') }}
              </label>
              <input
                v-model="bucketForm.bucket_name_jabvox"
                type="text"
                class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
              />
            </div>
          </div>
          <div class="flex items-center gap-3 mt-4">
            <button
              class="bg-violet-600 hover:bg-violet-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
              :disabled="uiFlags.isSavingConfig"
              @click="saveBucketConfig"
            >
              {{ t('JABVOX_AI_CHAT.DOCUMENTS.SAVE_CONFIG') }}
            </button>
            <button
              class="border border-slate-200 hover:bg-slate-50 text-slate-700 px-4 py-2 rounded-lg text-sm font-medium flex items-center gap-2 transition-colors disabled:opacity-50"
              :disabled="uiFlags.isSyncingDocuments"
              @click="syncDocuments"
            >
              <span
                class="i-ri-refresh-line"
                :class="uiFlags.isSyncingDocuments ? 'animate-spin' : ''"
              />
              {{
                uiFlags.isSyncingDocuments
                  ? t('JABVOX_AI_CHAT.DOCUMENTS.SYNCING')
                  : t('JABVOX_AI_CHAT.DOCUMENTS.SYNC')
              }}
            </button>
          </div>
        </div>

        <!-- Document list -->
        <div>
          <h2 class="text-base font-semibold text-slate-700 mb-3">
            {{ t('JABVOX_AI_CHAT.DOCUMENTS.DOCUMENT_LIST') }}
          </h2>
          <div
            v-if="documents.length === 0"
            class="text-center py-8 text-slate-400 text-sm"
          >
            {{ t('JABVOX_AI_CHAT.DOCUMENTS.EMPTY') }}
          </div>
          <div v-else class="space-y-2">
            <div
              v-for="doc in documents"
              :key="doc.id"
              class="bg-white border border-slate-200 rounded-xl px-4 py-3 flex items-center justify-between"
            >
              <div class="flex items-center gap-3 min-w-0">
                <span
                  class="i-ri-file-text-line text-slate-400 flex-shrink-0"
                />
                <div class="min-w-0">
                  <p class="text-sm text-slate-700 truncate font-medium">
                    {{ doc.name_jabvox }}
                  </p>
                  <p class="text-xs text-slate-400">
                    {{ formatBytes(doc.size_jabvox) }}
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-2 ml-4">
                <button
                  class="text-xs px-3 py-1 rounded-full border transition-colors font-medium"
                  :class="
                    doc.is_enabled_jabvox
                      ? 'bg-green-50 text-green-700 border-green-200 hover:bg-green-100'
                      : 'bg-slate-50 text-slate-500 border-slate-200 hover:bg-slate-100'
                  "
                  @click="toggleDocument(doc)"
                >
                  {{
                    doc.is_enabled_jabvox
                      ? t('JABVOX_AI_CHAT.DOCUMENTS.DISABLE')
                      : t('JABVOX_AI_CHAT.DOCUMENTS.ENABLE')
                  }}
                </button>
                <button
                  class="text-slate-400 hover:text-red-500 p-1.5 rounded hover:bg-red-50 transition-colors"
                  @click="deleteDocument(doc.id)"
                >
                  <span class="i-ri-delete-bin-line text-base" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- CONFIG TAB -->
      <div v-show="activeTab === 'config'" class="max-w-lg">
        <div class="bg-white border border-slate-200 rounded-xl p-6">
          <h2 class="text-base font-semibold text-slate-700 mb-4">
            {{ t('JABVOX_AI_CHAT.CONFIG.TITLE') }}
          </h2>
          <div
            class="flex items-start justify-between gap-4 p-4 rounded-lg border border-slate-100 bg-slate-50"
          >
            <div>
              <p class="text-sm font-medium text-slate-700">
                {{ t('JABVOX_AI_CHAT.CONFIG.WEB_SEARCH') }}
              </p>
              <p class="text-xs text-slate-500 mt-0.5">
                {{ t('JABVOX_AI_CHAT.CONFIG.WEB_SEARCH_DESC') }}
              </p>
            </div>
            <button
              class="flex-shrink-0 w-10 h-6 rounded-full transition-colors relative"
              :class="
                configForm.web_search_enabled_jabvox
                  ? 'bg-violet-600'
                  : 'bg-slate-300'
              "
              @click="
                configForm.web_search_enabled_jabvox =
                  !configForm.web_search_enabled_jabvox
              "
            >
              <span
                class="absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform"
                :class="
                  configForm.web_search_enabled_jabvox
                    ? 'translate-x-4'
                    : 'translate-x-0'
                "
              />
            </button>
          </div>
          <button
            class="mt-4 bg-violet-600 hover:bg-violet-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
            :disabled="uiFlags.isSavingConfig"
            @click="saveConfig"
          >
            {{ t('JABVOX_AI_CHAT.CONFIG.SAVE') }}
          </button>
        </div>
      </div>

      <!-- PERMISSIONS TAB -->
      <div v-show="activeTab === 'permissions'">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-lg font-semibold text-slate-700">
              {{ t('JABVOX_AI_CHAT.PERMISSIONS.TITLE') }}
            </h2>
            <p class="text-sm text-slate-500 mt-0.5">
              {{ t('JABVOX_AI_CHAT.PERMISSIONS.DESC') }}
            </p>
          </div>
          <button
            class="bg-violet-600 hover:bg-violet-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
            :disabled="uiFlags.isSavingPermissions"
            @click="savePermissions"
          >
            {{ t('JABVOX_AI_CHAT.PERMISSIONS.SAVE') }}
          </button>
        </div>
        <div
          class="bg-white border border-slate-200 rounded-xl overflow-hidden"
        >
          <table class="w-full">
            <thead class="bg-slate-50 border-b border-slate-200">
              <tr>
                <th
                  class="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide"
                >
                  {{ t('JABVOX_AI_CHAT.PERMISSIONS.USER') }}
                </th>
                <th
                  class="text-center px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide"
                >
                  {{ t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE') }}
                </th>
                <th
                  class="text-center px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide"
                >
                  {{ t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE_MODELS') }}
                </th>
                <th
                  class="text-center px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide"
                >
                  {{ t('JABVOX_AI_CHAT.PERMISSIONS.CAN_USE_DOCUMENTS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(perm, idx) in localPermissions"
                :key="perm.user_id"
                class="border-b border-slate-100 last:border-0"
              >
                <td class="px-4 py-3">
                  <div>
                    <p class="text-sm font-medium text-slate-700">
                      {{ perm.name }}
                    </p>
                    <p class="text-xs text-slate-400">{{ perm.email }}</p>
                  </div>
                </td>
                <td class="px-4 py-3 text-center">
                  <input
                    v-model="localPermissions[idx].can_use"
                    type="checkbox"
                    class="h-4 w-4 rounded border-slate-300 text-violet-600 focus:ring-violet-600"
                  />
                </td>
                <td class="px-4 py-3 text-center">
                  <input
                    v-model="localPermissions[idx].can_use_models"
                    type="checkbox"
                    class="h-4 w-4 rounded border-slate-300 text-violet-600 focus:ring-violet-600"
                  />
                </td>
                <td class="px-4 py-3 text-center">
                  <input
                    v-model="localPermissions[idx].can_use_documents"
                    type="checkbox"
                    class="h-4 w-4 rounded border-slate-300 text-violet-600 focus:ring-violet-600"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Model Modal -->
    <div
      v-if="showModelModal"
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
    >
      <div class="bg-white rounded-2xl shadow-xl w-full max-w-md">
        <div class="p-6 border-b border-slate-100">
          <h3 class="text-base font-semibold text-slate-800">
            {{
              editingModel
                ? t('JABVOX_AI_CHAT.MODELS.EDIT')
                : t('JABVOX_AI_CHAT.MODELS.ADD')
            }}
          </h3>
        </div>
        <div class="p-6 space-y-4">
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">
              {{ t('JABVOX_AI_CHAT.MODELS.NAME') }} *
            </label>
            <input
              v-model="modelForm.name_jabvox"
              type="text"
              class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
              :placeholder="t('JABVOX_AI_CHAT.MODELS.NAME_PLACEHOLDER')"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">
              {{ t('JABVOX_AI_CHAT.MODELS.PROVIDER') }}
            </label>
            <input
              v-model="modelForm.provider_jabvox"
              type="text"
              class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
              :placeholder="t('JABVOX_AI_CHAT.MODELS.PROVIDER_PLACEHOLDER')"
            />
            <p class="text-xs text-slate-400 mt-1">
              {{ t('JABVOX_AI_CHAT.MODELS.PROVIDER_HINT') }}
            </p>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">
              {{ t('JABVOX_AI_CHAT.MODELS.MODEL_API') }} *
            </label>
            <input
              v-model="modelForm.model_jabvox"
              type="text"
              class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
              :placeholder="t('JABVOX_AI_CHAT.MODELS.MODEL_PLACEHOLDER')"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">
              {{ t('JABVOX_AI_CHAT.MODELS.API_KEY') }}
            </label>
            <input
              v-model="modelForm.api_key_jabvox"
              type="password"
              class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
              :placeholder="
                editingModel
                  ? t('JABVOX_AI_CHAT.DOCUMENTS.SECRET_KEY_PLACEHOLDER')
                  : t('JABVOX_AI_CHAT.MODELS.API_KEY_PLACEHOLDER')
              "
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">
              {{ t('JABVOX_AI_CHAT.MODELS.BASE_URL') }}
            </label>
            <input
              v-model="modelForm.base_url_jabvox"
              type="text"
              class="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
              :placeholder="t('JABVOX_AI_CHAT.MODELS.BASE_URL_PLACEHOLDER')"
            />
            <p class="text-xs text-slate-400 mt-1">
              {{ t('JABVOX_AI_CHAT.MODELS.BASE_URL_HINT') }}
            </p>
          </div>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              v-model="modelForm.is_default_jabvox"
              type="checkbox"
              class="h-4 w-4 rounded border-slate-300 text-violet-600 focus:ring-violet-600"
            />
            <span class="text-sm text-slate-600">
              {{ t('JABVOX_AI_CHAT.MODELS.IS_DEFAULT') }}
            </span>
          </label>
        </div>
        <div class="px-6 py-4 border-t border-slate-100 flex gap-3 justify-end">
          <button
            class="px-4 py-2 rounded-lg text-sm text-slate-600 hover:bg-slate-100 transition-colors"
            @click="closeModelModal"
          >
            {{ t('JABVOX_AI_CHAT.MODELS.CANCEL') }}
          </button>
          <button
            class="bg-violet-600 hover:bg-violet-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
            :disabled="uiFlags.isSavingModel"
            @click="saveModel"
          >
            {{ t('JABVOX_AI_CHAT.MODELS.SAVE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
