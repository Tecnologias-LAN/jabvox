<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import {
  wtInboxesAPI,
  wtTemplatesAPI,
} from 'dashboard/api/jabvox/whatsappTemplates';
import { wfFlowsAPI } from 'dashboard/api/jabvox/whatsappFlows';
import { processVariable } from 'dashboard/helper/templateHelper';
import ConfirmDialog from './components/ConfirmDialog.vue';
import PromptDialog from './components/PromptDialog.vue';
import InlineFlowBuilder from './components/InlineFlowBuilder.vue';
import { getComponentMeta } from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/componentCatalog';
import FlowPreview from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/components/FlowPreview.vue';
import { useTemplateValidation } from './composables/useTemplateValidation';

const { t } = useI18n();

// ─── Tabs ────────────────────────────────────────────────────────────────────
const activeTab = ref('templates');
const stickyHeaderRef = ref(null);

// Confirmation / prompt dialogs (replace native window.confirm / window.prompt).
const confirmDialog = ref(null);
const promptDialog = ref(null);

// ─── Inboxes ─────────────────────────────────────────────────────────────────
const inboxes = ref([]);
const selectedInboxId = ref(null);
const syncing = ref(false);

const loadInboxes = async () => {
  try {
    const { data } = await wtInboxesAPI.getAll();
    inboxes.value = data.inboxes || [];
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

// ─── Metrics ─────────────────────────────────────────────────────────────────
const metrics = ref({});

const loadMetrics = async () => {
  try {
    // Account-wide KPI totals; the inbox selector only filters the template list.
    const { data } = await wtInboxesAPI.metrics();
    metrics.value = data;
  } catch {
    /* non-blocking */
  }
};

// ─── Filters ─────────────────────────────────────────────────────────────────
const filters = ref({
  q: '',
  meta_id: '',
  status: '',
  category: '',
  language: '',
  date_from: '',
  date_to: '',
});
const page = ref(1);
const perPage = 50;

const apiFilters = computed(() => {
  const f = { page: page.value, per_page: perPage };
  if (selectedInboxId.value) f.inbox_id = selectedInboxId.value;
  Object.entries(filters.value).forEach(([k, v]) => {
    if (v) f[k] = v;
  });
  return f;
});

// ─── Templates list ──────────────────────────────────────────────────────────
const templates = ref([]);
const totalTemplates = ref(0);
const loadingTemplates = ref(false);
// Filter panel starts expanded; the header toggles it to free up vertical space.
const filtersExpanded = ref(true);

const totalPages = computed(
  () => Math.ceil(totalTemplates.value / perPage) || 1
);

const loadTemplates = async () => {
  loadingTemplates.value = true;
  try {
    const { data } = await wtTemplatesAPI.getAll(apiFilters.value);
    templates.value = data.templates || [];
    totalTemplates.value = data.total || 0;
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    loadingTemplates.value = false;
  }
};

// Sync all WhatsApp Cloud inboxes with Meta — works without selecting an inbox — then reload
// so approved/rejected statuses show right away.
const syncAll = async () => {
  syncing.value = true;
  try {
    await wtInboxesAPI.syncAll();
    useAlert(t('JABVOX_WA_TEMPLATES.SYNCED'));
    await loadTemplates();
    await loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    syncing.value = false;
  }
};

// Sync a single inbox (used by the per-inbox button in the overview cards).
const syncOneInbox = async inboxId => {
  syncing.value = true;
  try {
    await wtInboxesAPI.sync(inboxId);
    useAlert(t('JABVOX_WA_TEMPLATES.SYNCED'));
    await loadTemplates();
    await loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    syncing.value = false;
  }
};

const clearFilters = () => {
  filters.value = {
    q: '',
    meta_id: '',
    status: '',
    category: '',
    language: '',
    date_from: '',
    date_to: '',
  };
  page.value = 1;
  loadTemplates();
};

const summaryKpis = computed(() => {
  const m = metrics.value || {};
  const usage = m.usage_this_month || m.sent_this_month || m.sent || 0;
  return [
    {
      key: 'total',
      label: t('JABVOX_WA_TEMPLATES.METRICS.TOTAL'),
      value: m.total ?? 0,
      icon: 'i-lucide-layout-template',
      accent: 'text-n-brand',
    },
    {
      key: 'approved',
      label: t('JABVOX_WA_TEMPLATES.METRICS.APPROVED'),
      value: m.approved ?? 0,
      icon: 'i-lucide-badge-check',
      accent: 'text-n-teal-11',
    },
    {
      key: 'pending',
      label: t('JABVOX_WA_TEMPLATES.METRICS.PENDING'),
      value: m.pending ?? 0,
      icon: 'i-lucide-clock-3',
      accent: 'text-n-amber-11',
    },
    {
      key: 'rejected',
      label: t('JABVOX_WA_TEMPLATES.METRICS.REJECTED'),
      value: m.rejected ?? 0,
      icon: 'i-lucide-shield-x',
      accent: 'text-n-ruby-11',
    },
    {
      key: 'disabled',
      label: t('JABVOX_WA_TEMPLATES.METRICS.DISABLED'),
      value: m.disabled ?? 0,
      icon: 'i-lucide-pause-circle',
      accent: 'text-n-slate-10',
    },
    {
      key: 'usage_month',
      label: t('JABVOX_WA_TEMPLATES.METRICS.USAGE_MONTH'),
      value: usage,
      icon: 'i-lucide-chart-column',
      accent: 'text-n-brand',
    },
  ];
});

// Decorative symbols rendered via bindings so they are not flagged as
// untranslatable raw text (they carry no linguistic meaning).
const DOT = '·';
const DASH = '—';
const VAR_OPEN = '{{';
const VAR_CLOSE = '}}';
const VERSION_PREFIX = 'v';

const mainTabs = computed(() => [
  { key: 'overview', label: t('JABVOX_WA_TEMPLATES.TABS.OVERVIEW') },
  { key: 'templates', label: t('JABVOX_WA_TEMPLATES.TABS.TEMPLATES') },
]);

const overviewMetrics = computed(() => [
  { key: 'total', label: t('JABVOX_WA_TEMPLATES.METRICS.TOTAL') },
  { key: 'approved', label: t('JABVOX_WA_TEMPLATES.METRICS.APPROVED') },
  { key: 'pending', label: t('JABVOX_WA_TEMPLATES.METRICS.PENDING') },
  { key: 'rejected', label: t('JABVOX_WA_TEMPLATES.METRICS.REJECTED') },
  { key: 'paused', label: t('JABVOX_WA_TEMPLATES.METRICS.PAUSED') },
  { key: 'disabled', label: t('JABVOX_WA_TEMPLATES.METRICS.DISABLED') },
  { key: 'quality_high', label: t('JABVOX_WA_TEMPLATES.METRICS.QUALITY_HIGH') },
  {
    key: 'quality_medium',
    label: t('JABVOX_WA_TEMPLATES.METRICS.QUALITY_MEDIUM'),
  },
  { key: 'quality_low', label: t('JABVOX_WA_TEMPLATES.METRICS.QUALITY_LOW') },
]);

const statusQuickFilters = [
  'APPROVED',
  'PENDING',
  'REJECTED',
  'DISABLED',
  'PAUSED',
];

const categoryQuickFilters = [
  'MARKETING',
  'UTILITY',
  'AUTHENTICATION',
  'SERVICE',
];

const selectedTemplateIds = ref([]);
const allVisibleSelected = computed(
  () =>
    templates.value.length > 0 &&
    selectedTemplateIds.value.length === templates.value.length
);

const toggleSelectAll = checked => {
  selectedTemplateIds.value = checked ? templates.value.map(tpl => tpl.id) : [];
};

const toggleSelectOne = (id, checked) => {
  if (checked) {
    if (!selectedTemplateIds.value.includes(id)) {
      selectedTemplateIds.value = [...selectedTemplateIds.value, id];
    }
    return;
  }
  selectedTemplateIds.value = selectedTemplateIds.value.filter(v => v !== id);
};

const selectedTemplates = computed(() =>
  templates.value.filter(tpl => selectedTemplateIds.value.includes(tpl.id))
);

const selectedCount = computed(() => selectedTemplateIds.value.length);

const filterChipActive = (kind, value) => {
  if (kind === 'status') return filters.value.status === value;
  return filters.value.category === value;
};

const applyFilters = () => {
  page.value = 1;
  loadTemplates();
};
const changePage = delta => {
  const n = page.value + delta;
  if (n < 1 || n > totalPages.value) return;
  page.value = n;
  loadTemplates();
};

const applyQuickFilter = (kind, value) => {
  const key = kind === 'status' ? 'status' : 'category';
  filters.value[key] = filters.value[key] === value ? '' : value;
  applyFilters();
};

const bulkSync = async () => {
  if (!selectedTemplates.value.length) return;
  try {
    await Promise.all(
      selectedTemplates.value.map(tpl => wtTemplatesAPI.sync(tpl.id))
    );
    useAlert(t('JABVOX_WA_TEMPLATES.SYNCED'));
    selectedTemplateIds.value = [];
    await loadTemplates();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const bulkDuplicate = async () => {
  if (!selectedTemplates.value.length) return;
  try {
    await Promise.all(
      selectedTemplates.value.map(tpl =>
        wtTemplatesAPI.duplicate(tpl.id, `${tpl.name}_copy_${Date.now()}`)
      )
    );
    useAlert(t('JABVOX_WA_TEMPLATES.DUPLICATED'));
    selectedTemplateIds.value = [];
    await loadTemplates();
    await loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

// ─── Status / quality helpers ────────────────────────────────────────────────
// Design-system status tokens (theme-aware, no hardcoded palette colors).
const statusClass = s => {
  switch ((s || '').toUpperCase()) {
    case 'APPROVED':
      return 'bg-n-teal-11/15 text-n-teal-11 ring-1 ring-inset ring-n-teal-11/30';
    case 'PENDING':
      return 'bg-n-amber-11/15 text-n-amber-11 ring-1 ring-inset ring-n-amber-11/30';
    case 'REJECTED':
      return 'bg-n-ruby-11/15 text-n-ruby-11 ring-1 ring-inset ring-n-ruby-11/30';
    case 'PAUSED':
      return 'bg-n-amber-11/15 text-n-amber-11 ring-1 ring-inset ring-n-amber-11/30';
    default:
      return 'bg-n-alpha-2 text-n-slate-11 ring-1 ring-inset ring-n-weak';
  }
};
const qualityClass = q => {
  switch ((q || '').toUpperCase()) {
    case 'GREEN':
      return 'text-n-teal-11';
    case 'YELLOW':
      return 'text-n-amber-11';
    case 'RED':
      return 'text-n-ruby-11';
    default:
      return 'text-n-slate-10';
  }
};

// Solid dot color used by the status quick-filter chips.
const statusDotClass = s => {
  switch ((s || '').toUpperCase()) {
    case 'APPROVED':
      return 'bg-n-teal-9';
    case 'PENDING':
      return 'bg-n-amber-9';
    case 'REJECTED':
      return 'bg-n-ruby-9';
    case 'PAUSED':
      return 'bg-n-amber-9';
    default:
      return 'bg-n-slate-9';
  }
};

// Icon for each quick-filter category chip.
const categoryIcon = c => {
  switch ((c || '').toUpperCase()) {
    case 'MARKETING':
      return 'i-lucide-megaphone';
    case 'UTILITY':
      return 'i-lucide-wrench';
    case 'AUTHENTICATION':
      return 'i-lucide-shield-check';
    case 'SERVICE':
      return 'i-lucide-headset';
    default:
      return 'i-lucide-tag';
  }
};

// True when any filter (text, ids, selects, chips) is currently set.
const hasActiveFilters = computed(() =>
  Object.values(filters.value).some(Boolean)
);

// ─── Localized label helpers (static keys, no dynamic-key lint warnings) ──────
const statusLabel = s => {
  switch ((s || '').toUpperCase()) {
    case 'APPROVED':
      return t('JABVOX_WA_TEMPLATES.STATUS.APPROVED');
    case 'PENDING':
      return t('JABVOX_WA_TEMPLATES.STATUS.PENDING');
    case 'REJECTED':
      return t('JABVOX_WA_TEMPLATES.STATUS.REJECTED');
    case 'PAUSED':
      return t('JABVOX_WA_TEMPLATES.STATUS.PAUSED');
    case 'DISABLED':
      return t('JABVOX_WA_TEMPLATES.STATUS.DISABLED');
    default:
      return s;
  }
};

const categoryLabel = c => {
  switch ((c || '').toUpperCase()) {
    case 'MARKETING':
      return t('JABVOX_WA_TEMPLATES.CATEGORIES.MARKETING');
    case 'UTILITY':
      return t('JABVOX_WA_TEMPLATES.CATEGORIES.UTILITY');
    case 'AUTHENTICATION':
      return t('JABVOX_WA_TEMPLATES.CATEGORIES.AUTHENTICATION');
    case 'SERVICE':
      return t('JABVOX_WA_TEMPLATES.CATEGORIES.SERVICE');
    default:
      return c;
  }
};

const templateKindHint = kind => {
  switch (kind) {
    case 'standard':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.STANDARD_HINT');
    case 'carousel':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.CAROUSEL_HINT');
    case 'flow':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.FLOW_HINT');
    default:
      return '';
  }
};

const templateKindDescriptionFor = kind => {
  switch (kind) {
    case 'standard':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.STANDARD_DESC');
    case 'carousel':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.CAROUSEL_DESC');
    case 'flow':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.FLOW_DESC');
    default:
      return '';
  }
};

const templateKindLabel = kind => {
  switch (kind) {
    case 'standard':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.STANDARD');
    case 'carousel':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.CAROUSEL');
    case 'authentication':
      return t('JABVOX_WA_TEMPLATES.CREATE.KIND.AUTHENTICATION');
    default:
      return kind;
  }
};

const qualityLabel = q => {
  switch ((q || '').toUpperCase()) {
    case 'GREEN':
      return t('JABVOX_WA_TEMPLATES.QUALITY.GREEN');
    case 'YELLOW':
      return t('JABVOX_WA_TEMPLATES.QUALITY.YELLOW');
    case 'RED':
      return t('JABVOX_WA_TEMPLATES.QUALITY.RED');
    default:
      return t('JABVOX_WA_TEMPLATES.QUALITY.UNKNOWN');
  }
};

const detailTabLabel = dt => {
  switch (dt) {
    case 'components':
      return t('JABVOX_WA_TEMPLATES.DETAIL.COMPONENTS');
    case 'variables':
      return t('JABVOX_WA_TEMPLATES.DETAIL.VARIABLES');
    case 'analytics':
      return t('JABVOX_WA_TEMPLATES.DETAIL.ANALYTICS');
    case 'history':
      return t('JABVOX_WA_TEMPLATES.DETAIL.HISTORY');
    case 'versions':
      return t('JABVOX_WA_TEMPLATES.DETAIL.VERSIONS');
    case 'meta_json':
      return t('JABVOX_WA_TEMPLATES.DETAIL.META_JSON');
    default:
      return dt;
  }
};

// ─── Template actions ─────────────────────────────────────────────────────────
const syncTemplate = async tpl => {
  try {
    await wtTemplatesAPI.sync(tpl.id);
    useAlert(t('JABVOX_WA_TEMPLATES.SYNCED'));
    loadTemplates();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

// ─── Create / Edit form ──────────────────────────────────────────────────────
const showForm = ref(false);
const editingTemplate = ref(null);
const formInboxId = ref(null);

// Nombre de la bandeja elegida, para confirmar visualmente sobre cuál se va a
// crear la plantilla (es la que la registra en Meta bajo su WABA).
const selectedFormInboxName = computed(() => {
  const inbox = inboxes.value.find(i => i.id === formInboxId.value);
  return inbox ? `${inbox.name} ${DASH} ${inbox.phone_number}` : '';
});
const saving = ref(false);
// Current step of the create/edit wizard (declared here so openCreate/openEdit
// can reset it without a forward reference).
const wizardStep = ref(1);

const LANGUAGES = [
  { value: 'es', label: 'Español' },
  { value: 'es_CO', label: 'Español (Colombia)' },
  { value: 'es_MX', label: 'Español (México)' },
  { value: 'es_AR', label: 'Español (Argentina)' },
  { value: 'en_US', label: 'English (US)' },
  { value: 'en_GB', label: 'English (UK)' },
  { value: 'pt_BR', label: 'Português (Brasil)' },
  { value: 'pt_PT', label: 'Português (Portugal)' },
  { value: 'fr', label: 'Français' },
  { value: 'de', label: 'Deutsch' },
];
const CATEGORIES = ['MARKETING', 'UTILITY', 'AUTHENTICATION'];
// FLOW no está aquí a propósito: ese botón no se elige de la lista, lo pone el
// sistema cuando el tipo de plantilla es Formulario (y su texto se edita en esa
// sección). Ofrecerlo suelto llevaría a una plantilla con un botón sin Flow.
const BUTTON_TYPES = [
  'QUICK_REPLY',
  'URL',
  'PHONE_NUMBER',
  'COPY_CODE',
  'VOICE_CALL',
];

const buttonTypeLabel = type =>
  t(`JABVOX_WA_TEMPLATES.CREATE.BUTTON_TYPES.${type}`);

// Dentro de una card de carrusel Meta solo admite estos tres.
const CARD_BUTTON_TYPES = ['QUICK_REPLY', 'URL', 'PHONE_NUMBER'];

const otpTypeLabel = type => t(`JABVOX_WA_TEMPLATES.CREATE.OTP_TYPES.${type}`);

const mediaTypeLabel = type =>
  t(`JABVOX_WA_TEMPLATES.CREATE.MEDIA_TYPES.${type}`);
// 'authentication' se deriva automáticamente al elegir esa categoría, no es una
// opción redundante en el selector de tipo de plantilla (sección 5 del diseño).
// Cada tipo se presenta como una tarjeta con icono y una línea que explica
// para qué sirve, en vez de un botón con solo el nombre.
const TEMPLATE_KIND_OPTIONS = [
  { key: 'standard', icon: 'i-lucide-message-square-text' },
  { key: 'carousel', icon: 'i-lucide-gallery-horizontal-end' },
  { key: 'flow', icon: 'i-lucide-clipboard-list' },
];
const OTP_TYPES = ['ONE_TAP', 'COPY_CODE', 'ZERO_TAP'];
// Categorías de Flow que admite Meta (distintas de las de plantilla). El valor
// viaja en inglés porque es lo que espera Meta; la etiqueta se traduce.
const FLOW_CATEGORIES = [
  'SURVEY',
  'LEAD_GENERATION',
  'APPOINTMENT_BOOKING',
  'CONTACT_US',
  'CUSTOMER_SUPPORT',
  'SIGN_UP',
  'SIGN_IN',
  'OTHER',
];

const flowCategoryLabel = category =>
  t(`JABVOX_WA_TEMPLATES.CREATE.FLOW.CATEGORIES.${category}`);
const CARD_MIN = 2;
const CARD_MAX = 10;
const CARD_HEADER_TYPES = ['IMAGE', 'VIDEO'];

// WhatsApp Flows publicados de la bandeja elegida en el formulario — se
// recargan cada vez que cambia formInboxId. El botón FLOW referencia el
// `meta_flow_id` de un JabvoxWhatsappFlow gestionado, nunca texto libre.
const publishedFlowsForInbox = ref([]);
const loadPublishedFlows = async inboxId => {
  if (!inboxId) {
    publishedFlowsForInbox.value = [];
    return;
  }
  try {
    const { data } = await wfFlowsAPI.getAll({
      status: 'published',
      inbox_id: inboxId,
    });
    publishedFlowsForInbox.value = data.flows || [];
  } catch {
    publishedFlowsForInbox.value = [];
  }
};
watch(formInboxId, id => loadPublishedFlows(id));
const HEADER_FORMATS = [
  'NONE',
  'TEXT',
  'IMAGE',
  'VIDEO',
  'DOCUMENT',
  'LOCATION',
];

const emptyAuthConfig = () => ({
  add_security_recommendation: false,
  code_expiration_minutes: 10,
  otp_type: 'COPY_CODE',
  supported_apps: [],
});

const emptyCard = () => ({
  header_type: 'IMAGE',
  header_handle: '',
  header_media_name: '',
  header_media_preview: '',
  body_content: '',
  buttons: [],
});

const emptyForm = () => ({
  name: '',
  category: 'UTILITY',
  language: 'es',
  template_kind: 'standard',
  header_type: 'NONE',
  header_content: '', // texto del header TEXT (o nombre del archivo, informativo)
  header_handle: '', // handle "h:..." devuelto por Meta al subir el media
  header_media_name: '', // nombre del archivo subido (documento)
  header_media_preview: '', // URL local (object URL) para la previa del media
  body: '',
  footer: '',
  buttons: [],
  var_descriptions: {},
  limited_time_offer: false,
  auth_config: emptyAuthConfig(),
  cards: [],
  // Formulario (WhatsApp Flow) construido junto a la plantilla, cuando el tipo
  // elegido es 'flow'. El backend lo publica en Meta antes de crear la plantilla.
  flow_screens: [],
  flow_category: 'SURVEY',
  flow_button_text: '',
});
const form = ref(emptyForm());
const uploadingMedia = ref(false);
const headerFileInput = ref(null);

// Elegir AUTHENTICATION como categoría fuerza template_kind = 'authentication'
// automáticamente (no es una opción separada y redundante en el selector).
watch(
  () => form.value.category,
  category => {
    if (category === 'AUTHENTICATION') {
      form.value.template_kind = 'authentication';
    } else if (form.value.template_kind === 'authentication') {
      form.value.template_kind = 'standard';
    }
  }
);

const isAuthenticationKind = computed(
  () => form.value.template_kind === 'authentication'
);
const isCarouselKind = computed(() => form.value.template_kind === 'carousel');
const isFlowKind = computed(() => form.value.template_kind === 'flow');

// Botones que se pintan en la previa del mensaje. En una plantilla de tipo
// Formulario el botón no vive en form.buttons (lo arma el backend al enlazar el
// Flow publicado), así que se agrega aquí para que la previa no salga sin él.
const previewButtons = computed(() => {
  if (isFlowKind.value) {
    const text =
      form.value.flow_button_text ||
      t('JABVOX_WA_TEMPLATES.CREATE.FLOW.BUTTON_DEFAULT');
    return [{ key: 'flow', text, isFlow: true }];
  }
  return form.value.buttons
    .filter(b => b.text)
    .map((b, index) => ({ key: `${index}-${b.text}`, text: b.text }));
});
const isStandardKind = computed(() => form.value.template_kind === 'standard');

// LTO solo visible para category MARKETING y template_kind standard.
const canShowLto = computed(
  () => form.value.category === 'MARKETING' && isStandardKind.value
);

// ─── Validación en vivo (paridad con el editor de Meta Business Manager) ───
// Usa el mismo composable que corren los specs de Vitest; las validaciones de
// variables ({{n}}) que YA existían arriba (detectedVars/invalidVars/
// bodyHasEdgeVar, basadas en processVariable de @chatwoot/utils) se mantienen
// intactas por compatibilidad -- este bloque solo AGREGA las reglas nuevas
// (consecutivas, mezcla posicional+NAMED, secuencia, contadores, botones).
const {
  bodyHasConsecutiveVars,
  bodyHasMixedVarTypes,
  bodyHasNonSequentialVars,
  counters: templateCounters,
  counterClass,
  buttonErrors,
  errors: templateValidationErrors,
  isValid: templateIsValid,
} = useTemplateValidation(form);

// ─── Carousel: cards ────────────────────────────────────────────────────────
const addCard = () => {
  if (form.value.cards.length >= CARD_MAX) return;
  form.value.cards.push(emptyCard());
};
const removeCard = i => form.value.cards.splice(i, 1);

const onCardFileChange = async (event, cardIndex) => {
  const file = event.target.files?.[0];
  if (!file) return;
  if (!formInboxId.value) {
    useAlert(t('JABVOX_WA_TEMPLATES.FORM.SELECT_INBOX_FIRST'));
    return;
  }
  // La previa se pinta de inmediato desde el archivo local: así el usuario ve
  // cómo queda la tarjeta aunque la subida a Meta falle (p. ej. si falta
  // configurar WHATSAPP_APP_ID), en vez de quedarse con la tarjeta vacía.
  const card = form.value.cards[cardIndex];
  card.header_media_name = file.name;
  card.header_media_preview = URL.createObjectURL(file);

  uploadingMedia.value = true;
  try {
    const { data } = await wtTemplatesAPI.uploadMedia({
      inboxId: formInboxId.value,
      file,
    });
    card.header_handle = data.handle;
  } catch (err) {
    useAlert(
      err?.response?.data?.error || t('JABVOX_WA_TEMPLATES.FORM.UPLOAD_ERROR')
    );
  } finally {
    uploadingMedia.value = false;
  }
};

const addCardButton = card => {
  if (card.buttons.length >= 2) return;
  card.buttons.push({
    type: 'QUICK_REPLY',
    text: '',
    url: '',
    phone_number: '',
  });
};
const removeCardButton = (card, i) => card.buttons.splice(i, 1);

// ─── Authentication: supported_apps (ONE_TAP/ZERO_TAP) ─────────────────────
const addSupportedApp = () => {
  form.value.auth_config.supported_apps.push({
    package_name: '',
    signature_hash: '',
  });
};
const removeSupportedApp = i =>
  form.value.auth_config.supported_apps.splice(i, 1);

const authRequiresSupportedApps = computed(() =>
  ['ONE_TAP', 'ZERO_TAP'].includes(form.value.auth_config.otp_type)
);

// Al cambiar el tipo de header, limpia lo que ya no aplica: el texto, o el media
// (handle/preview/nombre). Así un valor de texto no se manda como media ni al revés.
watch(
  () => form.value.header_type,
  (next, prev) => {
    if (next === prev) return;
    form.value.header_content = '';
    form.value.header_handle = '';
    form.value.header_media_name = '';
    form.value.header_media_preview = '';
  }
);

// Variables del cuerpo. Soporta posicional ({{1}}) y NAMED ({{nombre}}), con el
// mismo criterio que el resto del sistema (processVariable). Únicas, en orden.
const detectedVars = computed(() => {
  const matches = (form.value.body || '').match(/\{\{([^}]+)\}\}/g) || [];
  return [...new Set(matches.map(m => processVariable(m)))];
});

// Meta rechaza (INVALID_FORMAT) variables NAMED con espacios, mayúsculas o signos.
// Válidas: posicional puro ({{1}}) o nombre en minúsculas/números/guion_bajo
// ({{nombre}}, {{nombre_empresa}}). Devolvemos los tokens inválidos para avisar
// ANTES de mandar a Meta (p. ej. {{Nombre empresa}}).
const invalidVars = computed(() =>
  detectedVars.value.filter(v => !/^[0-9]+$/.test(v) && !/^[a-z0-9_]+$/.test(v))
);

// Mensaje precalculado (fuera del template) para evitar que un literal con
// "{{" dentro de una interpolación Vue choque con los propios delimitores
// {{ }} del parser.
const invalidVarsMessage = computed(() =>
  t('JABVOX_WA_TEMPLATES.CREATE.INVALID_VARS', {
    vars: invalidVars.value.map(v => VAR_OPEN + v + VAR_CLOSE).join(', '),
  })
);

// Meta rechaza (Invalid parameter) si el cuerpo EMPIEZA o TERMINA con una variable:
// "Leading or Trailing Params Not Allowed". Debe haber texto fijo antes y después.
const bodyHasEdgeVar = computed(() => {
  const body = (form.value.body || '').trim();
  if (!body) return false;
  return /^\{\{[^}]+\}\}/.test(body) || /\{\{[^}]+\}\}$/.test(body);
});

// ¿El header actual es de tipo media (imagen/video/documento)?
const isMediaHeader = computed(() =>
  ['IMAGE', 'VIDEO', 'DOCUMENT'].includes(form.value.header_type)
);

// Sube el archivo del header a Meta (Resumable Upload) y guarda el handle + previa.
const onHeaderFileChange = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  if (!formInboxId.value) {
    useAlert(t('JABVOX_WA_TEMPLATES.FORM.SELECT_INBOX_FIRST'));
    return;
  }
  uploadingMedia.value = true;
  try {
    const { data } = await wtTemplatesAPI.uploadMedia({
      inboxId: formInboxId.value,
      file,
    });
    form.value.header_handle = data.handle;
    form.value.header_media_name = file.name;
    form.value.header_content = file.name;
    // Previa local del archivo elegido (no sube nada extra: usa el blob del navegador).
    form.value.header_media_preview = URL.createObjectURL(file);
  } catch (err) {
    useAlert(
      err?.response?.data?.error || t('JABVOX_WA_TEMPLATES.FORM.UPLOAD_ERROR')
    );
  } finally {
    uploadingMedia.value = false;
  }
};

// Tope real de Meta: 10 botones combinados (antes tope artificial de 3). Las
// reglas finas de agrupación/exclusividad/cantidad por tipo las valida
// buttonErrors (useTemplateValidation) e impiden enviar, no agregar.
const addButton = () => {
  if (form.value.buttons.length >= 10) return;
  form.value.buttons.push({
    type: 'QUICK_REPLY',
    text: '',
    url: '',
    phone_number: '',
    flow_id: '',
  });
};
const removeButton = i => form.value.buttons.splice(i, 1);

const openCreate = () => {
  editingTemplate.value = null;
  form.value = emptyForm();
  formInboxId.value = selectedInboxId.value || (inboxes.value[0]?.id ?? null);
  wizardStep.value = 1;
  showForm.value = true;
};

const openEdit = tpl => {
  editingTemplate.value = tpl;
  form.value = {
    name: tpl.name,
    category: tpl.category,
    language: tpl.language,
    template_kind: tpl.template_kind || 'standard',
    header_type: tpl.header_type || 'NONE',
    header_content: tpl.header_content || '',
    header_handle: '',
    header_media_name: '',
    header_media_preview: '',
    body: tpl.body_content || '',
    footer: tpl.footer_content || '',
    buttons: (tpl.buttons_json || []).map(b => ({ ...b })),
    var_descriptions: Object.fromEntries(
      Object.entries(tpl.variables_json || {}).map(([k, v]) => [k, v])
    ),
    limited_time_offer: tpl.limited_time_offer || false,
    auth_config: { ...emptyAuthConfig(), ...(tpl.auth_config_json || {}) },
    cards: (tpl.cards_json || []).map(c => ({ ...emptyCard(), ...c })),
  };
  formInboxId.value = tpl.inbox_id;
  wizardStep.value = 1;
  showForm.value = true;
};

const submitForm = async () => {
  // Bloquea nombres de variable inválidos antes de gastar una petición a Meta,
  // que los rechaza con INVALID_FORMAT (espacios, mayúsculas o signos).
  if (invalidVars.value.length) {
    useAlert(
      t('JABVOX_WA_TEMPLATES.CREATE.INVALID_VARS', {
        vars: invalidVars.value.map(v => `{{${v}}}`).join(', '),
      })
    );
    return;
  }
  // Meta no permite variables al inicio o al final del cuerpo.
  if (bodyHasEdgeVar.value) {
    useAlert(t('JABVOX_WA_TEMPLATES.CREATE.EDGE_VAR'));
    return;
  }
  // Resto de reglas nuevas (consecutivas, mezcla posicional+NAMED, secuencia,
  // botones) -- mismo gate que ya bloquea el botón "Enviar a Meta" en el wizard.
  if (!templateIsValid.value) {
    useAlert(
      templateValidationErrors.value[0] || t('JABVOX_WA_TEMPLATES.ERROR')
    );
    return;
  }
  saving.value = true;
  // A TEXT header with no content is invalid for Meta: treat it as "no header".
  const hasHeaderContent = form.value.header_content?.trim();
  const headerType =
    form.value.header_type === 'NONE' ||
    (form.value.header_type === 'TEXT' && !hasHeaderContent)
      ? null
      : form.value.header_type;
  const payload = {
    name: form.value.name,
    category: form.value.category,
    language: form.value.language,
    template_kind: form.value.template_kind,
    header_type: isAuthenticationKind.value ? null : headerType,
    header_content:
      !isAuthenticationKind.value && headerType
        ? form.value.header_content
        : null,
    // Para header de media, Meta exige el handle "h:..." (subido con Resumable Upload),
    // no una URL. Va aparte de header_content.
    header_handle:
      !isAuthenticationKind.value &&
      headerType &&
      ['IMAGE', 'VIDEO', 'DOCUMENT'].includes(headerType)
        ? form.value.header_handle
        : null,
    body: isAuthenticationKind.value ? null : form.value.body,
    footer: isAuthenticationKind.value ? null : form.value.footer,
    buttons: isAuthenticationKind.value
      ? []
      : form.value.buttons.filter(b => b.text),
    inbox_id: formInboxId.value,
    limited_time_offer: canShowLto.value
      ? form.value.limited_time_offer
      : false,
    auth_config: isAuthenticationKind.value ? form.value.auth_config : {},
    cards: isCarouselKind.value ? form.value.cards : [],
  };
  // El backend crea y publica el Flow en Meta antes de crear la plantilla.
  if (isFlowKind.value) {
    payload.flow = {
      screens_json: form.value.flow_screens,
      category: form.value.flow_category,
    };
    payload.flow_button_text = form.value.flow_button_text;
  }
  try {
    if (editingTemplate.value) {
      await wtTemplatesAPI.update(editingTemplate.value.id, payload);
      useAlert(t('JABVOX_WA_TEMPLATES.UPDATED'));
    } else {
      await wtTemplatesAPI.create(payload);
      useAlert(t('JABVOX_WA_TEMPLATES.CREATED'));
    }
    showForm.value = false;
    form.value = emptyForm();
    loadTemplates();
    loadMetrics();
  } catch (err) {
    useAlert(err?.response?.data?.error || t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    saving.value = false;
  }
};

// Visual validation state for the wizard fields: red border when a required
// field is empty, green when it has content, neutral for optional empty ones.
const fieldClass = (value, required = false) => {
  const filled = String(value ?? '').trim() !== '';
  if (filled) return 'wa-field wa-field-valid';
  return required ? 'wa-field wa-field-invalid' : 'wa-field';
};

// Required-field checklist: drives the submit gate and the pending list shown
// on the final step. Once a header type is chosen, its content is required —
// removing the header is done by picking NONE, not by leaving it empty.
// Requisitos del formulario, separados para no engordar el check general.
// Reflejan lo que Meta valida al publicar un Flow: pantallas con id y título,
// un botón de avance por pantalla, una pantalla final, y campos con nombre.
const missingFlowFields = blank => {
  const missing = [];
  const label = t('JABVOX_WA_TEMPLATES.CREATE.FLOW.SECTION_TITLE');

  if (blank(form.value.flow_button_text)) {
    missing.push(t('JABVOX_WA_TEMPLATES.CREATE.FLOW.BUTTON_TEXT'));
  }
  const screens = form.value.flow_screens || [];
  if (!screens.length) {
    missing.push(label);
    return missing;
  }
  if (!screens.some(s => s.terminal)) {
    missing.push(t('JABVOX_WA_TEMPLATES.CREATE.FLOW.NEEDS_TERMINAL'));
  }

  screens.forEach(screen => {
    const name = screen.title || screen.id;
    const components = screen.components || [];
    const footers = components.filter(c => c.type === 'Footer');

    if (!footers.length) {
      missing.push(
        `${name}: ${t('JABVOX_WA_TEMPLATES.CREATE.FLOW.MISSING_FOOTER')}`
      );
    }
    footers.forEach(f => {
      if (blank(f.props?.label)) {
        missing.push(
          `${name}: ${t('JABVOX_WA_TEMPLATES.CREATE.FLOW.MISSING_FOOTER_LABEL')}`
        );
      }
      // Un botón que navega debe saber a dónde; Meta rechaza un destino vacío.
      if (
        f.props?.action?.name === 'navigate' &&
        blank(f.props?.action?.next)
      ) {
        missing.push(
          `${name}: ${t('JABVOX_WA_TEMPLATES.CREATE.FLOW.MISSING_NEXT')}`
        );
      }
    });
    // Todo campo que captura datos necesita nombre (es la clave de la respuesta)
    // y etiqueta visible.
    components.forEach(c => {
      const meta = getComponentMeta(c.type);
      if (!meta) return;
      (meta.fields || []).forEach(field => {
        if (!field.required) return;
        const value = c.props?.[field.key];
        const empty = Array.isArray(value) ? !value.length : blank(value);
        if (empty) missing.push(`${name} · ${meta.label}: ${field.label}`);
      });
    });
  });

  return missing;
};

const missingRequiredFields = computed(() => {
  const blank = v => String(v ?? '').trim() === '';
  const missing = [];
  if (!editingTemplate.value) {
    if (!formInboxId.value)
      missing.push(t('JABVOX_WA_TEMPLATES.CREATE.INBOX_LABEL'));
    if (blank(form.value.name))
      missing.push(t('JABVOX_WA_TEMPLATES.CREATE.NAME_LABEL'));
  }

  // Authentication no usa body/header/footer libres -- Meta los genera desde
  // auth_config. Solo se exige el propio auth_config.
  if (isAuthenticationKind.value) {
    if (blank(form.value.auth_config.otp_type))
      missing.push(t('JABVOX_WA_TEMPLATES.CREATE.AUTH.OTP_TYPE_LABEL'));
    if (
      authRequiresSupportedApps.value &&
      !form.value.auth_config.supported_apps.length
    )
      missing.push(t('JABVOX_WA_TEMPLATES.CREATE.AUTH.SUPPORTED_APPS_LABEL'));
    return missing;
  }

  if (blank(form.value.body))
    missing.push(t('JABVOX_WA_TEMPLATES.CREATE.BODY_LABEL'));
  if (form.value.header_type === 'TEXT' && blank(form.value.header_content))
    missing.push(t('JABVOX_WA_TEMPLATES.CREATE.HEADER_TYPE_LABEL'));
  // Header de media: se requiere el handle (archivo ya subido a Meta). Al editar una
  // plantilla existente que ya trae media, no se re-exige subir de nuevo.
  if (
    form.value.header_type &&
    !['NONE', 'TEXT', 'LOCATION'].includes(form.value.header_type) &&
    blank(form.value.header_handle) &&
    !editingTemplate.value
  )
    missing.push(t('JABVOX_WA_TEMPLATES.CREATE.HEADER_MEDIA_FILE_LABEL'));
  form.value.buttons.forEach((b, i) => {
    if (blank(b.text))
      missing.push(`${t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_TEXT')} ${i + 1}`);
    if (b.type === 'URL' && blank(b.url))
      missing.push(`${t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_URL')} ${i + 1}`);
    if (
      (b.type === 'PHONE_NUMBER' || b.type === 'VOICE_CALL') &&
      blank(b.phone_number)
    )
      missing.push(`${t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_PHONE')} ${i + 1}`);
    if (b.type === 'FLOW' && blank(b.flow_id))
      missing.push(
        `${t('JABVOX_WA_FLOWS.TEMPLATES_INTEGRATION.FLOW_BUTTON_LABEL')} ${i + 1}`
      );
  });

  // Carousel: 2-10 cards, cada una con su media subida.
  if (isCarouselKind.value) {
    if (
      form.value.cards.length < CARD_MIN ||
      form.value.cards.length > CARD_MAX
    ) {
      missing.push(t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.CARDS_COUNT_LABEL'));
    }
    form.value.cards.forEach((c, i) => {
      if (blank(c.header_handle) && !editingTemplate.value) {
        missing.push(
          `${t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.CARD_MEDIA_LABEL')} ${i + 1}`
        );
      }
    });
  }

  // Formulario: lo que Meta exige del Flow JSON antes de poder publicarlo.
  if (isFlowKind.value) missing.push(...missingFlowFields(blank));

  return missing;
});

const wizardSteps = [
  { id: 1, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.BASIC') },
  { id: 2, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.CONTENT') },
  { id: 3, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.VARIABLES') },
  { id: 4, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.BUTTONS') },
  { id: 5, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.PREVIEW') },
  { id: 6, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.SUBMIT') },
];

const nextWizardStep = () => {
  if (wizardStep.value < 6) wizardStep.value += 1;
};

const previousWizardStep = () => {
  if (wizardStep.value > 1) wizardStep.value -= 1;
};

// Selected template shown in the detail drawer (declared before the analytics
// computed that reads it, to avoid a forward reference).
const detailTemplate = ref(null);

const templateAnalytics = computed(() => {
  const raw = detailTemplate.value?.meta_json?.analytics || {};
  return {
    sent: raw.sent || 0,
    delivered: raw.delivered || 0,
    read: raw.read || 0,
    replied: raw.replied || 0,
    failed: raw.failed || 0,
    blocked: raw.blocked || 0,
  };
});

// URL del media de EJEMPLO que Meta guarda en la plantilla aprobada. Vive en el
// componente HEADER de meta_json (example.header_handle[0]); vale igual para
// plantillas creadas en Jabvox y en Meta.
const detailHeaderMediaUrl = computed(() => {
  const comps = detailTemplate.value?.meta_json?.components;
  if (!Array.isArray(comps)) return '';
  const header = comps.find(c => (c.type || '').toUpperCase() === 'HEADER');
  const ex = header?.example || {};
  const handle = ex.header_handle || ex.header_url || ex.header_handle_url;
  if (Array.isArray(handle)) return handle[0] || '';
  return handle || '';
});

const detailHeaderType = computed(() =>
  (detailTemplate.value?.header_type || '').toUpperCase()
);
const detailHeaderIsMedia = computed(() =>
  ['IMAGE', 'VIDEO', 'DOCUMENT'].includes(detailHeaderType.value)
);

// ─── Detail / History / Versions ────────────────────────────────────────────
const detailHistory = ref([]);
const detailVersions = ref([]);
const detailTab = ref('components');
const loadingDetail = ref(false);

const openDetail = async tpl => {
  loadingDetail.value = true;
  detailTab.value = 'components';
  try {
    const [{ data: d }, { data: h }, { data: v }] = await Promise.all([
      wtTemplatesAPI.get(tpl.id),
      wtTemplatesAPI.history(tpl.id),
      wtTemplatesAPI.versions(tpl.id),
    ]);
    detailTemplate.value = d;
    detailHistory.value = h.history || [];
    detailVersions.value = v.versions || [];
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    loadingDetail.value = false;
  }
};

const closeDetail = () => {
  detailTemplate.value = null;
};

const restoreVersion = ver => {
  confirmDialog.value?.open({
    title: t('JABVOX_WA_TEMPLATES.DETAIL.RESTORE'),
    description: t('JABVOX_WA_TEMPLATES.DETAIL.RESTORE_CONFIRM', {
      v: ver.version,
    }),
    data: { action: 'restoreVersion', ver },
  });
};

const performRestoreVersion = async ver => {
  try {
    await wtTemplatesAPI.restoreVersion(detailTemplate.value.id, ver.id);
    useAlert(t('JABVOX_WA_TEMPLATES.RESTORED'));
    openDetail(detailTemplate.value);
    loadTemplates();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

// Dispatches the confirmed action from ConfirmDialog to its handler.
const onConfirmAction = data => {
  if (data?.action === 'restoreVersion') performRestoreVersion(data.ver);
};

const duplicateTemplate = tpl => {
  promptDialog.value?.open({
    title: t('JABVOX_WA_TEMPLATES.DETAIL.DUPLICATE_NAME'),
    initialValue: `${tpl.name}_copy`,
    data: tpl,
  });
};

const performDuplicate = async ({ value: newName, data: tpl }) => {
  if (!newName) return;
  try {
    await wtTemplatesAPI.duplicate(tpl.id, newName);
    useAlert(t('JABVOX_WA_TEMPLATES.DUPLICATED'));
    loadTemplates();
    loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const switchTab = key => {
  activeTab.value = key;
  if (key === 'templates') {
    selectedTemplateIds.value = [];
  }
};

// Inbox is a list filter only: changing it re-filters the templates but leaves the KPI metrics
// as the account-wide totals.
watch(selectedInboxId, () => {
  page.value = 1;
  loadTemplates();
});

let autoSyncTimers = [];

onMounted(async () => {
  await loadInboxes();
  await Promise.all([loadTemplates(), loadMetrics()]);
  // Kick off a background refresh from Meta (only stale inboxes) so approved/rejected
  // statuses update automatically without blocking the page or hitting Meta every visit.
  // Reload a couple of times shortly after so the fresh statuses appear once the job runs.
  try {
    await wtInboxesAPI.syncAllAsync();
    autoSyncTimers = [4000, 10000].map(ms =>
      setTimeout(() => {
        loadTemplates();
        loadMetrics();
      }, ms)
    );
  } catch {
    // ignore — keep showing whatever we already loaded
  }
});

onBeforeUnmount(() => {
  autoSyncTimers.forEach(clearTimeout);
});
</script>

<template>
  <div class="wa-shell flex flex-col flex-1 h-full overflow-hidden">
    <div ref="stickyHeaderRef" class="wa-glass-header sticky top-0 z-20">
      <div class="flex flex-col gap-4 px-4 sm:px-6 py-4">
        <div
          class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4"
        >
          <div>
            <h1 class="wa-title text-xl sm:text-2xl font-semibold">
              {{ t('JABVOX_WA_TEMPLATES.HEADER.TITLE') }}
            </h1>
            <p class="text-xs sm:text-sm text-n-slate-10 mt-1 max-w-2xl">
              {{ t('JABVOX_WA_TEMPLATES.HEADER.SUBTITLE') }}
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <button
              class="inline-flex items-center gap-1.5 px-3.5 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand transition-opacity"
              @click="openCreate"
            >
              <span class="i-lucide-plus size-4" aria-hidden="true" />
              {{ t('JABVOX_WA_TEMPLATES.HEADER.CREATE') }}
            </button>
            <button
              class="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              :disabled="syncing"
              @click="syncAll"
            >
              <span
                :class="
                  syncing
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-refresh-cw'
                "
                class="size-4"
                aria-hidden="true"
              />
              {{ t('JABVOX_WA_TEMPLATES.HEADER.SYNC') }}
            </button>
          </div>
        </div>

        <div
          class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-2 sm:gap-3"
        >
          <div
            v-for="kpi in summaryKpis"
            :key="kpi.key"
            class="group flex flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 px-3.5 py-3 shadow-sm transition-colors hover:border-n-strong"
          >
            <div class="flex items-center justify-between gap-2">
              <p
                class="text-[11px] font-medium uppercase tracking-wide text-n-slate-10 truncate"
              >
                {{ kpi.label }}
              </p>
              <span
                :class="[kpi.icon, kpi.accent]"
                class="size-4 shrink-0"
                aria-hidden="true"
              />
            </div>
            <p class="text-2xl font-semibold text-n-slate-12 leading-none">
              {{ kpi.value }}
            </p>
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <div class="flex gap-1 px-4 sm:px-6 pb-1 shrink-0">
        <button
          v-for="tab in mainTabs"
          :key="tab.key"
          class="wa-tab px-4 py-2 text-sm rounded-lg transition-all"
          :class="activeTab === tab.key ? 'wa-tab-active' : ''"
          @click="switchTab(tab.key)"
        >
          {{ tab.label }}
        </button>
      </div>
    </div>

    <!-- ── OVERVIEW TAB ──────────────────────────────────────────────── -->
    <div v-if="activeTab === 'overview'" class="flex-1 overflow-auto p-6">
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 mb-6">
        <div
          v-for="m in overviewMetrics"
          :key="m.key"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
        >
          <p class="text-xs text-n-slate-10 mb-1">{{ m.label }}</p>
          <p class="text-2xl font-semibold text-n-slate-12">
            {{ metrics[m.key] ?? 0 }}
          </p>
        </div>
      </div>
      <h2 class="text-sm font-medium text-n-slate-12 mb-3">
        {{ t('JABVOX_WA_TEMPLATES.INBOX.LABEL') }}
      </h2>
      <div v-if="!inboxes.length" class="text-sm text-n-slate-11 py-4">
        {{ t('JABVOX_WA_TEMPLATES.INBOX.NONE') }}
      </div>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <div
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex items-center justify-between"
        >
          <div>
            <p class="font-medium text-n-slate-12 text-sm">{{ inbox.name }}</p>
            <p class="text-xs text-n-slate-10">{{ inbox.phone_number }}</p>
            <p class="text-xs text-n-slate-10">
              {{
                t('JABVOX_WA_TEMPLATES.OVERVIEW.WABA_LABELED', {
                  value:
                    inbox.waba_id || t('JABVOX_WA_TEMPLATES.OVERVIEW.NO_WABA'),
                })
              }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ inbox.template_count }}
              {{ t('JABVOX_WA_TEMPLATES.INBOX.TEMPLATES') }}
            </p>
          </div>
          <button
            class="px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 flex items-center gap-1 disabled:opacity-50"
            :disabled="syncing"
            @click="syncOneInbox(inbox.id)"
          >
            <span class="i-lucide-refresh-cw size-3" aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>

    <!-- ── TEMPLATES TAB ─────────────────────────────────────────────── -->
    <div
      v-else-if="activeTab === 'templates'"
      class="flex-1 overflow-hidden flex flex-col"
    >
      <!-- Advanced search and filters -->
      <div
        class="mx-4 sm:mx-6 my-4 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm shrink-0 overflow-hidden"
      >
        <!-- Panel heading: click to collapse/expand -->
        <button
          type="button"
          class="w-full flex items-center justify-between gap-3 px-4 sm:px-5 py-3.5 border-b border-n-weak bg-n-alpha-1 hover:bg-n-alpha-2 transition-colors text-left"
          :aria-expanded="filtersExpanded"
          @click="filtersExpanded = !filtersExpanded"
        >
          <div class="flex items-center gap-2.5 min-w-0">
            <span
              class="flex items-center justify-center size-8 rounded-lg bg-n-brand/10 text-n-brand shrink-0"
            >
              <span
                class="i-lucide-sliders-horizontal size-4"
                aria-hidden="true"
              />
            </span>
            <div class="min-w-0">
              <h2 class="text-sm font-semibold text-n-slate-12 leading-tight">
                {{ t('JABVOX_WA_TEMPLATES.FILTERS.TITLE') }}
              </h2>
              <p class="text-[11px] text-n-slate-10">
                {{
                  t('JABVOX_WA_TEMPLATES.FILTERS.RESULTS', {
                    count: totalTemplates,
                  })
                }}
              </p>
            </div>
            <span
              v-if="hasActiveFilters"
              class="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-full bg-n-brand/10 text-n-brand shrink-0"
            >
              <span class="i-lucide-filter size-3" aria-hidden="true" />
              {{ t('JABVOX_WA_TEMPLATES.FILTERS.ACTIVE_BADGE') }}
            </span>
          </div>
          <span
            class="i-lucide-chevron-down size-5 text-n-slate-10 shrink-0 transition-transform duration-200"
            :class="{ 'rotate-180': filtersExpanded }"
            aria-hidden="true"
          />
        </button>

        <div v-show="filtersExpanded" class="px-4 sm:px-5 py-4 space-y-4">
          <!-- Search + dropdown filters, each with its own label -->
          <div
            class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-x-3 gap-y-3"
          >
            <div class="md:col-span-2 xl:col-span-1 flex flex-col gap-1">
              <label class="text-[11px] font-medium text-n-slate-11">
                {{ t('JABVOX_WA_TEMPLATES.FILTERS.SEARCH_LABEL') }}
              </label>
              <div class="relative">
                <span
                  class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                  aria-hidden="true"
                />
                <input
                  v-model="filters.q"
                  class="reset-base wa-field text-sm w-full pl-9"
                  :placeholder="
                    t('JABVOX_WA_TEMPLATES.FILTERS.SEARCH_PLACEHOLDER')
                  "
                  @keyup.enter="applyFilters"
                />
              </div>
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-[11px] font-medium text-n-slate-11">
                {{ t('JABVOX_WA_TEMPLATES.FILTERS.META_ID_LABEL') }}
              </label>
              <div class="relative">
                <span
                  class="i-lucide-hash size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                  aria-hidden="true"
                />
                <input
                  v-model="filters.meta_id"
                  class="reset-base wa-field text-sm w-full pl-9"
                  :placeholder="
                    t('JABVOX_WA_TEMPLATES.FILTERS.META_ID_PLACEHOLDER')
                  "
                  @keyup.enter="applyFilters"
                />
              </div>
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-[11px] font-medium text-n-slate-11">
                {{ t('JABVOX_WA_TEMPLATES.FILTERS.INBOX_LABEL') }}
              </label>
              <select
                v-model="selectedInboxId"
                class="reset-base wa-field text-sm w-full"
              >
                <option :value="null">
                  {{ t('JABVOX_WA_TEMPLATES.INBOX.ALL') }}
                </option>
                <option v-for="i in inboxes" :key="i.id" :value="i.id">
                  {{ i.name }}
                </option>
              </select>
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-[11px] font-medium text-n-slate-11">
                {{ t('JABVOX_WA_TEMPLATES.FILTERS.LANGUAGE_LABEL') }}
              </label>
              <select
                v-model="filters.language"
                class="reset-base wa-field text-sm w-full"
              >
                <option value="">
                  {{ t('JABVOX_WA_TEMPLATES.FILTERS.ALL_LANGUAGES') }}
                </option>
                <option v-for="l in LANGUAGES" :key="l.value" :value="l.value">
                  {{ l.label }}
                </option>
              </select>
            </div>
          </div>

          <!-- Quick filters: status + category, each grouped with a label -->
          <div class="flex flex-col gap-3">
            <div class="flex flex-col gap-1.5">
              <span
                class="text-[11px] font-medium uppercase tracking-wide text-n-slate-9"
              >
                {{ t('JABVOX_WA_TEMPLATES.FILTERS.STATUS_GROUP') }}
              </span>
              <div class="flex items-center gap-2 flex-wrap">
                <button
                  v-for="s in statusQuickFilters"
                  :key="`status_${s}`"
                  class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs border transition-all"
                  :class="
                    filterChipActive('status', s)
                      ? 'border-n-brand bg-n-brand text-white shadow-sm'
                      : 'border-n-weak text-n-slate-11 bg-n-solid-1 hover:bg-n-alpha-1 hover:border-n-strong'
                  "
                  @click="applyQuickFilter('status', s)"
                >
                  <span
                    class="size-1.5 rounded-full shrink-0"
                    :class="
                      filterChipActive('status', s)
                        ? 'bg-white'
                        : statusDotClass(s)
                    "
                    aria-hidden="true"
                  />
                  {{ statusLabel(s) }}
                </button>
              </div>
            </div>

            <div class="flex flex-col gap-1.5">
              <span
                class="text-[11px] font-medium uppercase tracking-wide text-n-slate-9"
              >
                {{ t('JABVOX_WA_TEMPLATES.FILTERS.CATEGORY_GROUP') }}
              </span>
              <div class="flex items-center gap-2 flex-wrap">
                <button
                  v-for="c in categoryQuickFilters"
                  :key="`cat_${c}`"
                  class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs border transition-all"
                  :class="
                    filterChipActive('category', c)
                      ? 'border-n-brand bg-n-brand text-white shadow-sm'
                      : 'border-n-weak text-n-slate-11 bg-n-solid-1 hover:bg-n-alpha-1 hover:border-n-strong'
                  "
                  @click="applyQuickFilter('category', c)"
                >
                  <span
                    :class="categoryIcon(c)"
                    class="size-3 shrink-0"
                    aria-hidden="true"
                  />
                  {{ categoryLabel(c) }}
                </button>
              </div>
            </div>
          </div>

          <!-- Apply / Clear actions -->
          <div
            class="flex items-center justify-end gap-2 pt-1 border-t border-n-weak"
          >
            <button
              class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors disabled:opacity-50"
              :disabled="!hasActiveFilters"
              @click="clearFilters"
            >
              <span class="i-lucide-x size-3.5" aria-hidden="true" />
              {{ t('JABVOX_WA_TEMPLATES.FILTERS.CLEAR') }}
            </button>
            <button
              class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 transition-opacity"
              @click="applyFilters"
            >
              <span class="i-lucide-check size-3.5" aria-hidden="true" />
              {{ t('JABVOX_WA_TEMPLATES.FILTERS.APPLY') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Bulk actions bar (shown when templates are selected) -->
      <div
        v-if="selectedCount"
        class="mx-4 sm:mx-6 mb-4 flex flex-wrap items-center justify-between gap-2 rounded-xl border border-n-brand/30 bg-n-brand/5 px-3.5 py-2.5 shrink-0"
      >
        <span class="text-xs font-medium text-n-slate-12">
          {{ t('JABVOX_WA_TEMPLATES.BULK.SELECTED', { count: selectedCount }) }}
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            class="px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors"
            @click="bulkSync"
          >
            {{ t('JABVOX_WA_TEMPLATES.BULK.SYNC') }}
          </button>
          <button
            class="px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors"
            @click="bulkDuplicate"
          >
            {{ t('JABVOX_WA_TEMPLATES.BULK.DUPLICATE') }}
          </button>
        </div>
      </div>

      <!-- Cards gallery -->
      <div class="flex-1 min-h-0 overflow-y-auto px-4 sm:px-6 py-4">
        <div
          v-if="loadingTemplates"
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-4"
        >
          <div v-for="n in 8" :key="n" class="wa-card p-4 wa-skeleton">
            <div class="h-4 w-2/3 rounded mb-2 wa-shimmer" />
            <div class="h-3 w-1/2 rounded mb-4 wa-shimmer" />
            <div class="h-40 rounded-xl mb-3 wa-shimmer" />
            <div class="h-3 w-1/3 rounded wa-shimmer" />
          </div>
        </div>

        <div v-else-if="!templates.length" class="wa-empty py-20 text-center">
          <div class="wa-empty-icon mx-auto mb-4">
            <span class="i-lucide-layout-template size-7 text-n-brand" />
          </div>
          <p class="text-base font-semibold text-n-slate-12">
            {{ t('JABVOX_WA_TEMPLATES.GALLERY.EMPTY_TITLE') }}
          </p>
          <p class="text-sm text-n-slate-10 mt-1.5 max-w-md mx-auto">
            {{ t('JABVOX_WA_TEMPLATES.GALLERY.EMPTY_BODY') }}
          </p>
          <button
            class="wa-btn-primary mt-5 px-4 py-2 text-sm rounded-xl inline-flex items-center gap-1.5"
            @click="openCreate"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('JABVOX_WA_TEMPLATES.GALLERY.EMPTY_CTA') }}
          </button>
        </div>

        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-4"
        >
          <label
            class="col-span-full flex items-center gap-2 text-xs text-n-slate-10"
          >
            <input
              :checked="allVisibleSelected"
              type="checkbox"
              class="size-4 accent-n-brand"
              @change="toggleSelectAll($event.target.checked)"
            />
            {{ t('JABVOX_WA_TEMPLATES.GALLERY.SELECT_ALL') }}
          </label>

          <article
            v-for="tpl in templates"
            :key="tpl.id"
            class="wa-card wa-card-hover group p-4"
          >
            <div class="flex items-start justify-between gap-2 mb-3">
              <label
                class="inline-flex items-center gap-2 text-xs text-n-slate-10"
              >
                <input
                  :checked="selectedTemplateIds.includes(tpl.id)"
                  type="checkbox"
                  class="size-4 accent-n-brand"
                  @change="toggleSelectOne(tpl.id, $event.target.checked)"
                />
              </label>
              <span
                class="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-full"
                :class="statusClass(tpl.status)"
              >
                {{ statusLabel(tpl.status) }}
              </span>
            </div>

            <button class="w-full text-left" @click="openDetail(tpl)">
              <h3 class="text-sm font-semibold text-n-slate-12 truncate">
                {{ tpl.name }}
              </h3>
              <p class="text-xs text-n-slate-10 mt-0.5">
                {{ tpl.language }} {{ DOT }} {{ categoryLabel(tpl.category) }}
                {{ DOT }}
                {{
                  tpl.meta_template_id ||
                  t('JABVOX_WA_TEMPLATES.GALLERY.NO_META_ID')
                }}
              </p>

              <div class="mt-3 rounded-xl bg-[#0b141a] p-2.5">
                <div
                  class="rounded-lg bg-[#202c33] p-2 text-[11px] text-white/90"
                >
                  <p
                    v-if="tpl.header_type === 'TEXT' && tpl.header_content"
                    class="font-semibold border-b border-white/10 pb-1 mb-1"
                  >
                    {{ tpl.header_content }}
                  </p>
                  <p class="line-clamp-3 whitespace-pre-wrap">
                    {{ tpl.body_content || '…' }}
                  </p>
                  <p
                    v-if="tpl.footer_content"
                    class="text-white/40 mt-1 line-clamp-1"
                  >
                    {{ tpl.footer_content }}
                  </p>
                </div>
                <div v-if="tpl.buttons_json?.length" class="mt-1.5 grid gap-1">
                  <div
                    v-for="btn in tpl.buttons_json.slice(0, 2)"
                    :key="`${tpl.id}_${btn.text}`"
                    class="rounded bg-[#2a3942] py-1 text-center text-[10px] text-[#53bdeb]"
                  >
                    {{ btn.text }}
                  </div>
                </div>
              </div>

              <div class="mt-3 grid grid-cols-2 gap-2 text-xs">
                <div>
                  <p class="text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.GALLERY.VARIABLES') }}
                  </p>
                  <p class="text-n-slate-12 font-medium">
                    {{ Object.keys(tpl.variables_json || {}).length }}
                  </p>
                </div>
                <div>
                  <p class="text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.GALLERY.BUTTONS') }}
                  </p>
                  <p class="text-n-slate-12 font-medium">
                    {{ (tpl.buttons_json || []).length }}
                  </p>
                </div>
                <div>
                  <p class="text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.GALLERY.CREATED') }}
                  </p>
                  <p class="text-n-slate-12 font-medium">
                    {{ new Date(tpl.created_at).toLocaleDateString() }}
                  </p>
                </div>
                <div>
                  <p class="text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.GALLERY.UPDATED') }}
                  </p>
                  <p class="text-n-slate-12 font-medium">
                    {{ new Date(tpl.updated_at).toLocaleDateString() }}
                  </p>
                </div>
              </div>
            </button>

            <div class="mt-3 flex items-center gap-1.5 wa-card-actions">
              <button class="wa-icon-btn" @click="openEdit(tpl)">
                <span class="i-lucide-pencil size-3.5" />
              </button>
              <button class="wa-icon-btn" @click="duplicateTemplate(tpl)">
                <span class="i-lucide-copy size-3.5" />
              </button>
              <button class="wa-icon-btn" @click="syncTemplate(tpl)">
                <span class="i-lucide-refresh-cw size-3.5" />
              </button>
            </div>
          </article>
        </div>

        <!-- Pagination -->
        <div
          v-if="totalPages > 1"
          class="flex items-center justify-center gap-4 pt-4 text-sm text-n-slate-11"
        >
          <button
            class="px-3 py-1 rounded bg-n-alpha-2 disabled:opacity-50"
            :disabled="page <= 1"
            @click="changePage(-1)"
          >
            <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
          </button>
          <span>
            {{
              t('JABVOX_WA_TEMPLATES.GALLERY.PAGINATION', {
                page,
                pages: totalPages,
                total: totalTemplates,
              })
            }}
          </span>
          <button
            class="px-3 py-1 rounded bg-n-alpha-2 disabled:opacity-50"
            :disabled="page >= totalPages"
            @click="changePage(1)"
          >
            <span class="i-lucide-chevron-right size-4" aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>

    <!-- ── CREATE / EDIT FORM MODAL ──────────────────────────────────── -->
    <div v-if="showForm" class="fixed inset-0 z-50 flex">
      <div class="absolute inset-0 bg-black/50" @click="showForm = false" />
      <div
        class="relative ml-auto w-full md:max-w-[900px] h-full bg-n-solid-1 shadow-xl flex overflow-hidden"
      >
        <!-- Left: form -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <div
            class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak shrink-0"
          >
            <h2 class="font-semibold text-n-slate-12">
              {{
                editingTemplate
                  ? t('JABVOX_WA_TEMPLATES.CREATE.EDIT_TITLE')
                  : t('JABVOX_WA_TEMPLATES.CREATE.TITLE')
              }}
            </h2>
            <button
              class="text-n-slate-11 hover:text-n-slate-12"
              @click="showForm = false"
            >
              <span class="i-lucide-x size-5" />
            </button>
          </div>
          <div
            class="px-5 py-3 border-b border-n-weak shrink-0 overflow-x-auto"
          >
            <div class="flex items-center gap-2 min-w-max">
              <button
                v-for="step in wizardSteps"
                :key="step.id"
                class="inline-flex items-center gap-2 px-2.5 py-1.5 rounded-full text-xs border"
                :class="
                  wizardStep >= step.id
                    ? 'border-n-brand bg-n-brand text-white'
                    : 'border-n-weak text-n-slate-10 bg-n-solid-1'
                "
                @click="wizardStep = step.id"
              >
                <span
                  class="size-4 rounded-full bg-white/20 inline-flex items-center justify-center"
                >
                  {{ step.id }}
                </span>
                <span>{{ step.label }}</span>
              </button>
            </div>
          </div>

          <div class="flex-1 overflow-auto p-5 space-y-5">
            <section v-if="wizardStep === 1" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.SECTION_BASIC') }}
              </h3>
              <div class="grid grid-cols-2 gap-3">
                <div
                  v-if="!editingTemplate"
                  class="col-span-2 flex flex-col gap-1"
                >
                  <label class="text-xs text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.INBOX_LABEL') }}
                    <span class="text-n-ruby-11">*</span>
                  </label>
                  <select
                    v-model="formInboxId"
                    class="reset-base text-sm"
                    :class="fieldClass(formInboxId, true)"
                  >
                    <option :value="null" disabled>
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.INBOX_PLACEHOLDER') }}
                    </option>
                    <option v-for="i in inboxes" :key="i.id" :value="i.id">
                      {{ i.name }} {{ DASH }} {{ i.phone_number }}
                    </option>
                  </select>
                  <p
                    v-if="!inboxes.length"
                    class="text-[11px] text-n-amber-11 flex items-center gap-1"
                  >
                    <span
                      class="i-lucide-alert-triangle size-3"
                      aria-hidden="true"
                    />
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.NO_INBOXES') }}
                  </p>
                  <p
                    v-else-if="formInboxId"
                    class="text-[11px] text-n-teal-11 flex items-center gap-1"
                  >
                    <span class="i-lucide-check size-3" aria-hidden="true" />
                    {{
                      t('JABVOX_WA_TEMPLATES.CREATE.INBOX_TARGET', {
                        name: selectedFormInboxName,
                      })
                    }}
                  </p>
                </div>
                <div v-if="!editingTemplate" class="flex flex-col gap-1">
                  <label class="text-xs text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.NAME_LABEL') }}
                    <span class="text-n-ruby-11">*</span>
                  </label>
                  <input
                    v-model="form.name"
                    class="reset-base text-sm"
                    :class="fieldClass(form.name, true)"
                    :placeholder="
                      t('JABVOX_WA_TEMPLATES.CREATE.NAME_PLACEHOLDER')
                    "
                  />
                  <span class="text-xs text-n-slate-10">{{
                    t('JABVOX_WA_TEMPLATES.CREATE.NAME_HINT')
                  }}</span>
                </div>
                <div class="flex flex-col gap-1">
                  <label class="text-xs text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.CATEGORY_LABEL') }}
                    <span class="text-n-ruby-11">*</span>
                  </label>
                  <select
                    v-model="form.category"
                    class="reset-base text-sm"
                    :class="fieldClass(form.category, true)"
                  >
                    <option v-for="c in CATEGORIES" :key="c" :value="c">
                      {{ categoryLabel(c) }}
                    </option>
                  </select>
                </div>
                <div class="flex flex-col gap-1">
                  <label class="text-xs text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.LANGUAGE_LABEL') }}
                    <span class="text-n-ruby-11">*</span>
                  </label>
                  <select
                    v-model="form.language"
                    class="reset-base text-sm"
                    :class="fieldClass(form.language, true)"
                  >
                    <option
                      v-for="l in LANGUAGES"
                      :key="l.value"
                      :value="l.value"
                    >
                      {{ l.label }}
                    </option>
                  </select>
                </div>
              </div>
              <!-- Tipo de plantilla: Estándar / Carousel. AUTHENTICATION se
                   deriva automáticamente al elegir esa categoría arriba, no es
                   una opción redundante aquí (sección 5 del diseño). -->
              <div v-if="!isAuthenticationKind" class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.KIND.LABEL') }}
                </label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  <button
                    v-for="kind in TEMPLATE_KIND_OPTIONS"
                    :key="kind.key"
                    type="button"
                    class="flex items-start gap-2.5 p-3 rounded-xl border text-left transition-colors"
                    :class="
                      form.template_kind === kind.key
                        ? 'border-n-brand bg-n-brand/5 ring-1 ring-n-brand'
                        : 'border-n-weak bg-n-solid-1 hover:border-n-slate-6'
                    "
                    @click="form.template_kind = kind.key"
                  >
                    <span
                      :class="[
                        kind.icon,
                        form.template_kind === kind.key
                          ? 'text-n-brand'
                          : 'text-n-slate-10',
                      ]"
                      class="size-5 shrink-0 mt-0.5"
                      aria-hidden="true"
                    />
                    <span class="flex flex-col gap-0.5 min-w-0">
                      <span
                        class="text-sm font-medium"
                        :class="
                          form.template_kind === kind.key
                            ? 'text-n-brand'
                            : 'text-n-slate-12'
                        "
                      >
                        {{ templateKindLabel(kind.key) }}
                      </span>
                      <span class="text-[11px] text-n-slate-10 leading-snug">
                        {{ templateKindHint(kind.key) }}
                      </span>
                    </span>
                  </button>
                </div>

                <!-- Descripción de lo que hace el tipo seleccionado -->
                <div
                  class="flex items-start gap-2 rounded-lg bg-n-alpha-1 p-2.5 mt-1"
                >
                  <span
                    class="i-lucide-info size-3.5 text-n-slate-10 shrink-0 mt-px"
                    aria-hidden="true"
                  />
                  <p class="text-[11px] text-n-slate-11 leading-relaxed">
                    {{ templateKindDescriptionFor(form.template_kind) }}
                  </p>
                </div>
              </div>
              <p
                v-if="isAuthenticationKind"
                class="text-[11px] text-n-slate-10 rounded-lg bg-n-alpha-1 p-2.5"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.KIND.AUTH_AUTO_NOTE') }}
              </p>
            </section>

            <!-- ── AUTHENTICATION: formulario reducido, sin header/body/footer libres ── -->
            <section
              v-if="wizardStep === 2 && isAuthenticationKind"
              class="space-y-3"
            >
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.AUTH.SECTION_TITLE') }}
              </h3>
              <p class="text-xs text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.CREATE.AUTH.NOTE') }}
              </p>
              <label class="flex items-center gap-2 text-sm text-n-slate-11">
                <input
                  v-model="form.auth_config.add_security_recommendation"
                  type="checkbox"
                  class="reset-base"
                />
                {{
                  t('JABVOX_WA_TEMPLATES.CREATE.AUTH.SECURITY_RECOMMENDATION')
                }}
              </label>
              <div class="flex flex-col gap-1 max-w-xs">
                <label class="text-xs text-n-slate-11">
                  {{
                    t('JABVOX_WA_TEMPLATES.CREATE.AUTH.CODE_EXPIRATION_LABEL')
                  }}
                </label>
                <input
                  v-model.number="form.auth_config.code_expiration_minutes"
                  type="number"
                  min="1"
                  max="90"
                  class="reset-base text-sm wa-field wa-field-valid"
                />
              </div>
              <div class="flex flex-col gap-1 max-w-xs">
                <label class="text-xs text-n-slate-11">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.AUTH.OTP_TYPE_LABEL') }}
                </label>
                <select
                  v-model="form.auth_config.otp_type"
                  class="reset-base text-sm wa-field wa-field-valid"
                >
                  <option v-for="ot in OTP_TYPES" :key="ot" :value="ot">
                    {{ otpTypeLabel(ot) }}
                  </option>
                </select>
              </div>
              <div v-if="authRequiresSupportedApps" class="space-y-2">
                <div class="flex items-center justify-between">
                  <label class="text-xs text-n-slate-11">
                    {{
                      t('JABVOX_WA_TEMPLATES.CREATE.AUTH.SUPPORTED_APPS_LABEL')
                    }}
                  </label>
                  <button
                    class="text-xs text-n-brand hover:underline"
                    @click="addSupportedApp"
                  >
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.AUTH.ADD_APP') }}
                  </button>
                </div>
                <div
                  v-for="(app, i) in form.auth_config.supported_apps"
                  :key="i"
                  class="flex flex-wrap gap-2 items-center p-2.5 rounded-lg bg-n-alpha-1"
                >
                  <input
                    v-model="app.package_name"
                    class="reset-base text-xs flex-1 min-w-36"
                    :class="fieldClass(app.package_name, true)"
                    :placeholder="
                      t('JABVOX_WA_TEMPLATES.CREATE.AUTH.PACKAGE_NAME_PH')
                    "
                  />
                  <input
                    v-model="app.signature_hash"
                    class="reset-base text-xs flex-1 min-w-36"
                    :class="fieldClass(app.signature_hash, true)"
                    :placeholder="
                      t('JABVOX_WA_TEMPLATES.CREATE.AUTH.SIGNATURE_HASH_PH')
                    "
                  />
                  <button
                    class="text-n-ruby-11 p-1"
                    @click="removeSupportedApp(i)"
                  >
                    <span class="i-lucide-trash-2 size-3.5" />
                  </button>
                </div>
              </div>
            </section>

            <section
              v-if="wizardStep === 2 && !isAuthenticationKind"
              class="space-y-3"
            >
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.SECTION_CONTENT') }}
              </h3>
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_WA_TEMPLATES.CREATE.HEADER_TYPE_LABEL')
                }}</label>
                <select
                  v-model="form.header_type"
                  class="reset-base text-sm w-40"
                  :class="fieldClass(form.header_type)"
                >
                  <option v-for="f in HEADER_FORMATS" :key="f" :value="f">
                    {{ mediaTypeLabel(f) }}
                  </option>
                </select>
              </div>
              <div
                v-if="form.header_type === 'TEXT'"
                class="flex flex-col gap-1"
              >
                <input
                  v-model="form.header_content"
                  class="reset-base text-sm w-full"
                  :class="fieldClass(form.header_content, true)"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.HEADER_TEXT_PH')"
                  maxlength="60"
                />
                <span
                  class="text-[11px] self-end"
                  :class="
                    counterClass(
                      templateCounters.header.value,
                      templateCounters.header.max
                    )
                  "
                >
                  {{ templateCounters.header.value }}/{{
                    templateCounters.header.max
                  }}
                </span>
              </div>
              <p
                v-else-if="form.header_type === 'LOCATION'"
                class="text-[11px] text-n-slate-10 rounded-lg bg-n-alpha-1 p-2.5"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.HEADER_LOCATION_NOTE') }}
              </p>
              <div v-else-if="isMediaHeader" class="flex flex-col gap-2">
                <label class="text-xs text-n-slate-11">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.HEADER_MEDIA_FILE_LABEL') }}
                  <span class="text-n-ruby-11">*</span>
                </label>
                <input
                  ref="headerFileInput"
                  type="file"
                  :accept="
                    form.header_type === 'IMAGE'
                      ? 'image/jpeg,image/png'
                      : form.header_type === 'VIDEO'
                        ? 'video/mp4,video/3gpp'
                        : 'application/pdf'
                  "
                  class="reset-base text-sm w-full file:mr-3 file:rounded-md file:border-0 file:bg-n-brand file:text-white file:px-3 file:py-1 file:text-xs"
                  @change="onHeaderFileChange"
                />
                <div
                  v-if="uploadingMedia"
                  class="flex items-center gap-2 text-xs text-n-slate-10"
                >
                  <span
                    class="i-lucide-loader-2 size-3.5 animate-spin"
                    aria-hidden="true"
                  />
                  {{ t('JABVOX_WA_TEMPLATES.FORM.UPLOADING') }}
                </div>
                <!-- Previa del media elegido -->
                <div v-if="form.header_media_preview" class="mt-1">
                  <img
                    v-if="form.header_type === 'IMAGE'"
                    :src="form.header_media_preview"
                    alt="preview"
                    class="max-h-40 rounded-lg border border-n-weak"
                  />
                  <video
                    v-else-if="form.header_type === 'VIDEO'"
                    :src="form.header_media_preview"
                    controls
                    class="max-h-40 rounded-lg border border-n-weak bg-black"
                  />
                  <div
                    v-else
                    class="flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-11"
                  >
                    <span
                      class="i-lucide-file-text size-5"
                      aria-hidden="true"
                    />
                    {{ form.header_media_name }}
                  </div>
                </div>
                <p
                  v-if="form.header_handle"
                  class="text-[11px] text-n-teal-11 flex items-center gap-1"
                >
                  <span class="i-lucide-check size-3" aria-hidden="true" />
                  {{ t('JABVOX_WA_TEMPLATES.FORM.MEDIA_READY') }}
                </p>
                <p class="text-[11px] text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.HEADER_MEDIA_NOTE') }}
                </p>
              </div>
              <div class="flex flex-col gap-1">
                <div class="flex items-center justify-between">
                  <label class="text-xs text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.BODY_LABEL') }}
                    <span class="text-n-ruby-11">*</span>
                  </label>
                  <span
                    class="text-[11px]"
                    :class="
                      counterClass(
                        templateCounters.body.value,
                        templateCounters.body.max
                      )
                    "
                  >
                    {{ templateCounters.body.value }}/{{
                      templateCounters.body.max
                    }}
                  </span>
                </div>
                <textarea
                  v-model="form.body"
                  rows="5"
                  class="reset-base text-sm w-full resize-none"
                  :class="fieldClass(form.body, true)"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.BODY_PH')"
                />
                <!-- Validación en vivo, paridad con el editor de Meta -->
                <p v-if="bodyHasEdgeVar" class="text-[11px] text-n-ruby-11">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.EDGE_VAR') }}
                </p>
                <p
                  v-if="bodyHasConsecutiveVars"
                  class="text-[11px] text-n-ruby-11"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.CONSECUTIVE_VARS') }}
                </p>
                <p
                  v-if="bodyHasMixedVarTypes"
                  class="text-[11px] text-n-ruby-11"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.MIXED_VAR_TYPES') }}
                </p>
                <p
                  v-if="!bodyHasMixedVarTypes && bodyHasNonSequentialVars"
                  class="text-[11px] text-n-ruby-11"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.NON_SEQUENTIAL_VARS') }}
                </p>
                <p v-if="invalidVars.length" class="text-[11px] text-n-ruby-11">
                  {{ invalidVarsMessage }}
                </p>
              </div>
              <div class="flex flex-col gap-1">
                <div class="flex items-center justify-between">
                  <label class="text-xs text-n-slate-11">{{
                    t('JABVOX_WA_TEMPLATES.CREATE.FOOTER_LABEL')
                  }}</label>
                  <span
                    class="text-[11px]"
                    :class="
                      counterClass(
                        templateCounters.footer.value,
                        templateCounters.footer.max
                      )
                    "
                  >
                    {{ templateCounters.footer.value }}/{{
                      templateCounters.footer.max
                    }}
                  </span>
                </div>
                <input
                  v-model="form.footer"
                  class="reset-base text-sm w-full"
                  :class="fieldClass(form.footer)"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.FOOTER_PH')"
                  maxlength="60"
                />
              </div>
              <!-- LTO: visible solo para category MARKETING y template_kind standard -->
              <label
                v-if="canShowLto"
                class="flex items-center gap-2 text-sm text-n-slate-11"
              >
                <input
                  v-model="form.limited_time_offer"
                  type="checkbox"
                  class="reset-base"
                />
                {{ t('JABVOX_WA_TEMPLATES.CREATE.LTO.LABEL') }}
              </label>
            </section>

            <!-- ── FLOW: el formulario se construye aquí mismo; al guardar, el
                 backend lo publica en Meta y crea la plantilla enlazada ── -->
            <section v-if="wizardStep === 2 && isFlowKind" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.SECTION_TITLE') }}
              </h3>
              <div class="grid grid-cols-2 gap-3">
                <div class="flex flex-col gap-1">
                  <label class="text-xs text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.BUTTON_TEXT') }}
                    <span class="text-n-ruby-11">*</span>
                  </label>
                  <input
                    v-model="form.flow_button_text"
                    maxlength="25"
                    class="reset-base text-sm"
                    :class="fieldClass(form.flow_button_text, true)"
                    :placeholder="
                      t('JABVOX_WA_TEMPLATES.CREATE.FLOW.BUTTON_TEXT_PH')
                    "
                  />
                </div>
                <div class="flex flex-col gap-1">
                  <label class="text-xs text-n-slate-11">
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.CATEGORY') }}
                  </label>
                  <select
                    v-model="form.flow_category"
                    class="reset-base text-sm wa-field wa-field-valid"
                  >
                    <option v-for="fc in FLOW_CATEGORIES" :key="fc" :value="fc">
                      {{ flowCategoryLabel(fc) }}
                    </option>
                  </select>
                  <p class="text-[11px] text-n-slate-10">
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.CATEGORY_HELP') }}
                  </p>
                </div>
              </div>
              <InlineFlowBuilder v-model="form.flow_screens" />
            </section>

            <!-- ── CAROUSEL: editor de cards (2-10), cada una con su propio
                 uploader de media + hasta 2 botones ── -->
            <section
              v-if="wizardStep === 2 && isCarouselKind"
              class="space-y-3"
            >
              <div class="flex items-center justify-between">
                <h3
                  class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.SECTION_TITLE') }}
                </h3>
                <button
                  v-if="form.cards.length < CARD_MAX"
                  class="text-xs text-n-brand hover:underline"
                  @click="addCard"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.ADD_CARD') }}
                </button>
              </div>
              <p class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.NOTE') }}
              </p>
              <div
                v-for="(card, ci) in form.cards"
                :key="ci"
                class="rounded-xl border border-n-weak p-3"
              >
                <div class="flex items-center justify-between mb-2.5">
                  <p
                    class="text-xs font-medium text-n-slate-12 flex items-center gap-1.5"
                  >
                    <span
                      class="i-lucide-gallery-horizontal-end size-3.5 text-n-slate-10"
                      aria-hidden="true"
                    />
                    {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.CARD_LABEL') }}
                    {{ ci + 1 }}
                  </p>
                  <button class="text-n-ruby-11 p-1" @click="removeCard(ci)">
                    <span class="i-lucide-trash-2 size-3.5" />
                  </button>
                </div>

                <!-- Controles a la izquierda · previa de la tarjeta a la derecha -->
                <div class="grid grid-cols-1 lg:grid-cols-[1fr_190px] gap-3">
                  <div class="space-y-2 min-w-0">
                    <label class="text-[11px] text-n-slate-11 block">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.MEDIA_TYPE') }}
                    </label>
                    <select
                      v-model="card.header_type"
                      class="reset-base text-xs w-32 wa-field wa-field-valid"
                    >
                      <option
                        v-for="ht in CARD_HEADER_TYPES"
                        :key="ht"
                        :value="ht"
                      >
                        {{ mediaTypeLabel(ht) }}
                      </option>
                    </select>

                    <label class="text-[11px] text-n-slate-11 block">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.MEDIA_FILE') }}
                      <span class="text-n-ruby-11">*</span>
                    </label>
                    <input
                      type="file"
                      :accept="
                        card.header_type === 'IMAGE'
                          ? 'image/jpeg,image/png'
                          : 'video/mp4,video/3gpp'
                      "
                      class="reset-base text-xs w-full rounded-lg border px-2 py-1.5 file:mr-3 file:rounded-md file:border-0 file:bg-n-brand file:text-white file:px-3 file:py-1 file:text-xs"
                      :class="
                        card.header_handle
                          ? 'border-n-teal-8 bg-n-teal-2'
                          : 'border-n-ruby-8 bg-n-ruby-2'
                      "
                      @change="e => onCardFileChange(e, ci)"
                    />
                    <p
                      v-if="card.header_handle"
                      class="text-[11px] text-n-teal-11 flex items-center gap-1"
                    >
                      <span class="i-lucide-check size-3" aria-hidden="true" />
                      {{ t('JABVOX_WA_TEMPLATES.FORM.MEDIA_READY') }}
                    </p>
                    <p
                      v-else-if="card.header_media_name"
                      class="text-[11px] text-n-amber-11 flex items-center gap-1"
                    >
                      <span
                        class="i-lucide-alert-triangle size-3"
                        aria-hidden="true"
                      />
                      {{
                        t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.NOT_UPLOADED')
                      }}
                    </p>
                    <p
                      v-else
                      class="text-[11px] text-n-ruby-11 flex items-center gap-1"
                    >
                      <span class="i-lucide-circle size-3" aria-hidden="true" />
                      {{
                        t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.MEDIA_REQUIRED')
                      }}
                    </p>

                    <label class="text-[11px] text-n-slate-11 block">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.CARD_BODY') }}
                    </label>
                    <input
                      v-model="card.body_content"
                      class="reset-base text-xs w-full"
                      :class="fieldClass(card.body_content)"
                      :placeholder="
                        t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.CARD_BODY_PH')
                      "
                    />
                    <div class="flex items-center justify-between">
                      <p class="text-[11px] text-n-slate-10">
                        {{
                          t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.CARD_BUTTONS')
                        }}
                      </p>
                      <button
                        v-if="card.buttons.length < 2"
                        class="text-[11px] text-n-brand hover:underline"
                        @click="addCardButton(card)"
                      >
                        {{ t('JABVOX_WA_TEMPLATES.CREATE.ADD_BUTTON') }}
                      </button>
                    </div>
                    <div
                      v-for="(btn, bi) in card.buttons"
                      :key="bi"
                      class="flex flex-wrap gap-2 items-center p-2 rounded-lg bg-n-alpha-1"
                    >
                      <select
                        v-model="btn.type"
                        class="reset-base text-xs w-32"
                      >
                        <option
                          v-for="bt in CARD_BUTTON_TYPES"
                          :key="bt"
                          :value="bt"
                        >
                          {{ buttonTypeLabel(bt) }}
                        </option>
                      </select>
                      <input
                        v-model="btn.text"
                        maxlength="25"
                        class="reset-base text-xs flex-1 min-w-24"
                        :class="fieldClass(btn.text, true)"
                        :placeholder="
                          t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_TEXT')
                        "
                      />
                      <input
                        v-if="btn.type === 'URL'"
                        v-model="btn.url"
                        class="reset-base text-xs flex-1 min-w-36"
                        :class="fieldClass(btn.url, true)"
                        :placeholder="
                          t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_URL')
                        "
                      />
                      <input
                        v-if="btn.type === 'PHONE_NUMBER'"
                        v-model="btn.phone_number"
                        maxlength="20"
                        class="reset-base text-xs flex-1 min-w-36"
                        :class="fieldClass(btn.phone_number, true)"
                        :placeholder="
                          t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_PHONE')
                        "
                      />
                      <button
                        class="text-n-ruby-11 p-1"
                        @click="removeCardButton(card, bi)"
                      >
                        <span class="i-lucide-trash-2 size-3.5" />
                      </button>
                    </div>
                  </div>

                  <!-- Previa de la tarjeta tal como se verá en WhatsApp -->
                  <div class="lg:sticky lg:top-2 self-start">
                    <p
                      class="text-[10px] uppercase tracking-wide text-n-slate-10 mb-1.5"
                    >
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.PREVIEW') }}
                    </p>
                    <div
                      class="rounded-xl overflow-hidden border border-n-weak bg-[#e5ddd5] p-2"
                    >
                      <div
                        class="rounded-lg overflow-hidden bg-white shadow-sm"
                      >
                        <img
                          v-if="
                            card.header_type === 'IMAGE' &&
                            card.header_media_preview
                          "
                          :src="card.header_media_preview"
                          alt=""
                          class="w-full h-24 object-cover"
                        />
                        <video
                          v-else-if="
                            card.header_type === 'VIDEO' &&
                            card.header_media_preview
                          "
                          :src="card.header_media_preview"
                          class="w-full h-24 object-cover"
                          muted
                        />
                        <div
                          v-else
                          class="w-full h-24 flex flex-col items-center justify-center gap-1 bg-n-alpha-2 text-n-slate-9"
                        >
                          <span
                            :class="
                              card.header_type === 'VIDEO'
                                ? 'i-lucide-video'
                                : 'i-lucide-image'
                            "
                            class="size-5"
                            aria-hidden="true"
                          />
                          <span class="text-[10px]">
                            {{
                              t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.NO_MEDIA')
                            }}
                          </span>
                        </div>
                        <div class="p-2">
                          <p
                            class="text-[11px] text-gray-800 leading-snug break-words"
                          >
                            {{
                              card.body_content ||
                              t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.NO_BODY')
                            }}
                          </p>
                        </div>
                        <div
                          v-for="(btn, bi) in card.buttons"
                          :key="`prev-${bi}`"
                          class="border-t border-gray-200 py-1.5 text-center text-[11px] text-[#00a5f4] truncate px-2"
                        >
                          {{
                            btn.text ||
                            t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.NO_BUTTON')
                          }}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
              <p
                v-if="form.cards.length < CARD_MIN"
                class="text-[11px] text-n-ruby-11"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.CAROUSEL.MIN_CARDS_NOTE') }}
              </p>
            </section>

            <section v-if="wizardStep === 3" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.VARS_MANAGER') }}
              </h3>
              <div
                v-if="detectedVars.length"
                class="rounded-lg bg-n-alpha-1 p-3 space-y-2"
              >
                <p class="text-xs font-medium text-n-slate-11">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.VARS_TITLE') }}
                </p>
                <div
                  v-for="n in detectedVars"
                  :key="n"
                  class="flex items-center gap-2"
                >
                  <span
                    class="text-xs font-mono bg-n-alpha-2 px-2 py-0.5 rounded text-n-brand"
                  >
                    {{ VAR_OPEN }}{{ n }}{{ VAR_CLOSE }}
                  </span>
                  <input
                    v-model="form.var_descriptions[n]"
                    class="reset-base text-xs flex-1"
                    :class="fieldClass(form.var_descriptions[n])"
                    :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.VAR_DESC_PH')"
                  />
                </div>
              </div>
              <div
                v-else
                class="rounded-lg border border-dashed border-n-weak p-4 text-sm text-n-slate-10"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.VARS_EMPTY') }}
              </div>
            </section>

            <section v-if="wizardStep === 4" class="space-y-2">
              <div class="flex items-center justify-between">
                <h3
                  class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.BUTTONS_LABEL') }}
                </h3>
                <button
                  v-if="form.buttons.length < 10"
                  class="text-xs text-n-brand hover:underline"
                  @click="addButton"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.ADD_BUTTON') }}
                </button>
              </div>
              <div
                v-for="(btn, i) in form.buttons"
                :key="i"
                class="flex flex-wrap gap-2 items-center p-2.5 rounded-lg bg-n-alpha-1"
              >
                <select
                  v-model="btn.type"
                  class="reset-base text-xs w-32"
                  :class="fieldClass(btn.type)"
                >
                  <option v-for="bt in BUTTON_TYPES" :key="bt" :value="bt">
                    {{ buttonTypeLabel(bt) }}
                  </option>
                </select>
                <input
                  v-model="btn.text"
                  maxlength="25"
                  class="reset-base text-xs flex-1 min-w-24"
                  :class="fieldClass(btn.text, true)"
                  :placeholder="
                    btn.type === 'COPY_CODE'
                      ? t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_COPY_CODE')
                      : t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_TEXT')
                  "
                />
                <input
                  v-if="btn.type === 'URL'"
                  v-model="btn.url"
                  class="reset-base text-xs flex-1 min-w-36"
                  :class="fieldClass(btn.url, true)"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_URL')"
                />
                <input
                  v-if="
                    btn.type === 'PHONE_NUMBER' || btn.type === 'VOICE_CALL'
                  "
                  v-model="btn.phone_number"
                  maxlength="20"
                  class="reset-base text-xs flex-1 min-w-36"
                  :class="fieldClass(btn.phone_number, true)"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_PHONE')"
                />
                <!-- Botón FLOW: selecciona un JabvoxWhatsappFlow publicado de
                     la bandeja elegida, nunca un flow_id de texto libre. -->
                <select
                  v-if="btn.type === 'FLOW'"
                  v-model="btn.flow_id"
                  class="reset-base text-xs flex-1 min-w-48"
                  :class="fieldClass(btn.flow_id, true)"
                >
                  <option value="">
                    {{ t('JABVOX_WA_FLOWS.TEMPLATES_INTEGRATION.SELECT_FLOW') }}
                  </option>
                  <option
                    v-for="wf in publishedFlowsForInbox"
                    :key="wf.id"
                    :value="wf.meta_flow_id"
                  >
                    {{ wf.name }}
                  </option>
                </select>
                <p
                  v-if="btn.type === 'FLOW' && !publishedFlowsForInbox.length"
                  class="text-[11px] text-n-amber-11 basis-full"
                >
                  {{
                    t(
                      'JABVOX_WA_FLOWS.TEMPLATES_INTEGRATION.NO_PUBLISHED_FLOWS'
                    )
                  }}
                </p>
                <button class="text-n-ruby-11 p-1" @click="removeButton(i)">
                  <span class="i-lucide-trash-2 size-3.5" />
                </button>
              </div>
              <!-- Reglas de agrupación/exclusividad/cantidad por tipo, en vivo -->
              <div
                v-if="buttonErrors.length"
                class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-3 space-y-1"
              >
                <p
                  v-for="msg in buttonErrors"
                  :key="msg"
                  class="text-[11px] text-n-ruby-11"
                >
                  {{ msg }}
                </p>
              </div>
            </section>

            <section v-if="wizardStep === 5" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.PREVIEW_HEADING') }}
              </h3>
              <p class="text-sm text-n-slate-11">
                {{ t('JABVOX_WA_TEMPLATES.CREATE.PREVIEW_NOTE') }}
              </p>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
                <p class="text-xs text-n-slate-10 mb-2">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_TITLE') }}
                </p>
                <div class="grid grid-cols-2 gap-3 text-xs text-n-slate-11">
                  <p>
                    <span class="text-n-slate-9">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_CATEGORY') }}
                    </span>
                    {{ form.category }}
                  </p>
                  <p>
                    <span class="text-n-slate-9">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_LANGUAGE') }}
                    </span>
                    {{ form.language }}
                  </p>
                  <p>
                    <span class="text-n-slate-9">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_VARIABLES') }}
                    </span>
                    {{ detectedVars.length }}
                  </p>
                  <p>
                    <span class="text-n-slate-9">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_BUTTONS') }}
                    </span>
                    {{ form.buttons.filter(b => b.text).length }}
                  </p>
                </div>
              </div>
            </section>

            <section v-if="wizardStep === 6" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.SUBMIT_HEADING') }}
              </h3>
              <div
                class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 space-y-2 text-sm text-n-slate-11"
              >
                <p>{{ t('JABVOX_WA_TEMPLATES.CREATE.SUBMIT_NOTE') }}</p>
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.SUBMIT_HINT') }}
                </p>
              </div>
              <div
                v-if="missingRequiredFields.length"
                class="rounded-xl border border-n-ruby-6 bg-n-ruby-2 p-4 space-y-1.5"
              >
                <p class="text-sm font-medium text-n-ruby-11">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.MISSING_REQUIRED') }}
                </p>
                <ul class="list-disc ltr:pl-5 rtl:pr-5 text-xs text-n-ruby-11">
                  <li v-for="field in missingRequiredFields" :key="field">
                    {{ field }}
                  </li>
                </ul>
              </div>
              <!-- Validación en vivo (paridad con el editor de Meta): mismas
                   reglas que corre el servidor, mostradas ANTES de enviar. -->
              <div
                v-if="!isAuthenticationKind && templateValidationErrors.length"
                class="rounded-xl border border-n-ruby-6 bg-n-ruby-2 p-4 space-y-1.5"
              >
                <p class="text-sm font-medium text-n-ruby-11">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.VALIDATION_ERRORS_TITLE') }}
                </p>
                <ul class="list-disc ltr:pl-5 rtl:pr-5 text-xs text-n-ruby-11">
                  <li v-for="msg in templateValidationErrors" :key="msg">
                    {{ msg }}
                  </li>
                </ul>
              </div>
            </section>
          </div>
          <div class="flex gap-3 px-5 py-3.5 border-t border-n-weak shrink-0">
            <button
              class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 disabled:opacity-50"
              :disabled="wizardStep === 1"
              @click="previousWizardStep"
            >
              {{ t('JABVOX_WA_TEMPLATES.CREATE.BACK') }}
            </button>
            <button
              v-if="wizardStep < 6"
              class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
              @click="nextWizardStep"
            >
              {{ t('JABVOX_WA_TEMPLATES.CREATE.NEXT') }}
            </button>
            <button
              v-if="wizardStep === 6"
              class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
              :disabled="
                saving ||
                missingRequiredFields.length > 0 ||
                (!isAuthenticationKind && !templateIsValid)
              "
              @click="submitForm"
            >
              {{
                saving
                  ? t('JABVOX_WA_TEMPLATES.CREATE.SUBMITTING')
                  : editingTemplate
                    ? t('JABVOX_WA_TEMPLATES.CREATE.UPDATE')
                    : t('JABVOX_WA_TEMPLATES.CREATE.SUBMIT')
              }}
            </button>
            <button
              class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
              @click="showForm = false"
            >
              {{ t('JABVOX_WA_TEMPLATES.CREATE.CANCEL') }}
            </button>
          </div>
        </div>
        <!-- Right: live preview -->
        <div
          class="hidden md:flex w-80 border-l border-n-weak bg-n-alpha-1 flex-col overflow-hidden shrink-0"
        >
          <div class="px-4 py-3 border-b border-n-weak">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_WA_TEMPLATES.CREATE.PREVIEW_TITLE') }}
            </p>
          </div>
          <div
            class="flex-1 overflow-auto p-4 flex flex-col items-center gap-4"
          >
            <div
              class="w-full max-w-[200px] bg-[#0b141a] rounded-2xl p-3 shadow-lg"
            >
              <div
                class="bg-[#1f2c33] rounded-xl overflow-hidden text-white text-xs"
              >
                <div
                  class="bg-[#202c33] mx-2 mt-2 rounded-lg p-2.5 space-y-1.5 relative"
                >
                  <div
                    v-if="form.header_type === 'TEXT' && form.header_content"
                    class="font-semibold text-[11px] text-white/90 border-b border-white/10 pb-1.5 mb-1.5"
                  >
                    {{ form.header_content }}
                  </div>
                  <template v-else-if="isMediaHeader">
                    <img
                      v-if="
                        form.header_type === 'IMAGE' &&
                        form.header_media_preview
                      "
                      :src="form.header_media_preview"
                      alt="preview"
                      class="max-h-28 w-full rounded object-cover mb-1.5"
                    />
                    <video
                      v-else-if="
                        form.header_type === 'VIDEO' &&
                        form.header_media_preview
                      "
                      :src="form.header_media_preview"
                      class="max-h-28 w-full rounded bg-black mb-1.5"
                    />
                    <div
                      v-else-if="
                        form.header_type === 'DOCUMENT' &&
                        form.header_media_preview
                      "
                      class="flex items-center gap-1.5 bg-white/10 rounded px-2 py-1.5 text-white/70 text-[10px] mb-1.5"
                    >
                      <span
                        class="i-lucide-file-text size-4"
                        aria-hidden="true"
                      />
                      {{ form.header_media_name }}
                    </div>
                    <div
                      v-else
                      class="h-20 bg-white/10 rounded flex items-center justify-center text-white/40 text-[10px]"
                    >
                      {{ form.header_type }}
                    </div>
                  </template>
                  <p
                    class="text-[11px] leading-relaxed text-white/90 whitespace-pre-wrap"
                  >
                    {{ form.body || '…' }}
                  </p>
                  <p
                    v-if="form.footer"
                    class="text-[10px] text-white/40 border-t border-white/10 pt-1 mt-1"
                  >
                    {{ form.footer }}
                  </p>
                  <p class="text-right text-[9px] text-white/30">
                    {{
                      new Date().toLocaleTimeString([], {
                        hour: '2-digit',
                        minute: '2-digit',
                      })
                    }}
                  </p>
                </div>
                <div
                  v-if="previewButtons.length"
                  class="mx-2 mb-2 mt-0.5 space-y-1"
                >
                  <div
                    v-for="btn in previewButtons"
                    :key="btn.key"
                    class="bg-[#2a3942] rounded py-1.5 text-center text-[11px] text-[#53bdeb] font-medium flex items-center justify-center gap-1"
                  >
                    <span
                      v-if="btn.isFlow"
                      class="i-lucide-clipboard-list size-3"
                      aria-hidden="true"
                    />
                    {{ btn.text }}
                  </div>
                </div>
              </div>
            </div>
            <!-- Previa del formulario, debajo de la del mensaje: así se ve
                 primero lo que llega al chat y luego lo que abre el botón. -->
            <div v-if="isFlowKind && form.flow_screens.length" class="w-full">
              <p
                class="text-[10px] uppercase tracking-wide text-n-slate-10 mb-1.5 text-center"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.PREVIEW_TITLE') }}
              </p>
              <div
                class="rounded-xl border border-n-weak overflow-hidden h-[320px]"
              >
                <FlowPreview
                  :screens="form.flow_screens"
                  :flow-name="form.name"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ── DETAIL DRAWER ──────────────────────────────────────────────── -->
    <div v-if="detailTemplate" class="fixed inset-0 z-50 flex justify-end">
      <div class="absolute inset-0 bg-black/40" @click="closeDetail" />
      <div
        class="relative w-full md:max-w-[900px] h-full bg-n-solid-1 shadow-2xl flex flex-col overflow-hidden"
      >
        <div
          class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak shrink-0"
        >
          <div>
            <h2 class="font-semibold text-n-slate-12">
              {{ detailTemplate.name }}
            </h2>
            <div class="flex items-center gap-2 mt-0.5">
              <span
                class="inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full"
                :class="statusClass(detailTemplate.status)"
              >
                {{ statusLabel(detailTemplate.status) }}
              </span>
              <span class="text-xs text-n-slate-10">
                {{ detailTemplate.language }} {{ DOT }}
                {{ categoryLabel(detailTemplate.category) }}
              </span>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <button
              class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3"
              @click="
                openEdit(detailTemplate);
                closeDetail();
              "
            >
              {{ t('JABVOX_WA_TEMPLATES.ACTIONS.EDIT') }}
            </button>
            <button class="text-n-slate-11" @click="closeDetail">
              <span class="i-lucide-x size-5" />
            </button>
          </div>
        </div>
        <div class="flex gap-0 border-b border-n-weak px-5 shrink-0">
          <button
            v-for="dt in [
              'components',
              'variables',
              'analytics',
              'history',
              'versions',
              'meta_json',
            ]"
            :key="dt"
            class="px-3 py-2 text-xs -mb-px border-b-2 transition-colors"
            :class="
              detailTab === dt
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-11'
            "
            @click="detailTab = dt"
          >
            {{ detailTabLabel(dt) }}
          </button>
        </div>
        <div class="flex-1 overflow-auto p-5">
          <div v-if="detailTab === 'components'" class="space-y-4">
            <div
              v-if="detailTemplate.rejected_reason"
              class="p-3 rounded-lg bg-n-ruby-3 text-n-ruby-11 text-sm"
            >
              <span class="font-medium">
                {{ t('JABVOX_WA_TEMPLATES.DETAIL.REJECTED_REASON') }}
              </span>
              {{ detailTemplate.rejected_reason }}
            </div>
            <div class="grid grid-cols-2 gap-3 text-xs">
              <div>
                <span class="text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.DETAIL.META_ID') }}
                </span>
                <p class="font-mono text-n-slate-12 mt-0.5">
                  {{
                    detailTemplate.meta_template_id ||
                    t('JABVOX_WA_TEMPLATES.DETAIL.EMPTY_VALUE')
                  }}
                </p>
              </div>
              <div>
                <span class="text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.DETAIL.WABA_ID') }}
                </span>
                <p class="font-mono text-n-slate-12 mt-0.5">
                  {{
                    detailTemplate.waba_id ||
                    t('JABVOX_WA_TEMPLATES.DETAIL.EMPTY_VALUE')
                  }}
                </p>
              </div>
              <div>
                <span class="text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.DETAIL.INBOX') }}
                </span>
                <p class="text-n-slate-12 mt-0.5">
                  {{ detailTemplate.inbox_name }}
                </p>
              </div>
              <div>
                <span class="text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.DETAIL.QUALITY') }}
                </span>
                <p
                  class="mt-0.5"
                  :class="qualityClass(detailTemplate.quality_score)"
                >
                  {{ qualityLabel(detailTemplate.quality_score) }}
                </p>
              </div>
            </div>
            <div
              v-if="detailTemplate.header_type"
              class="rounded-lg bg-n-alpha-1 p-3"
            >
              <p class="text-xs font-medium text-n-slate-10 mb-1">
                {{
                  t('JABVOX_WA_TEMPLATES.DETAIL.HEADER_WITH_TYPE', {
                    type: detailTemplate.header_type,
                  })
                }}
              </p>
              <p v-if="!detailHeaderIsMedia" class="text-sm text-n-slate-12">
                {{
                  detailTemplate.header_content ||
                  t('JABVOX_WA_TEMPLATES.DETAIL.MEDIA')
                }}
              </p>
              <!-- Media de la plantilla (imagen/video/documento) + URL de Meta -->
              <template v-else>
                <img
                  v-if="detailHeaderType === 'IMAGE' && detailHeaderMediaUrl"
                  :src="detailHeaderMediaUrl"
                  alt="header"
                  class="w-full max-h-56 object-contain rounded-md bg-n-alpha-2"
                />
                <video
                  v-else-if="
                    detailHeaderType === 'VIDEO' && detailHeaderMediaUrl
                  "
                  :src="detailHeaderMediaUrl"
                  controls
                  class="w-full max-h-56 rounded-md bg-black"
                />
                <p v-else class="text-sm text-n-slate-12">
                  {{ t('JABVOX_WA_TEMPLATES.DETAIL.MEDIA') }}
                </p>
                <a
                  v-if="detailHeaderMediaUrl"
                  :href="detailHeaderMediaUrl"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="block truncate mt-1.5 text-[11px] text-n-blue-11 hover:underline"
                  :title="detailHeaderMediaUrl"
                >
                  {{ detailHeaderMediaUrl }}
                </a>
              </template>
            </div>
            <div
              v-if="detailTemplate.body_content"
              class="rounded-lg bg-n-alpha-1 p-3"
            >
              <p class="text-xs font-medium text-n-slate-10 mb-1">
                {{ t('JABVOX_WA_TEMPLATES.DETAIL.BODY') }}
              </p>
              <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
                {{ detailTemplate.body_content }}
              </p>
            </div>
            <div
              v-if="detailTemplate.footer_content"
              class="rounded-lg bg-n-alpha-1 p-3"
            >
              <p class="text-xs font-medium text-n-slate-10 mb-1">
                {{ t('JABVOX_WA_TEMPLATES.DETAIL.FOOTER') }}
              </p>
              <p class="text-sm text-n-slate-12">
                {{ detailTemplate.footer_content }}
              </p>
            </div>
            <div v-if="detailTemplate.buttons_json?.length" class="space-y-1.5">
              <p class="text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.DETAIL.BUTTONS') }}
              </p>
              <div
                v-for="btn in detailTemplate.buttons_json"
                :key="btn.text"
                class="flex items-center gap-2 text-xs p-2 rounded bg-n-alpha-1"
              >
                <span
                  class="font-mono bg-n-alpha-2 px-1.5 py-0.5 rounded text-n-brand"
                >
                  {{ btn.type }}
                </span>
                <span class="text-n-slate-12">{{ btn.text }}</span>
                <span v-if="btn.url" class="text-n-slate-10 truncate">{{
                  btn.url
                }}</span>
              </div>
            </div>
          </div>
          <div v-else-if="detailTab === 'variables'" class="space-y-2">
            <div
              v-if="!Object.keys(detailTemplate.variables_json || {}).length"
              class="text-sm text-n-slate-11"
            >
              {{ t('JABVOX_WA_TEMPLATES.DETAIL.EMPTY_VALUE') }}
            </div>
            <div
              v-for="(desc, n) in detailTemplate.variables_json"
              :key="n"
              class="flex items-center gap-3 p-2.5 rounded-lg bg-n-alpha-1"
            >
              <span
                class="font-mono text-sm text-n-brand bg-n-alpha-2 px-2 py-0.5 rounded"
              >
                {{ VAR_OPEN }}{{ n }}{{ VAR_CLOSE }}
              </span>
              <span class="text-sm text-n-slate-11">
                {{ desc || t('JABVOX_WA_TEMPLATES.DETAIL.EMPTY_VALUE') }}
              </span>
            </div>
          </div>
          <div v-else-if="detailTab === 'analytics'" class="space-y-3">
            <div class="grid grid-cols-2 md:grid-cols-3 gap-3">
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.ANALYTICS.SENT') }}
                </p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.sent }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.ANALYTICS.DELIVERED') }}
                </p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.delivered }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.ANALYTICS.READ') }}
                </p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.read }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.ANALYTICS.REPLIED') }}
                </p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.replied }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.ANALYTICS.FAILED') }}
                </p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.failed }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.ANALYTICS.BLOCKED') }}
                </p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.blocked }}
                </p>
              </div>
            </div>
          </div>
          <div v-else-if="detailTab === 'history'" class="space-y-2">
            <div v-if="!detailHistory.length" class="text-sm text-n-slate-11">
              {{ t('JABVOX_WA_TEMPLATES.DETAIL.EMPTY_VALUE') }}
            </div>
            <div
              v-for="log in detailHistory"
              :key="log.id"
              class="flex items-start gap-3 p-2.5 rounded-lg bg-n-alpha-1"
            >
              <span
                class="i-lucide-history size-4 text-n-slate-10 mt-0.5 shrink-0"
              />
              <div>
                <p class="text-sm text-n-slate-12">{{ log.description }}</p>
                <p class="text-xs text-n-slate-10">
                  {{ log.user_name }} {{ DOT }}
                  {{ new Date(log.created_at).toLocaleString() }}
                </p>
              </div>
            </div>
          </div>
          <div v-else-if="detailTab === 'versions'" class="space-y-2">
            <div v-if="!detailVersions.length" class="text-sm text-n-slate-11">
              {{ t('JABVOX_WA_TEMPLATES.DETAIL.EMPTY_VALUE') }}
            </div>
            <div
              v-for="ver in detailVersions"
              :key="ver.id"
              class="p-3 rounded-lg bg-n-alpha-1 space-y-1"
            >
              <div class="flex items-center justify-between">
                <span class="font-medium text-sm text-n-slate-12">
                  {{ VERSION_PREFIX }}{{ ver.version }}
                </span>
                <button
                  class="text-xs text-n-brand hover:underline"
                  @click="restoreVersion(ver)"
                >
                  {{ t('JABVOX_WA_TEMPLATES.DETAIL.RESTORE') }}
                </button>
              </div>
              <p class="text-xs text-n-slate-10">
                {{ ver.created_by_name }} {{ DOT }}
                {{ new Date(ver.created_at).toLocaleString() }}
              </p>
              <p class="text-xs text-n-slate-11 line-clamp-2">
                {{ ver.payload?.body_content }}
              </p>
            </div>
          </div>
          <div v-else-if="detailTab === 'meta_json'">
            <pre
              class="text-xs bg-n-alpha-1 rounded-lg p-3 overflow-auto text-n-slate-11 max-h-[500px]"
              >{{ JSON.stringify(detailTemplate.meta_json, null, 2) }}</pre
            >
          </div>
        </div>
      </div>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="onConfirmAction" />
    <PromptDialog ref="promptDialog" @submit="performDuplicate" />
  </div>
</template>

<style scoped>
/* Uses the shared Jabvox design-system tokens (n-* CSS variables) so this module
   matches the rest of the app in both light and dark themes. */
.wa-shell {
  background: var(--color-background);
  color: var(--color-body);
}

/* Header bar */
.wa-glass-header {
  background: var(--color-background);
  border-bottom: 1px solid var(--color-border-weak, var(--color-border));
}

/* Brand title */
.wa-title {
  color: var(--color-heading);
  letter-spacing: -0.01em;
}

/* Primary action */
.wa-btn-primary {
  color: #fff;
  font-weight: 600;
  background: var(--color-woot);
  border: 1px solid var(--color-woot);
  transition:
    filter 0.2s ease,
    transform 0.2s ease;
}
.wa-btn-primary:hover {
  filter: brightness(1.05);
  transform: translateY(-1px);
}

/* Ghost action */
.wa-btn-ghost {
  color: var(--color-body);
  background: var(--color-background-light);
  border: 1px solid var(--color-border-weak, var(--color-border));
  transition:
    background 0.2s ease,
    border-color 0.2s ease,
    color 0.2s ease;
}
.wa-btn-ghost:hover:not(:disabled) {
  background: var(--color-background);
  border-color: var(--color-border);
  color: var(--color-heading);
}

/* Wizard form fields: reset-base strips native styling, so every field gets
   an explicit visible border. Validation state is color-coded — red when a
   required field is empty, green when it has content. */
.wa-field {
  background: var(--color-background-light);
  color: var(--color-body);
  border: 1.5px solid var(--color-border, #94a3b8);
  border-radius: 0.5rem;
  padding: 0.45rem 0.65rem;
  transition:
    border-color 0.15s ease,
    box-shadow 0.15s ease;
}
.wa-field:focus {
  outline: none;
  border-color: var(--color-woot);
  box-shadow: 0 0 0 3px rgba(31, 147, 255, 0.15);
}
.wa-field::placeholder {
  color: var(--color-body);
  opacity: 0.45;
}
.wa-field-invalid {
  border-color: #ef4444;
  background: rgba(239, 68, 68, 0.04);
}
.wa-field-invalid:focus {
  border-color: #ef4444;
  box-shadow: 0 0 0 3px rgba(239, 68, 68, 0.15);
}
.wa-field-valid {
  border-color: #22c55e;
}
.wa-field-valid:focus {
  border-color: #22c55e;
  box-shadow: 0 0 0 3px rgba(34, 197, 94, 0.15);
}

/* KPI tiles */
.wa-kpi {
  background: var(--color-background-light);
  border: 1px solid var(--color-border-weak, var(--color-border));
  transition:
    transform 0.2s ease,
    border-color 0.2s ease;
}
.wa-kpi:hover {
  transform: translateY(-2px);
  border-color: var(--color-woot);
}

/* Tabs (pill style) */
.wa-tab {
  color: var(--color-body);
  background: transparent;
  border: 1px solid transparent;
}
.wa-tab:hover {
  color: var(--color-heading);
}
.wa-tab-active {
  color: var(--color-woot);
  background: var(--color-background-light);
  border-color: var(--color-border);
}

/* Template cards */
.wa-card {
  border-radius: 16px;
  background: var(--color-background-light);
  border: 1px solid var(--color-border-weak, var(--color-border));
}
.wa-card-hover {
  transition:
    transform 0.24s ease,
    border-color 0.24s ease,
    box-shadow 0.24s ease;
}
.wa-card-hover:hover {
  transform: translateY(-3px);
  border-color: var(--color-woot);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
}

/* Card action icons — revealed/brightened on card hover */
.wa-card-actions {
  opacity: 0.55;
  transition: opacity 0.2s ease;
}
.wa-card-hover:hover .wa-card-actions {
  opacity: 1;
}
.wa-icon-btn {
  padding: 6px;
  border-radius: 8px;
  color: var(--color-body);
  transition:
    background 0.18s ease,
    color 0.18s ease;
}
.wa-icon-btn:hover {
  background: var(--color-background);
  color: var(--color-heading);
}
.wa-icon-btn-danger {
  color: var(--color-error, #f06767);
}
.wa-icon-btn-danger:hover {
  background: var(--color-background);
  color: var(--color-error, #f06767);
}

/* Empty state */
.wa-empty {
  border-radius: 20px;
  border: 1px dashed var(--color-border);
  background: var(--color-background-light);
}
.wa-empty-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 64px;
  height: 64px;
  border-radius: 18px;
  background: var(--color-background);
  border: 1px solid var(--color-border);
}

/* Skeleton shimmer */
.wa-skeleton {
  pointer-events: none;
}
.wa-shimmer {
  background: linear-gradient(
    90deg,
    var(--color-background-light) 25%,
    var(--color-background) 37%,
    var(--color-background-light) 63%
  );
  background-size: 400% 100%;
  animation: wa-shimmer 1.4s ease infinite;
}
@keyframes wa-shimmer {
  0% {
    background-position: 100% 50%;
  }
  100% {
    background-position: 0 50%;
  }
}
</style>
