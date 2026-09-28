<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadSelect from '../components/LeadSelect.vue';
import AgentSelect from '../components/AgentSelect.vue';

const props = defineProps({
  task: {
    type: Object,
    default: null,
  },
  boardId: {
    type: [Number, String],
    required: true,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  defaultStageId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['submit', 'close', 'delete']);

const { t } = useI18n();

const title = ref('');
const description = ref('');
const priority = ref('normal');
const status = ref('open');
const stageId = ref(null);
const leadId = ref(null);
const assigneeIds = ref([]);
const dueDates = ref([]);

const isEdit = computed(() => Boolean(props.task));

const priorityOptions = computed(() => [
  { value: 'low', label: t('JABVOX_TASKS.TASK.PRIORITY_LOW') },
  { value: 'normal', label: t('JABVOX_TASKS.TASK.PRIORITY_NORMAL') },
  { value: 'high', label: t('JABVOX_TASKS.TASK.PRIORITY_HIGH') },
  { value: 'urgent', label: t('JABVOX_TASKS.TASK.PRIORITY_URGENT') },
]);

const statusOptions = computed(() => [
  { value: 'open', label: t('JABVOX_TASKS.TASK.STATUS_OPEN') },
  { value: 'done', label: t('JABVOX_TASKS.TASK.STATUS_DONE') },
]);

const toDatetimeLocal = value => {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const offset = date.getTimezoneOffset();
  const local = new Date(date.getTime() - offset * 60000);
  return local.toISOString().slice(0, 16);
};

// Recurrencia: vacío = tarea normal. Al completarla se crea la siguiente.
const RECURRENCE_UNITS = ['day', 'week', 'month', 'year'];
const recurrenceUnit = ref('');
const recurrenceCount = ref(1);
const recurrenceUntil = ref('');

const initialDueDates = value => {
  const list = value?.dueDatesJabvox;
  if (Array.isArray(list) && list.length) {
    return list.map(toDatetimeLocal).filter(Boolean);
  }
  const single = toDatetimeLocal(value?.dueAtJabvox);
  return single ? [single] : [];
};

watch(
  () => props.task,
  value => {
    title.value = value?.titleJabvox || '';
    description.value = value?.descriptionJabvox || '';
    priority.value = value?.priorityJabvox || 'normal';
    status.value = value?.statusJabvox || 'open';
    stageId.value =
      value?.stageId || props.defaultStageId || props.stages[0]?.id || null;
    leadId.value = value?.jabvoxLeadId || null;
    assigneeIds.value = Array.isArray(value?.assignees)
      ? value.assignees.map(a => a.id)
      : [value?.assigneeId].filter(Boolean);
    dueDates.value = initialDueDates(value);
    recurrenceUnit.value = value?.recurrenceUnitJabvox || '';
    recurrenceCount.value = value?.recurrenceCountJabvox || 1;
    recurrenceUntil.value = toDatetimeLocal(value?.recurrenceUntilJabvox);
  },
  { immediate: true }
);

const addDueDate = () => {
  dueDates.value.push('');
};

const removeDueDate = index => {
  dueDates.value.splice(index, 1);
};

const onSubmit = () => {
  if (!title.value.trim() || !stageId.value) return;
  const payload = {
    board_id: Number(props.boardId),
    stage_id: Number(stageId.value),
    title_jabvox: title.value.trim(),
    description_jabvox: description.value,
    priority_jabvox: priority.value,
    status_jabvox: status.value,
  };
  payload.jabvox_lead_id = leadId.value ? Number(leadId.value) : null;
  payload.assignee_ids = assigneeIds.value.map(Number);

  const isoDates = dueDates.value
    .filter(Boolean)
    .map(value => new Date(value).toISOString())
    .sort();
  payload.due_dates_jabvox = isoDates;
  payload.due_at_jabvox = isoDates.length ? isoDates[0] : null;

  payload.recurrence_unit_jabvox = recurrenceUnit.value || null;
  payload.recurrence_count_jabvox = recurrenceUnit.value
    ? Math.max(1, Number(recurrenceCount.value) || 1)
    : 1;
  payload.recurrence_until_jabvox =
    recurrenceUnit.value && recurrenceUntil.value
      ? new Date(recurrenceUntil.value).toISOString()
      : null;

  emit('submit', payload);
};

const onDelete = () => {
  if (!props.task) return;
  emit('delete', props.task);
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-3"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-lg rounded-xl bg-n-solid-1 border border-n-weak shadow-lg max-h-[90vh] flex flex-col"
    >
      <div class="px-5 py-4 border-b border-n-weak shrink-0">
        <h2 class="text-base font-semibold text-n-slate-12">
          {{
            isEdit
              ? t('JABVOX_TASKS.TASK.FORM.EDIT_TITLE')
              : t('JABVOX_TASKS.TASK.FORM.CREATE_TITLE')
          }}
        </h2>
      </div>

      <form
        class="px-5 py-4 space-y-4 overflow-y-auto"
        @submit.prevent="onSubmit"
      >
        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.TASK.FORM.TITLE') }}
          </label>
          <input
            v-model="title"
            type="text"
            :placeholder="t('JABVOX_TASKS.TASK.FORM.TITLE_PLACEHOLDER')"
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.TASK.FORM.DESCRIPTION') }}
          </label>
          <textarea
            v-model="description"
            rows="3"
            :placeholder="t('JABVOX_TASKS.TASK.FORM.DESCRIPTION_PLACEHOLDER')"
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          />
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="space-y-1">
            <label class="block text-sm font-medium text-n-slate-11">
              {{ t('JABVOX_TASKS.TASK.FORM.PRIORITY') }}
            </label>
            <select
              v-model="priority"
              class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
            >
              <option
                v-for="opt in priorityOptions"
                :key="opt.value"
                :value="opt.value"
              >
                {{ opt.label }}
              </option>
            </select>
          </div>

          <div class="space-y-1">
            <label class="block text-sm font-medium text-n-slate-11">
              {{ t('JABVOX_TASKS.TASK.FORM.STATUS') }}
            </label>
            <select
              v-model="status"
              class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
            >
              <option
                v-for="opt in statusOptions"
                :key="opt.value"
                :value="opt.value"
              >
                {{ opt.label }}
              </option>
            </select>
          </div>
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.TASK.FORM.STAGE') }}
          </label>
          <select
            v-model="stageId"
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          >
            <option v-for="s in stages" :key="s.id" :value="s.id">
              {{ s.nameJabvox }}
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.TASK.FORM.LEAD') }}
          </label>
          <LeadSelect v-model="leadId" />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.TASK.FORM.ASSIGNEES') }}
          </label>
          <AgentSelect v-model="assigneeIds" multiple />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.TASK.FORM.DUE_DATES') }}
          </label>
          <div
            v-for="(date, index) in dueDates"
            :key="index"
            class="flex items-center gap-2"
          >
            <input
              v-model="dueDates[index]"
              type="datetime-local"
              class="flex-1 min-w-0 px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
            />
            <button
              type="button"
              class="p-1.5 rounded-lg text-n-ruby-11 hover:bg-n-alpha-1"
              :title="t('JABVOX_TASKS.TASK.FORM.REMOVE_DATE')"
              @click="removeDueDate(index)"
            >
              <span class="i-lucide-x size-4" aria-hidden="true" />
            </button>
          </div>
          <button
            type="button"
            class="flex items-center gap-1 px-2.5 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3"
            @click="addDueDate"
          >
            <span class="i-lucide-plus size-4" aria-hidden="true" />
            {{ t('JABVOX_TASKS.TASK.FORM.ADD_DATE') }}
          </button>
          <p class="text-[11px] text-n-slate-10">
            {{ t('JABVOX_TASKS.TASK.FORM.DUE_DATES_HINT') }}
          </p>
        </div>

        <!-- Repetición: la tarea vuelve a aparecer al completarla. El intervalo y la
             fecha tope solo se piden cuando ya se eligió que se repite. -->
        <div class="flex flex-col gap-2">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.RECURRENCE.LABEL') }}
          </label>
          <div class="flex flex-wrap items-center gap-2">
            <select
              v-model="recurrenceUnit"
              class="h-9 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2"
            >
              <option value="">
                {{ t('JABVOX_TASKS.RECURRENCE.NONE') }}
              </option>
              <option
                v-for="unit in RECURRENCE_UNITS"
                :key="unit"
                :value="unit"
              >
                {{ t(`JABVOX_TASKS.RECURRENCE.${unit}`) }}
              </option>
            </select>

            <template v-if="recurrenceUnit">
              <input
                v-model.number="recurrenceCount"
                type="number"
                min="1"
                step="1"
                class="h-9 w-20 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2"
              />
              <label class="text-xs text-n-slate-11">
                {{ t('JABVOX_TASKS.RECURRENCE.UNTIL') }}
              </label>
              <input
                v-model="recurrenceUntil"
                type="datetime-local"
                class="h-9 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2"
              />
            </template>
          </div>
          <p v-if="recurrenceUnit" class="text-[11px] text-n-slate-10">
            {{ t('JABVOX_TASKS.RECURRENCE.HELP') }}
          </p>
        </div>

        <div class="flex items-center justify-between gap-2 pt-2">
          <button
            v-if="isEdit"
            type="button"
            class="flex items-center gap-1 px-3 py-2 text-sm rounded-lg text-n-ruby-11 hover:bg-n-alpha-1"
            @click="onDelete"
          >
            <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
            {{ t('JABVOX_TASKS.TASK.DELETE') }}
          </button>
          <span v-else />
          <div class="flex items-center gap-2">
            <button
              type="button"
              class="px-3 py-2 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
              @click="emit('close')"
            >
              {{ t('JABVOX_TASKS.TASK.FORM.CANCEL') }}
            </button>
            <button
              type="submit"
              class="px-3 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
              :disabled="!title.trim() || !stageId"
            >
              {{ t('JABVOX_TASKS.TASK.FORM.SAVE') }}
            </button>
          </div>
        </div>
      </form>
    </div>
  </div>
</template>
