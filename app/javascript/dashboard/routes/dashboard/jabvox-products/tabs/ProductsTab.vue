<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

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
const showForm = ref(false);
const editingProduct = ref(null);

const form = ref({
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

const totalPages = computed(() => Math.ceil(products.value.length / PAGE_SIZE));
const paginatedProducts = computed(() => {
  const start = (page.value - 1) * PAGE_SIZE;
  return products.value.slice(start, start + PAGE_SIZE);
});

onMounted(async () => {
  await Promise.all([
    store.dispatch('jabvoxProducts/fetchProduct'),
    store.dispatch('jabvoxProducts/fetchCurrency'),
    store.dispatch('jabvoxProducts/fetchItemType'),
    store.dispatch('jabvoxProducts/fetchUnit'),
    store.dispatch('jabvoxProducts/fetchTaxRate'),
  ]);
});

const openNew = () => {
  editingProduct.value = null;
  form.value = {
    name_jabvox: '',
    description_jabvox: '',
    price_jabvox: '',
    base_price_jabvox: '',
    tax_percentage_jabvox: '',
    active_jabvox: true,
    jabvox_currency_id: null,
    jabvox_item_type_id: null,
    jabvox_unit_of_measure_id: null,
  };
  showForm.value = true;
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
  showForm.value = true;
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
    showForm.value = false;
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const onDelete = async product => {
  if (
    !window.confirm(
      t('JABVOX_PRODUCTS.PRODUCTS.DELETE_CONFIRM', {
        name: product.name_jabvox,
      })
    )
  )
    return;
  try {
    await store.dispatch('jabvoxProducts/destroyProduct', product.id);
    useAlert(t('JABVOX_PRODUCTS.PRODUCTS.DELETE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const onImport = async () => {
  try {
    const result = await store.dispatch('jabvoxProducts/importProducts');
    const msg = result?.message || t('JABVOX_PRODUCTS.PRODUCTS.IMPORT_SUCCESS');
    useAlert(msg);
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.PRODUCTS.IMPORT_ERROR'));
  }
};
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_PRODUCTS.PRODUCTS.TITLE') }}
      </h2>
      <div class="flex gap-2">
        <Button
          variant="ghost"
          icon="i-lucide-download"
          :label="$t('JABVOX_PRODUCTS.PRODUCTS.IMPORT_BUTTON')"
          :is-loading="uiFlags.isImportingProducts"
          @click="onImport"
        />
        <Button
          icon="i-lucide-plus"
          :label="$t('JABVOX_PRODUCTS.PRODUCTS.NEW_BUTTON')"
          @click="openNew"
        />
      </div>
    </div>

    <div
      v-if="uiFlags.isFetchingProducts"
      class="text-sm text-slate-400 animate-pulse py-6 text-center"
    >
      {{ $t('JABVOX_PRODUCTS.LOADING') }}
    </div>

    <div
      v-else-if="products.length === 0"
      class="text-sm text-slate-400 text-center py-10"
    >
      {{ $t('JABVOX_PRODUCTS.PRODUCTS.EMPTY') }}
    </div>

    <template v-else>
      <table
        class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
      >
        <thead>
          <tr class="text-left text-slate-500 dark:text-slate-400">
            <th class="py-3 pr-4 font-medium">
              {{ $t('JABVOX_PRODUCTS.PRODUCTS.COLS.NAME') }}
            </th>
            <th class="py-3 pr-4 font-medium">
              {{ $t('JABVOX_PRODUCTS.PRODUCTS.COLS.TYPE') }}
            </th>
            <th class="py-3 pr-4 font-medium">
              {{ $t('JABVOX_PRODUCTS.PRODUCTS.COLS.PRICE') }}
            </th>
            <th class="py-3 pr-4 font-medium">
              {{ $t('JABVOX_PRODUCTS.PRODUCTS.COLS.CURRENCY') }}
            </th>
            <th class="py-3 pr-4 font-medium">
              {{ $t('JABVOX_PRODUCTS.PRODUCTS.COLS.STATUS') }}
            </th>
            <th class="py-3 pr-4 font-medium">
              {{ $t('JABVOX_PRODUCTS.PRODUCTS.COLS.ACTIONS') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
          <tr
            v-for="product in paginatedProducts"
            :key="product.id"
            class="hover:bg-slate-50 dark:hover:bg-slate-800/50"
          >
            <td
              class="py-3 pr-4 font-medium text-slate-800 dark:text-slate-100"
            >
              {{ product.name_jabvox }}
            </td>
            <td class="py-3 pr-4 text-slate-500">
              <span class="capitalize">{{ product.product_type_jabvox }}</span>
            </td>
            <td class="py-3 pr-4 text-slate-700 dark:text-slate-200">
              {{ product.price_jabvox }}
            </td>
            <td class="py-3 pr-4 text-slate-500">
              {{ product.currency?.symbol_jabvox || '—' }}
            </td>
            <td class="py-3 pr-4">
              <span
                class="text-xs px-2 py-1 rounded-full font-medium"
                :class="[
                  product.active_jabvox
                    ? 'bg-green-100 text-green-700'
                    : 'bg-slate-100 text-slate-500',
                ]"
              >
                {{
                  product.active_jabvox
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
                  @click="openEdit(product)"
                />
                <Button
                  size="small"
                  variant="ghost"
                  color-scheme="alert"
                  icon="i-lucide-trash-2"
                  @click="onDelete(product)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <div
        v-if="totalPages > 1"
        class="flex items-center justify-between text-sm text-slate-500 pt-2"
      >
        <span>{{
          $t('JABVOX_PRODUCTS.PAGE_INFO', { page, total: totalPages })
        }}</span>
        <div class="flex gap-2">
          <Button
            size="small"
            variant="ghost"
            icon="i-lucide-chevron-left"
            :disabled="page === 1"
            @click="page--"
          />
          <Button
            size="small"
            variant="ghost"
            icon="i-lucide-chevron-right"
            :disabled="page === totalPages"
            @click="page++"
          />
        </div>
      </div>
    </template>

    <div
      v-if="showForm"
      class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
      @click.self="showForm = false"
    >
      <div
        class="bg-white dark:bg-slate-900 rounded-xl shadow-xl p-6 w-full max-w-lg space-y-4"
      >
        <h3 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          {{
            editingProduct
              ? $t('JABVOX_PRODUCTS.PRODUCTS.FORM.EDIT')
              : $t('JABVOX_PRODUCTS.PRODUCTS.FORM.NEW')
          }}
        </h3>

        <div class="grid grid-cols-2 gap-4">
          <div class="col-span-2">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.PRODUCTS.FORM.NAME') }} *</label
            >
            <input
              v-model="form.name_jabvox"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>

          <div class="col-span-2">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.PRODUCTS.FORM.DESCRIPTION') }}</label
            >
            <textarea
              v-model="form.description_jabvox"
              rows="2"
              class="w-full resize-none rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.PRODUCTS.FORM.PRICE') }}</label
            >
            <input
              v-model="form.price_jabvox"
              type="number"
              step="0.01"
              min="0"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.PRODUCTS.FORM.TAX') }}</label
            >
            <select
              v-model="form.tax_percentage_jabvox"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option value="">—</option>
              <option
                v-for="rate in taxRates"
                :key="rate.id"
                :value="rate.percentage_jabvox"
              >
                {{ rate.name_jabvox }} ({{ rate.percentage_jabvox }}%)
              </option>
            </select>
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.PRODUCTS.FORM.TYPE') }}</label
            >
            <select
              v-model="form.jabvox_item_type_id"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option :value="null">—</option>
              <option v-for="it in itemTypes" :key="it.id" :value="it.id">
                {{ it.name_jabvox }}
              </option>
            </select>
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.PRODUCTS.FORM.CURRENCY') }}</label
            >
            <select
              v-model="form.jabvox_currency_id"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option :value="null">—</option>
              <option v-for="c in currencies" :key="c.id" :value="c.id">
                {{ c.symbol_jabvox }} – {{ c.name_jabvox }}
              </option>
            </select>
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.PRODUCTS.FORM.UNIT') }}</label
            >
            <select
              v-model="form.jabvox_unit_of_measure_id"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option :value="null">—</option>
              <option v-for="u in unitsOfMeasure" :key="u.id" :value="u.id">
                {{ u.name_jabvox }}
                {{ u.abbreviation_jabvox ? `(${u.abbreviation_jabvox})` : '' }}
              </option>
            </select>
          </div>

          <div class="col-span-2 flex items-center gap-2">
            <input
              id="product-active"
              v-model="form.active_jabvox"
              type="checkbox"
              class="rounded text-woot-500"
            />
            <label
              for="product-active"
              class="text-sm text-slate-700 dark:text-slate-300"
              >{{ $t('JABVOX_PRODUCTS.ACTIVE') }}</label
            >
          </div>
        </div>

        <div class="flex gap-3 pt-2">
          <Button
            :label="
              editingProduct
                ? $t('JABVOX_PRODUCTS.SAVE')
                : $t('JABVOX_PRODUCTS.CREATE')
            "
            :is-loading="uiFlags.isSavingProduct"
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
