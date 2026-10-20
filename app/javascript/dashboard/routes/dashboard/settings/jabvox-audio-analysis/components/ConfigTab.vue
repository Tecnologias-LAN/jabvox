<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import {
  audioInfaltablesAPI,
  audioAnatomyAPI,
  audioAdvisorsAPI,
  audioFilenamePatternsAPI,
  audioCodeMappingsAPI,
} from 'dashboard/api/jabvox/audioAnalysis';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SettingsCard from './SettingsCard.vue';
import ConfirmDialog from './ConfirmDialog.vue';

const { t } = useI18n();

const confirmDialog = ref(null);

// Surfaces the backend's validation message (p.ej. un 422) o un fallback i18n.
const apiErrorMessage = (error, fallbackKey) =>
  error?.response?.data?.error || t(fallbackKey);

// ---------- Sub-tabs internos ----------
// Pills que alternan la ref `activeSubTab`; cada sección carga sus datos al
// entrar la primera vez.
const subTabs = [
  {
    key: 'advisors',
    label: () => t('JABVOX_AUDIO.CONFIG.SUBTABS.ADVISORS'),
    icon: 'i-lucide-users',
  },
  {
    key: 'typifications',
    label: () => t('JABVOX_AUDIO.CONFIG.SUBTABS.TYPIFICATIONS'),
    icon: 'i-lucide-tags',
  },
  {
    key: 'infaltables',
    label: () => t('JABVOX_AUDIO.CONFIG.SUBTABS.INFALTABLES'),
    icon: 'i-lucide-list-checks',
  },
  {
    key: 'anatomy',
    label: () => t('JABVOX_AUDIO.CONFIG.SUBTABS.ANATOMY'),
    icon: 'i-lucide-heart-handshake',
  },
  {
    key: 'patterns',
    label: () => t('JABVOX_AUDIO.CONFIG.SUBTABS.PATTERNS'),
    icon: 'i-lucide-file-cog',
  },
  {
    key: 'mappings',
    label: () => t('JABVOX_AUDIO.CONFIG.SUBTABS.MAPPINGS'),
    icon: 'i-lucide-arrow-left-right',
  },
];
const activeSubTab = ref('advisors');

// ---------- Asesores ----------
const advisors = ref([]);
const advisorsLoaded = ref(false);
const editingAdvisor = ref(null);
const importingUsers = ref(false);

const loadAdvisors = async () => {
  try {
    const { data } = await audioAdvisorsAPI.getAll();
    advisors.value = data.advisors || [];
    advisorsLoaded.value = true;
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.LOAD_ERROR'));
  }
};
const newAdvisor = () => ({ name: '', external_id: '', user_id: null });
const saveAdvisor = async () => {
  if (!editingAdvisor.value.name) {
    useAlert(t('JABVOX_AUDIO.CONFIG.ADVISORS.NAME_REQUIRED'));
    return;
  }
  try {
    if (editingAdvisor.value.id)
      await audioAdvisorsAPI.update(
        editingAdvisor.value.id,
        editingAdvisor.value
      );
    else await audioAdvisorsAPI.create(editingAdvisor.value);
    editingAdvisor.value = null;
    await loadAdvisors();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};
const importUsers = async () => {
  importingUsers.value = true;
  try {
    await audioAdvisorsAPI.importUsers();
    await loadAdvisors();
    useAlert(t('JABVOX_AUDIO.CONFIG.ADVISORS.IMPORTED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.ADVISORS.IMPORT_ERROR'));
  } finally {
    importingUsers.value = false;
  }
};

// ---------- Anatomía / Cercanía ----------
const anatomyCriteria = ref([]);
const anatomyLoaded = ref(false);
const editingCriterion = ref(null);

const loadAnatomy = async () => {
  try {
    const { data } = await audioAnatomyAPI.getAll();
    anatomyCriteria.value = data.criteria || [];
    anatomyLoaded.value = true;
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.LOAD_ERROR'));
  }
};
const newCriterion = () => ({
  name: '',
  description: '',
  positive_signal: '',
  opportunity_signal: '',
});
const saveCriterion = async () => {
  if (!editingCriterion.value.name) {
    useAlert(t('JABVOX_AUDIO.CONFIG.ANATOMY.NAME_REQUIRED'));
    return;
  }
  try {
    if (editingCriterion.value.id)
      await audioAnatomyAPI.update(
        editingCriterion.value.id,
        editingCriterion.value
      );
    else await audioAnatomyAPI.create(editingCriterion.value);
    editingCriterion.value = null;
    await loadAnatomy();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};
const seedAnatomy = async () => {
  try {
    await audioAnatomyAPI.seedDefaults();
    await loadAnatomy();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};

// ---------- Tipificaciones (solo lectura; su CRUD vive en su propia sección) ----------
const typifications = ref([]);
const typificationsLoaded = ref(false);
// Conteo de infaltables por tipificación, cargado perezosamente.
const infaltablesCount = ref({});

const loadTypifications = async () => {
  try {
    const { data } = await typificationsAPI.getAll(false);
    typifications.value = data.typifications || [];
    typificationsLoaded.value = true;
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.LOAD_ERROR'));
  }
};

// ---------- Infaltables ----------
const selectedTypificationId = ref(null);
const infaltables = ref([]);
const loadingInfaltables = ref(false);
const bulkPaste = ref('');

const typificationOptions = computed(() => [
  { value: '', label: t('JABVOX_AUDIO.CONFIG.INFALTABLES.PICK_TYPIFICATION') },
  ...typifications.value.map(tp => ({ value: tp.id, label: tp.name })),
]);

const loadInfaltables = async () => {
  if (!selectedTypificationId.value) {
    infaltables.value = [];
    return;
  }
  loadingInfaltables.value = true;
  try {
    const { data } = await audioInfaltablesAPI.getAll(
      selectedTypificationId.value
    );
    // Normaliza a {text, optional} para la edición en bloque.
    infaltables.value = (data.infaltables || []).map(i => ({
      text: i.text,
      optional: Boolean(i.optional),
    }));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.LOAD_ERROR'));
  } finally {
    loadingInfaltables.value = false;
  }
};
const onTypificationChange = () => {
  bulkPaste.value = '';
  loadInfaltables();
};
const addInfaltable = () => {
  infaltables.value.push({ text: '', optional: false });
};
const removeInfaltable = index => {
  infaltables.value.splice(index, 1);
};
// Pega varios: una línea = un infaltable. Reemplaza la lista actual.
const applyBulkPaste = () => {
  const lines = bulkPaste.value
    .split('\n')
    .map(l => l.trim())
    .filter(l => l.length);
  infaltables.value = lines.map(text => ({ text, optional: false }));
  bulkPaste.value = '';
};
const saveInfaltables = async () => {
  if (!selectedTypificationId.value) return;
  const items = infaltables.value
    .filter(i => i.text && i.text.trim())
    .map(i => ({ text: i.text.trim(), optional: Boolean(i.optional) }));
  try {
    await audioInfaltablesAPI.bulkReplace(selectedTypificationId.value, items);
    await loadInfaltables();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};

// ---------- Formatos de archivo ----------
const patterns = ref([]);
const patternsLoaded = ref(false);
const knownFields = ref([]);
const editingPattern = ref(null);

// Probador de patrones (no guarda nada).
const probe = ref({ pattern: '', sample: '', date_format: '' });
const probeResult = ref(null);
const probing = ref(false);

// Muestra un campo conocido como marcador, p.ej. "phone" → "{phone}".
const fieldToken = field => `{${field}}`;

const loadPatterns = async () => {
  try {
    const { data } = await audioFilenamePatternsAPI.getAll();
    patterns.value = data.patterns || [];
    knownFields.value = data.known_fields || [];
    patternsLoaded.value = true;
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.LOAD_ERROR'));
  }
};
const newPattern = () => ({ name: '', pattern: '', date_format: '' });
const savePattern = async () => {
  if (!editingPattern.value.name || !editingPattern.value.pattern) {
    useAlert(t('JABVOX_AUDIO.CONFIG.PATTERNS.REQUIRED'));
    return;
  }
  try {
    if (editingPattern.value.id)
      await audioFilenamePatternsAPI.update(
        editingPattern.value.id,
        editingPattern.value
      );
    else await audioFilenamePatternsAPI.create(editingPattern.value);
    editingPattern.value = null;
    await loadPatterns();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};
const runProbe = async () => {
  if (!probe.value.pattern || !probe.value.sample) {
    useAlert(t('JABVOX_AUDIO.CONFIG.PATTERNS.PROBE_REQUIRED'));
    return;
  }
  probing.value = true;
  probeResult.value = null;
  try {
    const { data } = await audioFilenamePatternsAPI.test(
      probe.value.pattern,
      probe.value.sample,
      probe.value.date_format || undefined
    );
    probeResult.value = data;
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.PATTERNS.PROBE_ERROR'));
  } finally {
    probing.value = false;
  }
};
// Campos extraídos por el probador, como pares {clave, valor} para la tabla.
const probeFields = computed(() => {
  const fields = probeResult.value?.fields || {};
  return Object.entries(fields).map(([key, value]) => ({ key, value }));
});

// ---------- Mapeos (código→tipificación y código→asesor) ----------
const typificationMappings = ref([]);
const advisorMappings = ref([]);
const mappingsLoaded = ref(false);
// Editores inline independientes por sección.
const editingTypificationMapping = ref(null);
const editingAdvisorMapping = ref(null);

// Opciones de asesor para el Select (reutiliza la ref `advisors`).
const advisorOptions = computed(() => [
  { value: '', label: t('JABVOX_AUDIO.CONFIG.MAPPINGS.PICK_ADVISOR') },
  ...advisors.value.map(a => ({ value: a.id, label: a.name })),
]);

const loadTypificationMappings = async () => {
  try {
    const { data } = await audioCodeMappingsAPI.getAll('typification');
    typificationMappings.value = data.mappings || [];
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.LOAD_ERROR'));
  }
};
const loadAdvisorMappings = async () => {
  try {
    const { data } = await audioCodeMappingsAPI.getAll('advisor');
    advisorMappings.value = data.mappings || [];
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.CONFIG.LOAD_ERROR'));
  }
};
const loadMappings = async () => {
  // Necesita tipificaciones y asesores para poblar los Select.
  if (!typificationsLoaded.value) await loadTypifications();
  if (!advisorsLoaded.value) await loadAdvisors();
  await Promise.all([loadTypificationMappings(), loadAdvisorMappings()]);
  mappingsLoaded.value = true;
};

const newTypificationMapping = () => ({
  kind: 'typification',
  code: '',
  typification_id: null,
});
const newAdvisorMapping = () => ({
  kind: 'advisor',
  code: '',
  advisor_id: null,
});

const saveTypificationMapping = async () => {
  const m = editingTypificationMapping.value;
  if (!m.code || !m.code.trim()) {
    useAlert(t('JABVOX_AUDIO.CONFIG.MAPPINGS.CODE_REQUIRED'));
    return;
  }
  if (!m.typification_id) {
    useAlert(t('JABVOX_AUDIO.CONFIG.MAPPINGS.TYPIFICATION_REQUIRED'));
    return;
  }
  const payload = {
    kind: 'typification',
    code: m.code.trim(),
    typification_id: m.typification_id,
  };
  try {
    if (m.id) await audioCodeMappingsAPI.update(m.id, payload);
    else await audioCodeMappingsAPI.create(payload);
    editingTypificationMapping.value = null;
    await loadTypificationMappings();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};
const saveAdvisorMapping = async () => {
  const m = editingAdvisorMapping.value;
  if (!m.code || !m.code.trim()) {
    useAlert(t('JABVOX_AUDIO.CONFIG.MAPPINGS.CODE_REQUIRED'));
    return;
  }
  if (!m.advisor_id) {
    useAlert(t('JABVOX_AUDIO.CONFIG.MAPPINGS.ADVISOR_REQUIRED'));
    return;
  }
  const payload = {
    kind: 'advisor',
    code: m.code.trim(),
    advisor_id: m.advisor_id,
  };
  try {
    if (m.id) await audioCodeMappingsAPI.update(m.id, payload);
    else await audioCodeMappingsAPI.create(payload);
    editingAdvisorMapping.value = null;
    await loadAdvisorMappings();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};

// ---------- Borrado (una sola ConfirmDialog para todas las sub-tabs) ----------
const confirmDelete = (kind, id) => {
  confirmDialog.value?.open({
    title: t('JABVOX_AUDIO.DELETE'),
    description: t('JABVOX_AUDIO.CONFIRM_DELETE'),
    confirmLabel: t('JABVOX_AUDIO.DELETE'),
    cancelLabel: t('JABVOX_AUDIO.CANCEL'),
    data: { kind, id },
  });
};
const onConfirmDelete = async ({ kind, id }) => {
  try {
    if (kind === 'advisor') {
      await audioAdvisorsAPI.destroy(id);
      await loadAdvisors();
    } else if (kind === 'criterion') {
      await audioAnatomyAPI.destroy(id);
      await loadAnatomy();
    } else if (kind === 'pattern') {
      await audioFilenamePatternsAPI.destroy(id);
      await loadPatterns();
    } else if (kind === 'typification_mapping') {
      await audioCodeMappingsAPI.destroy(id);
      await loadTypificationMappings();
    } else if (kind === 'advisor_mapping') {
      await audioCodeMappingsAPI.destroy(id);
      await loadAdvisorMappings();
    }
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};

// Carga perezosa por sub-tab al activarla.
const switchSubTab = key => {
  activeSubTab.value = key;
  if (key === 'advisors' && !advisorsLoaded.value) loadAdvisors();
  if (key === 'anatomy' && !anatomyLoaded.value) loadAnatomy();
  if (key === 'patterns' && !patternsLoaded.value) loadPatterns();
  if (key === 'mappings' && !mappingsLoaded.value) loadMappings();
  if (
    (key === 'typifications' || key === 'infaltables') &&
    !typificationsLoaded.value
  )
    loadTypifications();
};

onMounted(() => {
  loadAdvisors();
});
</script>

<template>
  <div class="flex flex-col gap-5">
    <!-- Sub-tabs (pills) -->
    <div class="flex flex-wrap items-center gap-1.5">
      <button
        v-for="st in subTabs"
        :key="st.key"
        type="button"
        class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
        :class="
          activeSubTab === st.key
            ? 'bg-n-brand/10 text-n-brand'
            : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
        "
        @click="switchSubTab(st.key)"
      >
        <span :class="st.icon" class="size-4" />
        {{ st.label() }}
      </button>
    </div>

    <!-- ══════════════ Asesores ══════════════ -->
    <SettingsCard
      v-if="activeSubTab === 'advisors'"
      :title="t('JABVOX_AUDIO.CONFIG.ADVISORS.TITLE')"
      :description="t('JABVOX_AUDIO.CONFIG.ADVISORS.SUBTITLE')"
      icon="i-lucide-users"
    >
      <template #actions>
        <div class="flex items-center gap-2">
          <Button
            :label="t('JABVOX_AUDIO.CONFIG.ADVISORS.IMPORT')"
            icon="i-lucide-download"
            variant="outline"
            color="slate"
            size="sm"
            :is-loading="importingUsers"
            @click="importUsers"
          />
          <Button
            :label="t('JABVOX_AUDIO.CONFIG.ADVISORS.NEW')"
            icon="i-lucide-plus"
            size="sm"
            @click="editingAdvisor = newAdvisor()"
          />
        </div>
      </template>

      <!-- Editor inline -->
      <div
        v-if="editingAdvisor"
        class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 flex flex-col gap-4 mb-4"
      >
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="editingAdvisor.name"
            :label="t('JABVOX_AUDIO.CONFIG.ADVISORS.NAME')"
            :placeholder="t('JABVOX_AUDIO.CONFIG.ADVISORS.NAME')"
          />
          <Input
            v-model="editingAdvisor.external_id"
            :label="t('JABVOX_AUDIO.CONFIG.ADVISORS.EXTERNAL_ID')"
            :placeholder="t('JABVOX_AUDIO.CONFIG.ADVISORS.EXTERNAL_ID_HINT')"
          />
        </div>
        <div class="flex items-center gap-2">
          <Button :label="t('JABVOX_AUDIO.SAVE')" @click="saveAdvisor" />
          <Button
            :label="t('JABVOX_AUDIO.CANCEL')"
            variant="ghost"
            color="slate"
            @click="editingAdvisor = null"
          />
        </div>
      </div>

      <div v-if="advisors.length" class="flex flex-col gap-2">
        <div
          v-for="a in advisors"
          :key="a.id"
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak px-4 py-3 transition-colors hover:bg-n-alpha-1"
        >
          <div class="flex items-center gap-3 min-w-0">
            <span
              class="flex items-center justify-center size-8 rounded-lg bg-n-alpha-2 text-n-slate-11 shrink-0"
            >
              <span class="i-lucide-user size-4" />
            </span>
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ a.name }}
              </p>
              <p class="text-xs text-n-slate-11 truncate">
                <span v-if="a.external_id">{{ a.external_id }}</span>
                <span v-if="a.external_id && a.user_name"> · </span>
                <span v-if="a.user_name">{{ a.user_name }}</span>
              </p>
            </div>
          </div>
          <div class="flex items-center gap-1 shrink-0">
            <Button
              icon="i-lucide-pencil"
              variant="ghost"
              color="slate"
              size="sm"
              @click="editingAdvisor = { ...a }"
            />
            <Button
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              @click="confirmDelete('advisor', a.id)"
            />
          </div>
        </div>
      </div>

      <EmptyStateLayout
        v-else-if="advisorsLoaded"
        :title="t('JABVOX_AUDIO.CONFIG.ADVISORS.EMPTY_TITLE')"
        :subtitle="t('JABVOX_AUDIO.CONFIG.ADVISORS.EMPTY')"
        :show-backdrop="false"
      />
    </SettingsCard>

    <!-- ══════════════ Tipificaciones (lectura) ══════════════ -->
    <SettingsCard
      v-else-if="activeSubTab === 'typifications'"
      :title="t('JABVOX_AUDIO.CONFIG.TYPIFICATIONS.TITLE')"
      :description="t('JABVOX_AUDIO.CONFIG.TYPIFICATIONS.SUBTITLE')"
      icon="i-lucide-tags"
    >
      <div
        class="flex items-start gap-2 rounded-xl bg-n-brand/5 outline outline-1 outline-n-brand/20 px-4 py-3 text-sm text-n-slate-11 mb-4"
      >
        <span class="i-lucide-info size-4 text-n-brand shrink-0 mt-0.5" />
        {{ t('JABVOX_AUDIO.CONFIG.TYPIFICATIONS.NOTICE') }}
      </div>

      <div v-if="typifications.length" class="flex flex-col gap-2">
        <div
          v-for="tp in typifications"
          :key="tp.id"
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak px-4 py-3"
        >
          <span class="text-sm font-medium text-n-slate-12 truncate">
            {{ tp.name }}
          </span>
          <span
            v-if="infaltablesCount[tp.id] != null"
            class="text-xs text-n-slate-11 shrink-0"
          >
            {{
              t('JABVOX_AUDIO.CONFIG.TYPIFICATIONS.INFALTABLES_COUNT', {
                count: infaltablesCount[tp.id],
              })
            }}
          </span>
        </div>
      </div>

      <EmptyStateLayout
        v-else-if="typificationsLoaded"
        :title="t('JABVOX_AUDIO.CONFIG.TYPIFICATIONS.EMPTY_TITLE')"
        :subtitle="t('JABVOX_AUDIO.CONFIG.TYPIFICATIONS.EMPTY')"
        :show-backdrop="false"
      />
    </SettingsCard>

    <!-- ══════════════ Infaltables ══════════════ -->
    <SettingsCard
      v-else-if="activeSubTab === 'infaltables'"
      :title="t('JABVOX_AUDIO.CONFIG.INFALTABLES.TITLE')"
      :description="t('JABVOX_AUDIO.CONFIG.INFALTABLES.SUBTITLE')"
      icon="i-lucide-list-checks"
    >
      <div class="flex flex-col gap-5">
        <!-- Selector de tipificación -->
        <div class="flex flex-col gap-1.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AUDIO.CONFIG.INFALTABLES.TYPIFICATION') }}
          </span>
          <Select
            v-model="selectedTypificationId"
            :options="typificationOptions"
            @update:model-value="onTypificationChange"
          />
        </div>

        <div
          v-if="loadingInfaltables"
          class="flex items-center gap-2 py-6 text-sm text-n-slate-11"
        >
          <Spinner :size="16" />
          {{ t('JABVOX_AUDIO.CONFIG.INFALTABLES.LOADING') }}
        </div>

        <template v-else-if="selectedTypificationId">
          <!-- Lista editable -->
          <div class="flex flex-col gap-2">
            <div
              v-for="(item, index) in infaltables"
              :key="index"
              class="flex items-center gap-2 rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2"
            >
              <span class="text-xs text-n-slate-10 w-5 shrink-0 text-center">
                {{ index + 1 }}
              </span>
              <Input
                v-model="item.text"
                size="sm"
                class="flex-1"
                :placeholder="t('JABVOX_AUDIO.CONFIG.INFALTABLES.TEXT')"
              />
              <label
                class="flex items-center gap-1.5 text-xs text-n-slate-11 shrink-0"
              >
                <Switch v-model="item.optional" />
                {{ t('JABVOX_AUDIO.CONFIG.INFALTABLES.OPTIONAL') }}
              </label>
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="removeInfaltable(index)"
              />
            </div>

            <Button
              :label="t('JABVOX_AUDIO.CONFIG.INFALTABLES.ADD')"
              icon="i-lucide-plus"
              variant="outline"
              color="slate"
              size="sm"
              class="self-start"
              @click="addInfaltable"
            />
          </div>

          <!-- Pegar varios -->
          <div class="flex flex-col gap-1.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AUDIO.CONFIG.INFALTABLES.BULK_PASTE') }}
            </span>
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.CONFIG.INFALTABLES.BULK_PASTE_HINT') }}
            </p>
            <textarea
              v-model="bulkPaste"
              rows="4"
              class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-alpha-black1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
              :placeholder="t('JABVOX_AUDIO.CONFIG.INFALTABLES.BULK_PASTE')"
            />
            <Button
              :label="t('JABVOX_AUDIO.CONFIG.INFALTABLES.BULK_APPLY')"
              icon="i-lucide-wand-sparkles"
              variant="outline"
              color="slate"
              size="sm"
              class="self-start"
              @click="applyBulkPaste"
            />
          </div>

          <div class="flex items-center gap-2 pt-1">
            <Button
              :label="t('JABVOX_AUDIO.CONFIG.INFALTABLES.SAVE_ALL')"
              icon="i-lucide-save"
              @click="saveInfaltables"
            />
          </div>
        </template>

        <p v-else class="text-sm text-n-slate-11 py-6">
          {{ t('JABVOX_AUDIO.CONFIG.INFALTABLES.PICK_FIRST') }}
        </p>
      </div>
    </SettingsCard>

    <!-- ══════════════ Cercanía (Anatomía) ══════════════ -->
    <SettingsCard
      v-else-if="activeSubTab === 'anatomy'"
      :title="t('JABVOX_AUDIO.CONFIG.ANATOMY.TITLE')"
      :description="t('JABVOX_AUDIO.CONFIG.ANATOMY.SUBTITLE')"
      icon="i-lucide-heart-handshake"
    >
      <template #actions>
        <div class="flex items-center gap-2">
          <Button
            :label="t('JABVOX_AUDIO.CONFIG.ANATOMY.SEED')"
            icon="i-lucide-rotate-ccw"
            variant="outline"
            color="slate"
            size="sm"
            @click="seedAnatomy"
          />
          <Button
            :label="t('JABVOX_AUDIO.CONFIG.ANATOMY.NEW')"
            icon="i-lucide-plus"
            size="sm"
            @click="editingCriterion = newCriterion()"
          />
        </div>
      </template>

      <!-- Editor inline -->
      <div
        v-if="editingCriterion"
        class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 flex flex-col gap-4 mb-4"
      >
        <Input
          v-model="editingCriterion.name"
          :label="t('JABVOX_AUDIO.CONFIG.ANATOMY.NAME')"
          :placeholder="t('JABVOX_AUDIO.CONFIG.ANATOMY.NAME')"
        />
        <div class="flex flex-col gap-1.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AUDIO.CONFIG.ANATOMY.DESCRIPTION') }}
          </span>
          <textarea
            v-model="editingCriterion.description"
            rows="2"
            class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-alpha-black1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
            :placeholder="t('JABVOX_AUDIO.CONFIG.ANATOMY.DESCRIPTION')"
          />
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AUDIO.CONFIG.ANATOMY.POSITIVE') }}
            </span>
            <textarea
              v-model="editingCriterion.positive_signal"
              rows="2"
              class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-alpha-black1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
              :placeholder="t('JABVOX_AUDIO.CONFIG.ANATOMY.POSITIVE')"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AUDIO.CONFIG.ANATOMY.OPPORTUNITY') }}
            </span>
            <textarea
              v-model="editingCriterion.opportunity_signal"
              rows="2"
              class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-alpha-black1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
              :placeholder="t('JABVOX_AUDIO.CONFIG.ANATOMY.OPPORTUNITY')"
            />
          </div>
        </div>
        <div class="flex items-center gap-2">
          <Button :label="t('JABVOX_AUDIO.SAVE')" @click="saveCriterion" />
          <Button
            :label="t('JABVOX_AUDIO.CANCEL')"
            variant="ghost"
            color="slate"
            @click="editingCriterion = null"
          />
        </div>
      </div>

      <div v-if="anatomyCriteria.length" class="flex flex-col gap-2">
        <div
          v-for="c in anatomyCriteria"
          :key="c.id"
          class="rounded-xl border border-n-weak px-4 py-3"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-12">{{ c.name }}</p>
              <p
                v-if="c.description"
                class="text-xs text-n-slate-11 mt-0.5 whitespace-pre-wrap"
              >
                {{ c.description }}
              </p>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                @click="editingCriterion = { ...c }"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="confirmDelete('criterion', c.id)"
              />
            </div>
          </div>
          <div
            v-if="c.positive_signal || c.opportunity_signal"
            class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-2"
          >
            <p
              v-if="c.positive_signal"
              class="text-xs text-n-teal-11 flex items-start gap-1"
            >
              <span class="i-lucide-check size-3.5 shrink-0 mt-0.5" />
              {{ c.positive_signal }}
            </p>
            <p
              v-if="c.opportunity_signal"
              class="text-xs text-n-amber-11 flex items-start gap-1"
            >
              <span class="i-lucide-triangle-alert size-3.5 shrink-0 mt-0.5" />
              {{ c.opportunity_signal }}
            </p>
          </div>
        </div>
      </div>

      <EmptyStateLayout
        v-else-if="anatomyLoaded"
        :title="t('JABVOX_AUDIO.CONFIG.ANATOMY.EMPTY_TITLE')"
        :subtitle="t('JABVOX_AUDIO.CONFIG.ANATOMY.EMPTY')"
        :show-backdrop="false"
      />
    </SettingsCard>

    <!-- ══════════════ Formatos de archivo ══════════════ -->
    <template v-else-if="activeSubTab === 'patterns'">
      <SettingsCard
        :title="t('JABVOX_AUDIO.CONFIG.PATTERNS.TITLE')"
        :description="t('JABVOX_AUDIO.CONFIG.PATTERNS.SUBTITLE')"
        icon="i-lucide-file-cog"
      >
        <template #actions>
          <Button
            :label="t('JABVOX_AUDIO.CONFIG.PATTERNS.NEW')"
            icon="i-lucide-plus"
            size="sm"
            @click="editingPattern = newPattern()"
          />
        </template>

        <!-- Ayuda: campos reconocidos + ejemplo -->
        <div
          class="flex flex-col gap-2 rounded-xl bg-n-brand/5 outline outline-1 outline-n-brand/20 px-4 py-3 mb-4"
        >
          <p class="flex items-start gap-2 text-sm text-n-slate-11">
            <span class="i-lucide-info size-4 text-n-brand shrink-0 mt-0.5" />
            {{ t('JABVOX_AUDIO.CONFIG.PATTERNS.EXAMPLE') }}
          </p>
          <div v-if="knownFields.length" class="flex flex-wrap gap-1.5">
            <code
              v-for="f in knownFields"
              :key="f"
              class="text-xs px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-12"
            >
              {{ fieldToken(f) }}
            </code>
          </div>
        </div>

        <!-- Editor inline -->
        <div
          v-if="editingPattern"
          class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 flex flex-col gap-4 mb-4"
        >
          <Input
            v-model="editingPattern.name"
            :label="t('JABVOX_AUDIO.CONFIG.PATTERNS.NAME')"
            :placeholder="t('JABVOX_AUDIO.CONFIG.PATTERNS.NAME')"
          />
          <Input
            v-model="editingPattern.pattern"
            :label="t('JABVOX_AUDIO.CONFIG.PATTERNS.PATTERN')"
            placeholder="{phone}-{campaign} {advisor_name}"
          />
          <Input
            v-model="editingPattern.date_format"
            :label="t('JABVOX_AUDIO.CONFIG.PATTERNS.DATE_FORMAT')"
            placeholder="%Y%m%d"
          />
          <div class="flex items-center gap-2">
            <Button :label="t('JABVOX_AUDIO.SAVE')" @click="savePattern" />
            <Button
              :label="t('JABVOX_AUDIO.CANCEL')"
              variant="ghost"
              color="slate"
              @click="editingPattern = null"
            />
          </div>
        </div>

        <div v-if="patterns.length" class="flex flex-col gap-2">
          <div
            v-for="p in patterns"
            :key="p.id"
            class="flex items-center justify-between gap-3 rounded-xl border border-n-weak px-4 py-3 transition-colors hover:bg-n-alpha-1"
          >
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ p.name }}
              </p>
              <code class="text-xs text-n-slate-11 truncate block">
                {{ p.pattern }}
              </code>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                @click="editingPattern = { ...p }"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="confirmDelete('pattern', p.id)"
              />
            </div>
          </div>
        </div>

        <EmptyStateLayout
          v-else-if="patternsLoaded"
          :title="t('JABVOX_AUDIO.CONFIG.PATTERNS.EMPTY_TITLE')"
          :subtitle="t('JABVOX_AUDIO.CONFIG.PATTERNS.EMPTY')"
          :show-backdrop="false"
        />
      </SettingsCard>

      <!-- Probador de patrones -->
      <SettingsCard
        :title="t('JABVOX_AUDIO.CONFIG.PATTERNS.PROBE_TITLE')"
        :description="t('JABVOX_AUDIO.CONFIG.PATTERNS.PROBE_SUBTITLE')"
        icon="i-lucide-flask-conical"
      >
        <div class="flex flex-col gap-4">
          <Input
            v-model="probe.pattern"
            :label="t('JABVOX_AUDIO.CONFIG.PATTERNS.PATTERN')"
            placeholder="{phone}-{campaign} {advisor_name}"
          />
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="probe.sample"
              :label="t('JABVOX_AUDIO.CONFIG.PATTERNS.SAMPLE')"
              placeholder="3016615126-AMP Paula Ramírez"
            />
            <Input
              v-model="probe.date_format"
              :label="t('JABVOX_AUDIO.CONFIG.PATTERNS.DATE_FORMAT')"
              placeholder="%Y%m%d"
            />
          </div>
          <div class="flex items-center gap-2">
            <Button
              :label="t('JABVOX_AUDIO.CONFIG.PATTERNS.PROBE_RUN')"
              icon="i-lucide-play"
              :is-loading="probing"
              @click="runProbe"
            />
          </div>

          <!-- Resultado del probador -->
          <div
            v-if="probeResult"
            class="rounded-xl border border-n-weak bg-n-alpha-black1 p-4 flex flex-col gap-3"
          >
            <div v-if="probeFields.length" class="flex flex-col gap-1.5">
              <span class="text-xs font-semibold text-n-slate-11 uppercase">
                {{ t('JABVOX_AUDIO.CONFIG.PATTERNS.PROBE_FIELDS') }}
              </span>
              <div
                v-for="f in probeFields"
                :key="f.key"
                class="flex items-center gap-2 text-sm"
              >
                <code
                  class="text-xs px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-12 shrink-0"
                >
                  {{ f.key }}
                </code>
                <span class="text-n-slate-12 truncate">{{ f.value }}</span>
              </div>
            </div>
            <p v-else class="text-sm text-n-amber-11">
              {{ t('JABVOX_AUDIO.CONFIG.PATTERNS.PROBE_NO_MATCH') }}
            </p>

            <div
              v-if="probeResult.advisor"
              class="flex items-center gap-2 text-sm text-n-teal-11 border-t border-n-weak pt-3"
            >
              <span class="i-lucide-user-check size-4 shrink-0" />
              {{ t('JABVOX_AUDIO.CONFIG.PATTERNS.PROBE_ADVISOR') }}
              <span class="font-medium">
                {{ probeResult.advisor.name }}
              </span>
            </div>
          </div>
        </div>
      </SettingsCard>
    </template>

    <!-- ══════════════ Mapeos ══════════════ -->
    <template v-else-if="activeSubTab === 'mappings'">
      <!-- Intro -->
      <div
        class="flex items-start gap-2 rounded-xl bg-n-brand/5 outline outline-1 outline-n-brand/20 px-4 py-3 text-sm text-n-slate-11"
      >
        <span class="i-lucide-info size-4 text-n-brand shrink-0 mt-0.5" />
        {{ t('JABVOX_AUDIO.CONFIG.MAPPINGS.INTRO') }}
      </div>

      <!-- Código → Tipificación -->
      <SettingsCard
        :title="t('JABVOX_AUDIO.CONFIG.MAPPINGS.TYPIFICATION_TITLE')"
        :description="t('JABVOX_AUDIO.CONFIG.MAPPINGS.TYPIFICATION_SUBTITLE')"
        icon="i-lucide-tags"
      >
        <template #actions>
          <Button
            :label="t('JABVOX_AUDIO.CONFIG.MAPPINGS.ADD')"
            icon="i-lucide-plus"
            size="sm"
            @click="editingTypificationMapping = newTypificationMapping()"
          />
        </template>

        <!-- Editor inline -->
        <div
          v-if="editingTypificationMapping"
          class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 flex flex-col gap-4 mb-4"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="editingTypificationMapping.code"
              :label="t('JABVOX_AUDIO.CONFIG.MAPPINGS.CODE')"
              :placeholder="
                t('JABVOX_AUDIO.CONFIG.MAPPINGS.CODE_TYPIFICATION_PLACEHOLDER')
              "
            />
            <div class="flex flex-col gap-1.5">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_AUDIO.CONFIG.MAPPINGS.TYPIFICATION') }}
              </span>
              <Select
                v-model="editingTypificationMapping.typification_id"
                :options="typificationOptions"
              />
            </div>
          </div>
          <div class="flex items-center gap-2">
            <Button
              :label="t('JABVOX_AUDIO.SAVE')"
              @click="saveTypificationMapping"
            />
            <Button
              :label="t('JABVOX_AUDIO.CANCEL')"
              variant="ghost"
              color="slate"
              @click="editingTypificationMapping = null"
            />
          </div>
        </div>

        <div v-if="typificationMappings.length" class="flex flex-col gap-2">
          <div
            v-for="m in typificationMappings"
            :key="m.id"
            class="flex items-center justify-between gap-3 rounded-xl border border-n-weak px-4 py-3 transition-colors hover:bg-n-alpha-1"
          >
            <div class="flex items-center gap-2 min-w-0">
              <code
                class="text-xs px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-12 shrink-0"
              >
                {{ m.code }}
              </code>
              <span
                class="i-lucide-arrow-right size-3.5 text-n-slate-10 shrink-0"
              />
              <span class="text-sm text-n-slate-12 truncate">
                {{
                  m.typification_name ||
                  t('JABVOX_AUDIO.CONFIG.MAPPINGS.UNASSIGNED')
                }}
              </span>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                @click="editingTypificationMapping = { ...m }"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="confirmDelete('typification_mapping', m.id)"
              />
            </div>
          </div>
        </div>

        <EmptyStateLayout
          v-else-if="mappingsLoaded"
          :title="t('JABVOX_AUDIO.CONFIG.MAPPINGS.EMPTY_TITLE')"
          :subtitle="t('JABVOX_AUDIO.CONFIG.MAPPINGS.TYPIFICATION_EMPTY')"
          :show-backdrop="false"
        />
      </SettingsCard>

      <!-- Nombre/código del liker → Asesor -->
      <SettingsCard
        :title="t('JABVOX_AUDIO.CONFIG.MAPPINGS.ADVISOR_TITLE')"
        :description="t('JABVOX_AUDIO.CONFIG.MAPPINGS.ADVISOR_SUBTITLE')"
        icon="i-lucide-users"
      >
        <template #actions>
          <Button
            :label="t('JABVOX_AUDIO.CONFIG.MAPPINGS.ADD')"
            icon="i-lucide-plus"
            size="sm"
            @click="editingAdvisorMapping = newAdvisorMapping()"
          />
        </template>

        <!-- Editor inline -->
        <div
          v-if="editingAdvisorMapping"
          class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 flex flex-col gap-4 mb-4"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="editingAdvisorMapping.code"
              :label="t('JABVOX_AUDIO.CONFIG.MAPPINGS.CODE')"
              :placeholder="
                t('JABVOX_AUDIO.CONFIG.MAPPINGS.CODE_ADVISOR_PLACEHOLDER')
              "
            />
            <div class="flex flex-col gap-1.5">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_AUDIO.CONFIG.MAPPINGS.ADVISOR') }}
              </span>
              <Select
                v-model="editingAdvisorMapping.advisor_id"
                :options="advisorOptions"
              />
            </div>
          </div>
          <div class="flex items-center gap-2">
            <Button
              :label="t('JABVOX_AUDIO.SAVE')"
              @click="saveAdvisorMapping"
            />
            <Button
              :label="t('JABVOX_AUDIO.CANCEL')"
              variant="ghost"
              color="slate"
              @click="editingAdvisorMapping = null"
            />
          </div>
        </div>

        <div v-if="advisorMappings.length" class="flex flex-col gap-2">
          <div
            v-for="m in advisorMappings"
            :key="m.id"
            class="flex items-center justify-between gap-3 rounded-xl border border-n-weak px-4 py-3 transition-colors hover:bg-n-alpha-1"
          >
            <div class="flex items-center gap-2 min-w-0">
              <code
                class="text-xs px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-12 shrink-0"
              >
                {{ m.code }}
              </code>
              <span
                class="i-lucide-arrow-right size-3.5 text-n-slate-10 shrink-0"
              />
              <span class="text-sm text-n-slate-12 truncate">
                {{
                  m.advisor_name || t('JABVOX_AUDIO.CONFIG.MAPPINGS.UNASSIGNED')
                }}
              </span>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                @click="editingAdvisorMapping = { ...m }"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="confirmDelete('advisor_mapping', m.id)"
              />
            </div>
          </div>
        </div>

        <EmptyStateLayout
          v-else-if="mappingsLoaded"
          :title="t('JABVOX_AUDIO.CONFIG.MAPPINGS.EMPTY_TITLE')"
          :subtitle="t('JABVOX_AUDIO.CONFIG.MAPPINGS.ADVISOR_EMPTY')"
          :show-backdrop="false"
        />
      </SettingsCard>
    </template>

    <ConfirmDialog ref="confirmDialog" @confirm="onConfirmDelete" />
  </div>
</template>
