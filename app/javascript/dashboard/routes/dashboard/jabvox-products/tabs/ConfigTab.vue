<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConfirmDialog from '../components/ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();

const currencies = useMapGetter('jabvoxProducts/getCurrencies');
const itemTypes = useMapGetter('jabvoxProducts/getItemTypes');
const unitsOfMeasure = useMapGetter('jabvoxProducts/getUnitsOfMeasure');
const taxRates = useMapGetter('jabvoxProducts/getTaxRates');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const activeSubTab = ref('currencies');
const formDialog = ref(null);
const deleteDialog = ref(null);
const editingItem = ref(null);
const form = ref({});

const SUB_TABS = [
  {
    key: 'currencies',
    label: 'JABVOX_PRODUCTS.CONFIG.SUBTABS.CURRENCIES',
    icon: 'i-lucide-dollar-sign',
  },
  {
    key: 'itemTypes',
    label: 'JABVOX_PRODUCTS.CONFIG.SUBTABS.ITEM_TYPES',
    icon: 'i-lucide-shapes',
  },
  {
    key: 'units',
    label: 'JABVOX_PRODUCTS.CONFIG.SUBTABS.UNITS',
    icon: 'i-lucide-ruler',
  },
  {
    key: 'taxRates',
    label: 'JABVOX_PRODUCTS.CONFIG.SUBTABS.TAX_RATES',
    icon: 'i-lucide-percent',
  },
];

const currentList = computed(() => {
  if (activeSubTab.value === 'currencies') return currencies.value;
  if (activeSubTab.value === 'itemTypes') return itemTypes.value;
  if (activeSubTab.value === 'units') return unitsOfMeasure.value;
  return taxRates.value;
});

const isSaving = computed(() => {
  const map = {
    currencies: uiFlags.value.isSavingCurrency,
    itemTypes: uiFlags.value.isSavingItemType,
    units: uiFlags.value.isSavingUnit,
    taxRates: uiFlags.value.isSavingTaxRate,
  };
  return map[activeSubTab.value];
});

onMounted(() =>
  Promise.all([
    store.dispatch('jabvoxProducts/fetchCurrency'),
    store.dispatch('jabvoxProducts/fetchItemType'),
    store.dispatch('jabvoxProducts/fetchUnit'),
    store.dispatch('jabvoxProducts/fetchTaxRate'),
  ])
);

const actionPrefix = () => {
  if (activeSubTab.value === 'currencies') return 'Currency';
  if (activeSubTab.value === 'itemTypes') return 'ItemType';
  if (activeSubTab.value === 'units') return 'Unit';
  return 'TaxRate';
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
  formDialog.value?.open();
};

const openEdit = item => {
  editingItem.value = item;
  form.value = { ...item };
  formDialog.value?.open();
};

const onSubmit = async () => {
  if (!form.value.name_jabvox?.trim()) return;
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
    formDialog.value?.close();
    useAlert(t('JABVOX_PRODUCTS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const askDelete = item => {
  deleteDialog.value?.open({
    title: t('JABVOX_PRODUCTS.CONFIG.DELETE_TITLE'),
    description: t('JABVOX_PRODUCTS.CONFIG.DELETE_BODY', {
      name: item.name_jabvox,
    }),
    data: item,
  });
};
const doDelete = async item => {
  try {
    await store.dispatch(`jabvoxProducts/destroy${actionPrefix()}`, item.id);
    useAlert(t('JABVOX_PRODUCTS.DELETE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

// Secondary detail shown per row depending on sub-tab.
const rowDetail = item => {
  if (activeSubTab.value === 'currencies') return item.symbol_jabvox;
  if (activeSubTab.value === 'units') return item.abbreviation_jabvox;
  if (activeSubTab.value === 'taxRates') return `${item.percentage_jabvox}%`;
  return '';
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <!-- Sub-tabs -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div
        class="flex items-center gap-1 p-1 rounded-xl bg-n-alpha-1 border border-n-weak overflow-x-auto"
      >
        <button
          v-for="st in SUB_TABS"
          :key="st.key"
          class="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg whitespace-nowrap transition-colors shrink-0"
          :class="
            activeSubTab === st.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeSubTab = st.key"
        >
          <span :class="st.icon" class="size-3.5" />
          {{ t(st.label) }}
        </button>
      </div>
      <Button
        :label="t('JABVOX_PRODUCTS.NEW')"
        icon="i-lucide-plus"
        size="sm"
        @click="openNew"
      />
    </div>

    <!-- Empty -->
    <div
      v-if="!currentList.length"
      class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
    >
      {{ t('JABVOX_PRODUCTS.CONFIG.EMPTY') }}
    </div>

    <!-- List -->
    <div
      v-else
      class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm divide-y divide-n-weak overflow-hidden"
    >
      <div
        v-for="item in currentList"
        :key="item.id"
        class="flex items-center gap-3 px-4 py-3 hover:bg-n-alpha-1 transition-colors"
      >
        <div class="flex-1 min-w-0 flex items-center gap-2">
          <p class="text-sm font-medium text-n-slate-12 truncate">
            {{ item.name_jabvox }}
          </p>
          <code
            v-if="rowDetail(item)"
            class="text-xs font-mono text-n-slate-10 bg-n-alpha-2 rounded px-1.5 py-0.5"
          >
            {{ rowDetail(item) }}
          </code>
        </div>
        <Label
          :label="
            item.active_jabvox
              ? t('JABVOX_PRODUCTS.ACTIVE')
              : t('JABVOX_PRODUCTS.INACTIVE')
          "
          :color="item.active_jabvox ? 'teal' : 'slate'"
          compact
        />
        <Button
          icon="i-lucide-pencil"
          variant="ghost"
          color="slate"
          size="sm"
          @click="openEdit(item)"
        />
        <Button
          icon="i-lucide-trash-2"
          variant="ghost"
          color="ruby"
          size="sm"
          @click="askDelete(item)"
        />
      </div>
    </div>

    <!-- Form dialog -->
    <Dialog
      ref="formDialog"
      :title="
        editingItem ? t('JABVOX_PRODUCTS.EDIT') : t('JABVOX_PRODUCTS.NEW')
      "
      :confirm-button-label="t('JABVOX_PRODUCTS.SAVE')"
      :cancel-button-label="t('JABVOX_PRODUCTS.CANCEL')"
      :disable-confirm-button="!form.name_jabvox?.trim()"
      :is-loading="isSaving"
      width="lg"
      @confirm="onSubmit"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-if="activeSubTab === 'currencies'"
          v-model="form.symbol_jabvox"
          :label="t('JABVOX_PRODUCTS.CONFIG.SYMBOL')"
        />
        <Input
          v-model="form.name_jabvox"
          :label="`${t('JABVOX_PRODUCTS.COLS.NAME')} *`"
          autofocus
        />
        <Input
          v-if="activeSubTab === 'units'"
          v-model="form.abbreviation_jabvox"
          :label="t('JABVOX_PRODUCTS.CONFIG.ABBREVIATION')"
        />
        <Input
          v-if="activeSubTab === 'taxRates'"
          v-model="form.percentage_jabvox"
          type="number"
          step="0.01"
          min="0"
          max="100"
          :label="t('JABVOX_PRODUCTS.CONFIG.PERCENTAGE')"
        />
        <div
          class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_PRODUCTS.ACTIVE') }}
          </span>
          <Switch v-model="form.active_jabvox" />
        </div>
      </div>
    </Dialog>

    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
