<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

// Automatizaciones del tablero entero, en un cajón que se abre desde el rayo de la barra.
//
// Antes solo se llegaba a ellas columna por columna, desde el menú de cada etapa: para
// saber qué hacía el tablero había que abrir las columnas una a una. Aquí se ven todas de
// un vistazo y se entra a la que interese.
const props = defineProps({
  boardId: { type: [Number, String], required: true },
  stages: { type: Array, default: () => [] },
  // Tablero completo: hace falta su interruptor de copia por responsable.
  board: { type: Object, default: null },
});

const emit = defineEmits(['close', 'configure']);

const { t } = useI18n();
const store = useTasksStore();

// Recuento por etapa, cargado al abrir: el store no las guarda, así que se piden aquí.
// Una etapa sin respuesta se muestra con cero en vez de romper la lista.
const counts = ref({});

// --- Copia al tablero del responsable -------------------------------------
// Cada fila dice: "las tareas asignadas a X se copian a tal tablero suyo". Sin fila para
// un responsable, a ese no se le copia nada.
const copyEnabled = ref(false);
const targets = ref([]);
const ownedBoards = ref([]);
const savingCopy = ref(false);

const agents = useMapGetter('agents/getAgents');

// Solo usuarios que son dueños de algún tablero: al resto no hay dónde copiarles.
const ownerOptions = computed(() => {
  const ids = [...new Set(ownedBoards.value.map(b => b.ownerId))];
  return ids.map(id => agents.value.find(a => a.id === id)).filter(Boolean);
});

const boardsOf = ownerId =>
  ownedBoards.value.filter(b => b.ownerId === Number(ownerId));

const agentName = id => agents.value.find(a => a.id === id)?.name || `#${id}`;

// El tablero de origen no puede copiarse a sí mismo, y un responsable ya configurado no
// se ofrece dos veces (el backend lo rechaza por índice único).
const availableOwners = computed(() => {
  const used = new Set(targets.value.map(item => item.ownerId));
  return ownerOptions.value.filter(a => !used.has(a.id));
});

const loadCopyConfig = async () => {
  try {
    const [list, boards] = await Promise.all([
      store.fetchAssigneeTargets(props.boardId),
      store.fetchOwnedBoards(props.boardId),
    ]);
    targets.value = list || [];
    ownedBoards.value = (boards || []).filter(
      b => b.id !== Number(props.boardId)
    );
  } catch {
    targets.value = [];
    ownedBoards.value = [];
  }
};

const toggleCopy = async () => {
  const next = !copyEnabled.value;
  savingCopy.value = true;
  try {
    await store.updateBoard(props.boardId, {
      copy_to_assignee_board_jabvox: next,
    });
    copyEnabled.value = next;
  } catch {
    useAlert(t('JABVOX_TASKS.ASSIGNEE_COPY.ERROR'));
  } finally {
    savingCopy.value = false;
  }
};

const addTarget = async (ownerId, targetBoardId) => {
  if (!ownerId || !targetBoardId) return;
  try {
    const row = await store.createAssigneeTarget(props.boardId, {
      owner_id: Number(ownerId),
      target_board_id: Number(targetBoardId),
    });
    targets.value = [...targets.value, row];
  } catch (e) {
    useAlert(
      e?.response?.data?.errors?.join?.(', ') ||
        t('JABVOX_TASKS.ASSIGNEE_COPY.ERROR')
    );
  }
};

const changeTarget = async (row, targetBoardId) => {
  try {
    const updated = await store.updateAssigneeTarget(props.boardId, row.id, {
      target_board_id: Number(targetBoardId),
    });
    targets.value = targets.value.map(item =>
      item.id === row.id ? updated : item
    );
  } catch (e) {
    useAlert(
      e?.response?.data?.errors?.join?.(', ') ||
        t('JABVOX_TASKS.ASSIGNEE_COPY.ERROR')
    );
  }
};

const removeTarget = async row => {
  try {
    await store.deleteAssigneeTarget(props.boardId, row.id);
    targets.value = targets.value.filter(item => item.id !== row.id);
  } catch {
    useAlert(t('JABVOX_TASKS.ASSIGNEE_COPY.ERROR'));
  }
};

// Alta: se elige responsable y luego uno de SUS tableros.
const newOwnerId = ref('');
const newBoardId = ref('');

const onAdd = async () => {
  await addTarget(newOwnerId.value, newBoardId.value);
  newOwnerId.value = '';
  newBoardId.value = '';
};

onMounted(async () => {
  copyEnabled.value = Boolean(props.board?.copyToAssigneeBoardJabvox);
  await loadCopyConfig();
  const entries = await Promise.all(
    props.stages.map(async stage => {
      try {
        const list = await store.fetchAutomations(props.boardId, stage.id);
        return [stage.id, list || []];
      } catch {
        return [stage.id, []];
      }
    })
  );
  counts.value = Object.fromEntries(entries);
});

// Una etapa con su recuento y su papel, que es lo que hay que ver de un vistazo.
const rows = computed(() =>
  props.stages.map(stage => {
    const list = counts.value[stage.id] || [];
    return {
      stage,
      total: list.length,
      active: list.filter(a => a.activeJabvox).length,
    };
  })
);

const totalActive = computed(() =>
  rows.value.reduce((sum, r) => sum + r.active, 0)
);

const ROLE_STYLES = {
  initial: 'bg-n-slate-3 text-n-slate-11',
  done: 'bg-n-teal-3 text-n-teal-11',
  inactive: 'bg-n-ruby-3 text-n-ruby-11',
};
</script>

<template>
  <div
    class="fixed inset-0 z-40 flex justify-end bg-black/30"
    @click.self="emit('close')"
  >
    <aside
      class="w-full max-w-md h-full bg-n-solid-1 shadow-xl flex flex-col"
      role="dialog"
      aria-modal="true"
    >
      <header
        class="flex items-center justify-between gap-3 px-5 py-4 border-b border-n-weak shrink-0"
      >
        <div class="flex items-center gap-2 min-w-0">
          <span
            class="i-lucide-zap size-5 text-n-amber-11 shrink-0"
            aria-hidden="true"
          />
          <div class="min-w-0">
            <h2 class="text-sm font-semibold text-n-slate-12 truncate">
              {{ t('JABVOX_TASKS.AUTOMATIONS.DRAWER_TITLE') }}
            </h2>
            <p class="text-[11px] text-n-slate-10">
              {{
                t('JABVOX_TASKS.AUTOMATIONS.ACTIVE_COUNT', {
                  count: totalActive,
                })
              }}
            </p>
          </div>
        </div>
        <button
          type="button"
          class="p-1.5 rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
          :title="t('JABVOX_TASKS.AUTOMATIONS.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </header>

      <div class="flex-1 min-h-0 overflow-y-auto p-4 space-y-2">
        <button
          v-for="row in rows"
          :key="row.stage.id"
          type="button"
          class="w-full flex items-center justify-between gap-3 px-3 py-3 rounded-xl border border-n-weak hover:bg-n-alpha-1 text-left transition-colors"
          @click="emit('configure', row.stage)"
        >
          <div class="min-w-0 flex items-center gap-2.5">
            <span
              class="size-2.5 rounded-full shrink-0"
              :style="{ backgroundColor: row.stage.colorJabvox }"
              aria-hidden="true"
            />
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ row.stage.nameJabvox }}
              </p>
              <p class="text-[11px] text-n-slate-10">
                <template v-if="row.total">
                  {{
                    t('JABVOX_TASKS.AUTOMATIONS.STAGE_SUMMARY', {
                      active: row.active,
                      total: row.total,
                    })
                  }}
                </template>
                <template v-else>
                  {{ t('JABVOX_TASKS.AUTOMATIONS.STAGE_NONE') }}
                </template>
              </p>
            </div>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <span
              v-if="row.stage.roleJabvox"
              class="px-1.5 py-0.5 rounded text-[10px] font-medium"
              :class="ROLE_STYLES[row.stage.roleJabvox]"
            >
              {{ t(`JABVOX_TASKS.STAGE_ROLE.${row.stage.roleJabvox}`) }}
            </span>
            <span
              v-if="row.active"
              class="flex items-center gap-1 px-1.5 py-0.5 rounded bg-n-amber-3 text-n-amber-11 text-[10px] font-medium"
            >
              <span class="i-lucide-zap size-3" aria-hidden="true" />
              {{ row.active }}
            </span>
            <span
              class="i-lucide-chevron-right size-4 text-n-slate-10"
              aria-hidden="true"
            />
          </div>
        </button>

        <p v-if="!rows.length" class="text-sm text-n-slate-10 text-center py-8">
          {{ t('JABVOX_TASKS.AUTOMATIONS.NO_STAGES') }}
        </p>

        <!-- Copia al tablero personal del responsable -->
        <section class="pt-4 mt-2 border-t border-n-weak space-y-3">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h3 class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_TASKS.ASSIGNEE_COPY.TITLE') }}
              </h3>
              <p class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_TASKS.ASSIGNEE_COPY.HINT') }}
              </p>
            </div>
            <button
              type="button"
              class="shrink-0 px-2.5 py-1.5 rounded-lg text-xs font-medium border transition-colors disabled:opacity-50"
              :class="
                copyEnabled
                  ? 'bg-n-amber-3 text-n-amber-11 border-n-amber-6'
                  : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'
              "
              :disabled="savingCopy"
              @click="toggleCopy"
            >
              {{
                copyEnabled
                  ? t('JABVOX_TASKS.ASSIGNEE_COPY.ON')
                  : t('JABVOX_TASKS.ASSIGNEE_COPY.OFF')
              }}
            </button>
          </div>

          <template v-if="copyEnabled">
            <div
              v-for="row in targets"
              :key="row.id"
              class="flex items-center gap-2 px-3 py-2 rounded-xl border border-n-weak"
            >
              <span class="text-sm text-n-slate-12 truncate flex-1 min-w-0">
                {{ agentName(row.ownerId) }}
              </span>
              <select
                class="text-xs rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 px-2 py-1"
                :value="row.targetBoardId"
                @change="changeTarget(row, $event.target.value)"
              >
                <option
                  v-for="b in boardsOf(row.ownerId)"
                  :key="b.id"
                  :value="b.id"
                >
                  {{ b.nameJabvox }}
                </option>
              </select>
              <button
                type="button"
                class="p-1 rounded text-n-slate-10 hover:text-n-ruby-11"
                :title="t('JABVOX_TASKS.ASSIGNEE_COPY.REMOVE')"
                @click="removeTarget(row)"
              >
                <span class="i-lucide-trash-2 size-3.5" aria-hidden="true" />
              </button>
            </div>

            <div
              v-if="availableOwners.length"
              class="flex items-center gap-2 px-3 py-2 rounded-xl border border-dashed border-n-weak"
            >
              <select
                v-model="newOwnerId"
                class="flex-1 min-w-0 text-xs rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 px-2 py-1"
              >
                <option value="">
                  {{ t('JABVOX_TASKS.ASSIGNEE_COPY.PICK_OWNER') }}
                </option>
                <option v-for="a in availableOwners" :key="a.id" :value="a.id">
                  {{ a.name }}
                </option>
              </select>
              <select
                v-model="newBoardId"
                :disabled="!newOwnerId"
                class="text-xs rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 px-2 py-1 disabled:opacity-50"
              >
                <option value="">
                  {{ t('JABVOX_TASKS.ASSIGNEE_COPY.PICK_BOARD') }}
                </option>
                <option
                  v-for="b in boardsOf(newOwnerId)"
                  :key="b.id"
                  :value="b.id"
                >
                  {{ b.nameJabvox }}
                </option>
              </select>
              <button
                type="button"
                class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-40"
                :disabled="!newOwnerId || !newBoardId"
                :title="t('JABVOX_TASKS.ASSIGNEE_COPY.ADD')"
                @click="onAdd"
              >
                <span class="i-lucide-plus size-4" aria-hidden="true" />
              </button>
            </div>

            <p
              v-if="!ownerOptions.length"
              class="text-[11px] text-n-slate-10 py-1"
            >
              {{ t('JABVOX_TASKS.ASSIGNEE_COPY.NO_OWNED_BOARDS') }}
            </p>
          </template>
        </section>
      </div>
    </aside>
  </div>
</template>
