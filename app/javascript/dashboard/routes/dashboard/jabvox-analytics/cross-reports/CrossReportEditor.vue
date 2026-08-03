<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useAnalyticsCrossReportsStore } from 'dashboard/stores/jabvox/analytics/crossReports';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useAnalyticsCrossReportsStore();
const dsStore = useAnalyticsDataSourcesStore();

const isEdit = computed(() => Boolean(route.params.crossReportId));
const reportId = computed(() => route.params.crossReportId);

// --- Form state ---
const form = reactive({
  name_jabvox: '',
  description_jabvox: '',
  row_limit_jabvox: 1000,
});
// Each source: { key(local), dataSourceId, table, columns:[], filters:[], schemaTables:[], schemaColumns:[] }
const sources = ref([]);
// Each join: { key, leftAlias, leftColumn, rightAlias, rightColumn, joinType }
const joins = ref([]);
const result = ref(null);
const executing = computed(() => store.uiFlags.executing);
const saving = computed(() => store.uiFlags.saving);

const dataSources = computed(() => dsStore.list);

let localSeq = 0;
const nextKey = () => {
  localSeq += 1;
  return `s${localSeq}`;
};

const loadSchema = async src => {
  if (!src.dataSourceId) return;
  const schema = await dsStore.fetchSchema(src.dataSourceId);
  src.schema = schema;
};

const loadReport = async () => {
  const r = await store.show(reportId.value);
  form.name_jabvox = r.nameJabvox;
  form.description_jabvox = r.descriptionJabvox || '';
  form.row_limit_jabvox = r.rowLimitJabvox;
  sources.value = (r.sources || []).map(s => ({
    key: nextKey(),
    alias: s.alias,
    dataSourceId: s.dataSourceId,
    table: s.table,
    columns: s.columns || [],
    filters: s.filters || [],
    schema: null,
  }));
  // Load each source's schema so the column pickers work.
  await Promise.all(sources.value.map(loadSchema));
  joins.value = (r.joins || []).map(j => ({
    key: nextKey(),
    leftAlias: j.leftAlias,
    leftColumn: j.leftColumn,
    rightAlias: j.rightAlias,
    rightColumn: j.rightColumn,
    joinType: j.joinType,
  }));
};

// --- Sources ---
const addSource = () => {
  sources.value.push({
    key: nextKey(),
    alias: `t${sources.value.length + 1}`,
    dataSourceId: null,
    table: '',
    columns: [],
    filters: [],
    schema: null,
  });
};

const removeSource = key => {
  const src = sources.value.find(s => s.key === key);
  sources.value = sources.value.filter(s => s.key !== key);
  // Drop joins that referenced this source's alias.
  joins.value = joins.value.filter(
    j => j.leftAlias !== src?.alias && j.rightAlias !== src?.alias
  );
};

const onDataSourceChange = async src => {
  src.table = '';
  src.columns = [];
  await loadSchema(src);
};

const tablesFor = src => (src.schema || []).map(tbe => tbe.name);
const columnsFor = src => {
  const tbe = (src.schema || []).find(x => x.name === src.table);
  return (tbe?.columns || []).map(c => c.name);
};

const toggleColumn = (src, col) => {
  if (src.columns.includes(col)) {
    src.columns = src.columns.filter(c => c !== col);
  } else {
    src.columns = [...src.columns, col];
  }
};

// --- Joins ---
const addJoin = () => {
  joins.value.push({
    key: nextKey(),
    leftAlias: sources.value[0]?.alias || '',
    leftColumn: '',
    rightAlias: sources.value[1]?.alias || '',
    rightColumn: '',
    joinType: 'inner',
  });
};
const removeJoin = key => {
  joins.value = joins.value.filter(j => j.key !== key);
};
const aliases = computed(() => sources.value.map(s => s.alias));
const columnsForAlias = alias => {
  const src = sources.value.find(s => s.alias === alias);
  return src ? columnsFor(src) : [];
};

// --- Save / execute ---
const buildPayload = () => ({
  name_jabvox: form.name_jabvox,
  description_jabvox: form.description_jabvox,
  row_limit_jabvox: Number(form.row_limit_jabvox) || 1000,
  sources: sources.value.map(s => ({
    data_source_id: s.dataSourceId,
    table: s.table,
    alias: s.alias,
    columns: s.columns,
    filters: s.filters,
  })),
  joins: joins.value.map(j => ({
    left_alias: j.leftAlias,
    left_column: j.leftColumn,
    right_alias: j.rightAlias,
    right_column: j.rightColumn,
    join_type: j.joinType,
  })),
});

const validate = () => {
  if (!form.name_jabvox.trim())
    return t('JABVOX_ANALYTICS.CROSS_REPORTS.ERR_NAME');
  if (!sources.value.length)
    return t('JABVOX_ANALYTICS.CROSS_REPORTS.ERR_SOURCES');
  if (sources.value.some(s => !s.dataSourceId || !s.table)) {
    return t('JABVOX_ANALYTICS.CROSS_REPORTS.ERR_SOURCE_INCOMPLETE');
  }
  return null;
};

const save = async () => {
  const err = validate();
  if (err) {
    useAlert(err);
    return null;
  }
  try {
    const payload = buildPayload();
    const saved = isEdit.value
      ? await store.update(reportId.value, payload)
      : await store.create(payload);
    useAlert(t('JABVOX_ANALYTICS.CROSS_REPORTS.SAVED'));
    if (!isEdit.value) {
      router.replace({
        name: 'jabvox_analytics_cross_report_edit',
        params: { accountId: route.params.accountId, crossReportId: saved.id },
      });
    }
    return saved;
  } catch (e) {
    useAlert(
      e?.response?.data?.errors?.join(', ') ||
        t('JABVOX_ANALYTICS.CROSS_REPORTS.SAVE_ERROR')
    );
    return null;
  }
};

const runReport = async () => {
  const saved = await save();
  const id = saved?.id || reportId.value;
  if (!id) return;
  try {
    result.value = await store.execute(id);
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('JABVOX_ANALYTICS.CROSS_REPORTS.RUN_ERROR')
    );
  }
};

const exportCsv = () => {
  if (!result.value) return;
  const { columns, rows } = result.value;
  const esc = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csv = [
    columns.map(esc).join(','),
    ...rows.map(r => r.map(esc).join(',')),
  ].join('\n');
  // Prepend a UTF-8 BOM so Excel opens accented text correctly.
  const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8;' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `${form.name_jabvox || 'cruce'}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
};

const goBack = () =>
  router.push({
    name: 'jabvox_analytics_cross_reports',
    params: { accountId: route.params.accountId },
  });

const inputClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
const labelClass = 'mb-1 block text-sm font-medium text-n-slate-12';

onMounted(async () => {
  await dsStore.fetch();
  if (isEdit.value) await loadReport();
});
</script>

<template>
  <div class="flex flex-col gap-5 p-6">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-2">
        <Button variant="ghost" icon="i-lucide-arrow-left" @click="goBack" />
        <h2 class="text-lg font-medium text-n-slate-12">
          {{
            isEdit
              ? t('JABVOX_ANALYTICS.CROSS_REPORTS.EDIT_TITLE')
              : t('JABVOX_ANALYTICS.CROSS_REPORTS.NEW_TITLE')
          }}
        </h2>
      </div>
      <div class="flex items-center gap-2">
        <Button
          variant="outline"
          :label="t('JABVOX_ANALYTICS.CROSS_REPORTS.SAVE')"
          :is-loading="saving"
          @click="save"
        />
        <Button
          :label="t('JABVOX_ANALYTICS.CROSS_REPORTS.RUN')"
          icon="i-lucide-play"
          :is-loading="executing"
          @click="runReport"
        />
      </div>
    </div>

    <!-- Report meta -->
    <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
      <div class="md:col-span-2">
        <label :class="labelClass">{{
          t('JABVOX_ANALYTICS.CROSS_REPORTS.NAME')
        }}</label>
        <input v-model="form.name_jabvox" type="text" :class="inputClass" />
      </div>
      <div>
        <label :class="labelClass">{{
          t('JABVOX_ANALYTICS.CROSS_REPORTS.ROW_LIMIT')
        }}</label>
        <input
          v-model="form.row_limit_jabvox"
          type="number"
          min="1"
          :class="inputClass"
        />
      </div>
    </div>

    <!-- Sources -->
    <div class="flex flex-col gap-3">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.SOURCES') }}
        </h3>
        <Button
          variant="outline"
          size="sm"
          icon="i-lucide-plus"
          :label="t('JABVOX_ANALYTICS.CROSS_REPORTS.ADD_SOURCE')"
          @click="addSource"
        />
      </div>

      <div
        v-for="src in sources"
        :key="src.key"
        class="rounded-xl border border-n-weak p-4"
      >
        <div class="grid grid-cols-1 gap-3 md:grid-cols-4">
          <div>
            <label :class="labelClass">{{
              t('JABVOX_ANALYTICS.CROSS_REPORTS.ALIAS')
            }}</label>
            <input v-model="src.alias" type="text" :class="inputClass" />
          </div>
          <div>
            <label :class="labelClass">{{
              t('JABVOX_ANALYTICS.CROSS_REPORTS.DATA_SOURCE')
            }}</label>
            <select
              v-model="src.dataSourceId"
              :class="inputClass"
              @change="onDataSourceChange(src)"
            >
              <option :value="null">—</option>
              <option v-for="ds in dataSources" :key="ds.id" :value="ds.id">
                {{ ds.nameJabvox }}
              </option>
            </select>
          </div>
          <div>
            <label :class="labelClass">{{
              t('JABVOX_ANALYTICS.CROSS_REPORTS.TABLE')
            }}</label>
            <select
              v-model="src.table"
              :class="inputClass"
              @change="src.columns = []"
            >
              <option value="">—</option>
              <option v-for="tb in tablesFor(src)" :key="tb" :value="tb">
                {{ tb }}
              </option>
            </select>
          </div>
          <div class="flex items-end justify-end">
            <Button
              variant="ghost"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              @click="removeSource(src.key)"
            />
          </div>
        </div>

        <!-- Column picker -->
        <div v-if="src.table" class="mt-3">
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.COLUMNS') }}
            <span class="text-xs font-normal text-n-slate-10">
              ({{ t('JABVOX_ANALYTICS.CROSS_REPORTS.COLUMNS_HINT') }})
            </span>
          </label>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="col in columnsFor(src)"
              :key="col"
              type="button"
              class="rounded-full px-2.5 py-0.5 text-xs font-medium"
              :class="
                src.columns.includes(col)
                  ? 'bg-n-brand text-white'
                  : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
              "
              @click="toggleColumn(src, col)"
            >
              {{ col }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Joins (relations) -->
    <div class="flex flex-col gap-3">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.RELATIONS') }}
        </h3>
        <Button
          variant="outline"
          size="sm"
          icon="i-lucide-plus"
          :label="t('JABVOX_ANALYTICS.CROSS_REPORTS.ADD_RELATION')"
          :disabled="sources.length < 2"
          @click="addJoin"
        />
      </div>
      <p class="text-xs text-n-slate-10">
        {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.RELATIONS_HINT') }}
      </p>

      <div
        v-for="join in joins"
        :key="join.key"
        class="flex flex-wrap items-end gap-2 rounded-xl border border-n-weak p-3"
      >
        <select v-model="join.leftAlias" class="w-28" :class="[inputClass]">
          <option v-for="a in aliases" :key="a" :value="a">{{ a }}</option>
        </select>
        <select v-model="join.leftColumn" class="w-36" :class="[inputClass]">
          <option value="">—</option>
          <option
            v-for="c in columnsForAlias(join.leftAlias)"
            :key="c"
            :value="c"
          >
            {{ c }}
          </option>
        </select>
        <span class="pb-2 text-n-slate-10">=</span>
        <select v-model="join.rightAlias" class="w-28" :class="[inputClass]">
          <option v-for="a in aliases" :key="a" :value="a">{{ a }}</option>
        </select>
        <select v-model="join.rightColumn" class="w-36" :class="[inputClass]">
          <option value="">—</option>
          <option
            v-for="c in columnsForAlias(join.rightAlias)"
            :key="c"
            :value="c"
          >
            {{ c }}
          </option>
        </select>
        <select v-model="join.joinType" class="w-32" :class="[inputClass]">
          <option value="inner">
            {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.JOIN_INNER') }}
          </option>
          <option value="left">
            {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.JOIN_LEFT') }}
          </option>
        </select>
        <Button
          variant="ghost"
          color="ruby"
          size="sm"
          icon="i-lucide-trash-2"
          @click="removeJoin(join.key)"
        />
      </div>
    </div>

    <!-- Result -->
    <div v-if="result" class="flex flex-col gap-2">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.RESULT') }}
          <span class="ml-2 text-xs font-normal text-n-slate-10">
            {{
              t('JABVOX_ANALYTICS.CROSS_REPORTS.RESULT_COUNT', {
                count: result.row_count,
              })
            }}
            <span v-if="result.truncated" class="text-n-amber-11">
              · {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.TRUNCATED') }}
            </span>
          </span>
        </h3>
        <Button
          variant="outline"
          size="sm"
          icon="i-lucide-download"
          :label="t('JABVOX_ANALYTICS.CROSS_REPORTS.EXPORT_CSV')"
          @click="exportCsv"
        />
      </div>
      <div class="max-h-[400px] overflow-auto rounded-xl border border-n-weak">
        <table class="w-full text-xs">
          <thead class="sticky top-0 bg-n-alpha-2 text-left text-n-slate-11">
            <tr>
              <th
                v-for="col in result.columns"
                :key="col"
                class="whitespace-nowrap px-3 py-2 font-medium"
              >
                {{ col }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, ri) in result.rows"
              :key="ri"
              class="border-t border-n-weak"
            >
              <td
                v-for="(cell, ci) in row"
                :key="ci"
                class="whitespace-nowrap px-3 py-1.5 text-n-slate-11"
              >
                {{ cell }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
