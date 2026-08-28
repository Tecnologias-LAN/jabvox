<script setup>
// Filtro seleccionable por columna (MULTI-selección) para el visor de datos: un desplegable
// que carga los valores REALES (distintos) de la columna desde la BD. No se escribe el valor
// — se marcan uno o varios con checkbox (p.ej. Almacén 20, 30 y 40 → IN (20,30,40)). Dentro
// del desplegable hay una caja de búsqueda que refina esos valores (server-side).
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';

const props = defineProps({
  column: { type: String, required: true },
  table: { type: String, required: true },
  // valores seleccionados: array (vacío = sin filtro)
  modelValue: { type: Array, default: () => [] },
  fetcher: { type: Function, required: true }, // (params) => Promise<{values, truncated}>
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const open = ref(false);
const loading = ref(false);
const search = ref('');
const values = ref([]);
const truncated = ref(false);
const loadedOnce = ref(false);
const rootRef = ref(null);

const selected = computed(() => props.modelValue || []);
const selectedCount = computed(() => selected.value.length);
const isActive = computed(() => selectedCount.value > 0);

const isChecked = val => selected.value.some(v => String(v) === String(val));

const load = async () => {
  loading.value = true;
  try {
    const res = await props.fetcher({
      table: props.table,
      column: props.column,
      search: search.value || undefined,
      limit: 200,
    });
    values.value = res.values || [];
    truncated.value = Boolean(res.truncated);
    loadedOnce.value = true;
  } catch {
    values.value = [];
  } finally {
    loading.value = false;
  }
};

const debouncedLoad = useDebounceFn(load, 300);
watch(search, () => debouncedLoad());

const toggle = () => {
  open.value = !open.value;
  if (open.value && !loadedOnce.value) load();
};

// Marca/desmarca un valor manteniendo el resto (multi-selección).
const toggleValue = val => {
  const next = isChecked(val)
    ? selected.value.filter(v => String(v) !== String(val))
    : [...selected.value, val];
  emit('update:modelValue', next);
};

const clear = () => emit('update:modelValue', []);

const label = computed(() => {
  if (!selectedCount.value) return t('JABVOX_ANALYTICS.VIEWER.FILTER_ALL');
  if (selectedCount.value === 1) return String(selected.value[0]);
  return t('JABVOX_ANALYTICS.VIEWER.FILTER_N_SELECTED', {
    count: selectedCount.value,
  });
});

const onDocClick = e => {
  if (rootRef.value && !rootRef.value.contains(e.target)) open.value = false;
};
watch(open, isOpen => {
  if (isOpen) document.addEventListener('click', onDocClick, true);
  else document.removeEventListener('click', onDocClick, true);
});
onBeforeUnmount(() => document.removeEventListener('click', onDocClick, true));
</script>

<template>
  <div ref="rootRef" class="relative">
    <button
      type="button"
      class="flex w-full items-center justify-between gap-1 rounded-md border px-2 py-1 text-xs"
      :class="
        isActive
          ? 'border-n-brand bg-n-brand/10 text-n-brand'
          : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:border-n-strong'
      "
      @click.stop="toggle"
    >
      <span class="truncate">{{ label }}</span>
      <span
        class="i-lucide-chevron-down size-3.5 shrink-0"
        :class="{ 'rotate-180': open }"
      />
    </button>

    <div
      v-if="open"
      class="absolute left-0 z-30 mt-1 max-h-80 w-60 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 shadow-xl"
    >
      <!-- Búsqueda dentro del filtro -->
      <div class="border-b border-n-weak p-2">
        <div class="relative">
          <span
            class="i-lucide-search pointer-events-none absolute left-2 top-1/2 size-3.5 -translate-y-1/2 text-n-slate-10"
          />
          <input
            v-model="search"
            type="text"
            class="w-full rounded-md border border-n-weak bg-n-alpha-1 py-1 pl-7 pr-2 text-xs text-n-slate-12 outline-none focus:border-n-strong"
            :placeholder="t('JABVOX_ANALYTICS.VIEWER.FILTER_SEARCH')"
            @click.stop
          />
        </div>
      </div>

      <!-- Barra de acciones (limpiar) cuando hay selección -->
      <div
        v-if="isActive"
        class="flex items-center justify-between border-b border-n-weak px-3 py-1.5 text-xs"
      >
        <span class="text-n-slate-11">
          {{
            t('JABVOX_ANALYTICS.VIEWER.FILTER_N_SELECTED', {
              count: selectedCount,
            })
          }}
        </span>
        <button
          type="button"
          class="flex items-center gap-1 text-n-brand hover:underline"
          @click.stop="clear"
        >
          <span class="i-lucide-x size-3.5" />
          {{ t('JABVOX_ANALYTICS.VIEWER.FILTER_CLEAR_ONE') }}
        </button>
      </div>

      <div class="max-h-56 overflow-y-auto py-1">
        <div
          v-if="loading"
          class="px-3 py-3 text-center text-xs text-n-slate-10"
        >
          <span
            class="i-lucide-loader-circle mr-1 inline-block size-3.5 animate-spin"
          />
          {{ t('JABVOX_ANALYTICS.COMMON.LOADING') }}
        </div>

        <template v-else>
          <label
            v-for="val in values"
            :key="String(val)"
            class="flex w-full cursor-pointer items-center gap-2 px-3 py-1.5 text-left text-xs text-n-slate-12 hover:bg-n-alpha-2"
            @click.stop
          >
            <input
              type="checkbox"
              class="size-3.5 shrink-0 rounded border-n-weak"
              :checked="isChecked(val)"
              @change="toggleValue(val)"
            />
            <span class="truncate">{{ val }}</span>
          </label>

          <p
            v-if="!values.length"
            class="px-3 py-3 text-center text-xs text-n-slate-10"
          >
            {{ t('JABVOX_ANALYTICS.VIEWER.NO_ROWS') }}
          </p>
          <p
            v-if="truncated"
            class="border-t border-n-weak px-3 py-1.5 text-[11px] text-n-slate-10"
          >
            {{ t('JABVOX_ANALYTICS.VIEWER.FILTER_TRUNCATED') }}
          </p>
        </template>
      </div>
    </div>
  </div>
</template>
