<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'next/button/Button.vue';
import FilterSelect from './inputs/FilterSelect.vue';
import ConditionRow from './ConditionRow.vue';

// Un GRUPO agrupa varias condiciones entre paréntesis: "(A OR B)". Sus hijas se unen
// con childOperator (Y/O), y el propio grupo se une a lo que sigue con queryOperator.
// snakeKeys: las condiciones de automatizaciones usan attribute_key/filter_operator
// (snake_case); las de filtros usan attributeKey/filterOperator (camelCase). El grupo
// lee/escribe la forma correcta según este flag, para servir en ambos contextos.
const props = defineProps({
  filterTypes: { type: Array, required: true },
  showQueryOperator: { type: Boolean, default: false },
  snakeKeys: { type: Boolean, default: false },
});

const emit = defineEmits(['remove']);

const fieldName = {
  attributeKey: () => (props.snakeKeys ? 'attribute_key' : 'attributeKey'),
  filterOperator: () =>
    props.snakeKeys ? 'filter_operator' : 'filterOperator',
};

// Accessor de un campo de una hija, independiente del estilo de clave.
const fieldValue = (condition, field) => condition[fieldName[field]()];
const setFieldValue = (condition, field, value) => {
  condition[fieldName[field]()] = value;
};

const { t } = useI18n();

// queryOperator: une este grupo con el elemento SIGUIENTE (Y/O), igual que una fila.
const queryOperator = defineModel('queryOperator', {
  type: String,
  required: false,
  default: undefined,
  validator: value => ['and', 'or'].includes(value),
});

// childOperator: une las condiciones DENTRO del grupo (Y/O).
const childOperator = defineModel('childOperator', {
  type: String,
  required: true,
});

// conditions: array de condiciones planas del grupo.
const conditions = defineModel('conditions', {
  type: Array,
  required: true,
});

// Condición nueva con claves en el estilo correcto (camelCase o snake_case).
const buildDefaultCondition = () =>
  props.snakeKeys
    ? {
        attribute_key: 'status',
        filter_operator: 'equal_to',
        values: [],
        query_operator: 'or',
      }
    : {
        attributeKey: 'status',
        filterOperator: 'equal_to',
        values: [],
        queryOperator: 'or',
      };

const rowsRef = ref([]);

const operatorOptions = computed(() => [
  { value: 'or', label: t('FILTER.QUERY_DROPDOWN_LABELS.OR') },
  { value: 'and', label: t('FILTER.QUERY_DROPDOWN_LABELS.AND') },
]);

const queryOperatorOptions = computed(() => [
  { value: 'and', label: t('FILTER.QUERY_DROPDOWN_LABELS.AND') },
  { value: 'or', label: t('FILTER.QUERY_DROPDOWN_LABELS.OR') },
]);

const addCondition = () => {
  conditions.value.push(buildDefaultCondition());
};

const removeCondition = index => {
  if (conditions.value.length === 1) {
    // Un grupo con una sola condición no aporta paréntesis: se elimina el grupo.
    emit('remove');
  } else {
    conditions.value.splice(index, 1);
  }
};

const validate = () => {
  return (rowsRef.value || []).every(row => row.validate());
};

// El formulario padre resetea la validación de cada condición (fila o grupo).
// Sin exponer esto, resetValidation() del padre reventaba con
// "resetValidation is not a function" al guardar una regla con grupo.
const resetValidation = () => {
  (rowsRef.value || []).forEach(row => row.resetValidation?.());
};

defineExpose({ validate, resetValidation });
</script>

<template>
  <li class="list-none">
    <div class="flex items-start gap-2">
      <FilterSelect
        v-if="showQueryOperator"
        v-model="queryOperator"
        variant="faded"
        hide-icon
        class="mt-1 text-sm"
        :options="queryOperatorOptions"
      />
      <div
        class="flex-1 p-3 border border-dashed rounded-lg border-n-weak bg-n-alpha-1"
      >
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-2">
            <span class="text-sm text-n-slate-11">
              {{ t('FILTER.GROUP.LABEL') }}
            </span>
            <FilterSelect
              v-model="childOperator"
              variant="faded"
              hide-icon
              class="text-sm"
              :options="operatorOptions"
            />
          </div>
          <Button
            sm
            ghost
            slate
            icon="i-lucide-trash"
            @click.stop="emit('remove')"
          />
        </div>
        <ul class="grid gap-3 list-none">
          <template v-for="(condition, index) in conditions" :key="index">
            <ConditionRow
              ref="rowsRef"
              :attribute-key="fieldValue(condition, 'attributeKey')"
              :filter-operator="fieldValue(condition, 'filterOperator')"
              :values="condition.values"
              :filter-types="filterTypes"
              :show-query-operator="false"
              @update:attribute-key="
                val => setFieldValue(condition, 'attributeKey', val)
              "
              @update:filter-operator="
                val => setFieldValue(condition, 'filterOperator', val)
              "
              @update:values="val => (condition.values = val)"
              @remove="removeCondition(index)"
            />
          </template>
        </ul>
        <Button sm ghost blue class="mt-2" @click="addCondition">
          {{ t('FILTER.GROUP.ADD_CONDITION') }}
        </Button>
      </div>
    </div>
  </li>
</template>
