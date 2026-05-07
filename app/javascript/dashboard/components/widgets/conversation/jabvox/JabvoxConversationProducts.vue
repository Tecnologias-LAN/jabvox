<!-- eslint-disable vue/no-bare-strings-in-template -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
  conversationId: { type: [Number, String], default: null },
});

const store = useStore();
const { t } = useI18n();

const products = useMapGetter('jabvoxProducts/getProducts');
const discounts = useMapGetter('jabvoxProducts/getDiscounts');
const integrationConfig = useMapGetter('jabvoxProducts/getIntegrationConfig');
const orderStatusConfigs = useMapGetter('jabvoxProducts/getOrderStatusConfigs');
const orders = useMapGetter('jabvoxOrders/getOrders');
const uiFlags = useMapGetter('jabvoxOrders/getUIFlags');

const showForm = ref(false);
const docType = ref('QUOTE');
const sendingOrderId = ref(null);

const emptyItem = () => ({
  jabvox_product_id: null,
  name_snapshot: '',
  unit_price: 0,
  quantity: 1,
  discount_pct: 0,
  tax_pct: 0,
});

const items = ref([emptyItem()]);
const notes = ref('');

const activeProducts = computed(() =>
  products.value.filter(p => p.active_jabvox)
);

const orderTotal = computed(() =>
  items.value.reduce((sum, i) => {
    const base = i.unit_price * i.quantity;
    return (
      sum + base - (base * i.discount_pct) / 100 + (base * i.tax_pct) / 100
    );
  }, 0)
);

const formatCurrency = val =>
  Number(val).toLocaleString('es-CO', { minimumFractionDigits: 0 });

const formatQty = val => {
  const n = Number(val);
  return n % 1 === 0 ? String(Math.round(n)) : n.toString();
};

onMounted(async () => {
  const orderParams = { contact_id: props.contactId };
  if (props.conversationId) orderParams.conversation_id = props.conversationId;
  await Promise.all([
    store.dispatch('jabvoxProducts/fetchProduct'),
    store.dispatch('jabvoxProducts/fetchDiscount'),
    store.dispatch('jabvoxProducts/fetchIntegrationConfig'),
    store.dispatch('jabvoxProducts/fetchStatus'),
    store.dispatch('jabvoxOrders/fetchOrders', orderParams),
  ]);
});

const getStatusConfig = status =>
  orderStatusConfigs.value.find(s => s.key_jabvox === status);

const onStatusChange = async (order, status) => {
  try {
    await store.dispatch('jabvoxOrders/updateOrderStatus', {
      id: order.id,
      status,
    });
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const openForm = type => {
  docType.value = type;
  items.value = [emptyItem()];
  notes.value = '';
  showForm.value = true;
};

const onProductSelect = item => {
  const p = activeProducts.value.find(x => x.id === item.jabvox_product_id);
  if (!p) {
    item.name_snapshot = '';
    item.unit_price = 0;
    item.tax_pct = 0;
    return;
  }
  item.name_snapshot = p.name_jabvox;
  item.unit_price = Number(p.price_jabvox) || 0;
  item.tax_pct = Number(p.tax_percentage_jabvox) || 0;
};

const addItem = () => items.value.push(emptyItem());

const removeItem = idx => {
  if (items.value.length > 1) items.value.splice(idx, 1);
};

const onSave = async () => {
  const validItems = items.value.filter(i => i.name_snapshot.trim());
  if (!validItems.length) {
    useAlert(t('JABVOX_PRODUCTS.CONVERSATION.ITEMS_REQUIRED'));
    return;
  }
  try {
    await store.dispatch('jabvoxOrders/createOrder', {
      doc_type: docType.value,
      contact_id: props.contactId || undefined,
      conversation_id: props.conversationId || undefined,
      notes: notes.value,
      jabvox_order_items_attributes: validItems,
    });
    useAlert(t('JABVOX_PRODUCTS.CONVERSATION.ORDER_SAVED'));
    showForm.value = false;
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const onDelete = async order => {
  if (!window.confirm(t('JABVOX_PRODUCTS.CONVERSATION.ORDER_DELETE_CONFIRM')))
    return;
  try {
    await store.dispatch('jabvoxOrders/destroyOrder', order.id);
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const onSendToAlegra = async order => {
  sendingOrderId.value = order.id;
  try {
    await store.dispatch('jabvoxOrders/sendOrderToAlegra', order.id);
    useAlert(t('JABVOX_PRODUCTS.CONVERSATION.SENT_TO_ALEGRA'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  } finally {
    sendingOrderId.value = null;
  }
};

const onDownloadPdf = order => {
  const cfg = integrationConfig.value || {};
  const docLabel =
    order.doc_type === 'QUOTE'
      ? t('JABVOX_PRODUCTS.CONVERSATION.NEW_QUOTE')
      : t('JABVOX_PRODUCTS.CONVERSATION.NEW_SALE');

  const logoHtml = cfg.company_logo_jabvox
    ? `<img src="${cfg.company_logo_jabvox}" style="width:64px;height:64px;object-fit:contain;" />`
    : '';

  const rows = (order.items || [])
    .map(
      item => `
    <tr>
      <td style="padding:6px 8px;border-bottom:1px solid #e2e8f0;">${item.name_snapshot}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e2e8f0;text-align:center;">${item.quantity}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e2e8f0;text-align:right;">$${formatCurrency(item.unit_price)}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e2e8f0;text-align:center;">${item.discount_pct > 0 ? `-${item.discount_pct}%` : '-'}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e2e8f0;text-align:center;">${item.tax_pct > 0 ? `${item.tax_pct}%` : '-'}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:600;">$${formatCurrency(item.line_total)}</td>
    </tr>
  `
    )
    .join('');

  /* eslint-disable no-useless-escape */
  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <title>${docLabel} #${order.alegra_number || order.id}</title>
  <style>
    body { font-family: Arial, sans-serif; font-size: 13px; color: #1e293b; margin: 0; padding: 32px; }
    .header { display: flex; align-items: flex-start; gap: 16px; padding-bottom: 16px; border-bottom: 2px solid #e2e8f0; margin-bottom: 20px; }
    .logo { width: 64px; height: 64px; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
    .company { flex: 1; text-align: center; line-height: 1.4; }
    .company-name { font-size: 15px; font-weight: 700; margin-bottom: 2px; }
    .company small { font-size: 11px; color: #64748b; }
    .doc-info { text-align: right; flex-shrink: 0; }
    .doc-info .label { font-size: 10px; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; }
    .doc-info .number { font-size: 22px; font-weight: 700; line-height: 1; margin-top: 2px; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; }
    thead tr { background: #f8fafc; }
    th { padding: 8px; text-align: left; font-size: 11px; color: #64748b; font-weight: 600; border-bottom: 2px solid #e2e8f0; }
    th.right { text-align: right; }
    th.center { text-align: center; }
    .totals { margin-top: 12px; text-align: right; }
    .totals table { width: auto; margin-left: auto; }
    .totals td { padding: 3px 8px; font-size: 13px; }
    .totals .total-row td { font-weight: 700; font-size: 15px; border-top: 2px solid #e2e8f0; padding-top: 6px; }
    .notes { margin-top: 16px; padding: 10px; background: #f8fafc; border-radius: 6px; font-size: 12px; color: #64748b; }
    @media print { body { padding: 16px; } }
  </style>
</head>
<body>
  <div class="header">
    <div class="logo">${logoHtml}</div>
    <div class="company">
      <div class="company-name">${cfg.company_name_jabvox || ''}</div>
      ${cfg.company_nit_jabvox ? `<small>NIT: ${cfg.company_nit_jabvox}</small><br>` : ''}
      ${cfg.company_address_jabvox ? `<small>${cfg.company_address_jabvox}</small><br>` : ''}
      ${cfg.company_phone_jabvox ? `<small>${cfg.company_phone_jabvox}</small><br>` : ''}
      ${cfg.company_website_jabvox ? `<small><a href="${cfg.company_website_jabvox}" style="color:#2563eb;">${cfg.company_website_jabvox}</a></small><br>` : ''}
      ${cfg.company_email_jabvox ? `<small>${cfg.company_email_jabvox}</small>` : ''}
    </div>
    <div class="doc-info">
      <div class="label">${docLabel}</div>
      <div class="number">#${order.alegra_number || order.id}</div>
    </div>
  </div>

  <table>
    <thead>
      <tr>
        <th>Producto / Servicio</th>
        <th class="center">Cant.</th>
        <th class="right">Precio</th>
        <th class="center">Desc.</th>
        <th class="center">IVA</th>
        <th class="right">Total</th>
      </tr>
    </thead>
    <tbody>${rows}</tbody>
  </table>

  <div class="totals">
    <table>
      <tr><td style="color:#64748b;">Subtotal</td><td>$${formatCurrency(order.subtotal)}</td></tr>
      ${Number(order.discount_total) > 0 ? `<tr><td style="color:#64748b;">Descuento</td><td>-$${formatCurrency(order.discount_total)}</td></tr>` : ''}
      ${Number(order.tax_total) > 0 ? `<tr><td style="color:#64748b;">IVA</td><td>$${formatCurrency(order.tax_total)}</td></tr>` : ''}
      <tr class="total-row"><td>Total</td><td>$${formatCurrency(order.total)}</td></tr>
    </table>
  </div>

  ${order.notes ? `<div class="notes">${order.notes}</div>` : ''}

  <script>window.onload = function() { window.print(); }<\/script>
</body>
</html>`;
  /* eslint-enable no-useless-escape */

  const win = window.open('', '_blank', 'width=800,height=900');
  win.document.write(html);
  win.document.close();
};

const docLabel = type =>
  type === 'QUOTE'
    ? t('JABVOX_PRODUCTS.CONVERSATION.NEW_QUOTE')
    : t('JABVOX_PRODUCTS.CONVERSATION.NEW_SALE');
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="flex flex-col h-full overflow-y-auto">
    <!-- Header -->
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-slate-100 dark:border-slate-700 shrink-0"
    >
      <h2 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_PRODUCTS.CONVERSATION.PRODUCTS_TITLE') }}
      </h2>
      <div class="flex gap-1.5">
        <Button
          size="small"
          variant="ghost"
          icon="i-lucide-file-text"
          :label="$t('JABVOX_PRODUCTS.CONVERSATION.NEW_QUOTE')"
          @click="openForm('QUOTE')"
        />
        <Button
          size="small"
          icon="i-lucide-shopping-bag"
          :label="$t('JABVOX_PRODUCTS.CONVERSATION.NEW_SALE')"
          @click="openForm('SALE')"
        />
      </div>
    </div>

    <!-- Orders list -->
    <div class="flex-1 overflow-y-auto p-4 space-y-3">
      <div
        v-if="uiFlags.isFetching"
        class="text-sm text-slate-400 text-center py-8"
      >
        {{ $t('JABVOX_PRODUCTS.LOADING') }}
      </div>

      <div
        v-else-if="!orders.length"
        class="text-sm text-slate-400 text-center py-10"
      >
        {{ $t('JABVOX_PRODUCTS.CONVERSATION.PRODUCTS_EMPTY') }}
      </div>

      <div
        v-for="order in orders"
        :key="order.id"
        class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 overflow-hidden"
      >
        <!-- Order header -->
        <div
          class="flex items-center justify-between px-4 py-2.5 bg-slate-50 dark:bg-slate-700/40"
        >
          <div class="flex items-center gap-2">
            <span
              class="text-xs font-semibold px-2 py-0.5 rounded-full"
              :class="
                order.doc_type === 'QUOTE'
                  ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300'
                  : 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'
              "
            >
              {{ docLabel(order.doc_type) }}
            </span>
            <span
              v-if="order.alegra_number"
              class="text-xs text-slate-400 font-mono"
            >
              #{{ order.alegra_number }}
            </span>
            <!-- eslint-disable-next-line vue/max-attributes-per-line -->
            <span v-else class="text-xs text-slate-400 font-mono"
              >#{{ order.id }}</span
            >
            <div
              v-if="orderStatusConfigs.length"
              class="relative inline-flex items-center"
            >
              <span
                class="absolute left-2.5 w-2 h-2 rounded-full shrink-0 pointer-events-none"
                :style="{
                  backgroundColor:
                    getStatusConfig(order.status)?.color_jabvox || '#94a3b8',
                }"
              />
              <select
                :value="order.status"
                class="appearance-none text-xs rounded-full border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 pl-6 pr-6 py-1 focus:outline-none focus:ring-1 focus:ring-woot-500 cursor-pointer font-medium"
                @change="onStatusChange(order, $event.target.value)"
              >
                <option value="">—</option>
                <option
                  v-for="s in orderStatusConfigs"
                  :key="s.key_jabvox"
                  :value="s.key_jabvox"
                >
                  {{ s.label_jabvox }}
                </option>
              </select>
              <span
                class="pointer-events-none absolute right-2 i-lucide-chevron-down w-3 h-3 text-slate-400"
              />
            </div>
          </div>
          <div class="flex items-center gap-2">
            <span
              class="text-sm font-semibold text-slate-800 dark:text-slate-100"
            >
              ${{ formatCurrency(order.total) }}
            </span>
            <!-- PDF button -->
            <button
              class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
              :title="$t('JABVOX_PRODUCTS.CONVERSATION.DOWNLOAD_PDF')"
              @click="onDownloadPdf(order)"
            >
              <span class="i-lucide-file-down text-sm block" />
            </button>
            <!-- Send to Alegra -->
            <button
              class="transition-colors"
              :class="
                order.alegra_id
                  ? 'text-green-500 cursor-default'
                  : 'text-slate-400 hover:text-woot-600 dark:hover:text-woot-400'
              "
              :disabled="!!order.alegra_id || sendingOrderId === order.id"
              :title="
                order.alegra_id
                  ? $t('JABVOX_PRODUCTS.CONVERSATION.ALREADY_SENT')
                  : $t('JABVOX_PRODUCTS.CONVERSATION.SEND_TO_ALEGRA')
              "
              @click="!order.alegra_id && onSendToAlegra(order)"
            >
              <span
                v-if="sendingOrderId === order.id"
                class="i-lucide-loader-circle text-sm block animate-spin"
              />
              <span
                v-else-if="order.alegra_id"
                class="i-lucide-check-circle text-sm block"
              />
              <span v-else class="i-lucide-send text-sm block" />
            </button>
            <!-- Delete -->
            <button
              class="text-slate-300 hover:text-red-500 transition-colors"
              @click="onDelete(order)"
            >
              <span class="i-lucide-trash-2 text-sm block" />
            </button>
          </div>
        </div>

        <!-- Line items -->
        <div
          v-if="order.items?.length"
          class="divide-y divide-slate-100 dark:divide-slate-700"
        >
          <div
            v-for="item in order.items"
            :key="item.id"
            class="px-4 py-2 grid grid-cols-12 gap-2 text-xs text-slate-600 dark:text-slate-300"
          >
            <span
              class="col-span-5 font-medium text-slate-800 dark:text-slate-100 truncate"
              >{{ item.name_snapshot }}</span
            >
            <span class="col-span-2 text-center text-slate-400"
              >×{{ formatQty(item.quantity) }}</span
            >
            <span class="col-span-2 text-center text-slate-400"
              >${{ formatCurrency(item.unit_price) }}</span
            >
            <span
              v-if="item.discount_pct > 0"
              class="col-span-1 text-center text-amber-500"
              >-{{ item.discount_pct }}%</span
            >
            <span v-else class="col-span-1" />
            <span class="col-span-2 text-right font-semibold"
              >${{ formatCurrency(item.line_total) }}</span
            >
          </div>
        </div>

        <div
          v-if="order.notes"
          class="px-4 py-2 text-xs text-slate-400 italic border-t border-slate-100 dark:border-slate-700"
        >
          {{ order.notes }}
        </div>
      </div>
    </div>

    <!-- Create modal -->
    <div
      v-if="showForm"
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      @click.self="showForm = false"
    >
      <div
        class="bg-white dark:bg-slate-900 rounded-2xl shadow-2xl w-full max-w-xl max-h-[90vh] flex flex-col"
      >
        <!-- Modal header -->
        <div
          class="flex items-center justify-between px-6 py-4 border-b border-slate-100 dark:border-slate-700"
        >
          <h3
            class="text-base font-semibold text-slate-800 dark:text-slate-100"
          >
            {{ docLabel(docType) }}
          </h3>
          <div class="flex gap-2">
            <button
              class="text-xs px-3 py-1 rounded-full font-medium border transition-colors"
              :class="
                docType === 'QUOTE'
                  ? 'bg-blue-600 text-white border-blue-600'
                  : 'bg-white dark:bg-slate-800 text-slate-600 dark:text-slate-300 border-slate-200 dark:border-slate-700'
              "
              @click="docType = 'QUOTE'"
            >
              {{ $t('JABVOX_PRODUCTS.CONVERSATION.NEW_QUOTE') }}
            </button>
            <button
              class="text-xs px-3 py-1 rounded-full font-medium border transition-colors"
              :class="
                docType === 'SALE'
                  ? 'bg-green-600 text-white border-green-600'
                  : 'bg-white dark:bg-slate-800 text-slate-600 dark:text-slate-300 border-slate-200 dark:border-slate-700'
              "
              @click="docType = 'SALE'"
            >
              {{ $t('JABVOX_PRODUCTS.CONVERSATION.NEW_SALE') }}
            </button>
          </div>
        </div>

        <!-- Modal body -->
        <div class="overflow-y-auto flex-1 px-6 py-4 space-y-4">
          <!-- Column headers -->
          <div
            class="grid grid-cols-12 gap-2 text-xs font-medium text-slate-400 px-1"
          >
            <span class="col-span-5">{{
              $t('JABVOX_PRODUCTS.PRODUCTS.COLS.NAME')
            }}</span>
            <span class="col-span-2 text-center">{{
              $t('JABVOX_PRODUCTS.CONVERSATION.QUANTITY')
            }}</span>
            <span class="col-span-2 text-right">{{
              $t('JABVOX_PRODUCTS.CONVERSATION.UNIT_PRICE')
            }}</span>
            <span class="col-span-2">{{
              $t('JABVOX_PRODUCTS.CONVERSATION.DISCOUNT')
            }}</span>
            <span class="col-span-1 text-center">{{
              $t('JABVOX_PRODUCTS.CONVERSATION.TAX')
            }}</span>
          </div>

          <!-- Items -->
          <div
            v-for="(item, idx) in items"
            :key="idx"
            class="grid grid-cols-12 gap-2 items-center"
          >
            <!-- Product select -->
            <div class="col-span-5">
              <select
                v-model="item.jabvox_product_id"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-xs px-2 py-1.5 focus:outline-none focus:ring-1 focus:ring-woot-500"
                @change="onProductSelect(item)"
              >
                <option :value="null">—</option>
                <option v-for="p in activeProducts" :key="p.id" :value="p.id">
                  {{ p.name_jabvox }}
                </option>
              </select>
            </div>

            <!-- Qty -->
            <div class="col-span-2">
              <input
                v-model.number="item.quantity"
                type="number"
                min="0.01"
                step="0.01"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-xs px-2 py-1.5 text-center focus:outline-none focus:ring-1 focus:ring-woot-500"
              />
            </div>

            <!-- Price read-only -->
            <div
              class="col-span-2 text-right text-xs text-slate-600 dark:text-slate-300 font-medium pr-1"
            >
              ${{ formatCurrency(item.unit_price) }}
            </div>

            <!-- Discount select -->
            <div class="col-span-2">
              <select
                v-model="item.discount_pct"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-xs px-2 py-1.5 focus:outline-none focus:ring-1 focus:ring-woot-500"
              >
                <option :value="0">—</option>
                <option
                  v-for="d in discounts"
                  :key="d.id"
                  :value="Number(d.percentage_jabvox)"
                >
                  {{ d.name_jabvox }} ({{ d.percentage_jabvox }}%)
                </option>
              </select>
            </div>

            <!-- Tax read-only + remove btn -->
            <div class="col-span-1 flex items-center justify-between">
              <span class="text-xs text-slate-400">
                {{ item.tax_pct > 0 ? `${item.tax_pct}%` : '—' }}
              </span>
              <button
                :disabled="items.length === 1"
                class="text-slate-300 hover:text-red-500 disabled:opacity-30 disabled:cursor-not-allowed transition-colors ml-1"
                @click="removeItem(idx)"
              >
                <span class="i-lucide-x text-sm block" />
              </button>
            </div>
          </div>

          <!-- Add row -->
          <button
            class="flex items-center gap-1.5 text-xs text-woot-600 hover:text-woot-700 font-medium"
            @click="addItem"
          >
            <span class="i-lucide-plus text-sm" />
            {{ $t('JABVOX_PRODUCTS.CONVERSATION.ADD_ITEM') }}
          </button>

          <!-- Notes -->
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ $t('JABVOX_PRODUCTS.CONVERSATION.NOTES') }}
            </label>
            <textarea
              v-model="notes"
              rows="2"
              class="w-full resize-none rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>

          <!-- Total -->
          <div
            class="flex items-center justify-end gap-3 border-t border-slate-100 dark:border-slate-700 pt-3"
          >
            <span class="text-sm text-slate-500">Total:</span>
            <span
              class="text-base font-bold text-slate-800 dark:text-slate-100"
            >
              ${{ formatCurrency(orderTotal) }}
            </span>
          </div>
        </div>

        <!-- Modal footer -->
        <div
          class="flex gap-3 px-6 py-4 border-t border-slate-100 dark:border-slate-700"
        >
          <Button
            :label="$t('JABVOX_PRODUCTS.CREATE')"
            :is-loading="uiFlags.isSaving"
            @click="onSave"
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
