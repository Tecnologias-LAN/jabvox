<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  leadId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['openTask']);

const { t } = useI18n();
const store = useTasksStore();

const cursor = ref(new Date());

const isLoading = computed(() => store.uiFlags.fetchingTasks);
const tasks = computed(() => store.taskList);

const monthLabel = computed(() =>
  cursor.value.toLocaleDateString(undefined, {
    month: 'long',
    year: 'numeric',
  })
);

const weekdayLabels = computed(() => {
  const base = new Date(2023, 0, 1); // a Sunday
  return Array.from({ length: 7 }, (_, index) => {
    const day = new Date(base);
    day.setDate(base.getDate() + index);
    return day.toLocaleDateString(undefined, { weekday: 'short' });
  });
});

const monthRange = computed(() => {
  const year = cursor.value.getFullYear();
  const month = cursor.value.getMonth();
  const from = new Date(year, month, 1);
  const to = new Date(year, month + 1, 0, 23, 59, 59);
  return { from, to };
});

const calendarDays = computed(() => {
  const { from } = monthRange.value;
  const year = from.getFullYear();
  const month = from.getMonth();
  const firstWeekday = from.getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const cells = [];
  for (let i = 0; i < firstWeekday; i += 1) {
    cells.push(null);
  }
  for (let d = 1; d <= daysInMonth; d += 1) {
    cells.push(new Date(year, month, d));
  }
  return cells;
});

const tasksByDay = computed(() => {
  const map = {};
  tasks.value.forEach(task => {
    if (!task.dueAtJabvox) return;
    const date = new Date(task.dueAtJabvox);
    if (Number.isNaN(date.getTime())) return;
    const key = `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
    if (!map[key]) map[key] = [];
    map[key].push(task);
  });
  return map;
});

const dayKey = date =>
  `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
const tasksForDay = date => tasksByDay.value[dayKey(date)] || [];

const isToday = date => {
  const now = new Date();
  return (
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate()
  );
};

const fetch = async () => {
  const { from, to } = monthRange.value;
  const params = {
    board_id: props.boardId,
    from: from.toISOString(),
    to: to.toISOString(),
  };
  if (props.leadId) params.lead_id = props.leadId;
  await store.fetchTasks(params);
};

const prevMonth = () => {
  cursor.value = new Date(
    cursor.value.getFullYear(),
    cursor.value.getMonth() - 1,
    1
  );
};

const nextMonth = () => {
  cursor.value = new Date(
    cursor.value.getFullYear(),
    cursor.value.getMonth() + 1,
    1
  );
};

const goToday = () => {
  cursor.value = new Date();
};

watch([cursor, () => props.leadId, () => props.boardId], fetch, {
  immediate: true,
});
</script>

<template>
  <div class="flex flex-col h-full min-h-0">
    <div class="flex items-center justify-between gap-2 mb-3 shrink-0">
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ monthLabel }}
      </h3>
      <div class="flex items-center gap-1">
        <button
          type="button"
          class="p-1.5 rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
          :title="t('JABVOX_TASKS.CALENDAR.PREV')"
          @click="prevMonth"
        >
          <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
        </button>
        <button
          type="button"
          class="px-2 py-1 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
          @click="goToday"
        >
          {{ t('JABVOX_TASKS.CALENDAR.TODAY') }}
        </button>
        <button
          type="button"
          class="p-1.5 rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
          :title="t('JABVOX_TASKS.CALENDAR.NEXT')"
          @click="nextMonth"
        >
          <span class="i-lucide-chevron-right size-4" aria-hidden="true" />
        </button>
      </div>
    </div>

    <p v-if="isLoading" class="text-sm text-n-slate-10 mb-2">
      {{ t('JABVOX_TASKS.CALENDAR.LOADING') }}
    </p>

    <div class="grid grid-cols-7 gap-px mb-px shrink-0">
      <div
        v-for="label in weekdayLabels"
        :key="label"
        class="text-[11px] font-medium text-n-slate-10 text-center py-1"
      >
        {{ label }}
      </div>
    </div>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <div class="grid grid-cols-7 gap-px bg-n-weak">
        <div
          v-for="(day, index) in calendarDays"
          :key="index"
          class="min-h-24 bg-n-background p-1.5"
        >
          <template v-if="day">
            <div class="flex items-center justify-between mb-1">
              <span
                class="text-[11px] font-medium"
                :class="
                  isToday(day)
                    ? 'text-white bg-n-brand rounded-full px-1.5'
                    : 'text-n-slate-10'
                "
              >
                {{ day.getDate() }}
              </span>
            </div>
            <div class="space-y-1">
              <button
                v-for="task in tasksForDay(day)"
                :key="task.id"
                type="button"
                class="block w-full text-left text-[11px] px-1.5 py-1 rounded bg-n-blue-3 text-n-blue-11 truncate hover:bg-n-alpha-2"
                @click="emit('openTask', task)"
              >
                {{ task.titleJabvox }}
              </button>
            </div>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
