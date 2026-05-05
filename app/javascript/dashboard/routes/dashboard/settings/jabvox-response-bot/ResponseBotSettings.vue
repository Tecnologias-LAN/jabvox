<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const store = useStore();
const { t } = useI18n();

const seats = useMapGetter('jabvoxResponseBot/getSeats');
const configs = useMapGetter('jabvoxResponseBot/getConfigs');
const documents = useMapGetter('jabvoxResponseBot/getDocuments');
const aiModels = useMapGetter('jabvoxResponseBot/getAiModels');
const uiFlags = useMapGetter('jabvoxResponseBot/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

const CATEGORIES = ['proceso_venta', 'proceso_pago', 'quejas_y_reclamos', 'soporte'];

const activeTab = ref('configs');
const activeDocCategory = ref('all');

const tabs = [
  { key: 'seats', label: () => t('JABVOX_RESPONSE_BOT.TABS.SEATS'), icon: 'i-lucide-bot' },
  { key: 'configs', label: () => t('JABVOX_RESPONSE_BOT.TABS.CONFIG'), icon: 'i-lucide-settings' },
  { key: 'documents', label: () => t('JABVOX_RESPONSE_BOT.TABS.DOCUMENTS'), icon: 'i-lucide-file-text' },
];

// ── Config list ───────────────────────────────────────────────────────────────
const showNewForm = ref(false);
const expandedId = ref(null);

const newForm = ref({
  inbox_id: null,
  jabvox_response_bot_seat_id: null,
  jabvox_ai_chat_model_id: null,
  jabvox_audio_model_id: null,
  enabled_jabvox: false,
  active_labels_jabvox: [...CATEGORIES],
});

const editForms = ref({});

const openEdit = config => {
  expandedId.value = expandedId.value === config.id ? null : config.id;
  if (!editForms.value[config.id]) {
    editForms.value[config.id] = {
      jabvox_response_bot_seat_id: config.jabvox_response_bot_seat_id || null,
      jabvox_ai_chat_model_id: config.jabvox_ai_chat_model_id || null,
      jabvox_audio_model_id: config.jabvox_audio_model_id || null,
      enabled_jabvox: !!config.enabled_jabvox,
      active_labels_jabvox: config.active_labels_jabvox || [...CATEGORIES],
    };
  }
};

const toggleConfigLabel = (configId, label) => {
  const list = editForms.value[configId].active_labels_jabvox;
  const idx = list.indexOf(label);
  if (idx === -1) list.push(label);
  else list.splice(idx, 1);
};

const toggleNewLabel = label => {
  const list = newForm.value.active_labels_jabvox;
  const idx = list.indexOf(label);
  if (idx === -1) list.push(label);
  else list.splice(idx, 1);
};

const seatOptions = computed(() =>
  (seats.value || []).map(s => ({ value: s.id, label: s.name_jabvox }))
);

const modelOptions = computed(() =>
  (aiModels.value || []).map(m => ({
    value: m.id,
    label: m.name_jabvox + (m.is_default_jabvox ? ` (${t('JABVOX_RESPONSE_BOT.CONFIG.MODEL_DEFAULT')})` : ''),
  }))
);

const usedInboxIds = computed(() => new Set((configs.value || []).map(c => c.inbox_id)));

const availableInboxOptions = computed(() =>
  (inboxes.value || [])
    .filter(i => !usedInboxIds.value.has(i.id))
    .map(i => ({ value: i.id, label: i.name }))
);

const inboxName = inboxId => {
  const inbox = (inboxes.value || []).find(i => i.id === inboxId);
  return inbox?.name || `Bandeja #${inboxId}`;
};

const onCreateConfig = async () => {
  if (!newForm.value.inbox_id) {
    useAlert(t('JABVOX_RESPONSE_BOT.CONFIG.INBOX_REQUIRED'));
    return;
  }
  try {
    await store.dispatch('jabvoxResponseBot/createConfig', newForm.value);
    showNewForm.value = false;
    newForm.value = {
      inbox_id: null,
      jabvox_response_bot_seat_id: null,
      jabvox_ai_chat_model_id: null,
      jabvox_audio_model_id: null,
      enabled_jabvox: false,
      active_labels_jabvox: [...CATEGORIES],
    };
    useAlert(t('JABVOX_RESPONSE_BOT.CONFIG.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_RESPONSE_BOT.ERROR'));
  }
};

const onUpdateConfig = async config => {
  try {
    await store.dispatch('jabvoxResponseBot/updateConfig', {
      id: config.id,
      ...editForms.value[config.id],
    });
    useAlert(t('JABVOX_RESPONSE_BOT.CONFIG.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_RESPONSE_BOT.ERROR'));
  }
};

const onDestroyConfig = async config => {
  if (!window.confirm(t('JABVOX_RESPONSE_BOT.CONFIG.DELETE_CONFIRM', { name: inboxName(config.inbox_id) }))) return;
  try {
    await store.dispatch('jabvoxResponseBot/destroyConfig', config.id);
    if (expandedId.value === config.id) expandedId.value = null;
  } catch {
    useAlert(t('JABVOX_RESPONSE_BOT.ERROR'));
  }
};

const onSetupLabels = async () => {
  try {
    await store.dispatch('jabvoxResponseBot/setupLabels');
    useAlert(t('JABVOX_RESPONSE_BOT.CONFIG.SETUP_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_RESPONSE_BOT.ERROR'));
  }
};

// ── Documents ────────────────────────────────────────────────────────────────
const docCategoryTabs = computed(() => [
  { key: 'all', label: t('JABVOX_RESPONSE_BOT.DOCUMENTS.ALL_DOCS') },
  { key: 'selected', label: t('JABVOX_RESPONSE_BOT.DOCUMENTS.SELECTED_DOCS') },
]);

const filteredDocuments = computed(() => {
  if (activeDocCategory.value === 'selected')
    return (documents.value || []).filter(d => d.enabled_jabvox);
  return documents.value || [];
});

const onSync = async () => {
  try {
    const result = await store.dispatch('jabvoxResponseBot/syncDocuments');
    await store.dispatch('jabvoxResponseBot/fetchDocuments');
    useAlert(
      t('JABVOX_RESPONSE_BOT.DOCUMENTS.SYNC_SUCCESS').replace('{count}', result?.synced ?? 0)
    );
  } catch {
    useAlert(t('JABVOX_RESPONSE_BOT.ERROR'));
  }
};

const onToggleDoc = async doc => {
  try {
    await store.dispatch('jabvoxResponseBot/updateDocument', {
      id: doc.id,
      enabled_jabvox: !doc.enabled_jabvox,
    });
  } catch {
    useAlert(t('JABVOX_RESPONSE_BOT.ERROR'));
  }
};

const onChangeCategory = async (doc, category) => {
  try {
    await store.dispatch('jabvoxResponseBot/updateDocument', {
      id: doc.id,
      label_category_jabvox: category || null,
    });
    useAlert(t('JABVOX_RESPONSE_BOT.DOCUMENTS.UPDATE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_RESPONSE_BOT.ERROR'));
  }
};

const onDeleteDoc = async doc => {
  if (!window.confirm(t('JABVOX_RESPONSE_BOT.DOCUMENTS.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('jabvoxResponseBot/deleteDocument', doc.id);
    useAlert(t('JABVOX_RESPONSE_BOT.DOCUMENTS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_RESPONSE_BOT.ERROR'));
  }
};

const categoryColor = cat => {
  const colors = {
    proceso_venta: 'bg-green-100 text-green-700',
    proceso_pago: 'bg-blue-100 text-blue-700',
    quejas_y_reclamos: 'bg-red-100 text-red-700',
    soporte: 'bg-amber-100 text-amber-700',
  };
  return colors[cat] || 'bg-slate-100 text-slate-500';
};

// ── Init ─────────────────────────────────────────────────────────────────────
onMounted(() => {
  store.dispatch('jabvoxResponseBot/fetchSeats');
  store.dispatch('jabvoxResponseBot/fetchConfigs');
  store.dispatch('jabvoxResponseBot/fetchDocuments');
  store.dispatch('jabvoxResponseBot/fetchAiModels');
  store.dispatch('inboxes/get');
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <!-- Header -->
    <div class="shrink-0 border-b border-n-weak bg-n-surface-1">
      <div class="max-w-3xl mx-auto px-6 sm:px-8 pt-6 pb-0 flex items-center justify-between">
        <div>
          <h1 class="text-heading-1 text-n-slate-12">
            {{ t('JABVOX_RESPONSE_BOT.SETTINGS.TITLE') }}
          </h1>
          <p class="text-body-main text-n-slate-10 mt-0.5">
            {{ t('JABVOX_RESPONSE_BOT.SETTINGS.SUBTITLE') }}
          </p>
        </div>
      </div>
      <div class="flex px-6 sm:px-8 gap-1 max-w-3xl mx-auto mt-4">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px"
          :class="
            activeTab === tab.key
              ? 'border-woot-500 text-woot-600'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-12 hover:border-n-weak'
          "
          @click="activeTab = tab.key"
        >
          <span class="w-4 h-4" :class="[tab.icon]" />
          {{ tab.label() }}
        </button>
      </div>
    </div>

    <!-- Body -->
    <div class="flex-1 overflow-y-auto">

      <!-- ── Tab: Seats ── -->
      <div v-if="activeTab === 'seats'" class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-4">
        <p class="text-sm text-n-slate-10">{{ t('JABVOX_RESPONSE_BOT.SEATS.DESCRIPTION') }}</p>
        <div v-if="uiFlags.isFetchingSeats" class="text-sm text-n-slate-10 text-center py-10 animate-pulse">
          {{ t('JABVOX_RESPONSE_BOT.LOADING') }}
        </div>
        <div v-else-if="!seats.length" class="text-sm text-n-slate-10 text-center py-10">
          {{ t('JABVOX_RESPONSE_BOT.SEATS.EMPTY') }}
        </div>
        <div v-else class="grid gap-3">
          <div
            v-for="seat in seats"
            :key="seat.id"
            class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 p-5"
          >
            <div class="flex items-center justify-between gap-4">
              <div class="flex items-center gap-3 min-w-0">
                <div class="w-10 h-10 rounded-xl bg-woot-50 dark:bg-woot-900/20 flex items-center justify-center shrink-0">
                  <span class="i-lucide-bot w-5 h-5 text-woot-600 dark:text-woot-400" />
                </div>
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-n-slate-12 truncate">{{ seat.name_jabvox }}</p>
                  <p v-if="seat.prompt_jabvox" class="text-xs text-n-slate-10 mt-0.5 line-clamp-2">
                    {{ seat.prompt_jabvox }}
                  </p>
                </div>
              </div>
              <span
                class="text-xs font-medium px-2.5 py-1 rounded-full shrink-0"
                :class="seat.active_jabvox ? 'bg-green-100 text-green-700' : 'bg-slate-100 text-slate-500'"
              >
                {{ seat.active_jabvox ? t('JABVOX_RESPONSE_BOT.SEATS.ACTIVE') : t('JABVOX_RESPONSE_BOT.SEATS.INACTIVE') }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- ── Tab: Configs ── -->
      <div v-else-if="activeTab === 'configs'" class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-4">

        <!-- Header row -->
        <div class="flex items-center justify-between">
          <p class="text-sm text-n-slate-10">{{ t('JABVOX_RESPONSE_BOT.CONFIG.LIST_DESCRIPTION') }}</p>
          <button
            v-if="!showNewForm && availableInboxOptions.length > 0"
            class="flex items-center gap-1.5 text-sm font-medium px-3 py-1.5 rounded-lg bg-woot-500 text-white hover:bg-woot-600 transition-colors"
            @click="showNewForm = true"
          >
            <i class="i-lucide-plus w-4 h-4" />
            {{ t('JABVOX_RESPONSE_BOT.CONFIG.NEW') }}
          </button>
        </div>

        <div v-if="uiFlags.isFetchingConfigs" class="text-sm text-n-slate-10 text-center py-10 animate-pulse">
          {{ t('JABVOX_RESPONSE_BOT.LOADING') }}
        </div>
        <template v-else>

          <!-- New config form -->
          <div v-if="showNewForm" class="rounded-2xl border-2 border-dashed border-woot-300 bg-woot-25 dark:bg-woot-900/10 p-5 space-y-4">
            <div class="flex items-center justify-between">
              <p class="text-sm font-semibold text-woot-700 dark:text-woot-300">
                {{ t('JABVOX_RESPONSE_BOT.CONFIG.NEW') }}
              </p>
              <button class="text-slate-400 hover:text-slate-600" @click="showNewForm = false">
                <i class="i-lucide-x w-4 h-4" />
              </button>
            </div>

            <!-- Inbox (required) -->
            <div class="space-y-1.5">
              <label class="block text-xs font-medium text-slate-600 dark:text-slate-300">
                {{ t('JABVOX_RESPONSE_BOT.CONFIG.INBOX_LABEL') }} *
              </label>
              <ComboBox
                v-model="newForm.inbox_id"
                :options="availableInboxOptions"
                :placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.INBOX_PLACEHOLDER')"
                :search-placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.INBOX_PLACEHOLDER')"
              />
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div class="space-y-1.5">
                <label class="block text-xs font-medium text-slate-600 dark:text-slate-300">
                  {{ t('JABVOX_RESPONSE_BOT.CONFIG.SEAT_LABEL') }}
                </label>
                <ComboBox
                  v-model="newForm.jabvox_response_bot_seat_id"
                  :options="seatOptions"
                  :placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.SEAT_PLACEHOLDER')"
                  :search-placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.SEAT_PLACEHOLDER')"
                />
              </div>
              <div class="space-y-1.5">
                <label class="block text-xs font-medium text-slate-600 dark:text-slate-300">
                  {{ t('JABVOX_RESPONSE_BOT.CONFIG.MODEL_LABEL') }}
                </label>
                <ComboBox
                  v-model="newForm.jabvox_ai_chat_model_id"
                  :options="modelOptions"
                  :placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.MODEL_PLACEHOLDER')"
                  :search-placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.MODEL_PLACEHOLDER')"
                />
              </div>
            </div>

            <!-- Enable toggle -->
            <div class="flex items-center justify-between">
              <p class="text-sm font-medium text-n-slate-12">{{ t('JABVOX_RESPONSE_BOT.CONFIG.ENABLED_LABEL') }}</p>
              <button
                class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors shrink-0"
                :class="newForm.enabled_jabvox ? 'bg-woot-600' : 'bg-slate-200 dark:bg-slate-700'"
                @click="newForm.enabled_jabvox = !newForm.enabled_jabvox"
              >
                <span
                  class="inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform"
                  :class="newForm.enabled_jabvox ? 'translate-x-6' : 'translate-x-1'"
                />
              </button>
            </div>

            <!-- Labels -->
            <div class="space-y-2">
              <p class="text-xs font-medium text-slate-600 dark:text-slate-300">{{ t('JABVOX_RESPONSE_BOT.CONFIG.LABELS_TITLE') }}</p>
              <div class="flex flex-wrap gap-2">
                <label
                  v-for="cat in CATEGORIES"
                  :key="cat"
                  class="flex items-center gap-1.5 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    :checked="newForm.active_labels_jabvox.includes(cat)"
                    class="w-3.5 h-3.5 rounded text-woot-500"
                    @change="toggleNewLabel(cat)"
                  />
                  <span class="text-xs font-semibold px-2 py-0.5 rounded-full" :class="categoryColor(cat)">{{ cat }}</span>
                </label>
              </div>
            </div>

            <div class="flex justify-end gap-2">
              <button
                class="text-sm px-3 py-1.5 rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50"
                @click="showNewForm = false"
              >
                {{ t('JABVOX_RESPONSE_BOT.CONFIG.CANCEL') }}
              </button>
              <Button
                :label="uiFlags.isSaving ? t('JABVOX_RESPONSE_BOT.LOADING') : t('JABVOX_RESPONSE_BOT.CONFIG.SAVE')"
                :disabled="uiFlags.isSaving || !newForm.inbox_id"
                @click="onCreateConfig"
              />
            </div>
          </div>

          <!-- Empty state -->
          <div v-if="!configs.length && !showNewForm" class="text-center py-12 text-sm text-n-slate-10">
            {{ t('JABVOX_RESPONSE_BOT.CONFIG.EMPTY') }}
          </div>

          <!-- Existing configs list -->
          <div
            v-for="config in configs"
            :key="config.id"
            class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 overflow-hidden"
          >
            <!-- Card header -->
            <div class="flex items-center justify-between px-5 py-4 cursor-pointer" @click="openEdit(config)">
              <div class="flex items-center gap-3 min-w-0">
                <div class="w-9 h-9 rounded-xl bg-slate-100 dark:bg-slate-700 flex items-center justify-center shrink-0">
                  <span class="i-lucide-inbox w-4.5 h-4.5 text-slate-500" />
                </div>
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-n-slate-12 truncate">{{ inboxName(config.inbox_id) }}</p>
                  <p class="text-xs text-n-slate-10 truncate">
                    {{ seatOptions.find(s => s.value === config.jabvox_response_bot_seat_id)?.label || t('JABVOX_RESPONSE_BOT.CONFIG.NO_SEAT') }}
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-3 shrink-0">
                <span
                  class="text-xs font-medium px-2.5 py-1 rounded-full"
                  :class="config.enabled_jabvox ? 'bg-green-100 text-green-700' : 'bg-slate-100 text-slate-500'"
                >
                  {{ config.enabled_jabvox ? t('JABVOX_RESPONSE_BOT.CONFIG.ENABLED') : t('JABVOX_RESPONSE_BOT.CONFIG.DISABLED') }}
                </span>
                <i
                  class="w-4 h-4 text-slate-400 transition-transform"
                  :class="expandedId === config.id ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
                />
              </div>
            </div>

            <!-- Expanded edit form -->
            <div v-if="expandedId === config.id && editForms[config.id]" class="border-t border-slate-100 dark:border-slate-700 px-5 py-5 space-y-4">

              <!-- Enable toggle -->
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-semibold text-n-slate-12">{{ t('JABVOX_RESPONSE_BOT.CONFIG.ENABLED_LABEL') }}</p>
                  <p class="text-xs text-n-slate-10 mt-0.5">{{ t('JABVOX_RESPONSE_BOT.CONFIG.ENABLED_HINT') }}</p>
                </div>
                <button
                  class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors shrink-0"
                  :class="editForms[config.id].enabled_jabvox ? 'bg-woot-600' : 'bg-slate-200 dark:bg-slate-700'"
                  @click="editForms[config.id].enabled_jabvox = !editForms[config.id].enabled_jabvox"
                >
                  <span
                    class="inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform"
                    :class="editForms[config.id].enabled_jabvox ? 'translate-x-6' : 'translate-x-1'"
                  />
                </button>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div class="space-y-1.5">
                  <label class="block text-xs font-medium text-slate-600 dark:text-slate-300">{{ t('JABVOX_RESPONSE_BOT.CONFIG.SEAT_LABEL') }}</label>
                  <ComboBox
                    v-model="editForms[config.id].jabvox_response_bot_seat_id"
                    :options="seatOptions"
                    :placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.SEAT_PLACEHOLDER')"
                    :search-placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.SEAT_PLACEHOLDER')"
                  />
                </div>
                <div class="space-y-1.5">
                  <label class="block text-xs font-medium text-slate-600 dark:text-slate-300">{{ t('JABVOX_RESPONSE_BOT.CONFIG.MODEL_LABEL') }}</label>
                  <ComboBox
                    v-model="editForms[config.id].jabvox_ai_chat_model_id"
                    :options="modelOptions"
                    :placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.MODEL_PLACEHOLDER')"
                    :search-placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.MODEL_PLACEHOLDER')"
                  />
                </div>
                <div class="space-y-1.5">
                  <label class="block text-xs font-medium text-slate-600 dark:text-slate-300">{{ t('JABVOX_RESPONSE_BOT.CONFIG.AUDIO_MODEL_LABEL') }}</label>
                  <ComboBox
                    v-model="editForms[config.id].jabvox_audio_model_id"
                    :options="modelOptions"
                    :placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.AUDIO_MODEL_PLACEHOLDER')"
                    :search-placeholder="t('JABVOX_RESPONSE_BOT.CONFIG.AUDIO_MODEL_PLACEHOLDER')"
                  />
                </div>
              </div>

              <!-- Labels -->
              <div class="space-y-2">
                <p class="text-xs font-medium text-slate-600 dark:text-slate-300">{{ t('JABVOX_RESPONSE_BOT.CONFIG.LABELS_TITLE') }}</p>
                <div class="flex flex-wrap gap-2">
                  <label v-for="cat in CATEGORIES" :key="cat" class="flex items-center gap-1.5 cursor-pointer">
                    <input
                      type="checkbox"
                      :checked="editForms[config.id].active_labels_jabvox.includes(cat)"
                      class="w-3.5 h-3.5 rounded text-woot-500"
                      @change="toggleConfigLabel(config.id, cat)"
                    />
                    <span class="text-xs font-semibold px-2 py-0.5 rounded-full" :class="categoryColor(cat)">{{ cat }}</span>
                  </label>
                </div>
              </div>

              <div class="flex items-center justify-between pt-2 border-t border-slate-100 dark:border-slate-700">
                <button
                  class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-red-200 text-red-500 hover:bg-red-50 transition-colors"
                  @click="onDestroyConfig(config)"
                >
                  <i class="i-lucide-trash-2 w-3.5 h-3.5" />
                  {{ t('JABVOX_RESPONSE_BOT.CONFIG.DELETE') }}
                </button>
                <Button
                  :label="uiFlags.isSaving ? t('JABVOX_RESPONSE_BOT.LOADING') : t('JABVOX_RESPONSE_BOT.CONFIG.SAVE')"
                  :disabled="uiFlags.isSaving"
                  @click="onUpdateConfig(config)"
                />
              </div>
            </div>
          </div>

          <!-- Setup labels (global) -->
          <div v-if="configs.length > 0" class="flex items-center gap-3 pt-2">
            <button
              class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-slate-200 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700"
              @click="onSetupLabels"
            >
              <i class="i-lucide-tag-plus w-3.5 h-3.5" />
              {{ t('JABVOX_RESPONSE_BOT.CONFIG.SETUP_LABELS') }}
            </button>
            <p class="text-xs text-n-slate-10">{{ t('JABVOX_RESPONSE_BOT.CONFIG.SETUP_LABELS_HINT') }}</p>
          </div>
        </template>
      </div>

      <!-- ── Tab: Documents ── -->
      <div v-else-if="activeTab === 'documents'" class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-5">
        <div class="flex items-start justify-between gap-4">
          <p class="text-sm text-n-slate-10 max-w-lg">{{ t('JABVOX_RESPONSE_BOT.DOCUMENTS.DESCRIPTION') }}</p>
          <button
            class="shrink-0 flex items-center gap-1.5 text-sm font-medium px-4 py-2 rounded-lg bg-woot-500 text-white hover:bg-woot-600 disabled:opacity-50 transition-colors"
            :disabled="uiFlags.isSyncing"
            @click="onSync"
          >
            <i class="i-lucide-refresh-cw w-4 h-4" :class="{ 'animate-spin': uiFlags.isSyncing }" />
            {{ uiFlags.isSyncing ? t('JABVOX_RESPONSE_BOT.DOCUMENTS.SYNCING') : t('JABVOX_RESPONSE_BOT.DOCUMENTS.SYNC') }}
          </button>
        </div>

        <div class="flex gap-1 border-b border-slate-200 dark:border-slate-700">
          <button
            v-for="tab in docCategoryTabs"
            :key="tab.key"
            class="px-3 py-2 text-xs font-medium border-b-2 -mb-px transition-colors"
            :class="activeDocCategory === tab.key ? 'border-woot-500 text-woot-600' : 'border-transparent text-n-slate-10 hover:text-n-slate-12'"
            @click="activeDocCategory = tab.key"
          >
            {{ tab.label }}
          </button>
        </div>

        <div v-if="uiFlags.isFetchingDocuments" class="text-sm text-n-slate-10 text-center py-10 animate-pulse">
          {{ t('JABVOX_RESPONSE_BOT.LOADING') }}
        </div>
        <div v-else-if="!filteredDocuments.length" class="text-sm text-n-slate-10 text-center py-10">
          {{ t('JABVOX_RESPONSE_BOT.DOCUMENTS.EMPTY') }}
        </div>
        <div v-else class="rounded-xl border border-slate-200 dark:border-slate-700 overflow-hidden">
          <table class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm">
            <thead>
              <tr class="bg-slate-50 dark:bg-slate-800 text-left text-slate-500 dark:text-slate-400">
                <th class="px-4 py-3 text-xs font-medium">{{ t('JABVOX_RESPONSE_BOT.DOCUMENTS.FILE_LABEL') }}</th>
                <th class="px-4 py-3 text-xs font-medium">{{ t('JABVOX_RESPONSE_BOT.DOCUMENTS.CATEGORY_LABEL') }}</th>
                <th class="px-4 py-3 text-xs font-medium text-center">{{ t('JABVOX_RESPONSE_BOT.DOCUMENTS.ENABLED_LABEL') }}</th>
                <th class="px-4 py-3 text-xs font-medium text-right" />
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 dark:divide-slate-700 bg-white dark:bg-slate-800">
              <tr v-for="doc in filteredDocuments" :key="doc.id" class="hover:bg-slate-50 dark:hover:bg-slate-800/50">
                <td class="px-4 py-3">
                  <div class="flex items-center gap-2">
                    <i class="i-lucide-file-text w-4 h-4 text-slate-400 shrink-0" />
                    <span class="text-sm text-n-slate-12 truncate max-w-[220px]">{{ doc.name_jabvox }}</span>
                  </div>
                </td>
                <td class="px-4 py-3">
                  <select
                    :value="doc.label_category_jabvox || ''"
                    class="text-xs border border-slate-200 dark:border-slate-600 rounded-lg px-2 py-1 bg-white dark:bg-slate-700 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-woot-500"
                    @change="onChangeCategory(doc, $event.target.value || null)"
                  >
                    <option value="">{{ t('JABVOX_RESPONSE_BOT.DOCUMENTS.CATEGORY_UNASSIGNED') }}</option>
                    <option v-for="cat in CATEGORIES" :key="cat" :value="cat">
                      {{ t(`JABVOX_RESPONSE_BOT.DOCUMENTS.CATEGORIES.${cat}`) }}
                    </option>
                  </select>
                </td>
                <td class="px-4 py-3 text-center">
                  <button
                    class="relative inline-flex h-5 w-9 items-center rounded-full transition-colors"
                    :class="doc.enabled_jabvox ? 'bg-woot-500' : 'bg-slate-200 dark:bg-slate-700'"
                    @click="onToggleDoc(doc)"
                  >
                    <span
                      class="inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow transition-transform"
                      :class="doc.enabled_jabvox ? 'translate-x-4' : 'translate-x-0.5'"
                    />
                  </button>
                </td>
                <td class="px-4 py-3 text-right">
                  <button class="text-xs text-red-500 hover:text-red-700 transition-colors" @click="onDeleteDoc(doc)">
                    <i class="i-lucide-trash-2 w-4 h-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

    </div>
  </div>
</template>
