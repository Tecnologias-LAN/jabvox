<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import messageAPI from 'dashboard/api/inbox/message';
import JabvoxCallButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxCallButton.vue';
import JabvoxEmailButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxEmailButton.vue';
import JabvoxSmsButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxSmsButton.vue';
import JabvoxConversationProducts from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationProducts.vue';
import JabvoxConversationHistory from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationHistory.vue';
import JabvoxLeadRecordsByContact from 'dashboard/components/widgets/conversation/jabvox/JabvoxLeadRecordsByContact.vue';
import JabvoxConversationNotes from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationNotes.vue';
import ContactChatPanel from 'dashboard/components-next/Contacts/Pages/ContactChatPanel.vue';
import contactDetailAPI from 'dashboard/api/jabvox/contactDetail';
import contactsListAPI from 'dashboard/api/jabvox/contactsList';
import JabvoxLeadInfoByContact from 'dashboard/components/widgets/conversation/jabvox/JabvoxLeadInfoByContact.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const emit = defineEmits(['close', 'refresh']);
const store = useStore();
const { t } = useI18n();
const myVisibilities = useMapGetter(
  'jabvoxFieldVisibilities/getMyVisibilities'
);
const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');

const mask = (field, value) =>
  myVisibilities.value[field] !== false ? value : '***';

const activeTab = ref('chat');
// Info ampliada del contacto, plegada por defecto.
const showFullInfo = ref(false);
const messages = ref([]);
const isLoadingMessages = ref(false);
const managementStateId = ref(null);
const managementGroup = ref(null);
const managementAnswers = ref({});
const messagesContainer = ref(null);

const selectedManagementState = computed(() =>
  managementStates.value.find(s => s.id === managementStateId.value)
);

// Changing the group invalidates a substate that belongs to another group.
watch(managementGroup, () => {
  const state = selectedManagementState.value;
  if (
    state &&
    (state.state_group_jabvox || '') !== (managementGroup.value || '')
  )
    managementStateId.value = null;
});

const contactName = computed(
  () => props.conversation.contact?.name || t('JABVOX_KANBAN.UNKNOWN_CONTACT')
);
const contactEmail = computed(() =>
  mask('email', props.conversation.contact?.email || '')
);
const contactPhone = computed(() =>
  mask('phone', props.conversation.contact?.phone_number || '')
);
const contactIdentification = computed(() => {
  const id =
    props.conversation.contact?.additional_attributes
      ?.jabvox_identification_number;
  return id ? mask('identification', id) : '';
});
const contactType = computed(
  () =>
    props.conversation.contact?.additional_attributes?.jabvox_contact_type ||
    'persona'
);
const contactTypeLabel = computed(() =>
  contactType.value === 'empresa'
    ? t('JABVOX_KANBAN.CONTACT_TYPE_COMPANY')
    : t('JABVOX_KANBAN.CONTACT_TYPE_PERSON')
);
const avatarUrl = computed(() => props.conversation.contact?.avatar_url || '');
const assigneeName = computed(
  () => props.conversation.assignee?.name || t('JABVOX_KANBAN.UNASSIGNED')
);
const inboxName = computed(() => props.conversation.inbox?.name || '');
// Conversaciones del contacto, para que el chat ofrezca TODAS sus bandejas y no solo la
// que abrió la tarjeta.
const contactConversations = ref([]);

// Etapa del ciclo de vida del contacto: se puede cambiar desde aquí sin salir del tablero.
const lifecycleStages = ref([]);
const lifecycleStage = ref('');
const isSavingStage = ref(false);

const loadContactConversations = async id => {
  if (!id) {
    contactConversations.value = [];
    return;
  }
  try {
    const { data } = await contactDetailAPI.show(id);
    contactConversations.value = data.conversations || [];
    lifecycleStage.value = data.contact?.lifecycle_stage || '';
    lifecycleStages.value = data.lifecycle_stages || [];
  } catch {
    contactConversations.value = [];
    lifecycleStage.value = '';
    lifecycleStages.value = [];
  }
};

const contactId = computed(
  () => props.conversation.contact?.id || props.conversation.meta?.sender?.id
);

const changeLifecycleStage = async stage => {
  if (!stage || stage === lifecycleStage.value || isSavingStage.value) return;

  const previous = lifecycleStage.value;
  lifecycleStage.value = stage;
  isSavingStage.value = true;
  try {
    await contactsListAPI.updateLifecycle(contactId.value, stage);
    // El tablero pinta la etapa en la tarjeta: se recarga para que no quede desfasada.
    emit('refresh');
  } catch {
    // Si falla, se revierte para no dejar en pantalla un estado que no se guardó.
    lifecycleStage.value = previous;
    useAlert(t('JABVOX_KANBAN.STAGE_UPDATE_ERROR'));
  } finally {
    isSavingStage.value = false;
  }
};

const currentAccountId = useMapGetter('getCurrentAccountId');
const isProductsEnabled = computed(() =>
  store.getters['accounts/isFeatureEnabledonAccount'](
    currentAccountId.value,
    FEATURE_FLAGS.JABVOX_PRODUCTS
  )
);

const hasMultiTables = computed(() => {
  try {
    return (
      (store.getters['jabvoxCustomization/getMultiTables'] || []).length > 0
    );
  } catch {
    return false;
  }
});

const TABS = computed(() => {
  const tabs = [
    {
      key: 'chat',
      label: 'JABVOX_PRODUCTS.CONVERSATION.TAB_CHAT',
      icon: 'i-lucide-message-circle',
    },
  ];
  if (isProductsEnabled.value) {
    tabs.push({
      key: 'products',
      label: 'JABVOX_PRODUCTS.CONVERSATION.TAB_PRODUCTS',
      icon: 'i-lucide-shopping-cart',
    });
  }
  // Notes tab (with gestión) — the chat itself no longer carries the picker.
  tabs.push({
    key: 'notes',
    label: 'JABVOX_CUSTOMIZATION.LEAD_ROWS.NOTES_TAB',
    icon: 'i-lucide-sticky-note',
  });
  if (hasMultiTables.value) {
    tabs.push({
      key: 'records',
      label: 'JABVOX_CUSTOMIZATION.LEAD_ROWS.TAB',
      icon: 'i-lucide-list',
    });
  }
  tabs.push({
    key: 'history',
    label: 'JABVOX_PRODUCTS.CONVERSATION.TAB_HISTORY',
    icon: 'i-lucide-clock',
  });
  return tabs;
});

const scrollToBottom = () => {
  setTimeout(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight;
    }
  }, 50);
};

const loadMessages = async () => {
  isLoadingMessages.value = true;
  try {
    const response = await messageAPI.getPreviousMessages({
      // messages API resolves by display_id, not the PK
      conversationId: props.conversation.display_id,
      before: undefined,
      after: undefined,
    });
    messages.value = response.data?.payload || [];
  } catch {
    useAlert(t('JABVOX_KANBAN.LOAD_MESSAGES_ERROR'));
  } finally {
    isLoadingMessages.value = false;
    scrollToBottom();
  }
};

onMounted(() => {
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('jabvoxCustomization/fetchTables').catch(() => {});
  loadMessages();
});
watch(
  () => props.conversation.id,
  () => {
    activeTab.value = 'chat';
    managementStateId.value = null;
    managementGroup.value = null;
    managementAnswers.value = {};
    loadMessages();
    loadContactConversations(contactId.value);
  }
);

// También al abrir la ficha por primera vez.
watch(contactId, id => loadContactConversations(id), { immediate: true });
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <!-- Header -->
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <span class="text-sm font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_KANBAN.LEAD_DETAIL') }}
      </span>
      <button
        class="p-1 rounded hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-500"
        @click="emit('close')"
      >
        <i class="i-lucide-x text-lg" />
      </button>
    </div>

    <!-- Contact info -->
    <div
      class="px-4 py-3 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <div class="flex items-center gap-3 mb-2">
        <img
          v-if="avatarUrl"
          :src="avatarUrl"
          class="w-10 h-10 rounded-full object-cover shrink-0"
          :alt="contactName"
        />
        <div
          v-else
          class="w-10 h-10 rounded-full bg-woot-100 dark:bg-woot-800 flex items-center justify-center text-woot-600 dark:text-woot-300 font-semibold text-sm shrink-0"
        >
          {{ contactName.charAt(0).toUpperCase() }}
        </div>
        <div class="min-w-0 flex-1">
          <p
            class="text-sm font-semibold text-slate-800 dark:text-slate-100 truncate"
          >
            {{ contactName }}
          </p>
          <p
            v-if="contactEmail"
            class="text-xs text-slate-500 dark:text-slate-400 truncate"
          >
            {{ contactEmail }}
          </p>
          <div v-if="contactPhone" class="flex items-center gap-1">
            <p class="text-xs text-slate-500 dark:text-slate-400">
              {{ contactPhone }}
            </p>
          </div>
          <p
            v-if="contactIdentification"
            class="text-xs text-slate-500 dark:text-slate-400 font-mono"
          >
            {{ t('JABVOX_KANBAN.DOCUMENT_LABEL') }}: {{ contactIdentification }}
          </p>
          <div class="flex flex-wrap items-center gap-1.5 mt-1">
            <span
              class="inline-flex items-center px-1.5 py-0.5 rounded-md text-[10px] font-medium bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300"
            >
              {{ contactTypeLabel }}
            </span>
            <!-- Estado del contacto, editable aquí mismo. Cambiarlo NO depende de mover la
                 tarjeta: la columna dice dónde está en el proceso, la etapa qué es el
                 contacto para el negocio. -->
            <select
              v-if="contactId"
              :value="lifecycleStage"
              :disabled="isSavingStage"
              class="rounded-md border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-[11px] px-1.5 py-0.5 text-slate-700 dark:text-slate-200 disabled:opacity-50"
              @change="changeLifecycleStage($event.target.value)"
            >
              <option
                v-for="stage in lifecycleStages"
                :key="stage.id"
                :value="stage.id"
              >
                {{ stage.name }}
              </option>
            </select>
          </div>
        </div>
        <div class="flex items-center gap-1">
          <JabvoxCallButton
            v-if="contactPhone || contactId"
            :phone="contactPhone"
            :contact-id="contactId"
            :contact-name="contactName"
          />
          <JabvoxSmsButton
            v-if="contactPhone && contactId"
            :phone="contactPhone"
            :contact-id="contactId"
          />
          <JabvoxEmailButton
            v-if="contactEmail && contactId"
            :email="contactEmail"
            :contact-id="contactId"
          />
        </div>
      </div>
      <div
        class="flex flex-wrap items-center gap-3 text-xs text-slate-500 dark:text-slate-400"
      >
        <span class="flex items-center gap-1">
          <i class="i-lucide-hash text-base" />
          {{ conversation.display_id }}
        </span>
        <span class="flex items-center gap-1">
          <i class="i-lucide-mailbox text-base" />
          {{ inboxName }}
        </span>
        <span class="flex items-center gap-1">
          <i class="i-lucide-user text-base" />
          {{ assigneeName }}
        </span>
        <!-- Info completa del contacto: campaña, afiliado, país, etapa y sus campos
             personalizados. Va plegada para no empujar el chat hacia abajo. -->
        <button
          class="flex items-center gap-1 ml-auto rounded px-1.5 py-0.5 hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors"
          @click="showFullInfo = !showFullInfo"
        >
          <i
            :class="
              showFullInfo ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
            class="text-base"
          />
          {{ $t('JABVOX_KANBAN.FULL_INFO') }}
        </button>
      </div>

      <div
        v-if="showFullInfo && contactId"
        class="mt-3 pt-3 border-t border-slate-200 dark:border-slate-700 max-h-72 overflow-y-auto"
      >
        <JabvoxLeadInfoByContact :contact-id="contactId" />
      </div>
    </div>

    <!-- Tabs -->
    <div
      class="flex border-b border-slate-200 dark:border-slate-700 shrink-0 overflow-x-auto"
    >
      <button
        v-for="tab in TABS"
        :key="tab.key"
        class="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium border-b-2 whitespace-nowrap transition-colors"
        :class="[
          activeTab === tab.key
            ? 'border-woot-600 text-woot-600'
            : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300',
        ]"
        @click="activeTab = tab.key"
      >
        <i :class="tab.icon" />
        {{ $t(tab.label) }}
      </button>
    </div>

    <!-- Chat tab -->
    <!-- Chat: se reutiliza el panel de la ficha del contacto en vez de una copia a mano.
         Trae selector de bandeja, plantillas, adjuntos, audio y el asistente de IA; la
         versión anterior era un chat reimplementado sin nada de eso. -->
    <template v-if="activeTab === 'chat'">
      <ContactChatPanel
        :conversations="contactConversations"
        class="flex-1 min-h-0"
      />
    </template>

    <!-- Products tab -->
    <JabvoxConversationProducts
      v-else-if="activeTab === 'products'"
      :contact-id="contactId"
      :conversation-id="conversation.id"
    />

    <!-- History tab -->
    <JabvoxConversationHistory
      v-else-if="activeTab === 'history' && contactId"
      :contact-id="contactId"
      :conversation-id="conversation.id"
    />
    <div
      v-else-if="activeTab === 'history'"
      class="flex-1 flex items-center justify-center text-sm text-slate-400"
    >
      {{ $t('JABVOX_PRODUCTS.CONVERSATION.HISTORY_EMPTY') }}
    </div>

    <!-- Notes tab (with gestión) -->
    <JabvoxConversationNotes
      v-else-if="activeTab === 'notes'"
      :contact-id="contactId"
      :conversation-id="conversation.id"
      :conversation-display-id="conversation.display_id"
    />

    <!-- Records tab: multi-row custom tables (Asesorías, Casos…) -->
    <div v-else-if="activeTab === 'records'" class="flex-1 overflow-y-auto">
      <JabvoxLeadRecordsByContact :contact-id="contactId" />
    </div>
  </div>
</template>
