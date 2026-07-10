<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import { DESTROY_KEY } from 'dashboard/helper/jabvox/nestedAttributes';
import KpiCard from './KpiCard.vue';
import FilterBar from './FilterBar.vue';

// Generic state list (cards + table) shared by the 3 tabs. Each tab passes its
// items and the field names to read (since management/app/campaign objects use
// different keys), plus a `kind` flag to show questions/note for management.
const props = defineProps({
  items: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  nameField: { type: String, default: 'name' },
  colorField: { type: String, default: 'color' },
  activeField: { type: String, default: 'is_active' },
  withColor: { type: Boolean, default: true },
  withActive: { type: Boolean, default: true },
  kind: { type: String, default: 'simple' }, // 'management' | 'simple'
  description: { type: String, default: '' },
});

const emit = defineEmits(['create', 'edit', 'delete']);
const { t } = useI18n();

const search = ref('');
const status = ref('all');
const sort = ref('position');
const view = ref('cards');

const nameOf = it => it[props.nameField] ?? '';
const colorOf = it => it[props.colorField] || '#64748b';
const activeOf = it =>
  props.withActive ? (it[props.activeField] ?? true) : true;
const questionsOf = it => (it.questions || []).filter(q => !q[DESTROY_KEY]);

const total = computed(() => props.items.length);
const activeCount = computed(
  () => props.items.filter(it => activeOf(it)).length
);
const inactiveCount = computed(() => total.value - activeCount.value);
const withQuestionsCount = computed(
  () => props.items.filter(it => questionsOf(it).length > 0).length
);

const filtered = computed(() => {
  let list = [...props.items];
  const q = search.value.trim().toLowerCase();
  if (q) list = list.filter(it => nameOf(it).toLowerCase().includes(q));
  if (props.withActive && status.value === 'active') {
    list = list.filter(it => activeOf(it));
  } else if (props.withActive && status.value === 'inactive') {
    list = list.filter(it => !activeOf(it));
  }
  if (sort.value === 'name') {
    list.sort((a, b) => nameOf(a).localeCompare(nameOf(b)));
  }
  return list;
});

const resetFilters = () => {
  search.value = '';
  status.value = 'all';
  sort.value = 'position';
};

// ── grouping by state_group_jabvox (management states only) ──
// Headers only appear when at least one state has a group; ungrouped states
// then fall under a trailing "Sin grupo" section.
const showGrouped = computed(
  () =>
    props.kind === 'management' && props.items.some(it => it.state_group_jabvox)
);

const sections = computed(() => {
  if (!showGrouped.value) return [{ key: '__all__', items: filtered.value }];
  const byGroup = new Map();
  filtered.value.forEach(it => {
    const group = it.state_group_jabvox || '';
    if (!byGroup.has(group)) byGroup.set(group, []);
    byGroup.get(group).push(it);
  });
  const result = [...byGroup.entries()]
    .filter(([group]) => group !== '')
    .map(([group, list]) => ({ key: group, items: list }));
  if (byGroup.has('')) result.push({ key: '', items: byGroup.get('') });
  return result;
});

const sectionLabel = sec =>
  sec.key === '' ? t('JABVOX_MANAGEMENT_STATES.UNGROUPED') : sec.key;

// ── compact classification badges (management states only) ──
const FLAG_DEFS = [
  ['managed_jabvox', 'MANAGED'],
  ['contact_jabvox', 'CONTACT'],
  ['effective_contact_jabvox', 'EFFECTIVE_CONTACT'],
  ['advisory_jabvox', 'ADVISORY'],
];
const activeFlags = it =>
  FLAG_DEFS.filter(([field]) =>
    field === 'managed_jabvox' ? it[field] !== false : it[field] === true
  );
const levelOf = it => Number(it.positivity_level_jabvox) || 0;
const serviceOf = it =>
  it.service_type_jabvox && it.service_type_jabvox !== 'No'
    ? it.service_type_jabvox
    : '';

const noteModeColor = mode =>
  ({ required: 'ruby', optional: 'slate', hidden: 'amber' })[mode] || 'slate';
const noteModeLabel = mode =>
  t(`JABVOX_MANAGEMENT_STATES.FORM.NOTE_${(mode || 'optional').toUpperCase()}`);
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- KPIs -->
    <div
      class="grid grid-cols-1 sm:grid-cols-2 gap-3"
      :class="kind === 'management' ? 'xl:grid-cols-4' : 'xl:grid-cols-3'"
    >
      <KpiCard
        :label="t('JABVOX_MANAGEMENT_STATES.KPI.TOTAL')"
        :value="total"
        icon="i-lucide-layers"
        tone="iris"
      />
      <KpiCard
        v-if="withActive"
        :label="t('JABVOX_MANAGEMENT_STATES.KPI.ACTIVE')"
        :value="activeCount"
        icon="i-lucide-circle-check"
        tone="teal"
      />
      <KpiCard
        v-if="withActive"
        :label="t('JABVOX_MANAGEMENT_STATES.KPI.INACTIVE')"
        :value="inactiveCount"
        icon="i-lucide-circle-pause"
        tone="amber"
      />
      <KpiCard
        v-if="kind === 'management'"
        :label="t('JABVOX_MANAGEMENT_STATES.KPI.WITH_QUESTIONS')"
        :value="withQuestionsCount"
        icon="i-lucide-list-checks"
        tone="slate"
      />
    </div>

    <!-- Loading skeletons -->
    <div v-if="loading" class="flex flex-col gap-3">
      <div
        v-for="n in 4"
        :key="n"
        class="h-16 rounded-2xl border border-n-weak bg-n-alpha-1 animate-pulse"
      />
    </div>

    <!-- Empty -->
    <EmptyStateLayout
      v-else-if="!items.length"
      :title="t('JABVOX_MANAGEMENT_STATES.EMPTY_TITLE')"
      :subtitle="description"
    >
      <template #actions>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_MANAGEMENT_STATES.CREATE_FIRST')"
          size="sm"
          @click="emit('create')"
        />
      </template>
    </EmptyStateLayout>

    <template v-else>
      <FilterBar
        v-model:search="search"
        v-model:status="status"
        v-model:sort="sort"
        v-model:view="view"
        show-sort
        @reset="resetFilters"
      />

      <div
        v-if="!filtered.length"
        class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_MANAGEMENT_STATES.FILTERS.NO_RESULTS') }}
      </div>

      <!-- Card view -->
      <div v-else-if="view === 'cards'" class="flex flex-col gap-6">
        <section
          v-for="sec in sections"
          :key="sec.key"
          class="flex flex-col gap-3"
        >
          <h4
            v-if="showGrouped"
            class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            <span class="i-lucide-folder size-3.5 shrink-0" />
            {{ sectionLabel(sec) }}
            <span class="font-normal normal-case text-n-slate-9">
              ({{ sec.items.length }})
            </span>
          </h4>
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            <div
              v-for="it in sec.items"
              :key="it.id"
              class="group flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm transition-all hover:shadow-md hover:-translate-y-0.5"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="flex items-center gap-2 min-w-0">
                  <span
                    v-if="withColor"
                    class="size-3 rounded-full shrink-0 ring-1 ring-inset ring-n-weak"
                    :style="{ backgroundColor: colorOf(it) }"
                  />
                  <span
                    v-else
                    class="i-lucide-megaphone size-4 text-n-slate-10 shrink-0"
                  />
                  <p class="text-sm font-medium text-n-slate-12 truncate">
                    {{ nameOf(it) }}
                  </p>
                </div>
                <Label
                  v-if="withActive"
                  :label="
                    activeOf(it)
                      ? t('JABVOX_MANAGEMENT_STATES.KPI.ACTIVE')
                      : t('JABVOX_MANAGEMENT_STATES.INACTIVE')
                  "
                  :color="activeOf(it) ? 'teal' : 'slate'"
                  compact
                />
              </div>

              <!-- Management meta -->
              <div
                v-if="kind === 'management'"
                class="flex flex-wrap items-center gap-2"
              >
                <Label
                  :label="`${t('JABVOX_MANAGEMENT_STATES.CARD.NOTE_MODE_LABEL')}: ${noteModeLabel(it.note_mode)}`"
                  :color="noteModeColor(it.note_mode)"
                  compact
                />
                <span
                  v-if="questionsOf(it).length"
                  class="inline-flex items-center gap-1 text-xs text-n-slate-11"
                >
                  <span class="i-lucide-list-checks size-3.5" />
                  {{
                    t('JABVOX_MANAGEMENT_STATES.CARD.QUESTIONS_COUNT', {
                      count: questionsOf(it).length,
                    })
                  }}
                </span>
              </div>

              <!-- Classification badges -->
              <div
                v-if="kind === 'management'"
                class="flex flex-wrap items-center gap-1.5"
              >
                <span
                  v-if="levelOf(it) > 0"
                  class="inline-flex items-center rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] font-medium text-n-slate-11 tabular-nums"
                >
                  {{
                    t('JABVOX_MANAGEMENT_STATES.FLAGS.LEVEL', {
                      level: levelOf(it),
                    })
                  }}
                </span>
                <span
                  v-if="serviceOf(it)"
                  class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] font-medium text-n-slate-11"
                >
                  <span class="i-lucide-briefcase size-3 shrink-0" />
                  {{ serviceOf(it) }}
                </span>
                <span
                  v-for="[field, labelKey] in activeFlags(it)"
                  :key="field"
                  class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-1.5 py-0.5 text-[10px] font-semibold text-n-slate-11"
                  :title="t(`JABVOX_MANAGEMENT_STATES.FLAGS.${labelKey}`)"
                >
                  <span class="size-1.5 rounded-full bg-n-teal-9" />
                  {{ t(`JABVOX_MANAGEMENT_STATES.FLAGS.${labelKey}_ABBR`) }}
                </span>
              </div>

              <div
                class="flex items-center justify-end gap-1 pt-2 border-t border-n-weak"
              >
                <Button
                  icon="i-lucide-pencil"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  :title="t('JABVOX_MANAGEMENT_STATES.EDIT')"
                  @click="emit('edit', it)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  :title="t('JABVOX_MANAGEMENT_STATES.COMMON.DELETE')"
                  @click="emit('delete', it)"
                />
              </div>
            </div>
          </div>
        </section>
      </div>

      <!-- Table view -->
      <div
        v-else
        class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden overflow-x-auto"
      >
        <table class="min-w-full text-sm">
          <thead
            class="sticky top-0 bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
          >
            <tr>
              <th class="text-left px-4 py-2.5">
                {{ t('JABVOX_MANAGEMENT_STATES.TABLE.COL_NAME') }}
              </th>
              <th v-if="withActive" class="text-left px-4 py-2.5">
                {{ t('JABVOX_MANAGEMENT_STATES.TABLE.COL_STATUS') }}
              </th>
              <th v-if="kind === 'management'" class="text-left px-4 py-2.5">
                {{ t('JABVOX_MANAGEMENT_STATES.TABLE.COL_NOTE') }}
              </th>
              <th v-if="kind === 'management'" class="text-center px-4 py-2.5">
                {{ t('JABVOX_MANAGEMENT_STATES.TABLE.COL_QUESTIONS') }}
              </th>
              <th class="px-4 py-2.5" />
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <template v-for="sec in sections" :key="sec.key">
              <tr v-if="showGrouped" class="bg-n-alpha-1">
                <td
                  colspan="5"
                  class="px-4 py-2 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
                >
                  <span class="inline-flex items-center gap-1.5">
                    <span class="i-lucide-folder size-3.5 shrink-0" />
                    {{ sectionLabel(sec) }}
                    <span class="font-normal normal-case text-n-slate-9">
                      ({{ sec.items.length }})
                    </span>
                  </span>
                </td>
              </tr>
              <tr
                v-for="it in sec.items"
                :key="it.id"
                class="hover:bg-n-alpha-1 transition-colors"
              >
                <td class="px-4 py-3">
                  <div class="flex items-center gap-2">
                    <span
                      v-if="withColor"
                      class="size-3 rounded-full shrink-0 ring-1 ring-inset ring-n-weak"
                      :style="{ backgroundColor: colorOf(it) }"
                    />
                    <span class="font-medium text-n-slate-12">{{
                      nameOf(it)
                    }}</span>
                    <template v-if="kind === 'management'">
                      <span
                        v-if="levelOf(it) > 0"
                        class="inline-flex items-center rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] font-medium text-n-slate-11 tabular-nums"
                      >
                        {{
                          t('JABVOX_MANAGEMENT_STATES.FLAGS.LEVEL', {
                            level: levelOf(it),
                          })
                        }}
                      </span>
                      <span
                        v-if="serviceOf(it)"
                        class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] font-medium text-n-slate-11"
                      >
                        <span class="i-lucide-briefcase size-3 shrink-0" />
                        {{ serviceOf(it) }}
                      </span>
                      <span
                        v-for="[field, labelKey] in activeFlags(it)"
                        :key="field"
                        class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-1.5 py-0.5 text-[10px] font-semibold text-n-slate-11"
                        :title="t(`JABVOX_MANAGEMENT_STATES.FLAGS.${labelKey}`)"
                      >
                        <span class="size-1.5 rounded-full bg-n-teal-9" />
                        {{
                          t(`JABVOX_MANAGEMENT_STATES.FLAGS.${labelKey}_ABBR`)
                        }}
                      </span>
                    </template>
                  </div>
                </td>
                <td v-if="withActive" class="px-4 py-3">
                  <Label
                    :label="
                      activeOf(it)
                        ? t('JABVOX_MANAGEMENT_STATES.KPI.ACTIVE')
                        : t('JABVOX_MANAGEMENT_STATES.INACTIVE')
                    "
                    :color="activeOf(it) ? 'teal' : 'slate'"
                    compact
                  />
                </td>
                <td v-if="kind === 'management'" class="px-4 py-3">
                  <Label
                    :label="noteModeLabel(it.note_mode)"
                    :color="noteModeColor(it.note_mode)"
                    compact
                  />
                </td>
                <td
                  v-if="kind === 'management'"
                  class="px-4 py-3 text-center text-n-slate-11 tabular-nums"
                >
                  {{ questionsOf(it).length || '—' }}
                </td>
                <td class="px-4 py-3">
                  <div class="flex items-center justify-end gap-1">
                    <Button
                      icon="i-lucide-pencil"
                      variant="ghost"
                      color="slate"
                      size="sm"
                      @click="emit('edit', it)"
                    />
                    <Button
                      icon="i-lucide-trash-2"
                      variant="ghost"
                      color="ruby"
                      size="sm"
                      @click="emit('delete', it)"
                    />
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
