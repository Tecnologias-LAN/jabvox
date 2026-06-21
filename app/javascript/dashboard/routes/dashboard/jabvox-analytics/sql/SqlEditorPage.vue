<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsQueryStore } from 'dashboard/stores/jabvox/analytics/query';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsEmptyState from '../components/AnalyticsEmptyState.vue';
import AnalyticsDataTable from '../data-sources/AnalyticsDataTable.vue';
import SqlValidationFeedback from './SqlValidationFeedback.vue';

const { t } = useI18n();
const dsStore = useAnalyticsDataSourcesStore();
const queryStore = useAnalyticsQueryStore();
const capabilities = useAnalyticsCapabilitiesStore();
const { showError } = useAnalyticsError();

const selectedDsId = ref(null);

const canUseSql = computed(() => capabilities.canUseCustomSql);
const dataSources = computed(() => dsStore.list);

const sql = computed({
  get: () => queryStore.sql,
  set: value => {
    queryStore.sql = value;
  },
});

const validation = computed(() => queryStore.validation);
const rows = computed(() => queryStore.result.rows);
const resultColumns = computed(() => queryStore.result.columns);
const validating = computed(() => queryStore.uiFlags.validating);
const running = computed(() => queryStore.uiFlags.running);

const canExecute = computed(() =>
  Boolean(selectedDsId.value && sql.value.trim())
);

const validate = async () => {
  if (!canExecute.value) return;
  try {
    await queryStore.validateSql(selectedDsId.value);
  } catch (error) {
    showError(error);
  }
};

const run = async () => {
  if (!canExecute.value) return;
  try {
    await queryStore.runSql(selectedDsId.value);
  } catch (error) {
    showError(error);
  }
};

onMounted(() => {
  if (canUseSql.value) dsStore.fetch().catch(error => showError(error));
});

const controlClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div>
    <AnalyticsPageHeader :title="t('JABVOX_ANALYTICS.SQL.TITLE')" />

    <AnalyticsEmptyState
      v-if="!canUseSql"
      icon="i-lucide-lock"
      :title="t('JABVOX_ANALYTICS.SQL.NO_PERMISSION')"
    />

    <template v-else>
      <div class="mb-4 max-w-sm">
        <label class="mb-1 block text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.DATA_SOURCE') }}
        </label>
        <select
          :value="selectedDsId"
          :class="controlClass"
          @change="selectedDsId = Number($event.target.value) || null"
        >
          <option :value="null">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
          <option v-for="ds in dataSources" :key="ds.id" :value="ds.id">
            {{ ds.nameJabvox }}
          </option>
        </select>
      </div>

      <div
        class="mb-3 flex items-center gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-11"
      >
        <span class="i-lucide-info size-4 shrink-0" />
        {{ t('JABVOX_ANALYTICS.SQL.READ_ONLY_NOTICE') }}
      </div>

      <textarea
        v-model="sql"
        rows="8"
        spellcheck="false"
        class="block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 font-mono text-sm text-n-slate-12 outline-none focus:border-n-strong focus:ring-1 focus:ring-n-brand"
        placeholder="SELECT * FROM ..."
      />

      <div class="mt-3 flex items-center gap-3">
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="!canExecute || validating"
          @click="validate"
        >
          <span
            v-if="validating"
            class="i-lucide-loader-circle size-4 animate-spin"
          />
          {{ t('JABVOX_ANALYTICS.SQL.VALIDATE') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="!canExecute || running"
          @click="run"
        >
          <span
            v-if="running"
            class="i-lucide-loader-circle size-4 animate-spin"
          />
          <span v-else class="i-lucide-play size-4" />
          {{ t('JABVOX_ANALYTICS.SQL.RUN') }}
        </button>
      </div>

      <div v-if="validation" class="mt-3">
        <SqlValidationFeedback :validation="validation" />
      </div>

      <div class="mt-4">
        <AnalyticsDataTable
          :rows="rows"
          :columns="resultColumns"
          :loading="running"
        />
      </div>
    </template>
  </div>
</template>
