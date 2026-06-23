<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  leadId: { type: Number, required: true },
});

const store = useStore();

const tableRows = computed(() => {
  try {
    return (
      store.getters['jabvoxCustomization/getLeadTableRows'](props.leadId) || []
    );
  } catch {
    return [];
  }
});

const uiFlags = computed(() => {
  try {
    return store.getters['jabvoxCustomization/getUIFlags'];
  } catch {
    return {};
  }
});

// draft: { [tableId]: { [colName]: value } }
const drafts = ref({});
const savedTables = ref(new Set());

const initDrafts = rows => {
  rows.forEach(row => {
    if (!drafts.value[row.table_id]) {
      drafts.value[row.table_id] = { ...(row.data || {}) };
    }
  });
};

watch(tableRows, rows => initDrafts(rows), { immediate: true });

const isDirty = tableId => {
  const row = tableRows.value.find(r => r.table_id === tableId);
  const current = row?.data || {};
  const draft = drafts.value[tableId] || {};
  return JSON.stringify(current) !== JSON.stringify(draft);
};

const saveTable = async tableId => {
  try {
    await store.dispatch('jabvoxCustomization/updateLeadTableRow', {
      leadId: props.leadId,
      tableId,
      data: drafts.value[tableId] || {},
    });
    savedTables.value.add(tableId);
    setTimeout(() => savedTables.value.delete(tableId), 2000);
    useAlert('Datos guardados.');
  } catch {
    useAlert('Error al guardar.');
  }
};

const resetTable = tableId => {
  const row = tableRows.value.find(r => r.table_id === tableId);
  drafts.value[tableId] = { ...(row?.data || {}) };
};

const getInputType = colType => {
  const map = {
    integer: 'number',
    float: 'number',
    boolean: 'checkbox',
    date: 'date',
  };
  return map[colType] || 'text';
};

onMounted(() => {
  store.dispatch('jabvoxCustomization/fetchLeadTableRows', props.leadId);
});
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="flex flex-col gap-4 p-4">
    <div
      v-if="uiFlags.isFetchingRows"
      class="text-sm text-slate-400 py-8 text-center"
    >
      Cargando...
    </div>

    <div
      v-else-if="!tableRows.length"
      class="text-sm text-slate-400 py-8 text-center border border-dashed border-slate-200 dark:border-slate-700 rounded-xl"
    >
      No hay tablas personalizadas configuradas. Crea una en
      <strong>Configuración → Personalización</strong>.
    </div>

    <div
      v-for="row in tableRows"
      :key="row.table_id"
      class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 overflow-hidden"
    >
      <!-- Table header -->
      <div
        class="flex items-center justify-between px-4 py-3 bg-slate-50 dark:bg-slate-800 border-b border-slate-200 dark:border-slate-700"
      >
        <div>
          <p class="text-sm font-semibold text-slate-800 dark:text-slate-200">
            {{ row.table_name }}
          </p>
          <p v-if="row.table_description" class="text-xs text-slate-500">
            {{ row.table_description }}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <span
            v-if="savedTables.has(row.table_id)"
            class="text-xs text-green-600 flex items-center gap-1"
          >
            <span class="i-lucide-check size-3" /> Guardado
          </span>
          <Button
            v-if="isDirty(row.table_id)"
            variant="ghost"
            size="sm"
            label="Descartar"
            @click="resetTable(row.table_id)"
          />
          <Button
            size="sm"
            label="Guardar"
            :is-loading="uiFlags.isSaving"
            :disabled="!isDirty(row.table_id)"
            @click="saveTable(row.table_id)"
          />
        </div>
      </div>

      <!-- Columns / fields -->
      <div v-if="!row.columns.length" class="px-4 py-3 text-sm text-slate-400">
        Esta tabla no tiene columnas. Agrégalas en Personalización → Columnas.
      </div>
      <div v-else class="grid grid-cols-2 gap-x-6 gap-y-3 p-4">
        <div
          v-for="col in row.columns"
          :key="col.id"
          :class="
            col.column_type_jabvox === 'boolean'
              ? 'col-span-1 flex items-center gap-2'
              : 'col-span-1'
          "
        >
          <!-- Boolean -->
          <template v-if="col.column_type_jabvox === 'boolean'">
            <input
              :id="`col-${col.id}`"
              v-model="drafts[row.table_id][col.name_jabvox]"
              type="checkbox"
              class="rounded border-slate-300 text-woot-600 focus:ring-woot-500"
            />
            <label
              :for="`col-${col.id}`"
              class="text-sm text-slate-700 dark:text-slate-300 cursor-pointer"
            >
              {{ col.label_jabvox }}
              <span v-if="col.required_jabvox" class="text-red-500">*</span>
            </label>
          </template>

          <!-- Select -->
          <template v-else-if="col.column_type_jabvox === 'select'">
            <label
              class="block text-xs font-medium text-slate-500 dark:text-slate-400 mb-1"
            >
              {{ col.label_jabvox }}
              <span v-if="col.required_jabvox" class="text-red-500">*</span>
            </label>
            <select
              v-model="drafts[row.table_id][col.name_jabvox]"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option value="">— sin valor —</option>
              <option
                v-for="opt in col.options_jabvox || []"
                :key="opt"
                :value="opt"
              >
                {{ opt }}
              </option>
            </select>
          </template>

          <!-- Text / Number / Date -->
          <template v-else>
            <label
              class="block text-xs font-medium text-slate-500 dark:text-slate-400 mb-1"
            >
              {{ col.label_jabvox }}
              <span v-if="col.required_jabvox" class="text-red-500">*</span>
            </label>
            <input
              v-model="drafts[row.table_id][col.name_jabvox]"
              :type="getInputType(col.column_type_jabvox)"
              :step="col.column_type_jabvox === 'float' ? '0.01' : undefined"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
