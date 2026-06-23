<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import KpiCard from '../components/KpiCard.vue';
import SearchInput from '../components/SearchInput.vue';
import ConfirmDialog from '../components/ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();

const products = useMapGetter('jabvoxProducts/getProducts');
const currencies = useMapGetter('jabvoxProducts/getCurrencies');
const itemTypes = useMapGetter('jabvoxProducts/getItemTypes');
const unitsOfMeasure = useMapGetter('jabvoxProducts/getUnitsOfMeasure');
const taxRates = useMapGetter('jabvoxProducts/getTaxRates');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const PAGE_SIZE = 10;
const page = ref(1);
const search = ref('');
const formDialog = ref(null);
const deleteDialog = ref(null);
const editingProduct = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  description_jabvox: '',
  price_jabvox: '',
  base_price_jabvox: '',
  tax_percentage_jabvox: '',
  active_jabvox: true,
  jabvox_currency_id: null,
  jabvox_item_type_id: null,
  jabvox_unit_of_measure_id: null,
});
const form = ref(emptyForm());

// ── options for selects ──
const taxOptions = computed(() => [
  { value: '', label: '—' },
  ...taxRates.value.map(r => ({
    value: r.percentage_jabvox,
    label: `${r.name_jabvox} (${r.percentage_jabvox}%)`,
  })),
]);
const typeOptions = computed(() => [
  { value: null, label: '—' },
  ...itemTypes.value.map(it => ({ value: it.id, label: it.name_jabvox })),
]);
const currencyOptions = computed(() => [
  { value: null, label: '—' },
  ...currencies.value.map(c => ({
    value: c.id,
    label: `${c.symbol_jabvox} – ${c.name_jabvox}`,
  })),
]);
const unitOptions = computed(() => [
  { value: null, label: '—' },
  ...unitsOfMeasure.value.map(u => ({
    value: u.id,
    label: u.abbreviation_jabvox
      ? `${u.name_jabvox} (${u.abbreviation_jabvox})`
      : u.name_jabvox,
  })),
]);

// ── KPIs ──
const total = computed(() => products.value.length);
const activeCount = computed(
  () => products.value.filter(p => p.active_jabvox).length
);
const inactiveCount = computed(() => total.value - activeCount.value);

// ── filter + paginate ──
const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return products.value;
  return products.value.filter(p => p.name_jabvox?.toLowerCase().includes(q));
});
const totalPages = computed(() =>
  Math.max(1, Math.ceil(filtered.value.length / PAGE_SIZE))
);
const paginated = computed(() => {
  const start = (page.value - 1) * PAGE_SIZE;
  return filtered.value.slice(start, start + PAGE_SIZE);
});
const onSearch = () => {
  page.value = 1;
};

const currencySymbol = p =>
  p.currency?.symbol_jabvox ||
  currencies.value.find(c => c.id === p.jabvox_currency_id)?.symbol_jabvox ||
  '';

onMounted(() => {
  store.dispatch('jabvoxProducts/fetchProduct');
  store.dispatch('jabvoxProducts/fetchCurrency');
  store.dispatch('jabvoxProducts/fetchItemType');
  store.dispatch('jabvoxProducts/fetchUnit');
  store.dispatch('jabvoxProducts/fetchTaxRate');
});

const openNew = () => {
  editingProduct.value = null;
  form.value = emptyForm();
  formDialog.value?.open();
};

const openEdit = product => {
  editingProduct.value = product;
  form.value = {
    name_jabvox: product.name_jabvox,
    description_jabvox: product.description_jabvox || '',
    price_jabvox: product.price_jabvox,
    base_price_jabvox: product.base_price_jabvox || '',
    tax_percentage_jabvox: product.tax_percentage_jabvox || '',
    active_jabvox: product.active_jabvox,
    jabvox_currency_id: product.jabvox_currency_id,
    jabvox_item_type_id: product.jabvox_item_type_id,
    jabvox_unit_of_measure_id: product.jabvox_unit_of_measure_id,
  };
  formDialog.value?.open();
};

const onSubmit = async () => {
  if (!form.value.name_jabvox.trim()) {
    useAlert(t('JABVOX_PRODUCTS.PRODUCTS.FORM.NAME_REQUIRED'));
    return;
  }
  try {
    if (editingProduct.value) {
      await store.dispatch('jabvoxProducts/updateProduct', {
        id: editingProduct.value.id,
        ...form.value,
      });
      useAlert(t('JABVOX_PRODUCTS.PRODUCTS.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('jabvoxProducts/createProduct', form.value);
      useAlert(t('JABVOX_PRODUCTS.PRODUCTS.CREATE_SUCCESS'));
    }
    formDialog.value?.close();
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const askDelete = product => {
  deleteDialog.value?.open({
    title: t('JABVOX_PRODUCTS.PRODUCTS.DELETE_TITLE'),
    description: t('JABVOX_PRODUCTS.PRODUCTS.DELETE_BODY', {
      name: product.name_jabvox,
    }),
    data: product.id,
  });
};
const doDelete = async id => {
  try {
    await store.dispatch('jabvoxProducts/destroyProduct', id);
    useAlert(t('JABVOX_PRODUCTS.PRODUCTS.DELETE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const onImport = async () => {
  try {
    const result = await store.dispatch('jabvoxProducts/importProducts');
    useAlert(result?.message || t('JABVOX_PRODUCTS.PRODUCTS.IMPORT_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.PRODUCTS.IMPORT_ERROR'));
  }
};

const goPrev = () => {
  if (page.value > 1) page.value -= 1;
};
const goNext = () => {
  if (page.value < totalPages.value) page.value += 1;
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- KPIs -->
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
      <KpiCard
        :label="t('JABVOX_PRODUCTS.PRODUCTS.KPI_TOTAL')"
        :value="total"
        icon="i-lucide-package"
        tone="iris"
      />
      <KpiCard
        :label="t('JABVOX_PRODUCTS.PRODUCTS.KPI_ACTIVE')"
        :value="activeCount"
        icon="i-lucide-circle-check"
        tone="teal"
      />
      <KpiCard
        :label="t('JABVOX_PRODUCTS.PRODUCTS.KPI_INACTIVE')"
        :value="inactiveCount"
        icon="i-lucide-circle-pause"
        tone="amber"
      />
    </div>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetchingProducts"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <!-- Empty -->
    <EmptyStateLayout
      v-else-if="!products.length"
      :title="t('JABVOX_PRODUCTS.PRODUCTS.EMPTY_TITLE')"
      :subtitle="t('JABVOX_PRODUCTS.PRODUCTS.EMPTY')"
    >
      <template #actions>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_PRODUCTS.NEW')"
          size="sm"
          @click="openNew"
        />
      </template>
    </EmptyStateLayout>

    <template v-else>
      <!-- Toolbar -->
      <div class="flex flex-wrap items-center justify-between gap-3">
        <SearchInput
          v-model="search"
          :placeholder="t('JABVOX_PRODUCTS.PRODUCTS.SEARCH_PLACEHOLDER')"
          @update:model-value="onSearch"
        />
        <div class="flex items-center gap-2">
          <Button
            :label="t('JABVOX_PRODUCTS.PRODUCTS.IMPORT')"
            icon="i-lucide-download"
            variant="outline"
            color="slate"
            size="sm"
            :is-loading="uiFlags.isImportingProducts"
            @click="onImport"
          />
          <Button
            :label="t('JABVOX_PRODUCTS.NEW')"
            icon="i-lucide-plus"
            size="sm"
            @click="openNew"
          />
        </div>
      </div>

      <!-- No results -->
      <div
        v-if="!filtered.length"
        class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_PRODUCTS.PRODUCTS.NO_RESULTS') }}
      </div>

      <template v-else>
        <!-- Table (desktop) -->
        <div
          class="hidden sm:block rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden overflow-x-auto"
        >
          <table class="min-w-full text-sm">
            <thead
              class="bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
            >
              <tr>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.COLS.NAME') }}
                </th>
                <th class="text-right px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.PRODUCTS.FORM.PRICE') }}
                </th>
                <th class="text-center px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.ACTIVE') }}
                </th>
                <th class="px-4 py-2.5" />
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="product in paginated"
                :key="product.id"
                class="hover:bg-n-alpha-1 transition-colors"
              >
                <td class="px-4 py-3 font-medium text-n-slate-12">
                  {{ product.name_jabvox }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums text-n-slate-12">
                  {{ currencySymbol(product) }}{{ product.price_jabvox }}
                </td>
                <td class="px-4 py-3 text-center">
                  <Label
                    :label="
                      product.active_jabvox
                        ? t('JABVOX_PRODUCTS.ACTIVE')
                        : t('JABVOX_PRODUCTS.INACTIVE')
                    "
                    :color="product.active_jabvox ? 'teal' : 'slate'"
                    compact
                  />
                </td>
                <td class="px-4 py-3">
                  <div class="flex items-center justify-end gap-1">
                    <Button
                      icon="i-lucide-pencil"
                      variant="ghost"
                      color="slate"
                      size="sm"
                      @click="openEdit(product)"
                    />
                    <Button
                      icon="i-lucide-trash-2"
                      variant="ghost"
                      color="ruby"
                      size="sm"
                      @click="askDelete(product)"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Cards (mobile) -->
        <div class="sm:hidden flex flex-col gap-3">
          <div
            v-for="product in paginated"
            :key="product.id"
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm flex flex-col gap-2"
          >
            <div class="flex items-start justify-between gap-2">
              <p class="text-sm font-medium text-n-slate-12">
                {{ product.name_jabvox }}
              </p>
              <Label
                :label="
                  product.active_jabvox
                    ? t('JABVOX_PRODUCTS.ACTIVE')
                    : t('JABVOX_PRODUCTS.INACTIVE')
                "
                :color="product.active_jabvox ? 'teal' : 'slate'"
                compact
              />
            </div>
            <p class="text-sm font-semibold text-n-slate-12 tabular-nums">
              {{ currencySymbol(product) }}{{ product.price_jabvox }}
            </p>
            <div
              class="flex items-center justify-end gap-1 pt-1 border-t border-n-weak"
            >
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                @click="openEdit(product)"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="askDelete(product)"
              />
            </div>
          </div>
        </div>

        <!-- Pagination -->
        <div
          v-if="totalPages > 1"
          class="flex items-center justify-between gap-3"
        >
          <span class="text-xs text-n-slate-11 tabular-nums">
            {{ t('JABVOX_PRODUCTS.PAGE_INFO', { page, total: totalPages }) }}
          </span>
          <div class="flex items-center gap-2">
            <Button
              icon="i-lucide-chevron-left"
              variant="outline"
              color="slate"
              size="sm"
              :disabled="page <= 1"
              @click="goPrev"
            />
            <Button
              icon="i-lucide-chevron-right"
              variant="outline"
              color="slate"
              size="sm"
              :disabled="page >= totalPages"
              @click="goNext"
            />
          </div>
        </div>
      </template>
    </template>

    <!-- Form dialog -->
    <Dialog
      ref="formDialog"
      :title="
        editingProduct
          ? t('JABVOX_PRODUCTS.PRODUCTS.FORM.EDIT')
          : t('JABVOX_PRODUCTS.PRODUCTS.FORM.NEW')
      "
      :confirm-button-label="
        editingProduct ? t('JABVOX_PRODUCTS.SAVE') : t('JABVOX_PRODUCTS.CREATE')
      "
      :cancel-button-label="t('JABVOX_PRODUCTS.CANCEL')"
      :disable-confirm-button="!form.name_jabvox.trim()"
      :is-loading="uiFlags.isSavingProduct"
      width="2xl"
      overflow-y-auto
      @confirm="onSubmit"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.name_jabvox"
          :label="`${t('JABVOX_PRODUCTS.PRODUCTS.FORM.NAME')} *`"
          autofocus
        />
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_PRODUCTS.PRODUCTS.FORM.DESCRIPTION') }}
          </label>
          <textarea
            v-model="form.description_jabvox"
            rows="2"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y"
          />
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="form.price_jabvox"
            type="number"
            step="0.01"
            min="0"
            :label="t('JABVOX_PRODUCTS.PRODUCTS.FORM.PRICE')"
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_PRODUCTS.PRODUCTS.FORM.TAX') }}
            </label>
            <Select
              v-model="form.tax_percentage_jabvox"
              :options="taxOptions"
            />
          </div>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_PRODUCTS.PRODUCTS.FORM.TYPE') }}
            </label>
            <Select v-model="form.jabvox_item_type_id" :options="typeOptions" />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_PRODUCTS.PRODUCTS.FORM.CURRENCY') }}
            </label>
            <Select
              v-model="form.jabvox_currency_id"
              :options="currencyOptions"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_PRODUCTS.PRODUCTS.FORM.UNIT') }}
            </label>
            <Select
              v-model="form.jabvox_unit_of_measure_id"
              :options="unitOptions"
            />
          </div>
        </div>
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
