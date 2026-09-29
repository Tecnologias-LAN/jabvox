<script setup>
import { ref, computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useStoreGetters } from 'dashboard/composables/store';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import AgentSelect from './components/AgentSelect.vue';
import LeadSelect from './components/LeadSelect.vue';
import TaskAutomationsPanel from './components/TaskAutomationsPanel.vue';
import TaskComments from './components/TaskComments.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const { isAdmin } = useAdmin();
const route = useRoute();
const router = useRouter();
const getters = useStoreGetters();
const store = useTasksStore();

const task = ref(null);
const activities = ref([]);
const commentBody = ref('');
const isCommenting = ref(false);
const isLoading = ref(true);
const isEditing = ref(false);
const isSaving = ref(false);
const confirmDialog = ref(null);

const accountId = computed(() => getters.getCurrentAccountId.value);
const taskId = computed(() => route.params.taskId);
const stages = computed(() => store.stages);

const PRIORITIES = ['low', 'normal', 'high', 'urgent'];
const PRIORITY_KEYS = {
  low: 'JABVOX_TASKS.TASK.PRIORITY_LOW',
  normal: 'JABVOX_TASKS.TASK.PRIORITY_NORMAL',
  high: 'JABVOX_TASKS.TASK.PRIORITY_HIGH',
  urgent: 'JABVOX_TASKS.TASK.PRIORITY_URGENT',
};
const STATUS_KEYS = {
  open: 'JABVOX_TASKS.TASK.STATUS_OPEN',
  done: 'JABVOX_TASKS.TASK.STATUS_DONE',
};
// El historial guarda el estado en crudo ('open'/'done'): aquí se traduce y se pinta.
// Amarillo mientras está abierta, verde cuando se completó.
const STATUS_STYLE = {
  open: 'bg-n-amber-3 text-n-amber-11',
  done: 'bg-n-teal-3 text-n-teal-11',
};
const statusText = value =>
  STATUS_KEYS[value] ? t(STATUS_KEYS[value]) : value;
const statusChip = value =>
  STATUS_STYLE[value] || 'bg-n-alpha-2 text-n-slate-11';

const PRIORITY_CLASS = {
  low: 'bg-n-alpha-1 text-n-slate-10',
  normal: 'bg-n-blue-3 text-n-blue-11',
  high: 'bg-n-teal-3 text-n-teal-11',
  urgent: 'bg-n-ruby-9 text-white',
};
const ACTIVITY_ICON = {
  comment: 'i-lucide-message-square',
  recurrence_created: 'i-lucide-repeat',
  created: 'i-lucide-sparkles',
  title_changed: 'i-lucide-type',
  description_changed: 'i-lucide-align-left',
  stage_changed: 'i-lucide-arrow-right-left',
  status_changed: 'i-lucide-circle-check',
  priority_changed: 'i-lucide-flag',
  due_date_changed: 'i-lucide-calendar-clock',
  assignee_added: 'i-lucide-user-plus',
  assignee_removed: 'i-lucide-user-minus',
  lead_changed: 'i-lucide-user-round-cog',
};

// Editable copy of the task, populated from the loaded task when editing starts.
const form = reactive({
  title_jabvox: '',
  description_jabvox: '',
  priority_jabvox: 'normal',
  status_jabvox: 'open',
  stage_id: null,
  jabvox_lead_id: null,
  assignee_ids: [],
  due_at: '',
});

const priority = computed(() => task.value?.priorityJabvox || 'normal');
const priorityLabel = computed(() =>
  task.value ? t(PRIORITY_KEYS[priority.value] || PRIORITY_KEYS.normal) : ''
);
const priorityClass = computed(
  () => PRIORITY_CLASS[priority.value] || PRIORITY_CLASS.normal
);
const isDone = computed(() => task.value?.statusJabvox === 'done');
const statusLabel = computed(() =>
  task.value ? t(STATUS_KEYS[task.value.statusJabvox] || STATUS_KEYS.open) : ''
);
const assignees = computed(() => task.value?.assignees || []);
const stageName = computed(
  () =>
    stages.value.find(s => s.id === task.value?.stageId)?.nameJabvox ||
    task.value?.stageName ||
    ''
);

const formatDate = value => {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  });
};

// datetime-local needs "YYYY-MM-DDTHH:mm" in local time.
const toLocalInput = value => {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const initials = name =>
  (name || '?')
    .split(' ')
    .map(part => part[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();

const activityText = activity => {
  const m = activity.metadata || {};
  switch (activity.action) {
    case 'created':
      return t('JABVOX_TASKS.TASK.HISTORY.CREATED');
    case 'title_changed':
      return t('JABVOX_TASKS.TASK.HISTORY.TITLE_CHANGED', {
        from: m.from,
        to: m.to,
      });
    case 'description_changed':
      return t('JABVOX_TASKS.TASK.HISTORY.DESCRIPTION_CHANGED');
    case 'stage_changed':
      return t('JABVOX_TASKS.TASK.HISTORY.STAGE_CHANGED', {
        from: m.from,
        to: m.to,
      });
    case 'priority_changed':
      return t('JABVOX_TASKS.TASK.HISTORY.PRIORITY_CHANGED', {
        from: m.from,
        to: m.to,
      });
    case 'due_date_changed':
      return t('JABVOX_TASKS.TASK.HISTORY.DUE_DATE_CHANGED');
    case 'lead_changed':
      return t('JABVOX_TASKS.TASK.HISTORY.LEAD_CHANGED', {
        from: m.from,
        to: m.to,
      });
    case 'assignee_added':
      return t('JABVOX_TASKS.TASK.HISTORY.ASSIGNEE_ADDED', {
        name: m.userName,
      });
    case 'assignee_removed':
      return t('JABVOX_TASKS.TASK.HISTORY.ASSIGNEE_REMOVED', {
        name: m.userName,
      });
    default:
      return activity.action;
  }
};

const load = async () => {
  isLoading.value = true;
  try {
    task.value = await store.getTask(taskId.value);
    activities.value = await store.fetchTaskActivities(taskId.value);
  } catch {
    useAlert(t('JABVOX_TASKS.TASK.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

// Copy the loaded task into the editable form and enter edit mode.
// Enviar un comentario no recarga el historial entero: la respuesta ya trae la actividad
// creada, así que se inserta arriba, que es donde va por ser la más reciente.
const submitComment = async () => {
  const body = commentBody.value.trim();
  if (!body || isCommenting.value) return;
  isCommenting.value = true;
  try {
    const activity = await store.addTaskComment(taskId.value, body);
    activities.value = [activity, ...activities.value];
    commentBody.value = '';
  } catch {
    useAlert(t('JABVOX_TASKS.TASK.HISTORY.COMMENT_ERROR'));
  } finally {
    isCommenting.value = false;
  }
};

const startEdit = () => {
  const tk = task.value;
  form.title_jabvox = tk.titleJabvox || '';
  form.description_jabvox = tk.descriptionJabvox || '';
  form.priority_jabvox = tk.priorityJabvox || 'normal';
  form.status_jabvox = tk.statusJabvox || 'open';
  form.stage_id = tk.stageId || null;
  form.jabvox_lead_id = tk.jabvoxLeadId || null;
  form.assignee_ids = (tk.assignees || []).map(a => a.id);
  form.due_at = toLocalInput(tk.dueAtJabvox);
  isEditing.value = true;
};

const cancelEdit = () => {
  isEditing.value = false;
};

const save = async () => {
  if (!form.title_jabvox.trim()) {
    useAlert(t('JABVOX_TASKS.TASK.FORM.TITLE_REQUIRED'));
    return;
  }
  isSaving.value = true;
  try {
    await store.updateTask(task.value.id, {
      title_jabvox: form.title_jabvox.trim(),
      description_jabvox: form.description_jabvox,
      priority_jabvox: form.priority_jabvox,
      status_jabvox: form.status_jabvox,
      stage_id: form.stage_id ? Number(form.stage_id) : task.value.stageId,
      jabvox_lead_id: form.jabvox_lead_id ? Number(form.jabvox_lead_id) : null,
      assignee_ids: form.assignee_ids.map(Number),
      due_at_jabvox: form.due_at ? new Date(form.due_at).toISOString() : null,
    });
    useAlert(t('JABVOX_TASKS.TASK.UPDATED'));
    isEditing.value = false;
    await load();
  } catch {
    useAlert(t('JABVOX_TASKS.TASK.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const goBack = () => {
  if (task.value?.boardId) {
    router.push({
      name: 'jabvox_tasks_board',
      params: { accountId: accountId.value, boardId: task.value.boardId },
    });
    return;
  }
  router.push({
    name: 'jabvox_tasks_index',
    params: { accountId: accountId.value },
  });
};

const toggleDone = async () => {
  if (!task.value) return;
  try {
    await store.updateTask(task.value.id, {
      status_jabvox: isDone.value ? 'open' : 'done',
    });
    await load();
  } catch {
    useAlert(t('JABVOX_TASKS.TASK.ERROR'));
  }
};

const onDelete = () => {
  if (!task.value) return;
  confirmDialog.value?.open({
    title: t('JABVOX_TASKS.TASK.DELETE'),
    description: t('JABVOX_TASKS.TASK.DELETE_CONFIRM'),
    data: task.value.id,
  });
};

const doDelete = async taskIdToDelete => {
  try {
    await store.deleteTask(taskIdToDelete);
    useAlert(t('JABVOX_TASKS.TASK.DELETED'));
    goBack();
  } catch {
    useAlert(t('JABVOX_TASKS.TASK.ERROR'));
  }
};

watch(taskId, () => load(), { immediate: true });
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0 bg-n-background">
    <!-- Top bar -->
    <header
      class="flex items-center gap-3 px-4 sm:px-6 py-3 border-b border-n-weak bg-n-solid-1/80 backdrop-blur shrink-0"
    >
      <button
        type="button"
        class="flex items-center justify-center size-8 rounded-lg text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
        :title="t('JABVOX_TASKS.TASK.BACK')"
        @click="goBack"
      >
        <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
      </button>
      <div class="flex items-center gap-2 min-w-0">
        <span class="i-lucide-list-checks size-4 text-n-slate-10 shrink-0" />
        <h2 class="text-sm font-medium text-n-slate-11 truncate">
          {{ t('JABVOX_TASKS.TASK.DETAIL_TITLE') }}
        </h2>
      </div>

      <div v-if="task" class="ml-auto flex items-center gap-2">
        <template v-if="isEditing">
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-medium rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="cancelEdit"
          >
            {{ t('JABVOX_TASKS.AUTOMATION.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50"
            :disabled="isSaving"
            @click="save"
          >
            <span
              v-if="isSaving"
              class="i-lucide-loader-2 size-3.5 animate-spin"
              aria-hidden="true"
            />
            <span v-else class="i-lucide-check size-3.5" aria-hidden="true" />
            {{ t('JABVOX_TASKS.AUTOMATION.SAVE') }}
          </button>
        </template>
        <template v-else>
          <!-- Estado actual + acción en un solo control: la pastilla dice cómo está
               (amarillo abierta, verde completada) y el botón qué pasa al pulsarlo.
               Antes ponía "Completada" estando abierta, que se leía como el estado. -->
          <span
            class="hidden sm:inline-flex items-center gap-1 px-2 py-1 text-[11px] font-medium rounded-lg"
            :class="statusChip(task.statusJabvox)"
          >
            <span
              :class="isDone ? 'i-lucide-circle-check' : 'i-lucide-circle-dot'"
              class="size-3.5"
              aria-hidden="true"
            />
            {{ statusText(task.statusJabvox) }}
          </span>
          <button
            type="button"
            class="hidden sm:inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg border transition-colors"
            :class="
              isDone
                ? 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
                : 'border-n-teal-6 text-n-teal-11 hover:bg-n-teal-3'
            "
            @click="toggleDone"
          >
            <span
              :class="
                isDone ? 'i-lucide-rotate-ccw' : 'i-lucide-circle-check-big'
              "
              class="size-3.5"
              aria-hidden="true"
            />
            {{
              isDone
                ? t('JABVOX_TASKS.TASK.REOPEN')
                : t('JABVOX_TASKS.TASK.MARK_DONE')
            }}
          </button>
          <!-- Borrar es solo del administrador: se oculta en vez de dejar un botón que
               siempre responde 403. -->
          <button
            v-if="isAdmin"
            type="button"
            class="inline-flex items-center justify-center size-8 rounded-lg text-n-ruby-11 hover:bg-n-alpha-2 transition-colors"
            :title="t('JABVOX_TASKS.TASK.DELETE')"
            @click="onDelete"
          >
            <span class="i-lucide-trash-2 size-3.5" aria-hidden="true" />
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-n-brand text-white hover:opacity-90 transition-opacity"
            @click="startEdit"
          >
            <span class="i-lucide-pencil size-3.5" aria-hidden="true" />
            {{ t('JABVOX_TASKS.TASK.EDIT') }}
          </button>
        </template>
      </div>
    </header>

    <!-- Loading -->
    <div v-if="isLoading" class="flex-1 flex items-center justify-center">
      <span
        class="i-lucide-loader-2 size-6 text-n-slate-9 animate-spin"
        aria-hidden="true"
      />
    </div>

    <!-- Content -->
    <div v-else-if="task" class="flex-1 min-h-0 overflow-y-auto">
      <div
        class="mx-auto w-full max-w-5xl px-4 sm:px-6 py-5 flex flex-col lg:flex-row gap-5"
      >
        <!-- Main column -->
        <div class="flex-1 min-w-0 space-y-5">
          <!-- Title / description card -->
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
          >
            <!-- View mode -->
            <template v-if="!isEditing">
              <div class="flex items-start justify-between gap-3">
                <h1
                  class="text-xl sm:text-2xl font-semibold text-n-slate-12 break-words"
                  :class="isDone ? 'line-through text-n-slate-10' : ''"
                >
                  {{ task.titleJabvox }}
                </h1>
                <span
                  class="shrink-0 inline-flex items-center gap-1 text-[11px] font-medium rounded-full px-2.5 py-1"
                  :class="
                    isDone
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-alpha-2 text-n-slate-11'
                  "
                >
                  <span
                    :class="
                      isDone ? 'i-lucide-check' : 'i-lucide-circle-dashed'
                    "
                    class="size-3"
                    aria-hidden="true"
                  />
                  {{ statusLabel }}
                </span>
              </div>
              <p
                v-if="task.descriptionJabvox"
                class="mt-3 text-sm leading-relaxed text-n-slate-11 whitespace-pre-wrap break-words"
              >
                {{ task.descriptionJabvox }}
              </p>
              <p v-else class="mt-3 text-sm italic text-n-slate-9">
                {{ t('JABVOX_TASKS.TASK.NO_DESCRIPTION') }}
              </p>
            </template>

            <!-- Edit mode -->
            <template v-else>
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_TASKS.TASK.FORM.TITLE')
                }}</label>
                <input
                  v-model="form.title_jabvox"
                  class="reset-base text-base font-medium rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
                />
              </div>
              <div class="flex flex-col gap-1 mt-3">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_TASKS.TASK.FORM.DESCRIPTION')
                }}</label>
                <textarea
                  v-model="form.description_jabvox"
                  rows="4"
                  class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 resize-y"
                />
              </div>
            </template>
          </section>

          <!-- Meta card -->
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
          >
            <h3
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-4"
            >
              {{ t('JABVOX_TASKS.TASK.DETAILS') }}
            </h3>

            <!-- View mode meta -->
            <dl
              v-if="!isEditing"
              class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4"
            >
              <div class="flex items-center gap-3">
                <span
                  class="flex items-center justify-center size-9 rounded-lg bg-n-alpha-1 text-n-slate-10 shrink-0"
                >
                  <span class="i-lucide-flag size-4" aria-hidden="true" />
                </span>
                <div class="min-w-0">
                  <dt class="text-[11px] text-n-slate-10">
                    {{ t('JABVOX_TASKS.TASK.FORM.PRIORITY') }}
                  </dt>
                  <dd>
                    <span
                      class="inline-flex text-[11px] font-medium rounded-full px-2 py-0.5 mt-0.5"
                      :class="priorityClass"
                    >
                      {{ priorityLabel }}
                    </span>
                  </dd>
                </div>
              </div>

              <div v-if="stageName" class="flex items-center gap-3">
                <span
                  class="flex items-center justify-center size-9 rounded-lg bg-n-alpha-1 text-n-slate-10 shrink-0"
                >
                  <span class="i-lucide-columns-3 size-4" aria-hidden="true" />
                </span>
                <div class="min-w-0">
                  <dt class="text-[11px] text-n-slate-10">
                    {{ t('JABVOX_TASKS.TASK.FORM.STAGE') }}
                  </dt>
                  <dd class="text-sm text-n-slate-12 truncate">
                    {{ stageName }}
                  </dd>
                </div>
              </div>

              <div v-if="task.leadName" class="flex items-center gap-3">
                <span
                  class="flex items-center justify-center size-9 rounded-lg bg-n-alpha-1 text-n-slate-10 shrink-0"
                >
                  <span class="i-lucide-user size-4" aria-hidden="true" />
                </span>
                <div class="min-w-0">
                  <dt class="text-[11px] text-n-slate-10">
                    {{ t('JABVOX_TASKS.TASK.FORM.LEAD') }}
                  </dt>
                  <dd class="text-sm text-n-slate-12 truncate">
                    {{ task.leadName }}
                  </dd>
                </div>
              </div>

              <div v-if="task.dueAtJabvox" class="flex items-center gap-3">
                <span
                  class="flex items-center justify-center size-9 rounded-lg bg-n-alpha-1 text-n-slate-10 shrink-0"
                >
                  <span
                    class="i-lucide-calendar-clock size-4"
                    aria-hidden="true"
                  />
                </span>
                <div class="min-w-0">
                  <dt class="text-[11px] text-n-slate-10">
                    {{ t('JABVOX_TASKS.TASK.FORM.DUE_DATE') }}
                  </dt>
                  <dd class="text-sm text-n-slate-12">
                    {{ formatDate(task.dueAtJabvox) }}
                  </dd>
                </div>
              </div>
            </dl>

            <!-- Edit mode meta -->
            <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_TASKS.TASK.FORM.STATUS')
                }}</label>
                <select
                  v-model="form.status_jabvox"
                  class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
                >
                  <option value="open">{{ t(STATUS_KEYS.open) }}</option>
                  <option value="done">{{ t(STATUS_KEYS.done) }}</option>
                </select>
              </div>
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_TASKS.TASK.FORM.PRIORITY')
                }}</label>
                <select
                  v-model="form.priority_jabvox"
                  class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
                >
                  <option v-for="p in PRIORITIES" :key="p" :value="p">
                    {{ t(PRIORITY_KEYS[p]) }}
                  </option>
                </select>
              </div>
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_TASKS.TASK.FORM.STAGE')
                }}</label>
                <select
                  v-model="form.stage_id"
                  class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
                >
                  <option v-for="s in stages" :key="s.id" :value="s.id">
                    {{ s.nameJabvox }}
                  </option>
                </select>
              </div>
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_TASKS.TASK.FORM.DUE_DATE')
                }}</label>
                <input
                  v-model="form.due_at"
                  type="datetime-local"
                  class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
                />
              </div>
              <div class="flex flex-col gap-1 sm:col-span-2">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_TASKS.TASK.FORM.LEAD')
                }}</label>
                <LeadSelect
                  :model-value="form.jabvox_lead_id"
                  @update:model-value="val => (form.jabvox_lead_id = val)"
                />
              </div>
            </div>

            <!-- Assignees -->
            <div class="mt-5 pt-5 border-t border-n-weak">
              <p class="text-[11px] text-n-slate-10 mb-2">
                {{ t('JABVOX_TASKS.TASK.FORM.ASSIGNEES') }}
              </p>
              <AgentSelect
                v-if="isEditing"
                :model-value="form.assignee_ids"
                multiple
                @update:model-value="val => (form.assignee_ids = val)"
              />
              <template v-else>
                <div v-if="assignees.length" class="flex flex-wrap gap-2">
                  <span
                    v-for="agent in assignees"
                    :key="agent.id"
                    class="inline-flex items-center gap-1.5 pl-1 pr-2.5 py-1 text-xs rounded-full bg-n-alpha-1 text-n-slate-12 border border-n-weak"
                  >
                    <img
                      v-if="agent.thumbnail"
                      :src="agent.thumbnail"
                      :alt="agent.name"
                      class="size-5 rounded-full shrink-0 object-cover"
                    />
                    <span
                      v-else
                      class="flex items-center justify-center size-5 rounded-full bg-n-brand/15 text-[9px] font-semibold text-n-brand shrink-0"
                    >
                      {{ initials(agent.name) }}
                    </span>
                    {{ agent.name }}
                  </span>
                </div>
                <p v-else class="text-sm text-n-slate-11">
                  {{ t('JABVOX_TASKS.TASK.NO_ASSIGNEES') }}
                </p>
              </template>
            </div>
          </section>

          <!-- Comentarios de resolución: debajo de los detalles, que es donde se sigue
               el caso. Los mismos comentarios salen también en el historial. -->
          <TaskComments
            v-if="!isEditing"
            v-model="commentBody"
            :activities="activities"
            :is-sending="isCommenting"
            :format-date="formatDate"
            @submit="submitComment"
          />
        </div>

        <!-- Activity timeline -->
        <aside class="lg:w-80 shrink-0">
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
          >
            <h3
              class="flex items-center gap-2 text-sm font-semibold text-n-slate-12 mb-4"
            >
              <span
                class="i-lucide-history size-4 text-n-slate-10"
                aria-hidden="true"
              />
              {{ t('JABVOX_TASKS.TASK.HISTORY.TITLE') }}
            </h3>

            <ol v-if="activities.length" class="space-y-1">
              <li
                v-for="(activity, idx) in activities"
                :key="activity.id"
                class="relative flex gap-3 pb-4"
              >
                <span
                  v-if="idx < activities.length - 1"
                  class="absolute left-[15px] top-8 bottom-0 w-px bg-n-weak"
                  aria-hidden="true"
                />
                <span
                  class="relative z-10 flex items-center justify-center size-8 rounded-full bg-n-alpha-1 text-n-slate-11 shrink-0"
                >
                  <span
                    :class="ACTIVITY_ICON[activity.action] || 'i-lucide-dot'"
                    class="size-4"
                    aria-hidden="true"
                  />
                </span>
                <div class="min-w-0 pt-0.5 flex-1">
                  <p
                    v-if="activity.action === 'comment'"
                    class="text-sm text-n-slate-12 break-words whitespace-pre-line rounded-lg bg-n-alpha-1 px-2.5 py-2"
                  >
                    {{ activity.metadata?.body }}
                  </p>
                  <!-- El cambio de estado se arma aquí y no en activityText porque
                       lleva dos pastillas de color, y una cadena traducida no puede
                       llevar marcado dentro. -->
                  <p
                    v-else-if="activity.action === 'status_changed'"
                    class="text-sm text-n-slate-12 break-words flex flex-wrap items-center gap-1"
                  >
                    {{ t('JABVOX_TASKS.TASK.HISTORY.STATUS_CHANGED_PREFIX') }}
                    <span
                      class="px-1.5 py-0.5 rounded text-[11px] font-medium"
                      :class="statusChip(activity.metadata?.from)"
                    >
                      {{ statusText(activity.metadata?.from) }}
                    </span>
                    {{ t('JABVOX_TASKS.TASK.HISTORY.STATUS_CHANGED_TO') }}
                    <span
                      class="px-1.5 py-0.5 rounded text-[11px] font-medium"
                      :class="statusChip(activity.metadata?.to)"
                    >
                      {{ statusText(activity.metadata?.to) }}
                    </span>
                  </p>
                  <p v-else class="text-sm text-n-slate-12 break-words">
                    {{ activityText(activity) }}
                  </p>
                  <p class="text-[11px] text-n-slate-10 mt-0.5">
                    <span v-if="activity.userName">
                      {{ activity.userName }} ·
                    </span>
                    {{ formatDate(activity.createdAt) }}
                  </p>
                </div>
              </li>
            </ol>

            <div
              v-else
              class="flex flex-col items-center justify-center py-8 text-center"
            >
              <span
                class="i-lucide-history size-8 text-n-slate-8 mb-2"
                aria-hidden="true"
              />
              <p class="text-sm text-n-slate-10">
                {{ t('JABVOX_TASKS.TASK.HISTORY.EMPTY') }}
              </p>
            </div>
          </section>

          <!-- Automatizaciones de esta tarea (recordatorios recurrentes). Van aquí, no en
               la columna principal: son configuración, no el trabajo de la tarea. -->
          <TaskAutomationsPanel
            v-if="!isEditing"
            :task-id="task.id"
            class="mt-4"
          />
        </aside>
      </div>
    </div>

    <!-- Not found -->
    <div
      v-else
      class="flex-1 flex flex-col items-center justify-center text-center px-4"
    >
      <span
        class="i-lucide-file-question size-10 text-n-slate-8 mb-3"
        aria-hidden="true"
      />
      <p class="text-sm text-n-slate-10">
        {{ t('JABVOX_TASKS.TASK.NOT_FOUND') }}
      </p>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="doDelete" />
  </div>
</template>
