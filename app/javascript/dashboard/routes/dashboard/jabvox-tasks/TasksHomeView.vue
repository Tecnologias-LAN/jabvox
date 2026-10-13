<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';

const { t, locale } = useI18n();
const router = useRouter();
const getters = useStoreGetters();
const { isAdmin } = useAdmin();
const store = useTasksStore();

const accountId = computed(() => getters.getCurrentAccountId.value);
const activeFilter = ref('pending');
const hasError = ref(false);
const tasks = computed(() => store.taskList);
const isLoading = computed(() => store.uiFlags.fetchingTasks);

const filters = computed(() => [
  { key: 'pending', label: t('JABVOX_TASKS.HOME.FILTER_PENDING') },
  { key: 'completed', label: t('JABVOX_TASKS.HOME.FILTER_COMPLETED') },
  { key: 'deleted', label: t('JABVOX_TASKS.HOME.FILTER_DELETED') },
  { key: 'all', label: t('JABVOX_TASKS.HOME.FILTER_ALL') },
]);

const emptyMessage = computed(() => {
  if (activeFilter.value === 'pending') {
    return t('JABVOX_TASKS.HOME.EMPTY_PENDING');
  }
  if (activeFilter.value === 'completed') {
    return t('JABVOX_TASKS.HOME.EMPTY_COMPLETED');
  }
  if (activeFilter.value === 'deleted') {
    return t('JABVOX_TASKS.HOME.EMPTY_DELETED');
  }
  return t('JABVOX_TASKS.HOME.EMPTY_ALL');
});

const fetchTasks = async () => {
  hasError.value = false;
  const params = activeFilter.value === 'deleted' ? { deleted: true } : {};

  try {
    await store.fetchTasks(params);
  } catch {
    store.tasks = [];
    hasError.value = true;
    useAlert(t('JABVOX_TASKS.HOME.ERROR'));
  }
};

const filteredTasks = computed(() => {
  if (activeFilter.value === 'deleted' || activeFilter.value === 'all') {
    return tasks.value;
  }
  const status = activeFilter.value === 'completed' ? 'done' : 'open';
  return tasks.value.filter(task => task.statusJabvox === status);
});

const orderedTasks = computed(() =>
  [...filteredTasks.value].sort((left, right) => {
    const leftDue = left.dueAtJabvox
      ? new Date(left.dueAtJabvox).getTime()
      : Number.POSITIVE_INFINITY;
    const rightDue = right.dueAtJabvox
      ? new Date(right.dueAtJabvox).getTime()
      : Number.POSITIVE_INFINITY;
    return (
      leftDue - rightDue || left.titleJabvox.localeCompare(right.titleJabvox)
    );
  })
);

const taskMetadata = task => {
  const boardName = store.boardList.find(
    board => board.id === task.boardId
  )?.nameJabvox;
  return [boardName, task.stageName, task.leadName].filter(Boolean).join(' · ');
};

const formatDueDate = value => {
  if (!value) return t('JABVOX_TASKS.TASK.NO_DUE_DATE');
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return t('JABVOX_TASKS.TASK.NO_DUE_DATE');
  return date.toLocaleString(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  });
};

const openTask = task => {
  router.push({
    name: 'jabvox_tasks_detail',
    params: { accountId: accountId.value, taskId: task.id },
  });
};

const restoreTask = async id => {
  try {
    await store.restoreTask(id);
    useAlert(t('JABVOX_TASKS.HOME.RESTORED'));
    await fetchTasks();
  } catch {
    useAlert(t('JABVOX_TASKS.HOME.ERROR'));
  }
};

watch(activeFilter, fetchTasks);

onMounted(fetchTasks);
</script>

<template>
  <main class="flex h-full min-h-0 flex-col bg-n-background">
    <header
      class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak bg-n-solid-1 px-4 py-4 sm:px-6"
    >
      <div>
        <h1 class="text-lg font-semibold text-n-slate-12">
          {{ t('JABVOX_TASKS.HOME.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ t('JABVOX_TASKS.HOME.DESCRIPTION') }}
        </p>
      </div>
      <RouterLink
        v-if="store.boardList.length"
        :to="{
          name: 'jabvox_tasks_board',
          params: { accountId, boardId: store.boardList[0].id },
        }"
        class="inline-flex items-center gap-1.5 rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-1"
      >
        <span class="i-lucide-kanban size-4" aria-hidden="true" />
        {{ t('JABVOX_TASKS.HOME.OPEN_BOARD') }}
      </RouterLink>
    </header>

    <div
      class="flex shrink-0 gap-2 overflow-x-auto border-b border-n-weak px-4 sm:px-6"
      role="tablist"
      :aria-label="t('JABVOX_TASKS.HOME.FILTERS')"
    >
      <button
        v-for="filter in filters"
        :key="filter.key"
        type="button"
        role="tab"
        :aria-selected="activeFilter === filter.key"
        class="relative flex h-12 shrink-0 items-center px-1 text-sm after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:rounded-t"
        :class="
          activeFilter === filter.key
            ? 'font-semibold text-[#15605A] after:bg-[#27958C]'
            : 'text-n-slate-10 hover:text-n-slate-12 after:bg-transparent'
        "
        @click="activeFilter = filter.key"
      >
        {{ filter.label }}
        <span
          v-if="activeFilter === filter.key"
          class="ml-2 rounded-full bg-n-alpha-1 px-1.5 text-xs text-n-slate-10"
        >
          {{ orderedTasks.length }}
        </span>
      </button>
    </div>

    <div class="min-h-0 flex-1 overflow-y-auto p-4 sm:p-6">
      <p v-if="isLoading" class="py-8 text-center text-sm text-n-slate-10">
        {{ t('JABVOX_TASKS.HOME.LOADING') }}
      </p>

      <p
        v-else-if="hasError"
        class="py-8 text-center text-sm text-n-ruby-11"
        role="alert"
      >
        {{ t('JABVOX_TASKS.HOME.ERROR') }}
      </p>

      <div v-else-if="orderedTasks.length" class="mx-auto max-w-4xl space-y-2">
        <template v-for="task in orderedTasks" :key="task.id">
          <button
            v-if="activeFilter !== 'deleted'"
            type="button"
            class="flex w-full items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 text-left transition-colors hover:bg-n-alpha-1"
            @click="openTask(task)"
          >
            <span
              class="i-lucide-circle-dot size-5 shrink-0 text-n-amber-10"
              :class="
                task.statusJabvox === 'done'
                  ? 'i-lucide-circle-check text-n-teal-10'
                  : ''
              "
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ task.titleJabvox }}
              </span>
              <span class="mt-1 block truncate text-xs text-n-slate-10">
                {{ taskMetadata(task) }}
              </span>
            </span>
            <span
              class="hidden shrink-0 text-xs text-n-slate-10 sm:inline"
              :class="
                task.dueAtJabvox &&
                new Date(task.dueAtJabvox).getTime() < Date.now() &&
                task.statusJabvox !== 'done'
                  ? 'text-n-ruby-11'
                  : ''
              "
            >
              {{ formatDueDate(task.dueAtJabvox) }}
            </span>
            <span
              v-if="activeFilter === 'all'"
              class="rounded-full px-2 py-1 text-[11px]"
              :class="
                task.statusJabvox === 'done'
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{
                task.statusJabvox === 'done'
                  ? t('JABVOX_TASKS.TASK.STATUS_DONE')
                  : t('JABVOX_TASKS.TASK.STATUS_OPEN')
              }}
            </span>
            <span
              class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-9"
            />
          </button>

          <article
            v-else
            class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
          >
            <span
              class="i-lucide-trash-2 size-5 shrink-0 text-n-slate-9"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ task.titleJabvox }}
              </span>
              <span class="mt-1 block truncate text-xs text-n-slate-10">
                {{ taskMetadata(task) }}
              </span>
            </span>
            <button
              v-if="isAdmin"
              type="button"
              class="inline-flex shrink-0 items-center gap-1.5 rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-1"
              @click="restoreTask(task.id)"
            >
              <span class="i-lucide-undo-2 size-4" aria-hidden="true" />
              {{ t('JABVOX_TASKS.HOME.RESTORE') }}
            </button>
          </article>
        </template>
      </div>

      <div
        v-else
        class="mx-auto flex max-w-lg flex-col items-center py-16 text-center"
      >
        <span
          class="i-lucide-list-checks size-10 text-n-slate-8"
          aria-hidden="true"
        />
        <h2 class="mt-3 text-base font-medium text-n-slate-12">
          {{ t('JABVOX_TASKS.HOME.EMPTY_TITLE') }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ emptyMessage }}
        </p>
      </div>
    </div>
  </main>
</template>
