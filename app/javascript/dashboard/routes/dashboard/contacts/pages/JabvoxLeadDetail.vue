<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import messageAPI from 'dashboard/api/inbox/message';
import leadsAPI from 'dashboard/api/jabvox/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import JabvoxConversationProducts from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationProducts.vue';
import JabvoxConversationHistory from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationHistory.vue';
import JabvoxCallButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxCallButton.vue';
import JabvoxSmsButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxSmsButton.vue';
import JabvoxEmailButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxEmailButton.vue';
import JabvoxQuickButtons from 'dashboard/components/widgets/conversation/jabvox/JabvoxQuickButtons.vue';
import JabvoxLeadTableRows from 'dashboard/components/widgets/conversation/jabvox/JabvoxLeadTableRows.vue';
import TemplatesPicker from 'dashboard/components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue';
import WhatsAppTemplateReply from 'dashboard/components/widgets/conversation/WhatsappTemplates/WhatsAppTemplateReply.vue';
import ManagementQuestionsForm from 'dashboard/components/jabvox/managementStates/ManagementQuestionsForm.vue';
import {
  isManagementValid,
  buildManagementContentAttributes,
  noteRule,
  stateGroups,
  statesInGroup,
  hasGroups,
  CALL_SOURCES,
} from 'dashboard/composables/jabvox/useManagementState';

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const lead = useMapGetter('jabvoxLeads/getCurrentLead');
const leads = useMapGetter('jabvoxLeads/getLeads');
const uiFlags = useMapGetter('jabvoxLeads/getUIFlags');
const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');
const inboxes = useMapGetter('inboxes/getInboxes');
const currentUser = useMapGetter('getCurrentUser');
const contactNotesGetterFn = useMapGetter(
  'contactNotes/getAllNotesByContactId'
);

const activeTab = ref(route.query.tab || 'chat');
const messages = ref([]);
// Notas privadas de TODAS las conversaciones del contacto (ver loadAllConversationNotes).
const allConvNotes = ref([]);
const isLoadingMessages = ref(false);
const newMessage = ref('');
const isSending = ref(false);
const isNoteMode = ref(false);
const managementStateId = ref(null);
const managementGroup = ref(null);
const managementAnswers = ref({});
const chatContainer = ref(null);
const notesContainer = ref(null);

const contactNotesList = computed(() =>
  lead.value?.contact?.id
    ? contactNotesGetterFn.value(lead.value.contact.id)
    : []
);

const selectedManagementState = computed(() =>
  managementStates.value.find(s => s.id === managementStateId.value)
);

// Two-level picker (Estado → Subestado) when any active state has a group.
const managementHasGroups = computed(() => hasGroups(managementStates.value));
const managementGroups = computed(() => stateGroups(managementStates.value));
const managementGroupStates = computed(() =>
  managementGroup.value === null
    ? []
    : statesInGroup(managementStates.value, managementGroup.value)
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

// Documento y tipo de persona (viven en additional_attributes del contacto).
const contactIdentification = computed(
  () =>
    lead.value?.contact?.additional_attributes?.jabvox_identification_number ||
    ''
);
const contactType = computed(
  () =>
    lead.value?.contact?.additional_attributes?.jabvox_contact_type || 'persona'
);
// Biografía (mapeada desde description; vive en additional_attributes.description).
const contactBiography = computed(
  () => lead.value?.contact?.additional_attributes?.description || ''
);
// Origen de una nota/tipificación (dialer, click-to-call o detalle del lead) y
// nombre de la tipificación — guardados en content_attributes por cada flujo.
// Acepta snake_case (notas de conversación) y camelCase (notas de contacto).
const CALL_SOURCE_LABEL_KEYS = {
  dialer: 'JABVOX_LEADS.DETAIL.SOURCE_DIALER',
  click_to_call: 'JABVOX_LEADS.DETAIL.SOURCE_CLICK_TO_CALL',
  lead_detail: 'JABVOX_LEADS.DETAIL.SOURCE_LEAD_DETAIL',
  kanban: 'JABVOX_LEADS.DETAIL.SOURCE_KANBAN',
  conversations: 'JABVOX_LEADS.DETAIL.SOURCE_CONVERSATIONS',
};
const callSourceLabel = attrs => {
  const src = attrs?.jabvox_call_source || attrs?.jabvoxCallSource;
  return src && CALL_SOURCE_LABEL_KEYS[src]
    ? t(CALL_SOURCE_LABEL_KEYS[src])
    : '';
};
const typificationBadge = attrs =>
  attrs?.jabvox_typification_name || attrs?.jabvoxTypificationName || '';

const contactTypeLabel = computed(() =>
  contactType.value === 'empresa'
    ? t('JABVOX_LEADS.DETAIL.INFO.CONTACT_TYPE_COMPANY')
    : t('JABVOX_LEADS.DETAIL.INFO.CONTACT_TYPE_PERSON')
);

const selectedInboxId = ref(null);
const initialMessage = ref('');
const isStarting = ref(false);

const accountId = computed(() => route.params.accountId);
const leadId = computed(() => route.params.leadId);

const isCustomizationEnabled = computed(() =>
  store.getters['accounts/isFeatureEnabledonAccount'](
    accountId.value,
    FEATURE_FLAGS.JABVOX_CUSTOMIZATION
  )
);

const isProductsEnabled = computed(() =>
  store.getters['accounts/isFeatureEnabledonAccount'](
    accountId.value,
    FEATURE_FLAGS.JABVOX_PRODUCTS
  )
);

// Multi-row custom tables (Asesorías, Casos…) add a "records" tab only when the
// customization module is on AND at least one such table exists.
const hasMultiTables = computed(() => {
  try {
    return (
      isCustomizationEnabled.value &&
      (store.getters['jabvoxCustomization/getMultiTables'] || []).length > 0
    );
  } catch {
    return false;
  }
});

const availableTabs = computed(() => {
  const tabs = ['chat', 'notes'];
  // Products tab only when the module is enabled for this account.
  if (isProductsEnabled.value) tabs.push('products');
  tabs.push('history');
  if (hasMultiTables.value) tabs.push('records');
  return tabs;
});

const leadsTable = computed(() => {
  try {
    return store.getters['jabvoxCustomization/getLeadsTable'];
  } catch {
    return null;
  }
});

const leadsTableColumns = computed(() => leadsTable.value?.columns || []);

// ── Left-panel usability: collapsible sections + field search ──
// The lead has many custom fields, so the info panel gets long and pushes the
// action buttons below the fold. Sections can be collapsed to bring the buttons
// into view without scrolling, and a search box filters the custom fields.
const sectionsCollapsed = ref({ info: false, custom: false });
const toggleSection = key => {
  sectionsCollapsed.value = {
    ...sectionsCollapsed.value,
    [key]: !sectionsCollapsed.value[key],
  };
};

const fieldSearch = ref('');
// Custom-field columns filtered by the search box (matches the visible label).
const filteredLeadsColumns = computed(() => {
  const q = fieldSearch.value.trim().toLowerCase();
  if (!q) return leadsTableColumns.value;
  return leadsTableColumns.value.filter(col =>
    (col.label_jabvox || '').toLowerCase().includes(q)
  );
});

// ── Inline edit (contact fields + campaign + assignee + custom fields) ──
// The whole left panel is read-only until "Editar" is pressed. Then the
// editable fields turn into inputs and "Guardar"/"Cancelar" appear.
const isEditing = ref(false);
const isSavingFields = ref(false);
const assignees = useMapGetter('agents/getAgents');
const editForm = ref({
  phone_number: '',
  email: '',
  country: '',
  identification: '',
  campaign_name: '',
  assignee_id: null,
  custom: {},
});

const initEditForm = () => {
  if (!lead.value) return;
  const existing = lead.value.custom_fields_jabvox || {};
  const custom = {};
  leadsTableColumns.value.forEach(col => {
    custom[col.name_jabvox] = existing[col.name_jabvox] ?? '';
  });
  editForm.value = {
    phone_number: lead.value.contact?.phone_number || '',
    email: lead.value.contact?.email || '',
    country: lead.value.contact?.country || '',
    identification: contactIdentification.value || '',
    campaign_name: lead.value.campaign?.name || '',
    assignee_id: lead.value.assignee_id ?? null,
    custom,
  };
};

const startEdit = () => {
  initEditForm();
  isEditing.value = true;
};
const cancelEdit = () => {
  isEditing.value = false;
};

const saveAll = async () => {
  if (!lead.value || isSavingFields.value) return;
  isSavingFields.value = true;
  try {
    await store.dispatch('jabvoxLeads/updateLeadDetails', {
      id: lead.value.id,
      contact: {
        phone_number: editForm.value.phone_number,
        email: editForm.value.email,
        country: editForm.value.country,
        identification: editForm.value.identification,
      },
      campaign_name: editForm.value.campaign_name,
      assignee_id: editForm.value.assignee_id,
      custom_fields: editForm.value.custom,
    });
    await store.dispatch('jabvoxLeads/fetchLead', leadId.value);
    isEditing.value = false;
    useAlert(t('JABVOX_LEADS.DETAIL.CUSTOM_FIELDS_SAVED'));
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.CUSTOM_FIELDS_ERROR'));
  } finally {
    isSavingFields.value = false;
  }
};

const currentIndex = computed(() =>
  leads.value.findIndex(l => String(l.id) === String(leadId.value))
);
const prevLead = computed(() =>
  currentIndex.value > 0 ? leads.value[currentIndex.value - 1] : null
);
const nextLead = computed(() =>
  currentIndex.value >= 0 && currentIndex.value < leads.value.length - 1
    ? leads.value[currentIndex.value + 1]
    : null
);

const sortedMessages = computed(() =>
  [...messages.value].sort(
    (a, b) => new Date(a.created_at) - new Date(b.created_at)
  )
);

const privateNotes = computed(() =>
  sortedMessages.value.filter(m => m.message_type === 2 || m.private)
);

// Normaliza content_attributes a snake_case (las notas de contacto llegan en
// camelCase; las de conversación en snake_case). Así el render usa un solo formato.
const normalizeAttrs = attrs => {
  if (!attrs) return {};
  // Si ya viene en snake_case (notas de conversación), úsalo tal cual.
  if (
    'jabvox_management_state_name' in attrs ||
    'jabvox_call_source' in attrs
  ) {
    return attrs;
  }
  // Notas de contacto (camelCase) → mapear los campos que usa el render.
  return {
    jabvox_management_state_name: attrs.jabvoxManagementStateName,
    jabvox_management_state_color: attrs.jabvoxManagementStateColor,
    jabvox_management_state_group: attrs.jabvoxManagementStateGroup,
    jabvox_management_answers: attrs.jabvoxManagementAnswers,
    jabvox_typification_name: attrs.jabvoxTypificationName,
    jabvox_call_source: attrs.jabvoxCallSource,
  };
};

// TODAS las gestiones del lead, sin importar el origen ni la conversación:
//  - notas privadas de las conversaciones (principal + resto del contacto)
//  - notas de contacto (leads sin conversación)
// Deduplicadas por id y ordenadas por fecha ascendente. Es la lista única que
// muestra la pestaña "Notas", para que una gestión hecha desde cualquier origen
// (marcador, click-to-call, kanban, conversaciones, detalle) siempre se vea.
const unifiedNotes = computed(() => {
  const map = new Map();
  const add = (note, attrs, sourceTag) => {
    if (!note || note.id == null) return;
    const key = `${sourceTag}-${note.id}`;
    if (map.has(key)) return;
    map.set(key, {
      id: note.id,
      key,
      content: note.content,
      created_at: note.created_at || note.createdAt,
      content_attributes: normalizeAttrs(attrs),
    });
  };
  // Notas de la conversación principal (ya cargadas en messages) + todas las demás.
  privateNotes.value.forEach(m => add(m, m.content_attributes, 'conv'));
  allConvNotes.value.forEach(m => add(m, m.content_attributes, 'conv'));
  contactNotesList.value.forEach(n =>
    add(n, n.contentAttributes || n.content_attributes, 'contact')
  );
  return [...map.values()].sort(
    (a, b) => new Date(a.created_at) - new Date(b.created_at)
  );
});

const isPrivateNote = m => m.message_type === 2 || m.private;
const isIncoming = m => m.message_type === 0;

const msgBubbleClass = m => {
  if (isPrivateNote(m))
    return 'bg-n-amber-3 border border-n-amber-6 text-n-amber-11';
  if (isIncoming(m)) return 'bg-n-alpha-2 text-n-slate-12';
  return 'bg-n-brand text-white ml-auto';
};

const msgAlignClass = m =>
  isPrivateNote(m) || isIncoming(m) ? 'items-start' : 'items-end';

const formatTime = dateVal => {
  const ms = typeof dateVal === 'number' ? dateVal * 1000 : dateVal;
  return new Date(ms).toLocaleString('es-CO', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const scrollToBottom = container => {
  setTimeout(() => {
    if (container?.value) {
      container.value.scrollTop = container.value.scrollHeight;
    }
  }, 50);
};

const loadMessages = async () => {
  if (!lead.value?.conversation_display_id) return;
  isLoadingMessages.value = true;
  try {
    const response = await messageAPI.getPreviousMessages({
      conversationId: lead.value.conversation_display_id,
      before: undefined,
      after: undefined,
    });
    messages.value = response.data?.payload || [];
    scrollToBottom(chatContainer);
    scrollToBottom(notesContainer);
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.LOAD_MESSAGES_ERROR'));
  } finally {
    isLoadingMessages.value = false;
  }
};

const loadContactNotes = () => {
  if (!lead.value?.contact?.id) return;
  store.dispatch('contactNotes/get', { contactId: lead.value.contact.id });
};

// Notas privadas (gestiones) de TODAS las conversaciones del contacto, no solo
// la principal. Antes el detalle solo mostraba las notas de
// lead.conversation_display_id, así que una gestión creada en otra conversación
// (p. ej. la que el marcador usa, que es la más reciente) quedaba invisible.
// Cargamos en paralelo las notas privadas de cada conversación del contacto.
const loadAllConversationNotes = async () => {
  const contactId = lead.value?.contact?.id;
  if (!contactId) {
    allConvNotes.value = [];
    return;
  }
  try {
    await store.dispatch('contactConversations/get', contactId);
    const convs =
      store.getters['contactConversations/getAllConversationsByContactId'](
        contactId
      ) || [];
    const results = await Promise.allSettled(
      convs.map(conv =>
        axios.get(
          `/api/v1/accounts/${accountId.value}/conversations/${conv.id}/messages`
        )
      )
    );
    const notes = [];
    results.forEach(r => {
      if (r.status !== 'fulfilled') return;
      (r.value.data?.payload || [])
        .filter(m => m.message_type === 2 || m.private)
        .forEach(m => notes.push(m));
    });
    allConvNotes.value = notes;
  } catch {
    allConvNotes.value = [];
  }
};

// withGestion=true only for the Notes tab: there a management state is
// required. The chat's private note (withGestion=false) is plain text — its
// gestión picker was removed.
const sendMessage = async (privateFlag = false, withGestion = false) => {
  const noteText = newMessage.value.trim();
  // La nota es OPCIONAL según el note_mode del tipo de gestión: con una gestión
  // seleccionada y sin texto, el contenido cae al nombre de la gestión (igual
  // que el dialer). Sin gestión, la nota pura sí exige texto.
  const stateForNote = withGestion ? selectedManagementState.value : null;
  const content = noteText || stateForNote?.name_jabvox || '';
  if (!content || isSending.value) return;

  if (
    withGestion &&
    selectedManagementState.value &&
    !isManagementValid(
      selectedManagementState.value,
      managementAnswers.value,
      noteText
    )
  ) {
    useAlert(t('JABVOX_MANAGEMENT_STATES.QUESTIONS.INCOMPLETE'));
    return;
  }

  if (privateFlag && !lead.value?.conversation_display_id) {
    if (
      withGestion &&
      managementStates.value.length > 0 &&
      !managementStateId.value
    )
      return;
    isSending.value = true;
    try {
      // Una nota de contacto (lead sin conversación) también lleva su origen
      // 'lead_detail', para que el detalle muestre desde dónde se tipificó.
      const contentAttributes =
        withGestion && managementStateId.value
          ? buildManagementContentAttributes(
              selectedManagementState.value,
              managementAnswers.value,
              CALL_SOURCES.LEAD_DETAIL
            )
          : { jabvox_call_source: CALL_SOURCES.LEAD_DETAIL };
      await store.dispatch('contactNotes/create', {
        contactId: lead.value.contact.id,
        content,
        contentAttributes,
      });
      newMessage.value = '';
      managementStateId.value = null;
      managementGroup.value = null;
      managementAnswers.value = {};
      scrollToBottom(notesContainer);
    } catch {
      useAlert(t('JABVOX_LEADS.DETAIL.SEND_ERROR'));
    } finally {
      isSending.value = false;
    }
    return;
  }

  if (!lead.value?.conversation_display_id) return;
  if (
    withGestion &&
    managementStates.value.length > 0 &&
    !managementStateId.value
  )
    return;
  isSending.value = true;
  try {
    const payload = {
      conversationId: lead.value.conversation_display_id,
      message: content,
      private: privateFlag,
      echo_id: `jabvox_${Date.now()}`,
    };
    // Solo las notas PRIVADAS llevan gestión + origen; un mensaje saliente normal
    // no. El origen 'lead_detail' se marca vía el helper centralizado.
    if (privateFlag) {
      payload.contentAttributes =
        withGestion && managementStateId.value
          ? buildManagementContentAttributes(
              selectedManagementState.value,
              managementAnswers.value,
              CALL_SOURCES.LEAD_DETAIL
            )
          : { jabvox_call_source: CALL_SOURCES.LEAD_DETAIL };
    }
    const response = await messageAPI.create(payload);
    messages.value.push(response.data);
    newMessage.value = '';
    managementStateId.value = null;
    managementGroup.value = null;
    managementAnswers.value = {};
    scrollToBottom(privateFlag ? notesContainer : chatContainer);
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.SEND_ERROR'));
  } finally {
    isSending.value = false;
  }
};

const onChatKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage(isNoteMode.value);
  }
};

// Enter en la pestaña Notas guarda CON la gestión seleccionada (antes llamaba
// sendMessage(true) sin gestión y descartaba el estado + respuestas elegidas).
const onGestionNoteKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage(true, true);
  }
};

// Regla de la nota del tipo de gestión seleccionado (oculta/opcional/requerida).
const gestionNoteRule = computed(() => noteRule(selectedManagementState.value));

// El botón de guardar en Notas: con texto siempre; sin texto solo cuando hay
// una gestión seleccionada cuya nota NO es requerida (cae al nombre del estado).
const canSaveGestionNote = computed(() => {
  if (newMessage.value.trim()) return true;
  const state = selectedManagementState.value;
  return !!state && !gestionNoteRule.value.required;
});

// ── Gestiones expandibles en Notas: respuestas de preguntas y detalles ──
const expandedNotes = ref(new Set());
const toggleNoteExpanded = id => {
  const next = new Set(expandedNotes.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  expandedNotes.value = next;
};
// Respuestas guardadas con la gestión (snake_case en notas de conversación,
// camelCase en notas de contacto).
const noteAnswers = attrs =>
  attrs?.jabvox_management_answers || attrs?.jabvoxManagementAnswers || [];
const noteGroup = attrs =>
  attrs?.jabvox_management_state_group ||
  attrs?.jabvoxManagementStateGroup ||
  '';
const noteHasDetails = attrs =>
  noteAnswers(attrs).length > 0 || !!noteGroup(attrs);
const answerDisplay = value => {
  if (Array.isArray(value)) return value.join(', ');
  if (value === true) return t('JABVOX_LEADS.DETAIL.YES');
  if (value === false) return t('JABVOX_LEADS.DETAIL.NO');
  return `${value ?? ''}`;
};

const goToLead = id => {
  router.push({
    name: 'jabvox_lead_detail',
    params: { accountId: accountId.value, leadId: id },
  });
};

const goBack = () => {
  router.push({
    name: 'jabvox_leads_index',
    params: { accountId: accountId.value },
  });
};

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleDateString('es', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
};

// Plantilla de WhatsApp seleccionada para iniciar la conversación (WhatsApp API
// exige plantilla aprobada para el primer contacto, no texto libre).
const selectedTemplate = ref(null);

const selectedInbox = computed(() =>
  inboxes.value.find(i => i.id === selectedInboxId.value)
);
const selectedIsWhatsApp = computed(
  () => selectedInbox.value?.channel_type === 'Channel::Whatsapp'
);
// El inbox de WhatsApp API requiere plantilla para el primer mensaje: si el
// inbox seleccionado tiene plantillas aprobadas, mostramos el selector en vez
// del cuadro de texto libre.
const requiresTemplate = computed(() => {
  if (!selectedIsWhatsApp.value || !selectedInboxId.value) return false;
  const templates = store.getters['inboxes/getFilteredWhatsAppTemplates'](
    selectedInboxId.value
  );
  return Array.isArray(templates) && templates.length > 0;
});

// Al cambiar de inbox, se descarta la plantilla en curso.
watch(selectedInboxId, () => {
  selectedTemplate.value = null;
});

// Toma la gestión del lead: lo asigna (lead + contacto + conversaciones abiertas)
// al agente actual vía el backend, que usa LeadConversationAssignmentSync. Se
// llama al enviar plantilla para que la conversación quede en la bandeja del
// agente. No rompe el flujo si falla (el mensaje ya se envió).
const claimLead = async () => {
  try {
    await leadsAPI.claim(leadId.value);
    await store.dispatch('jabvoxLeads/fetchLead', leadId.value);
  } catch (e) {
    e?.toString();
  }
};

// Crea la conversación. `messagePayload` (opcional) trae la plantilla ya
// procesada { message, templateParams } cuando se inicia por WhatsApp API.
const createConversation = async messagePayload => {
  isStarting.value = true;
  try {
    const params = {
      contactId: lead.value.contact.id,
      inboxId: selectedInboxId.value,
      // Asignar la conversación al iniciarla. Sin esto quedaba sin dueño y no
      // aparecía en la bandeja del agente (los agentes solo ven las suyas), solo
      // accesible desde Leads. Hereda el dueño del LEAD (lead_assignee_id, no el
      // de la conversación) si lo tiene; si no, el usuario actual que la envía.
      assigneeId: lead.value.lead_assignee_id || currentUser.value?.id,
    };
    if (messagePayload) {
      // Enviar como plantilla: el MessageBuilder guarda template_params en
      // additional_attributes y el envío sale como template a Meta.
      params.message = {
        content: messagePayload.message,
        template_params: messagePayload.templateParams,
      };
    } else if (initialMessage.value.trim()) {
      params.message = { content: initialMessage.value.trim() };
    }
    await store.dispatch('contactConversations/create', {
      params,
      isFromWhatsApp: selectedIsWhatsApp.value,
    });
    initialMessage.value = '';
    selectedInboxId.value = null;
    selectedTemplate.value = null;
    await store.dispatch('jabvoxLeads/fetchLead', leadId.value);
    loadMessages();
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.START_CONV_ERROR'));
  } finally {
    isStarting.value = false;
  }
};

const startConversation = async () => {
  if (!selectedInboxId.value || isStarting.value) return;
  // Para WhatsApp API la conversación se inicia desde el envío de la plantilla
  // (handleTemplateSend), no desde este botón.
  if (requiresTemplate.value) return;
  await createConversation();
};

// Envío de la plantilla elegida: crea la conversación con template_params.
const handleTemplateSend = async payload => {
  if (!selectedInboxId.value || isStarting.value) return;
  await createConversation(payload);
};

// ── Plantilla dentro de una conversación YA abierta ─────────────────────────
// El icono de WhatsApp en la barra de composición abre este panel para elegir y
// enviar una plantilla a la conversación existente (no crea una nueva).
const showTemplatePanel = ref(false);
const panelTemplate = ref(null);

const toggleTemplatePanel = () => {
  showTemplatePanel.value = !showTemplatePanel.value;
  if (!showTemplatePanel.value) panelTemplate.value = null;
};

// El inbox de la conversación abierta (para listar sus plantillas aprobadas).
const conversationInboxId = computed(() => lead.value?.inbox_id || null);
const canSendTemplateInConversation = computed(() => {
  const id = conversationInboxId.value;
  if (!id) return false;
  const templates = store.getters['inboxes/getFilteredWhatsAppTemplates'](id);
  return Array.isArray(templates) && templates.length > 0;
});

const handleTemplateSendToConversation = async payload => {
  if (!lead.value?.conversation_display_id || isSending.value) return;
  isSending.value = true;
  try {
    const response = await messageAPI.create({
      conversationId: lead.value.conversation_display_id,
      message: payload.message,
      templateParams: payload.templateParams,
      echo_id: `jabvox_${Date.now()}`,
    });
    messages.value.push(response.data);
    // Al enviar plantilla, tomar la gestión: el lead y su conversación quedan
    // asignados a mí (aunque estuvieran sin dueño o de otro agente).
    await claimLead();
    showTemplatePanel.value = false;
    panelTemplate.value = null;
    scrollToBottom(chatContainer);
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.SEND_ERROR'));
  } finally {
    isSending.value = false;
  }
};

const loadLead = async () => {
  await store.dispatch('jabvoxLeads/fetchLead', leadId.value);
  messages.value = [];
  allConvNotes.value = [];
  newMessage.value = '';
  managementStateId.value = null;
  managementGroup.value = null;
  managementAnswers.value = {};
  isEditing.value = false;
  initEditForm();
  loadMessages();
  loadContactNotes();
  loadAllConversationNotes();
};

watch(leadId, loadLead);
watch(leadsTableColumns, initEditForm, { deep: true });
onMounted(async () => {
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('agents/get');
  if (isCustomizationEnabled.value) {
    await store.dispatch('jabvoxCustomization/fetchTables');
  }
  loadLead();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-background">
    <!-- Header -->
    <div
      class="shrink-0 border-b border-n-weak bg-n-solid-1 px-6 py-3.5 flex items-center gap-4"
    >
      <button
        class="flex items-center gap-1.5 h-8 px-2.5 rounded-lg text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
        @click="goBack"
      >
        <span class="i-lucide-arrow-left size-4" />
        {{ t('JABVOX_LEADS.DETAIL.BACK') }}
      </button>

      <div class="flex-1" />

      <div v-if="leads.length > 1" class="flex items-center gap-2">
        <button
          :disabled="!prevLead"
          class="group flex items-center gap-2 h-9 pl-2.5 pr-3.5 rounded-xl border border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-brand hover:text-n-brand disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          @click="prevLead && goToLead(prevLead.id)"
        >
          <span
            class="i-lucide-chevron-left size-4 group-hover:-translate-x-0.5 transition-transform"
          />
          <span class="text-left">
            <span
              class="block text-[10px] text-n-slate-10 leading-none uppercase tracking-wide"
            >
              {{ t('JABVOX_LEADS.DETAIL.PREV') }}
            </span>
            <span
              class="block text-xs font-medium truncate max-w-[110px] leading-tight mt-0.5 text-n-slate-12"
            >
              {{ prevLead?.contact?.name || '···' }}
            </span>
          </span>
        </button>
        <span
          class="text-xs font-medium text-n-slate-10 tabular-nums whitespace-nowrap px-1"
        >
          {{ currentIndex + 1 }}&thinsp;/&thinsp;{{ leads.length }}
        </span>
        <button
          :disabled="!nextLead"
          class="group flex items-center gap-2 h-9 pl-3.5 pr-2.5 rounded-xl border border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-brand hover:text-n-brand disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          @click="nextLead && goToLead(nextLead.id)"
        >
          <span class="text-right">
            <span
              class="block text-[10px] text-n-slate-10 leading-none uppercase tracking-wide"
            >
              {{ t('JABVOX_LEADS.DETAIL.NEXT') }}
            </span>
            <span
              class="block text-xs font-medium truncate max-w-[110px] leading-tight mt-0.5 text-n-slate-12"
            >
              {{ nextLead?.contact?.name || '···' }}
            </span>
          </span>
          <span
            class="i-lucide-chevron-right size-4 group-hover:translate-x-0.5 transition-transform"
          />
        </button>
      </div>
    </div>

    <!-- Loading lead -->
    <div
      v-if="uiFlags.isFetchingOne"
      class="flex-1 flex items-center justify-center gap-2 text-sm text-n-slate-10 animate-pulse"
    >
      <span class="i-lucide-loader-circle size-4 animate-spin" />
      {{ t('JABVOX_LEADS.DETAIL.LOADING') }}
    </div>

    <!-- Not found -->
    <div
      v-else-if="!lead"
      class="flex-1 flex flex-col items-center justify-center gap-2 text-sm text-n-slate-10"
    >
      <span class="i-lucide-search-x size-8 text-n-slate-9" />
      {{ t('JABVOX_LEADS.DETAIL.NOT_FOUND') }}
    </div>

    <!-- Content -->
    <div v-else class="flex-1 min-h-0 flex flex-col lg:flex-row">
      <!-- Left panel: lead info -->
      <div
        class="lg:w-80 shrink-0 border-b lg:border-b-0 lg:border-r border-n-weak bg-n-solid-1 p-5 space-y-4 overflow-y-auto"
      >
        <!-- Contact avatar + name -->
        <div class="flex flex-col items-center text-center gap-3 pb-1">
          <img
            v-if="lead.contact.avatar_url"
            :src="lead.contact.avatar_url"
            :alt="lead.contact.name"
            class="size-16 rounded-full object-cover shrink-0 ring-2 ring-n-weak"
          />
          <div
            v-else
            class="size-16 rounded-full bg-n-brand/10 flex items-center justify-center shrink-0 text-2xl font-semibold text-n-brand ring-2 ring-n-brand/20"
          >
            {{ lead.contact.name?.charAt(0)?.toUpperCase() || '?' }}
          </div>
          <div class="min-w-0 w-full">
            <button
              class="text-base font-semibold text-n-slate-12 hover:text-n-brand transition-colors truncate max-w-full"
              @click="
                router.push({
                  name: 'contacts_edit',
                  params: { accountId: accountId, contactId: lead.contact.id },
                })
              "
            >
              {{ lead.contact.name || '—' }}
            </button>
            <p class="text-xs text-n-slate-10 font-mono mt-0.5">
              #{{ lead.lead_number }}
            </p>
          </div>
        </div>

        <!-- Edit / Save / Cancel -->
        <div class="flex justify-end gap-2">
          <template v-if="!isEditing">
            <Button
              size="small"
              variant="ghost"
              icon="i-lucide-pencil"
              :label="t('JABVOX_LEADS.DETAIL.EDIT')"
              @click="startEdit"
            />
          </template>
          <template v-else>
            <Button
              size="small"
              variant="ghost"
              :label="t('JABVOX_LEADS.DETAIL.CANCEL')"
              @click="cancelEdit"
            />
            <Button
              size="small"
              icon="i-lucide-check"
              :is-loading="isSavingFields"
              :label="t('JABVOX_LEADS.DETAIL.SAVE')"
              @click="saveAll"
            />
          </template>
        </div>

        <!-- Info rows -->
        <div
          class="rounded-xl border border-n-weak bg-n-background overflow-hidden"
        >
          <button
            type="button"
            class="w-full flex items-center gap-2 px-3 py-2.5 text-left hover:bg-n-alpha-1 transition-colors"
            @click="toggleSection('info')"
          >
            <span
              class="size-4 shrink-0 text-n-slate-10 transition-transform"
              :class="
                sectionsCollapsed.info
                  ? 'i-lucide-chevron-right'
                  : 'i-lucide-chevron-down'
              "
            />
            <span
              class="text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
            >
              {{ t('JABVOX_LEADS.DETAIL.INFO.SECTION_TITLE') }}
            </span>
          </button>
          <dl
            v-show="!sectionsCollapsed.info"
            class="divide-y divide-n-weak border-t border-n-weak"
          >
            <!-- Phone (editable, siempre visible) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.PHONE') }}
              </dt>
              <input
                v-if="isEditing"
                v-model="editForm.phone_number"
                class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
              />
              <dd
                v-else
                class="text-sm text-n-slate-12 font-mono truncate flex-1 text-right"
              >
                {{ lead.contact.phone_number || '—' }}
              </dd>
            </div>
            <!-- Email (editable) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.EMAIL') }}
              </dt>
              <input
                v-if="isEditing"
                v-model="editForm.email"
                type="email"
                class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
              />
              <dd
                v-else
                class="text-sm text-n-slate-12 truncate flex-1 text-right"
              >
                {{ lead.contact.email || '—' }}
              </dd>
            </div>
            <!-- Documento (editable; vive en additional_attributes del contacto).
                 Siempre visible, aunque esté vacío, para poder asignarlo. -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.DOCUMENT') }}
              </dt>
              <input
                v-if="isEditing"
                v-model="editForm.identification"
                class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
              />
              <dd
                v-else
                class="text-sm text-n-slate-12 font-mono truncate flex-1 text-right"
              >
                {{ contactIdentification || '—' }}
              </dd>
            </div>
            <!-- Tipo de persona (solo lectura, por defecto persona) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.CONTACT_TYPE') }}
              </dt>
              <dd class="flex-1 text-right">
                <span
                  class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium bg-n-alpha-1 text-n-slate-11"
                >
                  {{ contactTypeLabel }}
                </span>
              </dd>
            </div>
            <!-- Country (editable, siempre visible) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.COUNTRY') }}
              </dt>
              <input
                v-if="isEditing"
                v-model="editForm.country"
                class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
              />
              <dd v-else class="text-sm text-n-slate-12 flex-1 text-right">
                {{ lead.contact.country || '—' }}
              </dd>
            </div>
            <!-- Campaign (editable) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.CAMPAIGN') }}
              </dt>
              <input
                v-if="isEditing"
                v-model="editForm.campaign_name"
                class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
              />
              <dd v-else class="text-sm text-n-slate-12 flex-1 text-right">
                {{ lead.campaign?.name || '—' }}
              </dd>
            </div>
            <!-- Affiliate (read-only) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.AFFILIATE') }}
              </dt>
              <dd class="text-sm text-n-slate-12 flex-1 text-right">
                {{
                  lead.affiliate_name || t('JABVOX_LEADS.TABLE.AFFILIATE_OWN')
                }}
              </dd>
            </div>
            <!-- Inbox (read-only) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.INBOX') }}
              </dt>
              <dd class="text-sm text-n-slate-12 flex-1 text-right">
                {{ lead.inbox_name || '—' }}
              </dd>
            </div>
            <!-- Assignee (editable) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.ASSIGNEE') }}
              </dt>
              <select
                v-if="isEditing"
                v-model="editForm.assignee_id"
                class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
              >
                <option :value="null">—</option>
                <option v-for="a in assignees" :key="a.id" :value="a.id">
                  {{ a.name }}
                </option>
              </select>
              <dd v-else class="text-sm text-n-slate-12 flex-1 text-right">
                {{ lead.assignee_name || '—' }}
              </dd>
            </div>
            <!-- Last management (read-only, comes from notes) -->
            <div
              v-if="lead.last_management_state"
              class="flex items-center gap-2 px-3 py-2.5"
            >
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.MANAGEMENT_STATE') }}
              </dt>
              <dd class="flex-1 text-right">
                <span
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-n-brand/10 text-n-brand"
                >
                  {{ lead.last_management_state }}
                </span>
              </dd>
            </div>
            <!-- Created at (read-only) -->
            <div class="flex items-center gap-2 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 w-24 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.CREATED_AT') }}
              </dt>
              <dd class="text-sm text-n-slate-12 flex-1 text-right">
                {{ formatDate(lead.created_at) }}
              </dd>
            </div>
            <!-- Biografía (read-only, mapeada desde description) — siempre visible -->
            <div class="flex flex-col gap-1 px-3 py-2.5">
              <dt class="text-xs text-n-slate-10 shrink-0">
                {{ t('JABVOX_LEADS.DETAIL.INFO.BIOGRAPHY') }}
              </dt>
              <dd
                class="text-sm text-n-slate-12 whitespace-pre-line break-words"
              >
                {{ contactBiography || '—' }}
              </dd>
            </div>
          </dl>
        </div>
        <!-- Custom fields inline (tabla vinculada a leads) -->
        <div
          v-if="isCustomizationEnabled && leadsTableColumns.length"
          class="rounded-xl border border-n-weak bg-n-background overflow-hidden"
        >
          <button
            type="button"
            class="w-full flex items-center gap-2 px-3 py-2.5 text-left hover:bg-n-alpha-1 transition-colors"
            @click="toggleSection('custom')"
          >
            <span
              class="size-4 shrink-0 text-n-slate-10 transition-transform"
              :class="
                sectionsCollapsed.custom
                  ? 'i-lucide-chevron-right'
                  : 'i-lucide-chevron-down'
              "
            />
            <span
              class="text-xs font-semibold text-n-slate-11 uppercase tracking-wide truncate"
            >
              {{ leadsTable.name_jabvox }}
            </span>
          </button>

          <div
            v-show="!sectionsCollapsed.custom"
            class="p-3 pt-0 space-y-2.5 border-t border-n-weak"
          >
            <!-- Field search -->
            <div class="relative pt-3">
              <span
                class="i-lucide-search absolute left-2.5 top-1/2 -translate-y-1/2 mt-1.5 size-3.5 text-n-slate-10 pointer-events-none"
              />
              <input
                v-model="fieldSearch"
                type="search"
                :placeholder="t('JABVOX_LEADS.DETAIL.SEARCH_FIELDS')"
                class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 pl-8 pr-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
              />
            </div>

            <dl class="space-y-2.5">
              <p
                v-if="!filteredLeadsColumns.length"
                class="text-xs text-n-slate-10 py-2 text-center"
              >
                {{ t('JABVOX_LEADS.DETAIL.NO_FIELDS_MATCH') }}
              </p>
              <div v-for="col in filteredLeadsColumns" :key="col.id">
                <dt class="text-xs text-n-slate-10 mb-1">
                  {{ col.label_jabvox }}
                </dt>
                <dd>
                  <!-- Read-only view -->
                  <span v-if="!isEditing" class="text-sm text-n-slate-12">
                    <template v-if="col.column_type_jabvox === 'boolean'">
                      {{
                        lead.custom_fields_jabvox?.[col.name_jabvox]
                          ? t('JABVOX_LEADS.DETAIL.YES')
                          : t('JABVOX_LEADS.DETAIL.NO')
                      }}
                    </template>
                    <template v-else>
                      {{ lead.custom_fields_jabvox?.[col.name_jabvox] || '—' }}
                    </template>
                  </span>
                  <!-- boolean -->
                  <input
                    v-else-if="col.column_type_jabvox === 'boolean'"
                    v-model="editForm.custom[col.name_jabvox]"
                    type="checkbox"
                    class="reset-base size-4 rounded border-n-weak text-n-brand focus:outline-none focus:border-n-slate-7"
                  />
                  <!-- select -->
                  <select
                    v-else-if="col.column_type_jabvox === 'select'"
                    v-model="editForm.custom[col.name_jabvox]"
                    class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
                  >
                    <option value="">—</option>
                    <option
                      v-for="opt in col.options_jabvox || []"
                      :key="opt"
                      :value="opt"
                    >
                      {{ opt }}
                    </option>
                  </select>
                  <!-- date -->
                  <input
                    v-else-if="col.column_type_jabvox === 'date'"
                    v-model="editForm.custom[col.name_jabvox]"
                    type="date"
                    class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
                  />
                  <!-- text / integer / float -->
                  <input
                    v-else
                    v-model="editForm.custom[col.name_jabvox]"
                    :type="
                      col.column_type_jabvox === 'integer' ||
                      col.column_type_jabvox === 'float'
                        ? 'number'
                        : 'text'
                    "
                    :step="col.column_type_jabvox === 'float' ? '0.01' : '1'"
                    class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
                  />
                </dd>
              </div>
            </dl>
          </div>
        </div>

        <div v-if="lead.contact" class="pt-1">
          <JabvoxQuickButtons :lead="lead" :contact="lead.contact" />
        </div>
      </div>

      <!-- Right panel: tabs -->
      <div class="flex-1 flex flex-col min-w-0 min-h-0 bg-n-background">
        <!-- Tab bar -->
        <div
          class="shrink-0 border-b border-n-weak bg-n-solid-1 flex items-center gap-1 px-4"
        >
          <button
            v-for="tab in availableTabs"
            :key="tab"
            class="px-3.5 py-3 text-sm font-medium border-b-2 -mb-px transition-colors"
            :class="
              activeTab === tab
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
            "
            @click="activeTab = tab"
          >
            {{ t(`JABVOX_LEADS.DETAIL.TABS.${tab.toUpperCase()}`) }}
          </button>
          <div class="flex-1" />
          <JabvoxCallButton
            v-if="lead.contact.phone_number || lead.contact.id"
            :phone="lead.contact.phone_number || ''"
            :contact-id="lead.contact.id"
            :lead-id="Number(leadId) || null"
            :contact-name="lead.contact.name"
            show-label
          />
          <JabvoxSmsButton
            v-if="lead.contact.phone_number && lead.contact.id"
            :phone="lead.contact.phone_number"
            :contact-id="lead.contact.id"
            show-label
          />
          <JabvoxEmailButton
            v-if="lead.contact.email && lead.contact.id"
            :email="lead.contact.email"
            :contact-id="lead.contact.id"
            show-label
          />
        </div>

        <!-- ── CHAT TAB ── -->
        <template v-if="activeTab === 'chat'">
          <div
            v-if="!lead.conversation_display_id"
            class="flex-1 min-h-0 overflow-y-auto flex flex-col items-center px-6 py-10 gap-5"
          >
            <div
              class="size-14 shrink-0 rounded-2xl bg-n-brand/10 flex items-center justify-center mt-auto"
            >
              <span class="i-lucide-message-circle-plus size-7 text-n-brand" />
            </div>
            <div class="text-center max-w-xs shrink-0">
              <p class="text-sm font-semibold text-n-slate-12 mb-1">
                {{ t('JABVOX_LEADS.DETAIL.CONTACT_VIA') }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{ t('JABVOX_LEADS.DETAIL.CONTACT_VIA_HINT') }}
              </p>
            </div>
            <div class="w-full max-w-sm space-y-3 shrink-0 mb-auto">
              <select
                v-model="selectedInboxId"
                class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
              >
                <option :value="null" disabled>
                  {{ t('JABVOX_LEADS.DETAIL.SELECT_INBOX') }}
                </option>
                <option
                  v-for="inbox in inboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
              <!-- WhatsApp API: primer contacto solo por plantilla aprobada -->
              <template v-if="requiresTemplate">
                <div v-if="!selectedTemplate" class="text-left">
                  <p class="text-xs text-n-slate-10 mb-2">
                    {{ t('JABVOX_LEADS.DETAIL.WHATSAPP_TEMPLATE_HINT') }}
                  </p>
                  <TemplatesPicker
                    :inbox-id="Number(selectedInboxId)"
                    @on-select="selectedTemplate = $event"
                  />
                </div>
                <div v-else class="text-left">
                  <WhatsAppTemplateReply
                    :template="selectedTemplate"
                    :contact-id="lead.contact.id"
                    @send-message="handleTemplateSend"
                    @reset-template="selectedTemplate = null"
                  />
                </div>
              </template>

              <!-- Resto de canales: mensaje libre opcional -->
              <template v-else>
                <textarea
                  v-model="initialMessage"
                  rows="2"
                  :placeholder="
                    t('JABVOX_LEADS.DETAIL.INITIAL_MESSAGE_PLACEHOLDER')
                  "
                  class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:border-n-slate-7 transition-colors resize-none"
                />
                <Button
                  :label="
                    isStarting
                      ? t('JABVOX_LEADS.DETAIL.STARTING')
                      : t('JABVOX_LEADS.DETAIL.START_CONVERSATION')
                  "
                  icon="i-lucide-send"
                  :disabled="!selectedInboxId || isStarting"
                  class="w-full justify-center"
                  @click="startConversation"
                />
              </template>
            </div>
          </div>
          <template v-else>
            <div
              ref="chatContainer"
              class="flex-1 overflow-y-auto px-4 py-4 space-y-3 min-h-0"
            >
              <div
                v-if="isLoadingMessages"
                class="flex items-center justify-center gap-2 py-8 text-sm text-n-slate-10 animate-pulse"
              >
                <span class="i-lucide-loader-circle size-4 animate-spin" />
                {{ t('JABVOX_LEADS.DETAIL.LOADING_MESSAGES') }}
              </div>
              <template v-else>
                <div
                  v-for="msg in sortedMessages"
                  :key="msg.id"
                  class="flex flex-col gap-1"
                  :class="msgAlignClass(msg)"
                >
                  <div
                    v-if="msg.content"
                    class="max-w-[85%] rounded-2xl px-3.5 py-2 text-sm whitespace-pre-wrap break-words shadow-sm"
                    :class="msgBubbleClass(msg)"
                  >
                    <div
                      v-if="isPrivateNote(msg)"
                      class="flex items-center gap-1 mb-1 text-xs text-n-amber-11 font-medium"
                    >
                      <span class="i-lucide-sticky-note size-3.5" />
                      {{ t('JABVOX_LEADS.DETAIL.NOTE_LABEL') }}
                    </div>
                    <div
                      v-if="
                        isPrivateNote(msg) &&
                        msg.content_attributes?.jabvox_management_state_name
                      "
                      class="inline-flex items-center gap-1 mb-1 px-2 py-0.5 rounded-full text-[11px] font-semibold text-white"
                      :style="{
                        backgroundColor:
                          msg.content_attributes
                            .jabvox_management_state_color || '#6b7280',
                      }"
                    >
                      {{ msg.content_attributes.jabvox_management_state_name }}
                    </div>
                    {{ msg.content }}
                  </div>
                  <span class="text-[11px] text-n-slate-10 px-1">
                    {{ formatTime(msg.created_at) }}
                  </span>
                </div>
                <div
                  v-if="sortedMessages.length === 0"
                  class="flex flex-col items-center justify-center gap-2 py-10 text-sm text-n-slate-10"
                >
                  <span
                    class="i-lucide-messages-square size-7 text-n-slate-9"
                  />
                  {{ t('JABVOX_LEADS.DETAIL.NO_MESSAGES') }}
                </div>
              </template>
            </div>

            <div
              class="shrink-0 border-t border-n-weak bg-n-solid-1 p-3 space-y-2"
            >
              <div class="flex gap-2">
                <button
                  class="text-xs px-2.5 py-1 rounded-md font-medium transition-colors"
                  :class="
                    !isNoteMode
                      ? 'bg-n-brand text-white'
                      : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="isNoteMode = false"
                >
                  {{ t('JABVOX_LEADS.DETAIL.REPLY') }}
                </button>
                <button
                  class="text-xs px-2.5 py-1 rounded-md font-medium transition-colors"
                  :class="
                    isNoteMode
                      ? 'bg-n-amber-9 text-white'
                      : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="isNoteMode = true"
                >
                  {{ t('JABVOX_LEADS.DETAIL.ADD_NOTE') }}
                </button>
              </div>
              <!-- Gestión removed from the chat note: it's captured in the
                   Notes tab instead. Chat private notes are plain text. -->
              <div v-if="false" class="space-y-2">
                <!-- Two-level picker: Estado (grupo) → Subestado -->
                <template v-if="managementHasGroups">
                  <div class="flex items-center gap-2">
                    <label
                      class="text-xs font-medium text-n-slate-11 whitespace-nowrap shrink-0"
                    >
                      {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.GROUP_LABEL') }}
                    </label>
                    <select
                      v-model="managementGroup"
                      class="reset-base flex-1 rounded-lg border text-xs px-2.5 py-1.5 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
                      :class="
                        managementGroup !== null
                          ? 'border-n-weak'
                          : 'border-n-amber-6'
                      "
                    >
                      <option :value="null" disabled>
                        {{
                          t(
                            'JABVOX_MANAGEMENT_STATES.REPLY_BOX.GROUP_PLACEHOLDER'
                          )
                        }}
                      </option>
                      <option v-for="g in managementGroups" :key="g" :value="g">
                        {{ g || t('JABVOX_MANAGEMENT_STATES.UNGROUPED') }}
                      </option>
                    </select>
                  </div>
                  <div class="flex items-center gap-2">
                    <label
                      class="text-xs font-medium text-n-slate-11 whitespace-nowrap shrink-0"
                    >
                      {{
                        t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_LABEL')
                      }}
                    </label>
                    <select
                      v-model="managementStateId"
                      :disabled="managementGroup === null"
                      class="reset-base flex-1 rounded-lg border text-xs px-2.5 py-1.5 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors disabled:opacity-60"
                      :class="
                        managementStateId ? 'border-n-weak' : 'border-n-amber-6'
                      "
                    >
                      <option :value="null" disabled>
                        {{
                          t(
                            'JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_PLACEHOLDER'
                          )
                        }}
                      </option>
                      <option
                        v-for="s in managementGroupStates"
                        :key="s.id"
                        :value="s.id"
                      >
                        {{ s.name_jabvox }}
                      </option>
                    </select>
                  </div>
                </template>
                <!-- Flat picker (accounts without groups) -->
                <div v-else class="flex items-center gap-2">
                  <label
                    class="text-xs font-medium text-n-slate-11 whitespace-nowrap shrink-0"
                  >
                    {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.LABEL') }}
                  </label>
                  <select
                    v-model="managementStateId"
                    class="reset-base flex-1 rounded-lg border text-xs px-2.5 py-1.5 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
                    :class="
                      managementStateId ? 'border-n-weak' : 'border-n-amber-6'
                    "
                  >
                    <option :value="null" disabled>
                      {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.PLACEHOLDER') }}
                    </option>
                    <option
                      v-for="s in managementStates"
                      :key="s.id"
                      :value="s.id"
                    >
                      {{ s.name_jabvox }}
                    </option>
                  </select>
                </div>
                <p
                  v-if="selectedManagementState?.usage_info_jabvox"
                  class="text-xs text-n-slate-10"
                >
                  {{ selectedManagementState.usage_info_jabvox }}
                </p>
              </div>
              <ManagementQuestionsForm
                v-if="isNoteMode && selectedManagementState"
                v-model="managementAnswers"
                :state="selectedManagementState"
                :contact="lead?.contact"
                :lead="lead"
                class="mt-2"
              />
              <!-- Panel de plantilla dentro de la conversación abierta -->
              <div
                v-if="showTemplatePanel && !isNoteMode"
                class="max-h-[22rem] overflow-y-auto rounded-lg border border-n-weak bg-n-alpha-1 p-3"
              >
                <div v-if="!panelTemplate">
                  <p class="text-xs text-n-slate-10 mb-2">
                    {{ t('JABVOX_LEADS.DETAIL.WHATSAPP_TEMPLATE_HINT') }}
                  </p>
                  <TemplatesPicker
                    :inbox-id="Number(conversationInboxId)"
                    @on-select="panelTemplate = $event"
                  />
                </div>
                <div v-else class="text-left">
                  <WhatsAppTemplateReply
                    :template="panelTemplate"
                    :contact-id="lead.contact.id"
                    @send-message="handleTemplateSendToConversation"
                    @reset-template="panelTemplate = null"
                  />
                </div>
              </div>
              <div class="flex gap-2 items-end">
                <button
                  v-if="!isNoteMode && canSendTemplateInConversation"
                  type="button"
                  :title="t('JABVOX_LEADS.DETAIL.SEND_TEMPLATE')"
                  class="reset-base shrink-0 size-9 rounded-lg border flex items-center justify-center transition-colors"
                  :class="
                    showTemplatePanel
                      ? 'border-n-brand bg-n-brand/10 text-n-brand'
                      : 'border-n-weak text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="toggleTemplatePanel"
                >
                  <span class="i-ri-whatsapp-line size-5" />
                </button>
                <textarea
                  v-model="newMessage"
                  rows="2"
                  :placeholder="
                    isNoteMode
                      ? t('JABVOX_LEADS.DETAIL.NOTE_PLACEHOLDER')
                      : t('JABVOX_LEADS.DETAIL.MESSAGE_PLACEHOLDER')
                  "
                  class="reset-base flex-1 resize-none rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-3 py-2 focus:outline-none focus:border-n-slate-7 transition-colors placeholder-n-slate-9"
                  @keydown="onChatKeydown"
                />
                <Button
                  size="small"
                  :is-loading="isSending"
                  :disabled="!newMessage.trim()"
                  icon="i-lucide-send"
                  @click="sendMessage(isNoteMode)"
                />
              </div>
            </div>
          </template>
        </template>

        <!-- ── NOTES TAB (private notes only) ── -->
        <template v-else-if="activeTab === 'notes'">
          <div class="flex flex-col flex-1 min-h-0 overflow-hidden">
            <div
              ref="notesContainer"
              class="flex-1 overflow-y-auto px-4 py-4 space-y-3 min-h-0"
            >
              <div
                v-if="isLoadingMessages"
                class="flex items-center justify-center gap-2 py-8 text-sm text-n-slate-10 animate-pulse"
              >
                <span class="i-lucide-loader-circle size-4 animate-spin" />
                {{ t('JABVOX_LEADS.DETAIL.LOADING_MESSAGES') }}
              </div>
              <template v-else>
                <!-- Lista ÚNICA de gestiones: notas privadas de TODAS las
                     conversaciones del contacto + notas de contacto, sin importar
                     el origen. unifiedNotes normaliza todo a snake_case. -->
                <div
                  v-for="note in unifiedNotes"
                  :key="note.key"
                  class="flex flex-col gap-1 items-start"
                >
                  <div
                    v-if="note.content"
                    class="max-w-[85%] rounded-2xl px-3.5 py-2 text-sm whitespace-pre-wrap break-words bg-n-amber-3 border border-n-amber-6 text-n-amber-11 shadow-sm"
                    :class="
                      noteHasDetails(note.content_attributes)
                        ? 'cursor-pointer hover:bg-n-amber-4 transition-colors'
                        : ''
                    "
                    @click="
                      noteHasDetails(note.content_attributes) &&
                        toggleNoteExpanded(note.key)
                    "
                  >
                    <div
                      v-if="
                        note.content_attributes?.jabvox_management_state_name
                      "
                      class="inline-flex items-center gap-1 mb-1 px-2 py-0.5 rounded-full text-[11px] font-semibold text-white"
                      :style="{
                        backgroundColor:
                          note.content_attributes
                            .jabvox_management_state_color || '#6b7280',
                      }"
                    >
                      {{ note.content_attributes.jabvox_management_state_name }}
                    </div>
                    <!-- Origen (marcador / click-to-call / kanban / conversaciones
                         / detalle) + tipificación -->
                    <div
                      v-if="
                        callSourceLabel(note.content_attributes) ||
                        typificationBadge(note.content_attributes)
                      "
                      class="flex flex-wrap gap-1 mb-1"
                    >
                      <span
                        v-if="typificationBadge(note.content_attributes)"
                        class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold bg-n-teal-3 text-n-teal-11 border border-n-teal-6"
                      >
                        <span class="i-lucide-tag size-3" />
                        {{ typificationBadge(note.content_attributes) }}
                      </span>
                      <span
                        v-if="callSourceLabel(note.content_attributes)"
                        class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium bg-n-alpha-2 text-n-slate-11 border border-n-weak"
                      >
                        <span class="i-lucide-phone-outgoing size-3" />
                        {{ callSourceLabel(note.content_attributes) }}
                      </span>
                    </div>
                    {{ note.content }}
                    <!-- Indicador de expandible + detalle de la gestión -->
                    <div
                      v-if="noteHasDetails(note.content_attributes)"
                      class="flex items-center gap-1 mt-1 text-[11px] font-medium text-n-amber-11/80 select-none"
                    >
                      <span
                        class="size-3 transition-transform"
                        :class="
                          expandedNotes.has(note.key)
                            ? 'i-lucide-chevron-down'
                            : 'i-lucide-chevron-right'
                        "
                      />
                      {{
                        expandedNotes.has(note.key)
                          ? t('JABVOX_LEADS.DETAIL.HIDE_GESTION_DETAILS')
                          : t('JABVOX_LEADS.DETAIL.SHOW_GESTION_DETAILS')
                      }}
                    </div>
                    <div
                      v-if="expandedNotes.has(note.key)"
                      class="mt-2 pt-2 border-t border-n-amber-6 space-y-1.5"
                      @click.stop
                    >
                      <div
                        v-if="noteGroup(note.content_attributes)"
                        class="text-xs"
                      >
                        <span class="font-semibold">
                          {{ t('JABVOX_LEADS.DETAIL.GESTION_GROUP') }}:
                        </span>
                        {{ noteGroup(note.content_attributes) }}
                      </div>
                      <div
                        v-for="ans in noteAnswers(note.content_attributes)"
                        :key="ans.question_id ?? ans.questionId ?? ans.label"
                        class="text-xs"
                      >
                        <span class="font-semibold">{{ ans.label }}:</span>
                        {{ answerDisplay(ans.value) }}
                      </div>
                      <p
                        v-if="!noteAnswers(note.content_attributes).length"
                        class="text-xs italic text-n-amber-11/70"
                      >
                        {{ t('JABVOX_LEADS.DETAIL.NO_GESTION_ANSWERS') }}
                      </p>
                    </div>
                  </div>
                  <span class="text-[11px] text-n-slate-10 px-1">
                    {{ formatTime(note.created_at) }}
                  </span>
                </div>
                <div
                  v-if="unifiedNotes.length === 0"
                  class="flex flex-col items-center justify-center gap-2 py-10 text-sm text-n-slate-10"
                >
                  <span class="i-lucide-sticky-note size-7 text-n-slate-9" />
                  {{ t('JABVOX_LEADS.DETAIL.NO_NOTES') }}
                </div>
              </template>
            </div>

            <div
              class="shrink-0 border-t border-n-weak bg-n-solid-1 p-3 space-y-2"
            >
              <div v-if="managementStates.length > 0" class="space-y-2">
                <!-- Two-level picker: Estado (grupo) → Subestado -->
                <template v-if="managementHasGroups">
                  <div class="flex items-center gap-2">
                    <label
                      class="text-xs font-medium text-n-slate-11 whitespace-nowrap shrink-0"
                    >
                      {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.GROUP_LABEL') }}
                    </label>
                    <select
                      v-model="managementGroup"
                      class="reset-base flex-1 rounded-lg border text-xs px-2.5 py-1.5 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
                      :class="
                        managementGroup !== null
                          ? 'border-n-weak'
                          : 'border-n-amber-6'
                      "
                    >
                      <option :value="null" disabled>
                        {{
                          t(
                            'JABVOX_MANAGEMENT_STATES.REPLY_BOX.GROUP_PLACEHOLDER'
                          )
                        }}
                      </option>
                      <option v-for="g in managementGroups" :key="g" :value="g">
                        {{ g || t('JABVOX_MANAGEMENT_STATES.UNGROUPED') }}
                      </option>
                    </select>
                  </div>
                  <div class="flex items-center gap-2">
                    <label
                      class="text-xs font-medium text-n-slate-11 whitespace-nowrap shrink-0"
                    >
                      {{
                        t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_LABEL')
                      }}
                    </label>
                    <select
                      v-model="managementStateId"
                      :disabled="managementGroup === null"
                      class="reset-base flex-1 rounded-lg border text-xs px-2.5 py-1.5 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors disabled:opacity-60"
                      :class="
                        managementStateId ? 'border-n-weak' : 'border-n-amber-6'
                      "
                    >
                      <option :value="null" disabled>
                        {{
                          t(
                            'JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_PLACEHOLDER'
                          )
                        }}
                      </option>
                      <option
                        v-for="s in managementGroupStates"
                        :key="s.id"
                        :value="s.id"
                      >
                        {{ s.name_jabvox }}
                      </option>
                    </select>
                  </div>
                </template>
                <!-- Flat picker (accounts without groups) -->
                <div v-else class="flex items-center gap-2">
                  <label
                    class="text-xs font-medium text-n-slate-11 whitespace-nowrap shrink-0"
                  >
                    {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.LABEL') }}
                  </label>
                  <select
                    v-model="managementStateId"
                    class="reset-base flex-1 rounded-lg border text-xs px-2.5 py-1.5 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
                    :class="
                      managementStateId ? 'border-n-weak' : 'border-n-amber-6'
                    "
                  >
                    <option :value="null" disabled>
                      {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.PLACEHOLDER') }}
                    </option>
                    <option
                      v-for="s in managementStates"
                      :key="s.id"
                      :value="s.id"
                    >
                      {{ s.name_jabvox }}
                    </option>
                  </select>
                </div>
                <p
                  v-if="selectedManagementState?.usage_info_jabvox"
                  class="text-xs text-n-slate-10"
                >
                  {{ selectedManagementState.usage_info_jabvox }}
                </p>
              </div>
              <ManagementQuestionsForm
                v-if="selectedManagementState"
                v-model="managementAnswers"
                :state="selectedManagementState"
                :contact="lead?.contact"
                :lead="lead"
                class="mt-2"
              />
              <div class="flex gap-2 items-end">
                <!-- La nota sigue el note_mode del tipo de gestión: oculta no se
                     muestra; opcional permite guardar sin texto (cae al nombre
                     de la gestión); requerida exige texto. -->
                <textarea
                  v-if="!(selectedManagementState && gestionNoteRule.hidden)"
                  v-model="newMessage"
                  rows="2"
                  :placeholder="
                    selectedManagementState && !gestionNoteRule.required
                      ? t('JABVOX_LEADS.DETAIL.NOTE_OPTIONAL_PLACEHOLDER')
                      : t('JABVOX_LEADS.DETAIL.NOTE_PLACEHOLDER')
                  "
                  class="reset-base flex-1 resize-none rounded-lg border border-n-amber-6 bg-n-amber-3 text-sm text-n-amber-11 px-3 py-2 focus:outline-none focus:border-n-amber-8 transition-colors placeholder-n-amber-11/60"
                  @keydown="onGestionNoteKeydown"
                />
                <span
                  v-else
                  class="flex-1 text-xs text-n-slate-10 italic self-center"
                >
                  {{ t('JABVOX_LEADS.DETAIL.NOTE_HIDDEN_HINT') }}
                </span>
                <Button
                  size="small"
                  :is-loading="isSending"
                  :disabled="!canSaveGestionNote"
                  icon="i-lucide-sticky-note"
                  @click="sendMessage(true, true)"
                />
              </div>
            </div>
          </div>
        </template>

        <!-- ── PRODUCTS TAB ── -->
        <div
          v-else-if="activeTab === 'products'"
          class="flex-1 overflow-y-auto"
        >
          <JabvoxConversationProducts
            :contact-id="lead.contact.id"
            :conversation-id="lead.conversation_id"
          />
        </div>

        <!-- ── HISTORY TAB ── -->
        <div v-else-if="activeTab === 'history'" class="flex-1 overflow-y-auto">
          <JabvoxConversationHistory
            :contact-id="lead.contact.id"
            :conversation-id="lead.conversation_id"
          />
        </div>

        <!-- ── RECORDS TAB (multi-row custom tables: Asesorías, Casos…) ── -->
        <div v-else-if="activeTab === 'records'" class="flex-1 overflow-y-auto">
          <JabvoxLeadTableRows :lead-id="Number(leadId)" />
        </div>
      </div>
    </div>
  </div>
</template>
