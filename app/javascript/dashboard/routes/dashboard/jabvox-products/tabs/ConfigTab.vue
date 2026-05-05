<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const currencies = useMapGetter('jabvoxProducts/getCurrencies');
const itemTypes = useMapGetter('jabvoxProducts/getItemTypes');
const unitsOfMeasure = useMapGetter('jabvoxProducts/getUnitsOfMeasure');
const taxRates = useMapGetter('jabvoxProducts/getTaxRates');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const activeSubTab = ref('currencies');
const showForm = ref(false);
const editingItem = ref(null);
const form = ref({});

const SUB_TABS = [
  { key: 'currencies', label: 'JABVOX_PRODUCTS.CONFIG.CURRENCIES' },
  { key: 'itemTypes', label: 'JABVOX_PRODUCTS.CONFIG.ITEM_TYPES' },
  { key: 'units', label: 'JABVOX_PRODUCTS.CONFIG.UNITS' },
  { key: 'taxRates', label: 'JABVOX_PRODUCTS.CONFIG.TAX_RATES' },
];

onMounted(() =>
  Promise.all([
    store.dispatch('jabvoxProducts/fetchCurrency'),
    store.dispatch('jabvoxProducts/fetchItemType'),
    store.dispatch('jabvoxProducts/fetchUnit'),
    store.dispatch('jabvoxProducts/fetchTaxRate'),
  ])
);

const currentList = () => {
  if (activeSubTab.value === 'currencies') return currencies.value;
  if (activeSubTab.value === 'itemTypes') return itemTypes.value;
  if (activeSubTab.value === 'units') return unitsOfMeasure.value;
  return taxRates.value;
};

const openNew = () => {
  editingItem.value = null;
  if (activeSubTab.value === 'currencies')
    form.value = { symbol_jabvox: '', name_jabvox: '', active_jabvox: true };
  else if (activeSubTab.value === 'itemTypes')
    form.value = { name_jabvox: '', active_jabvox: true };
  else if (activeSubTab.value === 'units')
    form.value = {
      name_jabvox: '',
      abbreviation_jabvox: '',
      active_jabvox: true,
    };
  else
    form.value = {
      name_jabvox: '',
      percentage_jabvox: '',
      active_jabvox: true,
    };
  showForm.value = true;
};

const openEdit = item => {
  editingItem.value = item;
  form.value = { ...item };
  showForm.value = true;
};

const actionPrefix = () => {
  if (activeSubTab.value === 'currencies') return 'Currency';
  if (activeSubTab.value === 'itemTypes') return 'ItemType';
  if (activeSubTab.value === 'units') return 'Unit';
  return 'TaxRate';
};

const onSubmit = async () => {
  try {
    const prefix = actionPrefix();
    if (editingItem.value) {
      await store.dispatch(`jabvoxProducts/update${prefix}`, {
        id: editingItem.value.id,
        ...form.value,
      });
    } else {
      await store.dispatch(`jabvoxProducts/create${prefix}`, form.value);
    }
    useAlert(t('JABVOX_PRODUCTS.SAVE_SUCCESS'));
    showForm.value = false;
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const onDelete = async item => {
  if (
    !window.confirm(
      t('JABVOX_PRODUCTS.DELETE_CONFIRM', { name: item.name_jabvox })
    )
  )
    return;
  try {
    const prefix = actionPrefix();
    await store.dispatch(`jabvoxProducts/destroy${prefix}`, item.id);
    useAlert(t('JABVOX_PRODUCTS.DELETE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const isSaving = () => {
  if (activeSubTab.value === 'currencies')
    return uiFlags.value.isSavingCurrency;
  if (activeSubTab.value === 'itemTypes') return uiFlags.value.isSavingItemType;
  if (activeSubTab.value === 'units') return uiFlags.value.isSavingUnit;
  return uiFlags.value.isSavingTaxRate;
};
</script>

<template>
  <div class="space-y-4">
    <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
      {{ $t('JABVOX_PRODUCTS.CONFIG.TITLE') }}
    </h2>

    <div class="flex gap-1 border-b border-slate-200 dark:border-slate-700">
      <button
        v-for="tab in SUB_TABS"
        :key="tab.key"
        class="px-4 py-2 text-sm font-medium border-b-2 transition-colors"
        :class="[
          activeSubTab === tab.key
            ? 'border-woot-600 text-woot-600'
            : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300',
        ]"
        @click="
          activeSubTab = tab.key;
          showForm = false;
        "
      >
        {{ $t(tab.label) }}
      </button>
    </div>

    <div class="flex justify-end">
      <Button
        icon="i-lucide-plus"
        :label="$t('JABVOX_PRODUCTS.NEW')"
        @click="openNew"
      />
    </div>

    <div
      v-if="currentList().length === 0"
      class="text-sm text-slate-400 text-center py-8"
    >
      {{ $t('JABVOX_PRODUCTS.CONFIG.EMPTY') }}
    </div>

    <table
      v-else
      class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
    >
      <thead>
        <tr class="text-left text-slate-500 dark:text-slate-400">
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.COLS.NAME') }}
          </th>
          <th
            v-if="activeSubTab === 'currencies'"
            class="py-3 pr-4 font-medium"
          >
            {{ $t('JABVOX_PRODUCTS.CONFIG.SYMBOL') }}
          </th>
          <th v-if="activeSubTab === 'units'" class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.CONFIG.ABBREVIATION') }}
          </th>
          <th v-if="activeSubTab === 'taxRates'" class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.CONFIG.PERCENTAGE') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.COLS.STATUS') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.COLS.ACTIONS') }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
        <tr
          v-for="item in currentList()"
          :key="item.id"
          class="hover:bg-slate-50 dark:hover:bg-slate-800/50"
        >
          <td class="py-3 pr-4 font-medium text-slate-800 dark:text-slate-100">
            {{ item.name_jabvox }}
          </td>
          <td
            v-if="activeSubTab === 'currencies'"
            class="py-3 pr-4 text-slate-500"
          >
            {{ item.symbol_jabvox }}
          </td>
          <td v-if="activeSubTab === 'units'" class="py-3 pr-4 text-slate-500">
            {{ item.abbreviation_jabvox || '—' }}
          </td>
          <td
            v-if="activeSubTab === 'taxRates'"
            class="py-3 pr-4 text-slate-500"
          >
            {{ item.percentage_jabvox }}%
          </td>
          <td class="py-3 pr-4">
            <span
              class="text-xs px-2 py-1 rounded-full font-medium"
              :class="[
                item.active_jabvox
                  ? 'bg-green-100 text-green-700'
                  : 'bg-slate-100 text-slate-500',
              ]"
            >
              {{
                item.active_jabvox
                  ? $t('JABVOX_PRODUCTS.ACTIVE')
                  : $t('JABVOX_PRODUCTS.INACTIVE')
              }}
            </span>
          </td>
          <td class="py-3 pr-4">
            <div class="flex gap-2">
              <Button
                size="small"
                variant="ghost"
                icon="i-lucide-pencil"
                @click="openEdit(item)"
              />
              <Button
                size="small"
                variant="ghost"
                color-scheme="alert"
                icon="i-lucide-trash-2"
                @click="onDelete(item)"
              />
            </div>
          </td>
        </tr>
      </tbody>
    </table>

    <div
      v-if="showForm"
      class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
      @click.self="showForm = false"
    >
      <div
        class="bg-white dark:bg-slate-900 rounded-xl shadow-xl p-6 w-full max-w-md space-y-4"
      >
        <h3 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          {{
            editingItem ? $t('JABVOX_PRODUCTS.EDIT') : $t('JABVOX_PRODUCTS.NEW')
          }}
        </h3>
        <div class="space-y-3">
          <div v-if="activeSubTab === 'currencies'">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.CONFIG.SYMBOL') }}</label
            >
            <input
              v-model="form.symbol_jabvox"
              type="text"
              :placeholder="$t('JABVOX_PRODUCTS.CONFIG.SYMBOL_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.COLS.NAME') }}</label
            >
            <input
              v-model="form.name_jabvox"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div v-if="activeSubTab === 'units'">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.CONFIG.ABBREVIATION') }}</label
            >
            <input
              v-model="form.abbreviation_jabvox"
              type="text"
              :placeholder="
                $t('JABVOX_PRODUCTS.CONFIG.ABBREVIATION_PLACEHOLDER')
              "
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div v-if="activeSubTab === 'taxRates'">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.CONFIG.PERCENTAGE') }}</label
            >
            <input
              v-model="form.percentage_jabvox"
              type="number"
              step="0.01"
              min="0"
              max="100"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              v-model="form.active_jabvox"
              type="checkbox"
              class="rounded text-woot-500"
            />
            <span class="text-sm text-slate-700 dark:text-slate-300">{{
              $t('JABVOX_PRODUCTS.ACTIVE')
            }}</span>
          </label>
        </div>
        <div class="flex gap-3 pt-2">
          <Button
            :label="$t('JABVOX_PRODUCTS.SAVE')"
            :is-loading="isSaving()"
            @click="onSubmit"
          />
          <Button
            variant="ghost"
            :label="$t('CANCEL')"
            @click="showForm = false"
          />
        </div>
      </div>
    </div>
  </div>
</template>
