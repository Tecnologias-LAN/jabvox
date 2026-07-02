<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { cdrConfigAPI, cdrPipelinesAPI } from 'dashboard/api/jabvox/cdr';
import { aiChatModelsAPI } from 'dashboard/api/jabvox/aiChat';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import { DESTROY_KEY } from 'dashboard/helper/jabvox/nestedAttributes';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SectionCard from './components/SectionCard.vue';
import PipelineDrawer from './components/PipelineDrawer.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();

// Declared early because the Connection tab's "default pipeline" select reads it.
const pipelines = ref([]);

const activeTab = ref('connection');
const tabs = [
  {
    key: 'connection',
    icon: 'i-lucide-database',
    label: () => t('JABVOX_CDR.SETTINGS.TABS.CONNECTION'),
  },
  {
    key: 'pipelines',
    icon: 'i-lucide-workflow',
    label: () => t('JABVOX_CDR.SETTINGS.TABS.PIPELINES'),
  },
];

// ── connection ──
const config = ref({
  mysql_host: '',
  mysql_port: 3306,
  mysql_username: '',
  mysql_password: '',
  mysql_database: 'asteriskcdrdb',
  mysql_table: 'cdr',
  ssh_host: '',
  ssh_port: 22,
  ssh_username: '',
  ssh_password: '',
  recordings_path: '/var/spool/asterisk/monitor',
  analysis_mode: 'manual',
  min_duration_seconds: 30,
  default_pipeline_id: null,
});
// Each connection section saves only its own fields (the backend PATCH merges,
// leaving the other groups untouched). Separate flags so the spinner shows only
// on the button that was pressed.
const SECTION_FIELDS = {
  mysql: [
    'mysql_host',
    'mysql_port',
    'mysql_username',
    'mysql_password',
    'mysql_database',
    'mysql_table',
  ],
  ssh: [
    'ssh_host',
    'ssh_port',
    'ssh_username',
    'ssh_password',
    'recordings_path',
  ],
  analysis: ['analysis_mode', 'min_duration_seconds', 'default_pipeline_id'],
};
const savingSection = ref(null); // 'mysql' | 'ssh' | 'analysis' | null
const testingMysql = ref(false);
const testingSsh = ref(false);
const mysqlStatus = ref(null);
const sshStatus = ref(null);
const showMysqlPassword = ref(false);
const showSshPassword = ref(false);

const analysisModeOptions = computed(() => [
  { value: 'manual', label: t('JABVOX_CDR.SETTINGS.MODE_MANUAL') },
  { value: 'auto_all', label: t('JABVOX_CDR.SETTINGS.MODE_AUTO_ALL') },
  { value: 'auto_min_duration', label: t('JABVOX_CDR.SETTINGS.MODE_AUTO_MIN') },
]);
const defaultPipelineOptions = computed(() => [
  { value: null, label: t('JABVOX_CDR.SETTINGS.NO_DEFAULT_PIPELINE') },
  ...pipelines.value.map(p => ({ value: p.id, label: p.name })),
]);

const loadConfig = async () => {
  const { data } = await cdrConfigAPI.get();
  config.value = {
    ...config.value,
    ...data,
    mysql_password: '',
    ssh_password: '',
  };
};

const saveSection = async section => {
  savingSection.value = section;
  // Send only this section's fields; the backend merges into the rest.
  const payload = {};
  SECTION_FIELDS[section].forEach(key => {
    payload[key] = config.value[key];
  });
  try {
    await cdrConfigAPI.update(payload);
    useAlert(t('JABVOX_CDR.SETTINGS.SAVED'));
    await loadConfig();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('JABVOX_CDR.SETTINGS.SAVE_ERROR')
    );
  } finally {
    savingSection.value = null;
  }
};

const testMysql = async () => {
  testingMysql.value = true;
  try {
    const { data } = await cdrConfigAPI.test(config.value);
    mysqlStatus.value = data.success;
    useAlert(data.message);
  } catch {
    mysqlStatus.value = false;
    useAlert(t('JABVOX_CDR.SETTINGS.TEST_ERROR'));
  } finally {
    testingMysql.value = false;
  }
};

const testSsh = async () => {
  testingSsh.value = true;
  try {
    const { data } = await cdrConfigAPI.testSsh(config.value);
    sshStatus.value = data.success;
    useAlert(data.message);
  } catch {
    sshStatus.value = false;
    useAlert(t('JABVOX_CDR.SETTINGS.TEST_ERROR'));
  } finally {
    testingSsh.value = false;
  }
};

// ── pipelines ──
const aiModels = ref([]);
const typifications = ref([]);
const pipelineSearch = ref('');
const pipelineDrawer = ref(null);
const deleteDialog = ref(null);

const filteredPipelines = computed(() => {
  const q = pipelineSearch.value.trim().toLowerCase();
  if (!q) return pipelines.value;
  return pipelines.value.filter(p => p.name?.toLowerCase().includes(q));
});

const stageCount = p => (p.stages || []).filter(s => !s[DESTROY_KEY]).length;

const loadPipelines = async () => {
  if (!aiModels.value.length) {
    const { data } = await aiChatModelsAPI.getAll();
    aiModels.value = data || [];
  }
  if (!typifications.value.length) {
    const { data } = await typificationsAPI.getAll(false);
    typifications.value = data.typifications || [];
  }
  const { data } = await cdrPipelinesAPI.getAll();
  pipelines.value = data.pipelines || [];
};

const askDeletePipeline = p => {
  deleteDialog.value?.open({
    title: t('JABVOX_CDR.SETTINGS.PIPELINE.DELETE_TITLE'),
    description: t('JABVOX_CDR.SETTINGS.PIPELINE.DELETE_BODY', {
      name: p.name,
    }),
    data: p.id,
  });
};
const doDeletePipeline = async id => {
  try {
    await cdrPipelinesAPI.destroy(id);
    await loadPipelines();
  } catch {
    useAlert(t('JABVOX_CDR.SETTINGS.SAVE_ERROR'));
  }
};

const switchTab = async key => {
  activeTab.value = key;
  if (key === 'pipelines' && !pipelines.value.length) await loadPipelines();
};

onMounted(async () => {
  await loadConfig();
  // Pipelines feed the "default pipeline" select on the Connection tab.
  await loadPipelines();
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-5xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-phone-call size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_CDR.SETTINGS.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_CDR.SETTINGS.SUBTITLE') }}
            </p>
          </div>
        </div>
        <Button
          v-if="activeTab === 'pipelines'"
          :label="t('JABVOX_CDR.SETTINGS.PIPELINE.NEW')"
          icon="i-lucide-plus"
          class="shrink-0"
          @click="pipelineDrawer?.openCreate()"
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
          @click="switchTab(tab.key)"
        >
          <span :class="tab.icon" class="size-4 shrink-0" />
          {{ tab.label() }}
        </button>
      </div>

      <!-- ── CONNECTION ── -->
      <form
        v-if="activeTab === 'connection'"
        class="flex flex-col gap-6"
        @submit.prevent
      >
        <!-- MySQL -->
        <SectionCard
          :title="t('JABVOX_CDR.SETTINGS.MYSQL')"
          :description="t('JABVOX_CDR.SETTINGS.SECTION_MYSQL_DESC')"
          icon="i-lucide-database"
        >
          <template #actions>
            <Label
              v-if="mysqlStatus !== null"
              :label="
                mysqlStatus
                  ? t('JABVOX_CDR.SETTINGS.STATUS_OK')
                  : t('JABVOX_CDR.SETTINGS.STATUS_ERROR')
              "
              :color="mysqlStatus ? 'teal' : 'ruby'"
            >
              <template #icon>
                <span
                  :class="
                    mysqlStatus ? 'i-lucide-circle-check' : 'i-lucide-circle-x'
                  "
                  class="size-3"
                />
              </template>
            </Label>
          </template>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="config.mysql_host"
              :label="t('JABVOX_CDR.SETTINGS.HOST')"
            />
            <Input
              v-model.number="config.mysql_port"
              type="number"
              label="Port"
            />
            <Input
              v-model="config.mysql_username"
              :label="t('JABVOX_CDR.SETTINGS.USER')"
            />
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_CDR.SETTINGS.PASSWORD') }}
              </label>
              <div class="relative">
                <Input
                  v-model="config.mysql_password"
                  :type="showMysqlPassword ? 'text' : 'password'"
                  custom-input-class="!pr-10"
                  placeholder="••••••••"
                />
                <button
                  type="button"
                  class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
                  @click="showMysqlPassword = !showMysqlPassword"
                >
                  <span
                    :class="
                      showMysqlPassword ? 'i-lucide-eye-off' : 'i-lucide-eye'
                    "
                    class="size-4"
                  />
                </button>
              </div>
            </div>
            <Input
              v-model="config.mysql_database"
              :label="t('JABVOX_CDR.SETTINGS.DATABASE')"
            />
            <Input
              v-model="config.mysql_table"
              :label="t('JABVOX_CDR.SETTINGS.TABLE')"
            />
          </div>

          <template #footer>
            <div class="flex items-center justify-end gap-2">
              <Button
                :label="t('JABVOX_CDR.SETTINGS.TEST')"
                icon="i-lucide-plug-zap"
                variant="outline"
                color="slate"
                size="sm"
                :is-loading="testingMysql"
                @click="testMysql"
              />
              <Button
                :label="t('JABVOX_CDR.SETTINGS.SAVE')"
                size="sm"
                :is-loading="savingSection === 'mysql'"
                @click="saveSection('mysql')"
              />
            </div>
          </template>
        </SectionCard>

        <!-- SSH -->
        <SectionCard
          :title="t('JABVOX_CDR.SETTINGS.SSH')"
          :description="t('JABVOX_CDR.SETTINGS.SECTION_SSH_DESC')"
          icon="i-lucide-hard-drive"
        >
          <template #actions>
            <Label
              v-if="sshStatus !== null"
              :label="
                sshStatus
                  ? t('JABVOX_CDR.SETTINGS.STATUS_OK')
                  : t('JABVOX_CDR.SETTINGS.STATUS_ERROR')
              "
              :color="sshStatus ? 'teal' : 'ruby'"
            >
              <template #icon>
                <span
                  :class="
                    sshStatus ? 'i-lucide-circle-check' : 'i-lucide-circle-x'
                  "
                  class="size-3"
                />
              </template>
            </Label>
          </template>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="config.ssh_host"
              :label="t('JABVOX_CDR.SETTINGS.HOST')"
            />
            <Input
              v-model.number="config.ssh_port"
              type="number"
              label="Port"
            />
            <Input
              v-model="config.ssh_username"
              :label="t('JABVOX_CDR.SETTINGS.USER')"
            />
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_CDR.SETTINGS.PASSWORD') }}
              </label>
              <div class="relative">
                <Input
                  v-model="config.ssh_password"
                  :type="showSshPassword ? 'text' : 'password'"
                  custom-input-class="!pr-10"
                  placeholder="••••••••"
                />
                <button
                  type="button"
                  class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
                  @click="showSshPassword = !showSshPassword"
                >
                  <span
                    :class="
                      showSshPassword ? 'i-lucide-eye-off' : 'i-lucide-eye'
                    "
                    class="size-4"
                  />
                </button>
              </div>
            </div>
            <div class="sm:col-span-2">
              <Input
                v-model="config.recordings_path"
                :label="t('JABVOX_CDR.SETTINGS.RECORDINGS_PATH')"
                custom-input-class="font-mono"
              />
            </div>
          </div>

          <template #footer>
            <div class="flex items-center justify-end gap-2">
              <Button
                :label="t('JABVOX_CDR.SETTINGS.TEST')"
                icon="i-lucide-plug-zap"
                variant="outline"
                color="slate"
                size="sm"
                :is-loading="testingSsh"
                @click="testSsh"
              />
              <Button
                :label="t('JABVOX_CDR.SETTINGS.SAVE')"
                size="sm"
                :is-loading="savingSection === 'ssh'"
                @click="saveSection('ssh')"
              />
            </div>
          </template>
        </SectionCard>

        <!-- Analysis -->
        <SectionCard
          :title="t('JABVOX_CDR.SETTINGS.ANALYSIS')"
          :description="t('JABVOX_CDR.SETTINGS.SECTION_ANALYSIS_DESC')"
          icon="i-lucide-cpu"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_CDR.SETTINGS.ANALYSIS') }}
              </label>
              <Select
                v-model="config.analysis_mode"
                :options="analysisModeOptions"
              />
            </div>
            <Input
              v-if="config.analysis_mode === 'auto_min_duration'"
              v-model.number="config.min_duration_seconds"
              type="number"
              :label="t('JABVOX_CDR.SETTINGS.MIN_DURATION')"
            />
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_CDR.SETTINGS.PIPELINE') }}
              </label>
              <Select
                v-model="config.default_pipeline_id"
                :options="defaultPipelineOptions"
              />
            </div>
          </div>

          <template #footer>
            <div class="flex justify-end">
              <Button
                :label="t('JABVOX_CDR.SETTINGS.SAVE')"
                size="sm"
                :is-loading="savingSection === 'analysis'"
                @click="saveSection('analysis')"
              />
            </div>
          </template>
        </SectionCard>
      </form>

      <!-- ── PIPELINES ── -->
      <div v-else-if="activeTab === 'pipelines'" class="flex flex-col gap-5">
        <EmptyStateLayout
          v-if="!pipelines.length"
          :title="t('JABVOX_CDR.SETTINGS.PIPELINE.EMPTY_TITLE')"
          :subtitle="t('JABVOX_CDR.SETTINGS.PIPELINE.SUBTITLE')"
        >
          <template #actions>
            <Button
              icon="i-lucide-plus"
              :label="t('JABVOX_CDR.SETTINGS.PIPELINE.NEW')"
              size="sm"
              @click="pipelineDrawer?.openCreate()"
            />
          </template>
        </EmptyStateLayout>

        <template v-else>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="relative w-full sm:w-64">
              <Input
                v-model="pipelineSearch"
                :placeholder="
                  t('JABVOX_CDR.SETTINGS.PIPELINE.SEARCH_PLACEHOLDER')
                "
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
              {{
                t('JABVOX_CDR.SETTINGS.PIPELINE.COUNT', {
                  count: pipelines.length,
                })
              }}
            </span>
          </div>

          <div
            v-if="!filteredPipelines.length"
            class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_CDR.SETTINGS.PIPELINE.NO_RESULTS') }}
          </div>

          <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div
              v-for="p in filteredPipelines"
              :key="p.id"
              class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm transition-shadow hover:shadow-md"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="flex items-center gap-2 min-w-0">
                  <span
                    class="i-lucide-workflow size-4 text-n-slate-10 shrink-0"
                  />
                  <p class="text-sm font-semibold text-n-slate-12 truncate">
                    {{ p.name }}
                  </p>
                </div>
                <Label
                  v-if="p.is_default"
                  :label="t('JABVOX_CDR.SETTINGS.PIPELINE.DEFAULT')"
                  color="teal"
                  compact
                />
              </div>
              <p class="flex items-center gap-1.5 text-xs text-n-slate-11">
                <span class="i-lucide-list-checks size-3.5" />
                {{ t('JABVOX_CDR.SETTINGS.PIPELINE.STAGES') }}:
                {{ stageCount(p) }}
              </p>
              <div
                class="flex items-center justify-end gap-1 pt-2 border-t border-n-weak"
              >
                <Button
                  icon="i-lucide-pencil"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  :title="t('JABVOX_CDR.SETTINGS.EDIT')"
                  @click="pipelineDrawer?.openEdit(p)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  :title="t('JABVOX_CDR.SETTINGS.DELETE')"
                  @click="askDeletePipeline(p)"
                />
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>

    <!-- Drawers / dialogs -->
    <PipelineDrawer
      ref="pipelineDrawer"
      :ai-models="aiModels"
      :typifications="typifications"
      @saved="loadPipelines"
    />
    <ConfirmDialog ref="deleteDialog" @confirm="doDeletePipeline" />
  </div>
</template>
