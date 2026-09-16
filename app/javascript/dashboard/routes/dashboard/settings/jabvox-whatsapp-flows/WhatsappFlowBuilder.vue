<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useJabvoxPermissions } from 'dashboard/composables/useJabvoxPermissions';
import { wfFlowsAPI } from 'dashboard/api/jabvox/whatsappFlows';
import { useFlowValidation } from './composables/useFlowValidation';
import {
  addScreen,
  removeScreen,
  duplicateScreen,
  moveScreenUp,
  moveScreenDown,
  reindexScreens,
  addComponentToScreen,
  removeComponentFromScreen,
  updateComponentProps,
} from './screenHelpers';
import {
  createComponentInstance,
  isAtLimit,
  MAX_COMPONENTS_PER_SCREEN,
} from './componentCatalog';

import ScreenList from './components/ScreenList.vue';
import ScreenEditor from './components/ScreenEditor.vue';
import ComponentPalette from './components/ComponentPalette.vue';
import FlowPreview from './components/FlowPreview.vue';
import FlowJsonView from './components/FlowJsonView.vue';
import ValidationPanel from './components/ValidationPanel.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';
import PromptDialog from './components/PromptDialog.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { jabvoxCan } = useJabvoxPermissions();

const canManage = computed(() => jabvoxCan('jabvox_whatsapp_flows_manage'));

const isNew = computed(() => route.params.flowId === 'new');
const flowId = computed(() => route.params.flowId);

const loading = ref(true);
const saving = ref(false);
const publishing = ref(false);

const flow = ref({
  id: null,
  name: '',
  category: 'OTHER',
  description: '',
  status: 'draft',
  meta_status: null,
  inbox_id: route.query.inbox_id ? Number(route.query.inbox_id) : null,
  screens_json: [],
});

// Un Flow PUBLISHED en Meta es inmutable (sección 6 de la arquitectura): la
// UI bloquea edición de screens_json y solo permite ver/duplicar/deprecar.
const isReadonly = computed(
  () => flow.value.meta_status === 'PUBLISHED' || !canManage.value
);

const categories = ref([]);

const loadCategories = async () => {
  try {
    const { data } = await wfFlowsAPI.categories();
    categories.value = data.categories || data || [];
  } catch {
    categories.value = [
      'SIGN_UP',
      'SIGN_IN',
      'APPOINTMENT_BOOKING',
      'LEAD_GENERATION',
      'CONTACT_US',
      'CUSTOMER_SUPPORT',
      'SURVEY',
      'OTHER',
    ];
  }
};

const loadFlow = async () => {
  if (isNew.value) {
    loading.value = false;
    return;
  }
  loading.value = true;
  try {
    const { data } = await wfFlowsAPI.get(flowId.value);
    flow.value = { ...flow.value, ...data };
  } catch {
    useAlert(t('JABVOX_WA_FLOWS.BUILDER.ERROR_LOAD'));
  } finally {
    loading.value = false;
  }
};

// ─── Screens ──────────────────────────────────────────────────────────────
const selectedScreenId = ref('');

onMounted(async () => {
  await Promise.all([loadCategories(), loadFlow()]);
  if (!selectedScreenId.value && flow.value.screens_json.length) {
    selectedScreenId.value = flow.value.screens_json[0].id;
  }
});

const orderedScreens = computed(() =>
  [...flow.value.screens_json].sort((a, b) => a.order - b.order)
);

const selectedScreen = computed(() =>
  flow.value.screens_json.find(s => s.id === selectedScreenId.value)
);

const isFirstScreen = computed(
  () => orderedScreens.value[0]?.id === selectedScreenId.value
);

const promptDialog = ref(null);
const confirmDialog = ref(null);

const onAddScreen = () => {
  promptDialog.value?.open({
    title: t('JABVOX_WA_FLOWS.BUILDER.SCREENS.NEW_TITLE_PROMPT'),
    initialValue: t('JABVOX_WA_FLOWS.BUILDER.SCREENS.UNTITLED'),
    data: { action: 'addScreen' },
  });
};

const onRemoveScreen = screenId => {
  confirmDialog.value?.open({
    title: t('JABVOX_WA_FLOWS.BUILDER.SCREENS.REMOVE_CONFIRM_TITLE'),
    description: t('JABVOX_WA_FLOWS.BUILDER.SCREENS.REMOVE_CONFIRM_BODY'),
    data: { action: 'removeScreen', screenId },
  });
};

const onDuplicateScreen = screenId => {
  flow.value.screens_json = duplicateScreen(flow.value.screens_json, screenId);
};

const onMoveScreenUp = screenId => {
  flow.value.screens_json = moveScreenUp(flow.value.screens_json, screenId);
};

const onMoveScreenDown = screenId => {
  flow.value.screens_json = moveScreenDown(flow.value.screens_json, screenId);
};

const onReorderScreens = newOrder => {
  flow.value.screens_json = reindexScreens(newOrder);
};

const onSelectScreen = screenId => {
  selectedScreenId.value = screenId;
};

const onUpdateScreen = patch => {
  flow.value.screens_json = flow.value.screens_json.map(s =>
    s.id === selectedScreenId.value ? { ...s, ...patch } : s
  );
};

const onConfirmPrompt = ({ value, data }) => {
  if (data?.action === 'addScreen' && value) {
    flow.value.screens_json = addScreen(flow.value.screens_json, value);
    const created = flow.value.screens_json[flow.value.screens_json.length - 1];
    selectedScreenId.value = created.id;
  }
};

const onConfirmDialog = data => {
  if (data?.action === 'removeScreen') {
    const wasSelected = selectedScreenId.value === data.screenId;
    flow.value.screens_json = removeScreen(
      flow.value.screens_json,
      data.screenId
    );
    if (wasSelected) {
      selectedScreenId.value = orderedScreens.value[0]?.id || '';
    }
  }
};

// ─── Components dentro de la screen seleccionada ───────────────────────────
const onAddComponent = type => {
  if (!selectedScreen.value) return;
  if (isAtLimit(selectedScreen.value.components, type)) return;
  if (selectedScreen.value.components.length >= MAX_COMPONENTS_PER_SCREEN)
    return;
  const id = `cmp_${Date.now().toString(36)}_${Math.floor(Math.random() * 1000)}`;
  const component = createComponentInstance(type, id);
  flow.value.screens_json = addComponentToScreen(
    flow.value.screens_json,
    selectedScreenId.value,
    component
  );
};

const onRemoveComponent = componentId => {
  flow.value.screens_json = removeComponentFromScreen(
    flow.value.screens_json,
    selectedScreenId.value,
    componentId
  );
};

const onUpdateComponent = ({ componentId, props }) => {
  flow.value.screens_json = updateComponentProps(
    flow.value.screens_json,
    selectedScreenId.value,
    componentId,
    props
  );
};

const onReorderComponents = newComponents => {
  flow.value.screens_json = flow.value.screens_json.map(s =>
    s.id === selectedScreenId.value ? { ...s, components: newComponents } : s
  );
};

// ─── Validación ──────────────────────────────────────────────────────────
const {
  errors: validationErrors,
  validating,
  validated,
  validate,
} = useFlowValidation();

const errorScreenIds = computed(() => [
  ...new Set(validationErrors.value.map(e => e.screen_id).filter(Boolean)),
]);

const componentErrorsForSelectedScreen = computed(() =>
  validationErrors.value.filter(e => e.screen_id === selectedScreenId.value)
);

const runValidate = async () => {
  if (!flow.value.id) {
    useAlert(t('JABVOX_WA_FLOWS.BUILDER.SAVE_BEFORE_VALIDATE'));
    return;
  }
  await validate(flow.value.id);
};

// Tab inferior activa (declarada aquí, antes de goToField, para que pueda
// referenciarla sin un forward-reference).
const activeBottomTab = ref('builder');

const goToField = error => {
  if (error.screen_id) selectedScreenId.value = error.screen_id;
  activeBottomTab.value = 'builder';
};

// ─── Guardar / Publicar ────────────────────────────────────────────────────
const saveDraft = async () => {
  if (!flow.value.name?.trim()) {
    useAlert(t('JABVOX_WA_FLOWS.BUILDER.NAME_REQUIRED'));
    return;
  }
  saving.value = true;
  const payload = {
    name: flow.value.name,
    category: flow.value.category,
    description: flow.value.description,
    inbox_id: flow.value.inbox_id,
    screens_json: flow.value.screens_json,
  };
  try {
    if (flow.value.id) {
      const { data } = await wfFlowsAPI.update(flow.value.id, payload);
      flow.value = { ...flow.value, ...data };
    } else {
      const { data } = await wfFlowsAPI.create(payload);
      flow.value = { ...flow.value, ...data };
      router.replace({
        name: 'jabvox_whatsapp_flows_builder',
        params: { flowId: data.id },
      });
    }
    useAlert(t('JABVOX_WA_FLOWS.BUILDER.SAVED'));
  } catch (err) {
    useAlert(
      err?.response?.data?.error || t('JABVOX_WA_FLOWS.BUILDER.ERROR_SAVE')
    );
  } finally {
    saving.value = false;
  }
};

const publishFlow = async () => {
  if (!flow.value.id) {
    useAlert(t('JABVOX_WA_FLOWS.BUILDER.SAVE_BEFORE_PUBLISH'));
    return;
  }
  publishing.value = true;
  try {
    const { data } = await wfFlowsAPI.publish(flow.value.id);
    flow.value = { ...flow.value, ...data };
    useAlert(t('JABVOX_WA_FLOWS.BUILDER.PUBLISHED'));
  } catch (err) {
    // El backend devuelve { error, errors } con status 422 cuando la
    // validación/publicación falla (Validator local o rechazo de Meta).
    const payload = err?.response?.data;
    useAlert(payload?.error || t('JABVOX_WA_FLOWS.BUILDER.ERROR_PUBLISH'));
    if (payload?.errors) {
      validationErrors.value = payload.errors;
      activeBottomTab.value = 'validation';
    }
  } finally {
    publishing.value = false;
  }
};

// ─── Tabs inferiores: builder / json / validación ──────────────────────────
const bottomTabs = computed(() => [
  { key: 'builder', label: t('JABVOX_WA_FLOWS.BUILDER.TABS.BUILDER') },
  { key: 'json', label: t('JABVOX_WA_FLOWS.BUILDER.TABS.JSON') },
  {
    key: 'validation',
    label: t('JABVOX_WA_FLOWS.BUILDER.TABS.VALIDATION'),
    badge: validationErrors.value.length || null,
  },
]);

const goBack = () => {
  router.push({ name: 'jabvox_whatsapp_flows_settings_index' });
};

const CATEGORY_LABELS = {
  SIGN_UP: 'JABVOX_WA_FLOWS.CATEGORIES.SIGN_UP',
  SIGN_IN: 'JABVOX_WA_FLOWS.CATEGORIES.SIGN_IN',
  APPOINTMENT_BOOKING: 'JABVOX_WA_FLOWS.CATEGORIES.APPOINTMENT_BOOKING',
  LEAD_GENERATION: 'JABVOX_WA_FLOWS.CATEGORIES.LEAD_GENERATION',
  CONTACT_US: 'JABVOX_WA_FLOWS.CATEGORIES.CONTACT_US',
  CUSTOMER_SUPPORT: 'JABVOX_WA_FLOWS.CATEGORIES.CUSTOMER_SUPPORT',
  SURVEY: 'JABVOX_WA_FLOWS.CATEGORIES.SURVEY',
  OTHER: 'JABVOX_WA_FLOWS.CATEGORIES.OTHER',
};
const categoryLabel = c => t(CATEGORY_LABELS[c] || c);
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-n-background">
    <!-- Header -->
    <div
      class="flex items-center justify-between gap-3 px-4 sm:px-6 py-3 border-b border-n-weak shrink-0"
    >
      <div class="flex items-center gap-3 min-w-0">
        <button class="wf-icon-btn" @click="goBack">
          <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
        </button>
        <div class="min-w-0">
          <input
            v-model="flow.name"
            class="reset-base text-base font-semibold text-n-slate-12 bg-transparent border-none px-0 py-0 focus:outline-none truncate"
            :disabled="isReadonly"
            :placeholder="t('JABVOX_WA_FLOWS.BUILDER.NAME_PLACEHOLDER')"
          />
          <div class="flex items-center gap-2 mt-0.5">
            <select
              v-model="flow.category"
              class="reset-base text-xs text-n-slate-10 bg-transparent border-none px-0 py-0 focus:outline-none"
              :disabled="isReadonly"
            >
              <option v-for="c in categories" :key="c" :value="c">
                {{ categoryLabel(c) }}
              </option>
            </select>
            <span
              v-if="flow.meta_status"
              class="text-[10px] px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ flow.meta_status }}
            </span>
          </div>
        </div>
      </div>

      <div class="flex items-center gap-2 shrink-0">
        <button
          class="wf-btn-secondary"
          :disabled="validating"
          @click="runValidate"
        >
          <span
            :class="
              validating
                ? 'i-lucide-loader-2 animate-spin'
                : 'i-lucide-shield-check'
            "
            class="size-4"
            aria-hidden="true"
          />
          {{ t('JABVOX_WA_FLOWS.BUILDER.ACTIONS.VALIDATE') }}
        </button>
        <button
          v-if="!isReadonly"
          class="wf-btn-secondary"
          :disabled="saving"
          @click="saveDraft"
        >
          <span
            :class="saving ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-save'"
            class="size-4"
            aria-hidden="true"
          />
          {{ t('JABVOX_WA_FLOWS.BUILDER.ACTIONS.SAVE_DRAFT') }}
        </button>
        <button
          v-if="!isReadonly"
          class="wf-btn-primary"
          :disabled="publishing || !flow.id"
          :title="
            !flow.id ? t('JABVOX_WA_FLOWS.BUILDER.SAVE_BEFORE_PUBLISH') : ''
          "
          @click="publishFlow"
        >
          <span
            :class="
              publishing ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-rocket'
            "
            class="size-4"
            aria-hidden="true"
          />
          {{ t('JABVOX_WA_FLOWS.BUILDER.ACTIONS.PUBLISH') }}
        </button>
      </div>
    </div>

    <div v-if="loading" class="flex-1 flex items-center justify-center">
      <span
        class="i-lucide-loader-2 animate-spin size-6 text-n-slate-9"
        aria-hidden="true"
      />
    </div>

    <template v-else>
      <!-- 3 columnas: screens | editor+tabs | preview -->
      <div
        class="flex-1 min-h-0 grid grid-cols-1 lg:grid-cols-[220px_1fr_320px] overflow-hidden"
      >
        <div
          class="border-r border-n-weak overflow-hidden hidden lg:flex lg:flex-col"
        >
          <ScreenList
            :screens="flow.screens_json"
            :selected-screen-id="selectedScreenId"
            :readonly="isReadonly"
            :error-screen-ids="errorScreenIds"
            @select="onSelectScreen"
            @add="onAddScreen"
            @remove="onRemoveScreen"
            @duplicate="onDuplicateScreen"
            @reorder="onReorderScreens"
            @move-up="onMoveScreenUp"
            @move-down="onMoveScreenDown"
          />
        </div>

        <div class="flex flex-col overflow-hidden">
          <!-- Tabs inferiores -->
          <div class="flex gap-1 px-3 pt-2 border-b border-n-weak shrink-0">
            <button
              v-for="tab in bottomTabs"
              :key="tab.key"
              class="wf-tab px-3 py-1.5 text-xs rounded-t-lg"
              :class="{ 'wf-tab-active': activeBottomTab === tab.key }"
              @click="activeBottomTab = tab.key"
            >
              {{ tab.label }}
              <span v-if="tab.badge" class="ml-1 text-n-ruby-11">
                ({{ tab.badge }})
              </span>
            </button>
          </div>

          <div class="flex-1 min-h-0 overflow-hidden">
            <template v-if="activeBottomTab === 'builder'">
              <div
                class="h-full grid grid-cols-1 md:grid-cols-[1fr_200px] overflow-hidden"
              >
                <ScreenEditor
                  v-if="selectedScreen"
                  :screen="selectedScreen"
                  :screens="flow.screens_json"
                  :is-first-screen="isFirstScreen"
                  :readonly="isReadonly"
                  :component-errors="componentErrorsForSelectedScreen"
                  @update-screen="onUpdateScreen"
                  @remove-component="onRemoveComponent"
                  @update-component="onUpdateComponent"
                  @reorder-components="onReorderComponents"
                />
                <div v-else class="flex items-center justify-center p-6">
                  <p class="text-sm text-n-slate-10 text-center">
                    {{ t('JABVOX_WA_FLOWS.BUILDER.SCREENS.SELECT_OR_CREATE') }}
                  </p>
                </div>
                <div
                  class="border-l border-n-weak overflow-hidden hidden md:block"
                >
                  <ComponentPalette
                    v-if="selectedScreen"
                    :screen-components="selectedScreen.components"
                    :disabled="isReadonly"
                    @add="onAddComponent"
                  />
                </div>
              </div>
            </template>

            <FlowJsonView
              v-else-if="activeBottomTab === 'json'"
              :screens="flow.screens_json"
            />

            <ValidationPanel
              v-else-if="activeBottomTab === 'validation'"
              :errors="validationErrors"
              :validating="validating"
              :validated="validated"
              @go-to-field="goToField"
            />
          </div>
        </div>

        <div class="border-l border-n-weak overflow-hidden hidden lg:block">
          <FlowPreview :screens="flow.screens_json" :flow-name="flow.name" />
        </div>
      </div>
    </template>

    <ConfirmDialog ref="confirmDialog" @confirm="onConfirmDialog" />
    <PromptDialog ref="promptDialog" @submit="onConfirmPrompt" />
  </div>
</template>

<style scoped>
.wf-field {
  background: var(--color-background-light);
  color: var(--color-body);
  border: 1.5px solid var(--color-border, #94a3b8);
  border-radius: 0.5rem;
  padding: 0.4rem 0.6rem;
}
.wf-field:focus {
  outline: none;
  border-color: var(--color-woot);
  box-shadow: 0 0 0 3px rgba(31, 147, 255, 0.15);
}

.wf-icon-btn {
  padding: 6px;
  border-radius: 8px;
  color: var(--color-body);
  transition:
    background 0.18s ease,
    color 0.18s ease;
}
.wf-icon-btn:hover {
  background: var(--color-background);
  color: var(--color-heading);
}

.wf-icon-btn-xs {
  padding: 4px;
  border-radius: 6px;
  color: var(--color-body);
}
.wf-icon-btn-xs:hover:not(:disabled) {
  background: var(--color-background);
  color: var(--color-heading);
}
.wf-icon-btn-xs:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}

.wf-btn-primary {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
  padding: 0.5rem 0.9rem;
  font-size: 0.8125rem;
  font-weight: 500;
  border-radius: 0.5rem;
  background: var(--color-woot);
  color: white;
  transition: opacity 0.15s ease;
}
.wf-btn-primary:hover:not(:disabled) {
  opacity: 0.9;
}
.wf-btn-primary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.wf-btn-secondary {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
  padding: 0.5rem 0.75rem;
  font-size: 0.8125rem;
  font-weight: 500;
  border-radius: 0.5rem;
  border: 1px solid var(--color-border);
  background: var(--color-background-light);
  color: var(--color-body);
  transition: background 0.15s ease;
}
.wf-btn-secondary:hover:not(:disabled) {
  background: var(--color-background);
}
.wf-btn-secondary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.wf-tab {
  color: var(--color-body);
  background: transparent;
  border: 1px solid transparent;
  border-bottom: none;
}
.wf-tab-active {
  color: var(--color-woot);
  background: var(--color-background-light);
  border-color: var(--color-border);
}

.wf-screen-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem;
  border-radius: 0.5rem;
  cursor: pointer;
  border: 1px solid transparent;
}
.wf-screen-item:hover {
  background: var(--color-background);
}
.wf-screen-item-active {
  background: var(--color-background-light);
  border-color: var(--color-woot);
}

.wf-component-item {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.4rem 0.5rem;
  border-radius: 0.5rem;
  font-size: 0.8125rem;
  color: var(--color-body);
  border: 1px solid transparent;
}
.wf-component-item:hover {
  background: var(--color-background);
}
.wf-component-item-active {
  background: var(--color-background-light);
  border-color: var(--color-woot);
  color: var(--color-heading);
}

.wf-palette-btn {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.4rem 0.5rem;
  border-radius: 0.5rem;
  font-size: 0.75rem;
  border: 1px solid var(--color-border);
  background: var(--color-background-light);
  color: var(--color-body);
}
.wf-palette-btn:hover:not(:disabled) {
  border-color: var(--color-woot);
  color: var(--color-heading);
}
.wf-palette-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.wf-variable-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  width: 100%;
  padding: 0.35rem 0.5rem;
  border-radius: 0.375rem;
  font-size: 0.75rem;
  color: var(--color-body);
  text-align: left;
}
.wf-variable-item:hover {
  background: var(--color-background);
}
</style>
