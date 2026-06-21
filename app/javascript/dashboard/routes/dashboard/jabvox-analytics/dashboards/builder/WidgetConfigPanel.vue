<script setup>
import { ref, reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsWidgetsStore } from 'dashboard/stores/jabvox/analytics/widgets';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';

const props = defineProps({
  open: {
    type: Boolean,
    default: false,
  },
  widget: {
    type: Object,
    default: null,
  },
  dashboardId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();
const dsStore = useAnalyticsDataSourcesStore();
const widgetsStore = useAnalyticsWidgetsStore();
const capabilities = useAnalyticsCapabilitiesStore();
const { showError } = useAnalyticsError();

const saving = ref(false);

const form = reactive({
  titleJabvox: '',
  dataSourceId: null,
  table: '',
  measure: '',
  groupBy: '',
  customSql: false,
  sql: '',
});

const dataSources = computed(() => dsStore.list);
const canUseSql = computed(() => capabilities.canUseCustomSql);

const schema = computed(() => {
  const raw = dsStore.schemaFor(form.dataSourceId);
  if (!raw) return [];
  if (Array.isArray(raw)) return raw;
  return [...(raw.tables || []), ...(raw.views || [])];
});

const tableColumns = computed(() => {
  const node = schema.value.find(item => item.name === form.table);
  return node?.columns || [];
});

const resetForm = () => {
  const w = props.widget || {};
  const spec = w.querySpecJabvox || {};
  form.titleJabvox = w.titleJabvox || '';
  form.dataSourceId = w.dataSourceId || null;
  form.table = spec.table || '';
  form.measure = spec.measure || '';
  form.groupBy = spec.groupBy || '';
  form.customSql = Boolean(w.customSqlJabvox);
  form.sql = w.customSqlJabvox || '';
};

watch(
  () => props.open,
  async isOpen => {
    if (!isOpen) return;
    resetForm();
    if (!dataSources.value.length) {
      await dsStore.fetch().catch(error => showError(error));
    }
    if (form.dataSourceId && !dsStore.schemaFor(form.dataSourceId)) {
      await dsStore.fetchSchema(form.dataSourceId).catch(() => {});
    }
  },
  { immediate: true }
);

const onDataSourceChange = async value => {
  form.dataSourceId = value;
  form.table = '';
  form.measure = '';
  form.groupBy = '';
  if (value && !dsStore.schemaFor(value)) {
    await dsStore.fetchSchema(value).catch(error => showError(error));
  }
};

const handleSave = async () => {
  saving.value = true;
  try {
    const payload = {
      title_jabvox: form.titleJabvox,
      data_source_id: form.dataSourceId,
    };
    if (form.customSql) {
      payload.custom_sql_jabvox = form.sql;
      payload.query_spec_jabvox = {};
    } else {
      payload.custom_sql_jabvox = null;
      payload.query_spec_jabvox = {
        table: form.table,
        measure: form.measure,
        groupBy: form.groupBy || null,
      };
    }
    await widgetsStore.updateWidget(
      props.dashboardId,
      props.widget.id,
      payload
    );
    useAlert(t('JABVOX_ANALYTICS.COMMON.SAVE'));
    emit('saved');
  } catch (error) {
    showError(error);
  } finally {
    saving.value = false;
  }
};

const labelClass = 'mb-1 block text-sm font-medium text-n-slate-12';
const inputClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div>
    <div
      v-if="open && widget"
      class="fixed inset-y-0 right-0 z-50 flex w-full max-w-md flex-col border-l border-n-weak bg-n-solid-1 shadow-xl"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak px-4 py-3"
      >
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.TITLE') }}
        </h3>
        <button
          type="button"
          class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <div class="flex flex-1 flex-col gap-4 overflow-y-auto p-4">
        <!-- Title -->
        <div>
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.WIDGET_TITLE') }}
          </label>
          <input
            v-model="form.titleJabvox"
            type="text"
            :class="inputClass"
            :placeholder="
              t('JABVOX_ANALYTICS.WIDGETS.CONFIG.WIDGET_TITLE_PLACEHOLDER')
            "
          />
        </div>

        <!-- Data source -->
        <div>
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.DATA_SOURCE') }}
          </label>
          <select
            :value="form.dataSourceId"
            :class="inputClass"
            @change="onDataSourceChange(Number($event.target.value) || null)"
          >
            <option :value="null">
              {{ t('JABVOX_ANALYTICS.COMMON.NONE') }}
            </option>
            <option v-for="ds in dataSources" :key="ds.id" :value="ds.id">
              {{ ds.nameJabvox }}
            </option>
          </select>
        </div>

        <!-- Custom SQL toggle -->
        <label
          v-if="canUseSql"
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <input
            v-model="form.customSql"
            type="checkbox"
            class="size-4 rounded border-n-weak"
          />
          {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.CUSTOM_SQL') }}
        </label>

        <!-- Custom SQL editor -->
        <div v-if="form.customSql && canUseSql">
          <textarea
            v-model="form.sql"
            rows="6"
            :class="inputClass"
            :placeholder="t('JABVOX_ANALYTICS.WIDGETS.CONFIG.SQL_PLACEHOLDER')"
          />
        </div>

        <!-- Visual query spec -->
        <template v-else>
          <div>
            <label :class="labelClass">
              {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.TABLE') }}
            </label>
            <select v-model="form.table" :class="inputClass">
              <option value="">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
              <option v-for="tbl in schema" :key="tbl.name" :value="tbl.name">
                {{ tbl.name }}
              </option>
            </select>
          </div>
          <div>
            <label :class="labelClass">
              {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.MEASURE') }}
            </label>
            <select v-model="form.measure" :class="inputClass">
              <option value="">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
              <option
                v-for="col in tableColumns"
                :key="col.name"
                :value="col.name"
              >
                {{ col.name }}
              </option>
            </select>
          </div>
          <div>
            <label :class="labelClass">
              {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.GROUP_BY') }}
            </label>
            <select v-model="form.groupBy" :class="inputClass">
              <option value="">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
              <option
                v-for="col in tableColumns"
                :key="col.name"
                :value="col.name"
              >
                {{ col.name }}
              </option>
            </select>
          </div>
        </template>
      </div>

      <div
        class="flex items-center justify-end gap-3 border-t border-n-weak px-4 py-3"
      >
        <button
          type="button"
          class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
          @click="emit('close')"
        >
          {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="saving"
          @click="handleSave"
        >
          <span
            v-if="saving"
            class="i-lucide-loader-circle size-4 animate-spin"
          />
          {{ t('JABVOX_ANALYTICS.COMMON.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>
