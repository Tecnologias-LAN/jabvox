<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';

// Automatizaciones del tablero entero, en un cajón que se abre desde el rayo de la barra.
//
// Antes solo se llegaba a ellas columna por columna, desde el menú de cada etapa: para
// saber qué hacía el tablero había que abrir las columnas una a una. Aquí se ven todas de
// un vistazo y se entra a la que interese.
const props = defineProps({
  boardId: { type: [Number, String], required: true },
  stages: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'configure']);

const { t } = useI18n();
const store = useTasksStore();

// Recuento por etapa, cargado al abrir: el store no las guarda, así que se piden aquí.
// Una etapa sin respuesta se muestra con cero en vez de romper la lista.
const counts = ref({});

onMounted(async () => {
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
      </div>
    </aside>
  </div>
</template>
