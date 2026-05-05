<script setup>
/* global axios */
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
  conversationId: { type: [Number, String], default: null },
});

const store = useStore();
const getByContactId = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);
const orders = useMapGetter('jabvoxOrders/getOrders');
const accountId = useMapGetter('getCurrentAccountId');

const conversations = computed(() => {
  if (typeof getByContactId.value !== 'function') return [];
  return getByContactId.value(props.contactId) || [];
});

// All messages keyed by convId: { [convId]: Message[] }
const allMessages = ref({});
const isLoadingMessages = ref(false);
const expandedDays = ref(new Set());

// Normalize Chatwoot's seconds-based timestamps and ISO strings to Date
const toDate = val => {
  if (!val) return new Date(0);
  const num = Number(val);
  if (!isNaN(num) && num > 0) return new Date(num < 1e11 ? num * 1000 : num);
  return new Date(val);
};

const isoDateKey = val => {
  const d = toDate(val);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
};

const formatDayLabel = val =>
  toDate(val).toLocaleDateString('es-CO', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });

const formatTime = val => {
  if (!val) return '—';
  return toDate(val).toLocaleTimeString('es-CO', {
    hour: '2-digit',
    minute: '2-digit',
  });
};

const formatCurrency = val =>
  Number(val).toLocaleString('es-CO', { minimumFractionDigits: 0 });

const formatQty = val => {
  const n = Number(val);
  return n % 1 === 0 ? String(Math.round(n)) : n.toString();
};

const senderName = msg => msg?.meta?.sender?.name || msg?.sender?.name || '';

const messageContent = msg => {
  if (msg.content) return msg.content;
  if (msg.attachments?.length) return `[${msg.attachments.length} archivo(s)]`;
  return '';
};

const managementState = msg => {
  if (!msg.private) return null;
  const name = msg.content_attributes?.jabvox_management_state_name;
  const color = msg.content_attributes?.jabvox_management_state_color;
  if (!name) return null;
  return { name, color: color || '#6366f1' };
};

const docLabel = type => (type === 'QUOTE' ? 'Cotización' : 'Venta');
const orderRef = order =>
  order.alegra_number ? `#${order.alegra_number}` : `#${order.id}`;

// Load messages for all conversations in parallel
const loadAllMessages = async convs => {
  if (!convs.length) return;
  isLoadingMessages.value = true;
  await Promise.allSettled(
    convs.map(async conv => {
      if (allMessages.value[conv.id]) return; // already loaded
      try {
        const { data } = await axios.get(
          `/api/v1/accounts/${accountId.value}/conversations/${conv.id}/messages`
        );
        const msgs = (data.payload || [])
          .filter(m => m.message_type === 0 || m.message_type === 1)
          .map(m => ({ ...m, _conv_id: conv.id }));
        allMessages.value[conv.id] = msgs;
      } catch {
        allMessages.value[conv.id] = [];
      }
    })
  );
  isLoadingMessages.value = false;
};

// When conversations arrive from the store, load their messages
watch(
  conversations,
  convs => {
    if (convs.length) loadAllMessages(convs);
  },
  { immediate: true }
);

onMounted(() => {
  if (props.contactId) {
    store.dispatch('contactConversations/get', props.contactId);
    const params = { contact_id: props.contactId };
    if (props.conversationId) params.conversation_id = props.conversationId;
    store.dispatch('jabvoxOrders/fetchOrders', params);
  }
});

// Build day groups from messages (by message date) + orders (by order date)
const dayGroups = computed(() => {
  const groups = {};

  // Group each message under its sent date
  Object.values(allMessages.value).forEach(msgs => {
    msgs.forEach(msg => {
      if (!msg.created_at) return;
      const key = isoDateKey(msg.created_at);
      if (!groups[key])
        groups[key] = {
          key,
          date: msg.created_at,
          chat: [],
          notes: [],
          orders: [],
        };
      if (msg.private) {
        groups[key].notes.push(msg);
      } else {
        groups[key].chat.push(msg);
      }
    });
  });

  // Group orders under their created date
  orders.value.forEach(order => {
    const key = isoDateKey(order.created_at);
    if (!groups[key])
      groups[key] = {
        key,
        date: order.created_at,
        chat: [],
        notes: [],
        orders: [],
      };
    groups[key].orders.push(order);
  });

  // Sort everything inside each group chronologically
  return Object.values(groups)
    .sort((a, b) => b.key.localeCompare(a.key))
    .map(g => ({
      ...g,
      chat: g.chat
        .slice()
        .sort((a, b) => new Date(a.created_at) - new Date(b.created_at)),
      notes: g.notes
        .slice()
        .sort((a, b) => new Date(a.created_at) - new Date(b.created_at)),
      orders: g.orders
        .slice()
        .sort((a, b) => new Date(b.created_at) - new Date(a.created_at)),
    }));
});

// Auto-expand the most recent day
watch(
  dayGroups,
  groups => {
    if (groups.length && expandedDays.value.size === 0) {
      expandedDays.value = new Set([groups[0].key]);
    }
  },
  { immediate: true }
);

const toggleDay = key => {
  const next = new Set(expandedDays.value);
  if (next.has(key)) next.delete(key);
  else next.add(key);
  expandedDays.value = next;
};
const isDayExpanded = key => expandedDays.value.has(key);
</script>

<template>
  <div class="flex flex-col h-full overflow-y-auto">
    <div class="flex-1 overflow-y-auto p-4 space-y-2">
      <!-- Loading state -->
      <div
        v-if="isLoadingMessages && !dayGroups.length"
        class="text-sm text-slate-400 text-center py-10 animate-pulse"
      >
        {{ $t('JABVOX_PRODUCTS.LOADING') }}
      </div>

      <div
        v-else-if="!dayGroups.length"
        class="text-sm text-slate-400 text-center py-10"
      >
        {{ $t('JABVOX_PRODUCTS.CONVERSATION.HISTORY_EMPTY') }}
      </div>

      <!-- Day groups -->
      <div
        v-for="group in dayGroups"
        :key="group.key"
        class="rounded-xl border border-slate-200 dark:border-slate-700 overflow-hidden"
      >
        <!-- Day header -->
        <button
          class="w-full flex items-center justify-between px-4 py-2.5 bg-slate-50 dark:bg-slate-800 hover:bg-slate-100 dark:hover:bg-slate-700/60 transition-colors text-left"
          @click="toggleDay(group.key)"
        >
          <span
            class="text-xs font-semibold text-slate-700 dark:text-slate-200 capitalize"
          >
            {{ formatDayLabel(group.date) }}
          </span>
          <div class="flex items-center gap-1.5 text-slate-400 text-xs">
            <span v-if="group.orders.length">{{ group.orders.length }} pedido(s)</span>
            <span
              v-if="
                group.orders.length && (group.chat.length || group.notes.length)
              "
              >·</span>
            <span v-if="group.chat.length">{{ group.chat.length }} mensaje(s)</span>
            <span v-if="group.chat.length && group.notes.length">·</span>
            <span v-if="group.notes.length">{{ group.notes.length }} nota(s)</span>
            <i
              class="ml-1"
              :class="
                isDayExpanded(group.key)
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
            />
          </div>
        </button>

        <div v-if="isDayExpanded(group.key)" class="bg-white dark:bg-slate-800">
          <!-- ── Pedidos ── -->
          <div
            v-if="group.orders.length"
            class="border-t border-slate-100 dark:border-slate-700"
          >
            <div class="px-4 pt-3 pb-1 flex items-center gap-1.5">
              <i class="i-lucide-shopping-cart text-xs text-slate-400" />
              <span
                class="text-xs font-semibold text-slate-400 uppercase tracking-wide"
                >Pedidos</span>
            </div>
            <div class="px-3 pb-3 space-y-2">
              <div
                v-for="order in group.orders"
                :key="order.id"
                class="rounded-lg border border-slate-100 dark:border-slate-700 overflow-hidden"
              >
                <div
                  class="flex items-center justify-between px-3 py-2 bg-slate-50 dark:bg-slate-700/30"
                >
                  <div class="flex items-center gap-2">
                    <span
                      class="text-xs font-semibold px-1.5 py-0.5 rounded-full"
                      :class="
                        order.doc_type === 'QUOTE'
                          ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300'
                          : 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300'
                      "
                    >
                      {{ docLabel(order.doc_type) }}
                    </span>
                    <span class="text-xs font-mono text-slate-500">{{
                      orderRef(order)
                    }}</span>
                    <span class="text-xs text-slate-400">{{
                      formatTime(order.created_at)
                    }}</span>
                  </div>
                  <span
                    class="text-sm font-bold text-slate-800 dark:text-slate-100"
                  >
                    ${{ formatCurrency(order.total) }}
                  </span>
                </div>
                <div v-if="order.items?.length" class="px-3 py-2">
                  <table class="w-full text-xs">
                    <thead>
                      <tr
                        class="text-slate-400 border-b border-slate-100 dark:border-slate-700"
                      >
                        <th class="text-left pb-1 font-medium">Producto</th>
                        <th class="text-center pb-1 font-medium w-8">Cant.</th>
                        <th class="text-right pb-1 font-medium w-16">Precio</th>
                        <th class="text-center pb-1 font-medium w-10">Desc.</th>
                        <th class="text-center pb-1 font-medium w-10">IVA</th>
                        <th class="text-right pb-1 font-medium w-16">Total</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="item in order.items"
                        :key="item.id"
                        class="text-slate-600 dark:text-slate-300"
                      >
                        <td class="py-0.5 truncate max-w-[100px]">
                          {{ item.name_snapshot }}
                        </td>
                        <td class="py-0.5 text-center text-slate-400">
                          {{ formatQty(item.quantity) }}
                        </td>
                        <td class="py-0.5 text-right text-slate-400">
                          ${{ formatCurrency(item.unit_price) }}
                        </td>
                        <td class="py-0.5 text-center">
                          <span
                            v-if="Number(item.discount_pct) > 0"
                            class="text-amber-500"
                            >{{ item.discount_pct }}%</span>
                          <span v-else class="text-slate-300">—</span>
                        </td>
                        <td class="py-0.5 text-center">
                          <span
                            v-if="Number(item.tax_pct) > 0"
                            class="text-blue-500"
                            >{{ item.tax_pct }}%</span>
                          <span v-else class="text-slate-300">—</span>
                        </td>
                        <td class="py-0.5 text-right font-semibold">
                          ${{ formatCurrency(item.line_total) }}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <p
                  v-if="order.notes"
                  class="px-3 pb-2 text-xs text-slate-400 italic"
                >
                  {{ order.notes }}
                </p>
              </div>
            </div>
          </div>

          <!-- ── Chat ── -->
          <div
            v-if="group.chat.length"
            class="border-t border-slate-100 dark:border-slate-700"
          >
            <div class="px-4 pt-3 pb-1 flex items-center gap-1.5">
              <i class="i-lucide-message-circle text-xs text-slate-400" />
              <span
                class="text-xs font-semibold text-slate-400 uppercase tracking-wide"
                >Chat</span>
            </div>
            <div class="px-4 pb-3 space-y-2">
              <div v-for="msg in group.chat" :key="msg.id" class="text-xs">
                <div class="flex items-center gap-1 text-slate-400 mb-0.5">
                  <span class="font-medium text-slate-600 dark:text-slate-300">
                    {{
                      senderName(msg) ||
                      (msg.message_type === 1 ? 'Agente' : 'Contacto')
                    }}
                  </span>
                  <span>·</span>
                  <span>{{ formatTime(msg.created_at) }}</span>
                </div>
                <p
                  class="text-slate-700 dark:text-slate-200 whitespace-pre-wrap break-words"
                >
                  {{ messageContent(msg) }}
                </p>
              </div>
            </div>
          </div>

          <!-- ── Notas ── -->
          <div
            v-if="group.notes.length"
            class="border-t border-slate-100 dark:border-slate-700"
          >
            <div class="px-4 pt-3 pb-1 flex items-center gap-1.5">
              <i class="i-lucide-pencil-line text-xs text-amber-500" />
              <span
                class="text-xs font-semibold text-amber-500 uppercase tracking-wide"
                >Notas</span>
            </div>
            <div class="px-4 pb-3 space-y-2">
              <div v-for="msg in group.notes" :key="msg.id" class="text-xs">
                <div class="flex items-center gap-1 text-slate-400 mb-0.5">
                  <span class="font-medium text-slate-600 dark:text-slate-300">
                    {{ senderName(msg) || 'Agente' }}
                  </span>
                  <span>·</span>
                  <span>{{ formatTime(msg.created_at) }}</span>
                </div>
                <span
                  v-if="managementState(msg)"
                  class="inline-flex items-center gap-1 font-semibold px-2 py-0.5 rounded-full mb-0.5"
                  :style="{
                    backgroundColor: managementState(msg).color + '22',
                    color: managementState(msg).color,
                    border: '1px solid ' + managementState(msg).color + '55',
                  }"
                >
                  <span
                    class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                    :style="{ backgroundColor: managementState(msg).color }"
                  />
                  {{ managementState(msg).name }}
                </span>
                <p
                  class="text-amber-800 dark:text-amber-300 italic whitespace-pre-wrap break-words"
                >
                  {{ messageContent(msg) }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
