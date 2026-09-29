<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import JabvoxConversationProducts from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationProducts.vue';
import JabvoxConversationHistory from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationHistory.vue';
import JabvoxLeadTableRows from 'dashboard/components/widgets/conversation/jabvox/JabvoxLeadTableRows.vue';

// Panel derecho de la ficha del contacto, en dos grupos:
//   · Contacto  → atributos, notas, media, combinar (lo que ya tenía la ficha)
//   · Actividad → gestiones, productos, registros, historial (lo que traía el detalle de lead)
//
// Se agrupa así porque son dos preguntas distintas: "quién es este contacto" y "qué ha
// pasado con él". Ocho pestañas en una sola fila quedarían ilegibles.
//
// Cada grupo se puede plegar: en pantallas cortas un grupo abierto se queda con todo el
// alto en vez de repartirlo y dejar dos mitades sin espacio útil.
const props = defineProps({
  contactId: { type: [Number, String], required: true },
  managements: { type: Array, default: () => [] },
  orders: { type: Array, default: () => [] },
  records: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['addManagement']);

const { t } = useI18n();

const CONTACT_TABS = ['attributes', 'notes', 'media', 'merge'];
const ACTIVITY_TABS = ['managements', 'orders', 'records', 'history'];

const contactTab = ref('attributes');
const activityTab = ref('managements');
// Ambos grupos abiertos por defecto; plegar uno da todo el alto al otro.
const openGroups = ref({ contact: true, activity: true });

const toggleGroup = key => {
  // Nunca dejar los dos cerrados: el panel quedaría vacío sin razón.
  const other = key === 'contact' ? 'activity' : 'contact';
  if (openGroups.value[key] && !openGroups.value[other]) return;
  openGroups.value[key] = !openGroups.value[key];
};

// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tabLabel = key => t(`JABVOX_CONTACTS.DETAIL.TABS.${key.toUpperCase()}`);

const activityCounts = computed(() => ({
  managements: props.managements.length,
  orders: props.orders.length,
  // Los registros llegan agrupados por tabla: lo que cuenta es el total de filas.
  records: props.records.reduce(
    (total, table) => total + (table.rows?.length || 0),
    0
  ),
  history: 0,
}));

const formatDate = value => {
  if (!value) return '';
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleString();
};
</script>

<template>
  <div class="flex flex-col h-full min-h-0">
    <!-- Grupo 1: datos del contacto -->
    <section
      class="flex flex-col min-h-0 border-b border-n-weak"
      :class="openGroups.contact ? 'flex-1' : 'flex-shrink-0'"
    >
      <header class="px-3 pt-2.5 pb-2 flex-shrink-0">
        <button
          class="reset-base flex items-center gap-1.5 w-full mb-2 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10 hover:text-n-slate-12 transition-colors"
          @click="toggleGroup('contact')"
        >
          <span
            class="size-3 transition-transform"
            :class="
              openGroups.contact
                ? 'i-lucide-chevron-down'
                : 'i-lucide-chevron-right'
            "
          />
          {{ t('JABVOX_CONTACTS.DETAIL.GROUPS.CONTACT') }}
        </button>
        <div
          v-if="openGroups.contact"
          class="flex flex-wrap items-center gap-1"
        >
          <button
            v-for="tab in CONTACT_TABS"
            :key="tab"
            class="reset-base text-xs rounded-lg px-2.5 py-1 whitespace-nowrap transition-colors"
            :class="
              contactTab === tab
                ? 'bg-n-brand text-white'
                : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="contactTab = tab"
          >
            {{ tabLabel(tab) }}
          </button>
        </div>
      </header>
      <div
        v-if="openGroups.contact"
        class="flex-1 overflow-y-auto overflow-x-hidden min-h-0 px-3 pb-3"
      >
        <!-- El contenido de cada pestaña lo pone la ficha, que es quien tiene los
             componentes de Chatwoot (atributos, notas, media, combinar). -->
        <slot :name="contactTab" />
      </div>
    </section>

    <!-- Grupo 2: actividad -->
    <section
      class="flex flex-col min-h-0"
      :class="openGroups.activity ? 'flex-1' : 'flex-shrink-0'"
    >
      <header class="px-3 pt-2.5 pb-2 flex-shrink-0">
        <button
          class="reset-base flex items-center gap-1.5 w-full mb-2 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10 hover:text-n-slate-12 transition-colors"
          @click="toggleGroup('activity')"
        >
          <span
            class="size-3 transition-transform"
            :class="
              openGroups.activity
                ? 'i-lucide-chevron-down'
                : 'i-lucide-chevron-right'
            "
          />
          {{ t('JABVOX_CONTACTS.DETAIL.GROUPS.ACTIVITY') }}
        </button>
        <div
          v-if="openGroups.activity"
          class="flex flex-wrap items-center gap-1"
        >
          <button
            v-for="tab in ACTIVITY_TABS"
            :key="tab"
            class="reset-base flex items-center gap-1 text-xs rounded-lg px-2.5 py-1 whitespace-nowrap transition-colors"
            :class="
              activityTab === tab
                ? 'bg-n-brand text-white'
                : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="activityTab = tab"
          >
            {{ tabLabel(tab) }}
            <span
              v-if="activityCounts[tab]"
              class="text-[10px] tabular-nums opacity-70"
            >
              {{ activityCounts[tab] }}
            </span>
          </button>
        </div>
      </header>

      <div
        v-if="openGroups.activity"
        class="flex-1 overflow-y-auto overflow-x-hidden min-h-0 px-3 pb-3"
      >
        <div v-if="isLoading" class="flex justify-center py-8">
          <Spinner />
        </div>

        <!-- Gestiones: estado, quién y cuándo -->
        <template v-else-if="activityTab === 'managements'">
          <Button
            :label="t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.ADD')"
            icon="i-lucide-plus"
            size="xs"
            class="w-full mb-2"
            @click="emit('addManagement')"
          />
          <p
            v-if="!managements.length"
            class="text-xs text-n-slate-10 py-6 text-center"
          >
            {{ t('JABVOX_CONTACTS.DETAIL.EMPTY.MANAGEMENTS') }}
          </p>
          <div
            v-for="m in managements"
            :key="`${m.source}-${m.id}`"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-2.5 mb-2"
          >
            <div class="flex items-start justify-between gap-2">
              <span class="text-xs font-medium text-n-slate-12 break-words">
                {{ m.state_name || t('JABVOX_CONTACTS.DETAIL.NO_STATE') }}
              </span>
              <span
                class="text-[11px] text-n-slate-10 whitespace-nowrap flex-shrink-0"
              >
                {{ formatDate(m.created_at) }}
              </span>
            </div>
            <p
              v-if="m.content"
              class="text-xs text-n-slate-11 mt-1 whitespace-pre-wrap break-words"
            >
              {{ m.content }}
            </p>
            <!-- Respuestas a las preguntas del estado: sin esto la gestión pierde
                 justamente lo que el agente tipificó. -->
            <dl v-if="m.answers?.length" class="mt-1.5 flex flex-col gap-0.5">
              <div
                v-for="(a, i) in m.answers"
                :key="i"
                class="flex gap-1.5 text-[11px]"
              >
                <dt class="text-n-slate-10 flex-shrink-0">{{ a.label }}</dt>
                <dd class="text-n-slate-11 break-words">
                  {{ Array.isArray(a.value) ? a.value.join(', ') : a.value }}
                </dd>
              </div>
            </dl>
            <p v-if="m.user" class="text-[11px] text-n-slate-10 mt-1">
              {{ m.user }}
            </p>
          </div>
        </template>

        <!-- Productos: el mismo panel de la conversación, con su formulario de alta -->
        <template v-else-if="activityTab === 'orders'">
          <JabvoxConversationProducts :contact-id="contactId" />
        </template>

        <!-- Registros: las tablas personalizadas de varias filas del contacto (asesorías,
             casos…). El panel trae su propio alta/edición/borrado por fila. -->
        <template v-else-if="activityTab === 'records'">
          <JabvoxLeadTableRows :contact-id="contactId" />
        </template>

        <!-- Historial: conversaciones y pedidos agrupados por día -->
        <template v-else-if="activityTab === 'history'">
          <JabvoxConversationHistory :contact-id="contactId" />
        </template>
      </div>
    </section>
  </div>
</template>
