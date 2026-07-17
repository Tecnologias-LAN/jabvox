<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dataExportAPI } from 'dashboard/api/jabvox/dataExport';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const apiError = (e, fallback) => e?.response?.data?.error || t(fallback);

// ---------- Tabs ----------
const activeTab = ref('config'); // 'config' | 'history'

// ---------- Target (the account's single external DB) ----------
const target = ref(null);
const editing = ref(null);
const testResult = ref(null);
const testing = ref(false);
const building = ref(false);
const syncing = ref(false);
const loading = ref(true);
const confirmDialog = ref(null);

// ---------- Export groups (modules to export) ----------
const groups = ref([]); // [{ key, always, table_count }]
const selectedGroups = ref([]); // array of group keys

// ---------- History ----------
const historyItems = ref([]);
const historyCounts = ref({});
const historyStatus = ref(''); // '' | queued | exported | failed
const historyPage = ref(1);
const historyTotal = ref(0);
const historyLoading = ref(false);

const engineOptions = computed(() => [
  { value: 'postgresql', label: 'PostgreSQL' },
  { value: 'mysql', label: 'MySQL' },
  { value: 'mariadb', label: 'MariaDB' },
]);

const sslOptions = computed(() => [
  { value: 'disable', label: t('JABVOX_DATA_EXPORT.SSL.DISABLE') },
  { value: 'prefer', label: t('JABVOX_DATA_EXPORT.SSL.PREFER') },
  { value: 'require', label: t('JABVOX_DATA_EXPORT.SSL.REQUIRE') },
]);

// Group key -> i18n label + description, so the checklist explains what it exports.
const groupLabel = key =>
  t(`JABVOX_DATA_EXPORT.GROUPS.${key.toUpperCase()}.LABEL`, key);
const groupDesc = key =>
  t(`JABVOX_DATA_EXPORT.GROUPS.${key.toUpperCase()}.DESC`, '');

const loadGroups = async () => {
  try {
    const { data } = await dataExportAPI.availableGroups();
    groups.value = data.groups || [];
    // Default selection: everything available (first-time setup).
    if (!target.value && selectedGroups.value.length === 0) {
      selectedGroups.value = groups.value.map(g => g.key);
    }
  } catch {
    groups.value = [];
  }
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await dataExportAPI.getAll();
    target.value = (data.targets || [])[0] || null;
    selectedGroups.value = target.value?.selected_modules_jabvox || [];
    await loadGroups();
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.ERRORS.LOAD'));
  } finally {
    loading.value = false;
  }
};

// ---------- Form ----------
const newTarget = () => ({
  name_jabvox: '',
  engine_jabvox: 'postgresql',
  host_jabvox: '',
  port_jabvox: null,
  database_jabvox: '',
  username_jabvox: '',
  password_jabvox: '',
  ssl_mode_jabvox: 'prefer',
  allow_private_network_jabvox: false,
});

const openNew = () => {
  editing.value = newTarget();
  testResult.value = null;
  selectedGroups.value = groups.value.map(g => g.key);
};
const openEdit = () => {
  editing.value = { ...target.value, password_jabvox: '' };
  testResult.value = null;
  selectedGroups.value = target.value?.selected_modules_jabvox || [];
};
const cancelEdit = () => {
  editing.value = null;
  testResult.value = null;
};

const isToggleable = g => !g.always;
const isGroupSelected = key => selectedGroups.value.includes(key);
const toggleGroup = key => {
  const g = groups.value.find(x => x.key === key);
  if (g?.always) return; // always-on groups can't be turned off
  if (isGroupSelected(key)) {
    selectedGroups.value = selectedGroups.value.filter(k => k !== key);
  } else {
    selectedGroups.value = [...selectedGroups.value, key];
  }
};

const payload = () => ({
  ...editing.value,
  selected_modules_jabvox: selectedGroups.value,
});

const canSave = computed(
  () =>
    editing.value?.name_jabvox &&
    editing.value?.host_jabvox &&
    editing.value?.database_jabvox
);

const testConnection = async () => {
  testing.value = true;
  testResult.value = null;
  try {
    const { data } = await dataExportAPI.test(editing.value);
    testResult.value = data;
  } catch (e) {
    testResult.value = {
      success: false,
      message: apiError(e, 'JABVOX_DATA_EXPORT.ERRORS.TEST'),
    };
  } finally {
    testing.value = false;
  }
};

const save = async () => {
  try {
    if (target.value) {
      const { data } = await dataExportAPI.update(target.value.id, payload());
      target.value = data;
    } else {
      const { data } = await dataExportAPI.create(payload());
      target.value = data;
    }
    editing.value = null;
    useAlert(t('JABVOX_DATA_EXPORT.SAVED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.ERRORS.SAVE'));
  }
};

const buildSchema = async () => {
  building.value = true;
  try {
    await dataExportAPI.buildSchema(target.value.id);
    await load();
    useAlert(t('JABVOX_DATA_EXPORT.SCHEMA_BUILT'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.ERRORS.SCHEMA'));
  } finally {
    building.value = false;
  }
};

const toggleEnabled = async () => {
  try {
    const { data } = await dataExportAPI.toggle(
      target.value.id,
      !target.value.enabled_jabvox
    );
    target.value = data;
    useAlert(
      target.value.enabled_jabvox
        ? t('JABVOX_DATA_EXPORT.ENABLED')
        : t('JABVOX_DATA_EXPORT.DISABLED')
    );
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.ERRORS.TOGGLE'));
  }
};

const syncNow = async () => {
  syncing.value = true;
  try {
    await dataExportAPI.syncNow(target.value.id);
    useAlert(t('JABVOX_DATA_EXPORT.SYNC_QUEUED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.ERRORS.SYNC'));
  } finally {
    syncing.value = false;
  }
};

const confirmDelete = () => {
  confirmDialog.value?.open({
    title: t('JABVOX_DATA_EXPORT.DELETE.TITLE'),
    message: t('JABVOX_DATA_EXPORT.DELETE.MESSAGE'),
    confirm: t('JABVOX_DATA_EXPORT.DELETE.CONFIRM'),
    onConfirm: async () => {
      try {
        await dataExportAPI.destroy(target.value.id);
        target.value = null;
        useAlert(t('JABVOX_DATA_EXPORT.DELETED'));
      } catch (e) {
        useAlert(apiError(e, 'JABVOX_DATA_EXPORT.ERRORS.DELETE'));
      }
    },
  });
};

// ---------- History ----------
const loadHistory = async () => {
  if (!target.value) return;
  historyLoading.value = true;
  try {
    const { data } = await dataExportAPI.history(target.value.id, {
      status: historyStatus.value || undefined,
      page: historyPage.value,
    });
    historyItems.value = data.items || [];
    historyCounts.value = data.counts || {};
    historyTotal.value = data.total || 0;
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.ERRORS.HISTORY'));
  } finally {
    historyLoading.value = false;
  }
};

const setHistoryStatus = status => {
  historyStatus.value = status;
  historyPage.value = 1;
  loadHistory();
};

const historyPages = computed(() => Math.ceil(historyTotal.value / 25) || 1);
const changeHistoryPage = delta => {
  const next = historyPage.value + delta;
  if (next < 1 || next > historyPages.value) return;
  historyPage.value = next;
  loadHistory();
};

const openTab = tab => {
  activeTab.value = tab;
  if (tab === 'history') loadHistory();
};

const statusClass = status =>
  ({
    exported: 'text-n-teal-11 bg-n-teal-3',
    queued: 'text-n-amber-11 bg-n-amber-3',
    failed: 'text-n-ruby-11 bg-n-ruby-3',
  })[status] || 'text-n-slate-11 bg-n-alpha-2';

onMounted(load);
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div class="flex flex-col gap-4 p-6 max-w-4xl mx-auto">
      <!-- Header -->
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold text-n-slate-12">
          {{ t('JABVOX_DATA_EXPORT.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_DATA_EXPORT.SUBTITLE') }}
        </p>
      </div>

      <!-- Tabs -->
      <div class="flex gap-1 border-b border-n-weak">
        <button
          class="px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors"
          :class="
            activeTab === 'config'
              ? 'border-n-brand text-n-brand'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="openTab('config')"
        >
          {{ t('JABVOX_DATA_EXPORT.TABS.CONFIG') }}
        </button>
        <button
          class="px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors"
          :class="
            activeTab === 'history'
              ? 'border-n-brand text-n-brand'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          :disabled="!target"
          @click="openTab('history')"
        >
          {{ t('JABVOX_DATA_EXPORT.TABS.HISTORY') }}
        </button>
      </div>

      <div v-if="loading" class="flex justify-center py-10">
        <Spinner />
      </div>

      <!-- ====================== CONFIG TAB ====================== -->
      <template v-else-if="activeTab === 'config'">
        <!-- Explanation card -->
        <div
          class="rounded-xl bg-n-alpha-1 border border-n-weak p-4 text-sm text-n-slate-11 flex flex-col gap-1"
        >
          <p class="font-medium text-n-slate-12">
            {{ t('JABVOX_DATA_EXPORT.EXPLAIN.TITLE') }}
          </p>
          <p>{{ t('JABVOX_DATA_EXPORT.EXPLAIN.BODY') }}</p>
          <p class="text-xs text-n-slate-10 mt-1">
            {{ t('JABVOX_DATA_EXPORT.EXPLAIN.ONE_DB') }}
          </p>
        </div>

        <!-- No target + not editing: prompt to connect -->
        <div
          v-if="!target && !editing"
          class="rounded-xl border border-dashed border-n-weak p-8 flex flex-col items-center gap-3 text-center"
        >
          <span class="i-lucide-database size-8 text-n-slate-10" />
          <p class="text-sm text-n-slate-11">
            {{ t('JABVOX_DATA_EXPORT.EMPTY') }}
          </p>
          <Button :label="t('JABVOX_DATA_EXPORT.CONNECT')" @click="openNew" />
        </div>

        <!-- Saved target summary -->
        <div
          v-else-if="target && !editing"
          class="rounded-xl border border-n-weak p-5 flex flex-col gap-4"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="flex flex-col gap-1">
              <div class="flex items-center gap-2">
                <span class="font-semibold text-n-slate-12">{{
                  target.name_jabvox
                }}</span>
                <span
                  class="text-xs px-2 py-0.5 rounded-full"
                  :class="
                    target.enabled_jabvox
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-alpha-2 text-n-slate-11'
                  "
                >
                  {{
                    target.enabled_jabvox
                      ? t('JABVOX_DATA_EXPORT.ACTIVE')
                      : t('JABVOX_DATA_EXPORT.INACTIVE')
                  }}
                </span>
              </div>
              <span class="text-sm text-n-slate-11">
                {{ target.engine_jabvox }} · {{ target.host_jabvox }}:{{
                  target.port_jabvox || '—'
                }}
                / {{ target.database_jabvox }}
              </span>
              <span
                v-if="target.last_error_jabvox"
                class="text-xs text-n-ruby-11"
              >
                {{ target.last_error_jabvox }}
              </span>
            </div>
            <Switch
              :model-value="target.enabled_jabvox"
              @update:model-value="toggleEnabled"
            />
          </div>

          <!-- Selected modules summary -->
          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="key in target.selected_modules_jabvox || []"
              :key="key"
              class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ groupLabel(key) }}
            </span>
          </div>

          <div class="flex flex-wrap gap-2 pt-2 border-t border-n-weak">
            <Button
              variant="ghost"
              size="sm"
              :label="t('JABVOX_DATA_EXPORT.EDIT')"
              @click="openEdit"
            />
            <Button
              variant="ghost"
              size="sm"
              :is-loading="building"
              :label="t('JABVOX_DATA_EXPORT.BUILD_SCHEMA')"
              @click="buildSchema"
            />
            <Button
              variant="ghost"
              size="sm"
              :is-loading="syncing"
              :label="t('JABVOX_DATA_EXPORT.SYNC_NOW')"
              @click="syncNow"
            />
            <Button
              variant="ghost"
              size="sm"
              color="ruby"
              :label="t('JABVOX_DATA_EXPORT.DELETE.BUTTON')"
              @click="confirmDelete"
            />
          </div>
        </div>

        <!-- Editing / creating form -->
        <div
          v-else-if="editing"
          class="rounded-xl border border-n-weak p-5 flex flex-col gap-4"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input
              v-model="editing.name_jabvox"
              :label="t('JABVOX_DATA_EXPORT.FORM.NAME')"
            />
            <Select
              v-model="editing.engine_jabvox"
              :label="t('JABVOX_DATA_EXPORT.FORM.ENGINE')"
              :options="engineOptions"
            />
            <Input
              v-model="editing.host_jabvox"
              :label="t('JABVOX_DATA_EXPORT.FORM.HOST')"
            />
            <Input
              v-model="editing.port_jabvox"
              type="number"
              :label="t('JABVOX_DATA_EXPORT.FORM.PORT')"
            />
            <Input
              v-model="editing.database_jabvox"
              :label="t('JABVOX_DATA_EXPORT.FORM.DATABASE')"
            />
            <Input
              v-model="editing.username_jabvox"
              :label="t('JABVOX_DATA_EXPORT.FORM.USERNAME')"
            />
            <Input
              v-model="editing.password_jabvox"
              type="password"
              :label="t('JABVOX_DATA_EXPORT.FORM.PASSWORD')"
              :placeholder="
                target ? t('JABVOX_DATA_EXPORT.FORM.PASSWORD_KEEP') : ''
              "
            />
            <Select
              v-model="editing.ssl_mode_jabvox"
              :label="t('JABVOX_DATA_EXPORT.FORM.SSL')"
              :options="sslOptions"
            />
          </div>

          <label class="flex items-center gap-2 text-sm text-n-slate-11">
            <Switch v-model="editing.allow_private_network_jabvox" />
            {{ t('JABVOX_DATA_EXPORT.FORM.ALLOW_PRIVATE') }}
          </label>

          <!-- Module selection -->
          <div class="flex flex-col gap-2 pt-3 border-t border-n-weak">
            <p class="font-medium text-n-slate-12 text-sm">
              {{ t('JABVOX_DATA_EXPORT.MODULES.TITLE') }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_DATA_EXPORT.MODULES.HINT') }}
            </p>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-1">
              <label
                v-for="g in groups"
                :key="g.key"
                class="flex items-start gap-2 p-2 rounded-lg border border-n-weak cursor-pointer"
                :class="[
                  isGroupSelected(g.key)
                    ? 'bg-n-brand/5 border-n-brand/40'
                    : '',
                  g.always ? 'opacity-70 cursor-default' : '',
                ]"
              >
                <input
                  type="checkbox"
                  class="mt-0.5"
                  :checked="isGroupSelected(g.key)"
                  :disabled="!isToggleable(g)"
                  @change="toggleGroup(g.key)"
                />
                <span class="flex flex-col">
                  <span class="text-sm text-n-slate-12">
                    {{ groupLabel(g.key) }}
                    <span v-if="g.always" class="text-xs text-n-slate-10">
                      ({{ t('JABVOX_DATA_EXPORT.MODULES.ALWAYS') }})
                    </span>
                  </span>
                  <span class="text-xs text-n-slate-10">{{
                    groupDesc(g.key)
                  }}</span>
                  <span class="text-xs text-n-slate-9">{{
                    t('JABVOX_DATA_EXPORT.MODULES.TABLES', { n: g.table_count })
                  }}</span>
                </span>
              </label>
            </div>
          </div>

          <!-- Test connection -->
          <div class="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              :is-loading="testing"
              :label="t('JABVOX_DATA_EXPORT.FORM.TEST')"
              @click="testConnection"
            />
            <span
              v-if="testResult"
              class="text-sm"
              :class="testResult.success ? 'text-n-teal-11' : 'text-n-ruby-11'"
            >
              {{ testResult.message }}
            </span>
          </div>

          <div class="flex gap-2 pt-2 border-t border-n-weak">
            <Button
              :label="t('JABVOX_DATA_EXPORT.FORM.SAVE')"
              :disabled="!canSave"
              @click="save"
            />
            <Button
              variant="ghost"
              :label="t('JABVOX_DATA_EXPORT.FORM.CANCEL')"
              @click="cancelEdit"
            />
          </div>
        </div>
      </template>

      <!-- ====================== HISTORY TAB ====================== -->
      <template v-else-if="activeTab === 'history'">
        <!-- Counts summary -->
        <div class="grid grid-cols-3 gap-3">
          <button
            class="rounded-xl border border-n-weak p-4 flex flex-col items-start hover:bg-n-alpha-1"
            :class="historyStatus === 'exported' ? 'border-n-teal-6' : ''"
            @click="setHistoryStatus('exported')"
          >
            <span class="text-2xl font-semibold text-n-teal-11">{{
              historyCounts.exported || 0
            }}</span>
            <span class="text-xs text-n-slate-11">{{
              t('JABVOX_DATA_EXPORT.HISTORY.EXPORTED')
            }}</span>
          </button>
          <button
            class="rounded-xl border border-n-weak p-4 flex flex-col items-start hover:bg-n-alpha-1"
            :class="historyStatus === 'queued' ? 'border-n-amber-6' : ''"
            @click="setHistoryStatus('queued')"
          >
            <span class="text-2xl font-semibold text-n-amber-11">{{
              historyCounts.queued || 0
            }}</span>
            <span class="text-xs text-n-slate-11">{{
              t('JABVOX_DATA_EXPORT.HISTORY.QUEUED')
            }}</span>
          </button>
          <button
            class="rounded-xl border border-n-weak p-4 flex flex-col items-start hover:bg-n-alpha-1"
            :class="historyStatus === 'failed' ? 'border-n-ruby-6' : ''"
            @click="setHistoryStatus('failed')"
          >
            <span class="text-2xl font-semibold text-n-ruby-11">{{
              historyCounts.failed || 0
            }}</span>
            <span class="text-xs text-n-slate-11">{{
              t('JABVOX_DATA_EXPORT.HISTORY.FAILED')
            }}</span>
          </button>
        </div>

        <div class="flex items-center gap-2">
          <Button
            size="sm"
            :variant="historyStatus === '' ? 'solid' : 'ghost'"
            :label="t('JABVOX_DATA_EXPORT.HISTORY.ALL')"
            @click="setHistoryStatus('')"
          />
          <span class="text-xs text-n-slate-10 ml-auto">
            {{ t('JABVOX_DATA_EXPORT.HISTORY.TOTAL', { n: historyTotal }) }}
          </span>
        </div>

        <div v-if="historyLoading" class="flex justify-center py-10">
          <Spinner />
        </div>

        <div
          v-else-if="historyItems.length === 0"
          class="text-center text-sm text-n-slate-11 py-10"
        >
          {{ t('JABVOX_DATA_EXPORT.HISTORY.EMPTY') }}
        </div>

        <div v-else class="rounded-xl border border-n-weak overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-n-alpha-1 text-n-slate-11 text-xs">
              <tr>
                <th class="text-left px-3 py-2">
                  {{ t('JABVOX_DATA_EXPORT.HISTORY.MODEL') }}
                </th>
                <th class="text-left px-3 py-2">
                  {{ t('JABVOX_DATA_EXPORT.HISTORY.RECORD') }}
                </th>
                <th class="text-left px-3 py-2">
                  {{ t('JABVOX_DATA_EXPORT.HISTORY.STATUS') }}
                </th>
                <th class="text-left px-3 py-2">
                  {{ t('JABVOX_DATA_EXPORT.HISTORY.ATTEMPTS') }}
                </th>
                <th class="text-left px-3 py-2">
                  {{ t('JABVOX_DATA_EXPORT.HISTORY.WHEN') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="item in historyItems"
                :key="item.id"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2 text-n-slate-12">{{ item.model }}</td>
                <td class="px-3 py-2 text-n-slate-11">#{{ item.record_id }}</td>
                <td class="px-3 py-2">
                  <span
                    class="text-xs px-2 py-0.5 rounded-full"
                    :class="statusClass(item.status)"
                  >
                    {{
                      t(
                        `JABVOX_DATA_EXPORT.HISTORY.STATUS_${item.status.toUpperCase()}`
                      )
                    }}
                  </span>
                  <span
                    v-if="item.error"
                    class="block text-xs text-n-ruby-11 mt-0.5"
                  >
                    {{ item.error }}
                  </span>
                </td>
                <td class="px-3 py-2 text-n-slate-11">{{ item.attempts }}</td>
                <td class="px-3 py-2 text-n-slate-10 text-xs">
                  {{ item.last_attempt_at }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="historyPages > 1"
          class="flex items-center justify-center gap-3"
        >
          <Button
            size="sm"
            variant="ghost"
            :disabled="historyPage <= 1"
            label="←"
            @click="changeHistoryPage(-1)"
          />
          <span class="text-xs text-n-slate-11">
            {{ historyPage }} / {{ historyPages }}
          </span>
          <Button
            size="sm"
            variant="ghost"
            :disabled="historyPage >= historyPages"
            label="→"
            @click="changeHistoryPage(1)"
          />
        </div>
      </template>

      <ConfirmDialog ref="confirmDialog" />
    </div>
  </div>
</template>
