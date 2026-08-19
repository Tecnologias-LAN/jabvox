<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import bulkWhatsappAPI from 'dashboard/api/jabvox/bulkWhatsapp';
import LeadsPickerTab from './LeadsPickerTab.vue';
import BatchReportDialog from './components/BatchReportDialog.vue';
import AnalyticsTab from './components/AnalyticsTab.vue';

const { t } = useI18n();
const rootStore = useStore();
const { isAdmin } = useAdmin();
const currentUserId = useMapGetter('getCurrentUserID');

const reportDialog = ref(null);
// Audiencia a reenviar: respuesta de reuseBatch con los lead_ids ya filtrados por
// estado, para precargar la selección en LeadsPickerTab.
const reuseData = ref(null);

const activeTab = ref('send');
// Only real administrators manage the webhook config; custom-role senders get
// the send + history tabs (matches the backend split in ConfigController).
const TABS = computed(() =>
  isAdmin.value
    ? ['send', 'history', 'reports', 'settings']
    : ['send', 'history', 'reports']
);

// Within the Send tab: choose the recipient source (CSV upload or existing leads).
const source = ref('csv');
const SOURCES = ['csv', 'leads'];

// ── Catalogs ────────────────────────────────────────────────────────────────
const allInboxes = useMapGetter('inboxes/getInboxes');
const senders = ref([]);

// Paso 1 solo ofrece bandejas de canal WhatsApp (Cloud API oficial).
const inboxes = computed(() =>
  (allInboxes.value || []).filter(ib => ib.channel_type === 'Channel::Whatsapp')
);

// Todos los usuarios de la cuenta que devuelve el backend pueden ser emisores;
// el propio backend valida quién puede enviar (admin o rol con permiso). No se
// vuelve a filtrar por rol aquí para no ocultar agentes/roles autorizados.
const availableSenders = computed(() => senders.value || []);

// Etiqueta legible del emisor tolerante a datos faltantes: evita mostrar "()".
const senderLabel = u => {
  const name = (u?.name || '').trim();
  const email = (u?.email || '').trim();
  if (name && email) return `${name} (${email})`;
  return name || email || `#${u?.id}`;
};

// ── Config (webhook only; the report email is chosen per send) ───────────────
const webhookUrl = ref('');
const savingConfig = ref(false);

// A bulk send needs the webhook configured.
const configReady = computed(() => !!webhookUrl.value.trim());

// ── Send form ─────────────────────────────────────────────────────────────
const selectedInboxId = ref('');
const selectedSenderId = ref('');
const file = ref(null);
const parsedPreview = ref([]);
const parseError = ref('');
const sending = ref(false);
const fileInput = ref(null);

const REQUIRED_HEADERS = ['nombre', 'numero', 'template', 'idioma'];

const selectedInbox = computed(() =>
  inboxes.value.find(ib => ib.id === Number(selectedInboxId.value))
);

// Official WhatsApp channels send approved templates; generic API inboxes send a plain text
// message. Mirrors the backend detection so the UI matches what will happen.
const sendMode = computed(() => {
  const ib = selectedInbox.value;
  if (!ib) return null;
  // Solo bandejas WhatsApp Cloud API → envío por plantilla aprobada.
  return ib.channel_type === 'Channel::Whatsapp' ? 'template' : 'text';
});

const canSend = computed(
  () =>
    configReady.value &&
    !!file.value &&
    !!selectedInboxId.value &&
    !!selectedSenderId.value &&
    !parseError.value &&
    parsedPreview.value.length > 0
);

// ── Wizard stepper (4 pasos, secuencial y obligatorio para AMBOS flujos) ─────
// 1: bandeja + emisor | 2: destinatarios (CSV: archivo / leads: audiencia) |
// 3: plantilla + variables (o texto) | 4: previsualización + enviar.
// Tanto CSV como leads recorren los 4 pasos. En leads, LeadsPickerTab muestra la
// sección que corresponde al paso vía la prop `step`.
const wizardStep = ref(1);
const leadsRef = ref(null);
// Validez del paso actual reportada por LeadsPickerTab (audiencia/mensaje/envío).
const leadsStepValid = ref(false);
const onLeadsValidity = valid => {
  leadsStepValid.value = valid;
};

// Validez de cada paso — "Siguiente" se bloquea si el paso actual no es válido.
const step1Valid = computed(
  () => configReady.value && !!selectedInboxId.value && !!selectedSenderId.value
);
const step2Valid = computed(() => {
  if (source.value === 'csv') {
    return !parseError.value && parsedPreview.value.length > 0;
  }
  return leadsStepValid.value; // audiencia seleccionada
});
// Paso 3 (plantilla/variables): en CSV la plantilla va en el archivo, así que no
// requiere acción; en leads depende de que el mensaje esté completo.
const step3Valid = computed(() =>
  source.value === 'csv' ? true : leadsStepValid.value
);
const canGoNext = computed(() => {
  if (wizardStep.value === 1) return step1Valid.value;
  if (wizardStep.value === 2) return step2Valid.value;
  if (wizardStep.value === 3) return step3Valid.value;
  return true;
});

const nextStep = () => {
  if (!canGoNext.value) return;
  wizardStep.value = Math.min(wizardStep.value + 1, 4);
};
const prevStep = () => {
  wizardStep.value = Math.max(wizardStep.value - 1, 1);
};
const resetWizard = () => {
  wizardStep.value = 1;
};

// Downloads a sample CSV that matches the selected inbox's mode: for official WhatsApp the
// 'template' column holds an approved template name; for API inboxes it holds the message text.
const downloadSample = () => {
  if (!sendMode.value) return;
  const rows =
    sendMode.value === 'template'
      ? [
          'nombre,numero,template,idioma',
          'Juan Perez,573001234567,bienvenida,es',
          'Maria Lopez,573007654321,promocion_junio,es',
        ]
      : [
          'nombre,numero,template,idioma',
          'Juan Perez,573001234567,Hola Juan, gracias por escribirnos.,es',
          'Maria Lopez,573007654321,Hola Maria, tu pedido va en camino.,es',
        ];
  // Prepend a UTF-8 BOM so Excel opens accented names correctly.
  const blob = new Blob([`\uFEFF${rows.join('\n')}`], {
    type: 'text/csv;charset=utf-8;',
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download =
    sendMode.value === 'template'
      ? 'ejemplo_plantilla.csv'
      : 'ejemplo_texto.csv';
  a.click();
  URL.revokeObjectURL(url);
};

// Lightweight client-side preview/validation; the backend re-parses authoritatively.
const parseCsv = text => {
  const lines = text
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(Boolean);
  if (!lines.length)
    return { rows: [], error: t('JABVOX_BULK_WA.SEND.EMPTY_FILE') };

  const headers = lines[0].split(',').map(h => h.trim().toLowerCase());
  const missing = REQUIRED_HEADERS.filter(h => !headers.includes(h));
  if (missing.length) {
    return {
      rows: [],
      error: t('JABVOX_BULK_WA.SEND.MISSING_HEADERS', {
        cols: missing.join(', '),
      }),
    };
  }

  const rows = lines.slice(1).map(line => {
    const cells = line.split(',');
    const obj = {};
    headers.forEach((h, i) => {
      obj[h] = (cells[i] || '').trim();
    });
    return obj;
  });
  return { rows, error: '' };
};

const onFileChange = event => {
  const f = event.target.files?.[0];
  parsedPreview.value = [];
  parseError.value = '';
  if (!f) {
    file.value = null;
    return;
  }
  file.value = f;
  const reader = new FileReader();
  reader.onload = e => {
    const { rows, error } = parseCsv(String(e.target.result || ''));
    parseError.value = error;
    parsedPreview.value = rows;
  };
  reader.readAsText(f);
};

const resetForm = () => {
  file.value = null;
  parsedPreview.value = [];
  parseError.value = '';
  if (fileInput.value) fileInput.value.value = '';
  resetWizard();
};

// ── History ───────────────────────────────────────────────────────────────
const batches = ref([]);
const loadingBatches = ref(false);

const loadBatches = async () => {
  loadingBatches.value = true;
  try {
    const { data } = await bulkWhatsappAPI.getBatches();
    batches.value = data;
  } catch {
    useAlert(t('JABVOX_BULK_WA.HISTORY.ERROR'));
  } finally {
    loadingBatches.value = false;
  }
};

// After a leads-based send, jump to the history tab and refresh it.
const onLeadsSent = () => {
  activeTab.value = 'history';
  reuseData.value = null;
  loadBatches();
};

// Abre el reporte por ejecución de un batch del historial.
const openReport = batch => reportDialog.value?.openDialog(batch);

// "Reenviar a esta audiencia": la respuesta trae los lead_ids ya filtrados por
// estado, la bandeja, el emisor y (si aplica) plantilla/idioma/variables. Vamos
// al tab de envío en modo leads con la audiencia precargada; el usuario puede
// avanzar el wizard y confirmar. reuseData lo consume LeadsPickerTab vía prop.
const onBatchReused = data => {
  reuseData.value = data;
  source.value = 'leads';
  if (data?.inbox_id != null) selectedInboxId.value = data.inbox_id;
  if (data?.sender_user_id != null)
    selectedSenderId.value = data.sender_user_id;
  wizardStep.value = 2;
  activeTab.value = 'send';
};

const onSend = async () => {
  if (!canSend.value) return;
  sending.value = true;
  try {
    await bulkWhatsappAPI.send({
      file: file.value,
      inboxId: selectedInboxId.value,
      senderUserId: selectedSenderId.value,
    });
    useAlert(t('JABVOX_BULK_WA.SEND.SUCCESS'));
    resetForm();
    activeTab.value = 'history';
    loadBatches();
  } catch (error) {
    useAlert(error?.response?.data?.error || t('JABVOX_BULK_WA.SEND.ERROR'));
  } finally {
    sending.value = false;
  }
};

// Step 4 can submit when CSV is ready, or when LeadsPickerTab reports it can send.
const canSubmitStep4 = computed(() =>
  source.value === 'csv' ? canSend.value : leadsStepValid.value
);

// Unified step-4 submit: CSV sends here; leads delegates to LeadsPickerTab
// (which owns the audience/template state) via its exposed send().
const submitWizard = () => {
  if (source.value === 'csv') {
    onSend();
  } else {
    leadsRef.value?.send();
  }
};

const statusClass = status =>
  ({
    sent: 'bg-n-teal-3 text-n-teal-11',
    failed: 'bg-n-ruby-3 text-n-ruby-11',
    pending: 'bg-n-amber-3 text-n-amber-11',
  })[status] || 'bg-n-alpha-2 text-n-slate-10';

const formatDate = value => {
  if (!value) return '—';
  const d = new Date(value);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
};

// ── Settings (webhook URL only) ────────────────────────────────────────────
const loadConfig = async () => {
  try {
    const { data } = await bulkWhatsappAPI.getConfig();
    webhookUrl.value = data.webhook_url_jabvox || '';
  } catch {
    useAlert(t('JABVOX_BULK_WA.SETTINGS.ERROR'));
  }
};

const saveConfig = async () => {
  savingConfig.value = true;
  try {
    await bulkWhatsappAPI.updateConfig({
      webhook_url_jabvox: webhookUrl.value.trim(),
    });
    useAlert(t('JABVOX_BULK_WA.SETTINGS.SAVED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.[0] || t('JABVOX_BULK_WA.SETTINGS.ERROR')
    );
  } finally {
    savingConfig.value = false;
  }
};

const loadSenders = async () => {
  try {
    const { data } = await bulkWhatsappAPI.getSenders();
    const list = Array.isArray(data) ? data : [];
    // Non-admins can only send as themselves (enforced by the backend too),
    // so the picker offers just their own user, preselected.
    if (isAdmin.value) {
      senders.value = list;
    } else {
      senders.value = list.filter(u => u.id === currentUserId.value);
      selectedSenderId.value = currentUserId.value;
    }
  } catch (e) {
    // Surface the failure instead of leaving an empty "()" picker.
    senders.value = [];
    useAlert(
      e?.response?.data?.error || t('JABVOX_BULK_WA.SEND.SENDERS_ERROR')
    );
  }
};

onMounted(() => {
  rootStore.dispatch('inboxes/get');
  loadSenders();
  loadConfig();
  loadBatches();
});
</script>

<template>
  <div class="flex flex-col flex-1 h-full overflow-hidden bg-n-background">
    <!-- Header -->
    <div class="px-4 sm:px-6 py-4 border-b border-n-weak bg-n-solid-1 shrink-0">
      <h1 class="text-xl font-semibold text-n-slate-12 flex items-center gap-2">
        <span
          class="i-lucide-send-horizontal size-5 text-n-brand"
          aria-hidden="true"
        />
        {{ t('JABVOX_BULK_WA.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-10 mt-1 max-w-2xl">
        {{ t('JABVOX_BULK_WA.SUBTITLE') }}
      </p>

      <div
        class="flex items-center gap-1 mt-4 p-0.5 rounded-lg bg-n-alpha-1 w-fit"
      >
        <button
          v-for="tab in TABS"
          :key="tab"
          type="button"
          class="px-3 py-1.5 text-sm rounded-md transition-colors"
          :class="
            activeTab === tab
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11'
          "
          @click="activeTab = tab"
        >
          {{ t(`JABVOX_BULK_WA.TABS.${tab.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <div class="flex-1 min-h-0 overflow-y-auto p-4 sm:p-6">
      <!-- SEND -->
      <div
        v-if="activeTab === 'send'"
        class="mx-auto w-full max-w-3xl space-y-5"
      >
        <!-- Config required notice -->
        <div
          v-if="!configReady"
          class="flex items-start gap-3 rounded-xl border border-n-amber-6 bg-n-amber-3 px-4 py-3"
        >
          <span
            class="i-lucide-triangle-alert size-5 text-n-amber-11 shrink-0 mt-0.5"
            aria-hidden="true"
          />
          <div class="min-w-0">
            <p class="text-sm font-medium text-n-amber-12">
              {{ t('JABVOX_BULK_WA.SEND.CONFIG_REQUIRED_TITLE') }}
            </p>
            <p class="text-xs text-n-amber-11 mt-0.5">
              {{ t('JABVOX_BULK_WA.SEND.CONFIG_REQUIRED_BODY') }}
            </p>
            <button
              v-if="isAdmin"
              type="button"
              class="mt-2 text-xs font-medium text-n-brand hover:underline"
              @click="activeTab = 'settings'"
            >
              {{ t('JABVOX_BULK_WA.SEND.GO_TO_SETTINGS') }}
            </button>
          </div>
        </div>

        <!-- Stepper: 4 pasos, secuencial y obligatorio -->
        <div class="flex items-center gap-2">
          <div
            v-for="(labelKey, i) in ['STEP1', 'STEP2', 'STEP3', 'STEP4']"
            :key="labelKey"
            class="flex items-center gap-2"
            :class="i > 0 ? 'flex-1' : ''"
          >
            <span
              v-if="i > 0"
              class="h-px flex-1"
              :class="wizardStep > i ? 'bg-n-brand' : 'bg-n-weak'"
            />
            <span
              class="inline-flex items-center gap-1.5 text-[11px] font-medium rounded-full px-2.5 py-1"
              :class="
                wizardStep === i + 1
                  ? 'bg-n-brand text-white'
                  : wizardStep > i + 1
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-alpha-1 text-n-slate-10'
              "
            >
              {{ i + 1 }}. {{ t(`JABVOX_BULK_WA.WIZARD.${labelKey}`) }}
            </span>
          </div>
        </div>

        <!-- Paso 1: bandeja + emisor (source toggle vive en el paso 2) -->
        <section
          v-show="wizardStep === 1"
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm space-y-4"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-xs text-n-slate-11">{{
                t('JABVOX_BULK_WA.SEND.INBOX')
              }}</label>
              <select
                v-model="selectedInboxId"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              >
                <option value="">
                  {{ t('JABVOX_BULK_WA.SEND.INBOX_PLACEHOLDER') }}
                </option>
                <option v-for="ib in inboxes" :key="ib.id" :value="ib.id">
                  {{ ib.name }}
                </option>
              </select>
              <span
                v-if="sendMode"
                class="inline-flex items-center gap-1 w-fit mt-0.5 text-[11px] font-medium rounded-full px-2 py-0.5"
                :class="
                  sendMode === 'template'
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-blue-3 text-n-blue-11'
                "
              >
                <span
                  :class="
                    sendMode === 'template'
                      ? 'i-lucide-badge-check'
                      : 'i-lucide-message-circle'
                  "
                  class="size-3"
                  aria-hidden="true"
                />
                {{
                  sendMode === 'template'
                    ? t('JABVOX_BULK_WA.SEND.MODE_TEMPLATE')
                    : t('JABVOX_BULK_WA.SEND.MODE_TEXT')
                }}
              </span>
            </div>

            <div class="flex flex-col gap-1">
              <label class="text-xs text-n-slate-11">{{
                t('JABVOX_BULK_WA.SEND.SENDER')
              }}</label>
              <select
                v-model="selectedSenderId"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              >
                <option value="">
                  {{ t('JABVOX_BULK_WA.SEND.SENDER_PLACEHOLDER') }}
                </option>
                <option v-for="u in availableSenders" :key="u.id" :value="u.id">
                  {{ senderLabel(u) }}
                </option>
              </select>
              <span class="text-[11px] text-n-slate-9">
                {{ t('JABVOX_BULK_WA.SEND.SENDER_HINT') }}
              </span>
            </div>
          </div>
        </section>

        <!-- Paso 2: origen de destinatarios (CSV o Desde Jabvox) -->
        <section
          v-show="wizardStep === 2"
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm space-y-4"
        >
          <!-- Source toggle -->
          <div
            class="flex items-center gap-1 p-0.5 rounded-lg bg-n-alpha-1 w-fit"
          >
            <button
              v-for="s in SOURCES"
              :key="s"
              type="button"
              class="px-3 py-1.5 text-sm rounded-md transition-colors"
              :class="
                source === s
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11'
              "
              @click="source = s"
            >
              {{ t(`JABVOX_BULK_WA.SOURCE.${s.toUpperCase()}`) }}
            </button>
          </div>
        </section>

        <!-- Leads source (pasos 2B/3/4 los gestiona internamente) -->
        <LeadsPickerTab
          v-if="source === 'leads'"
          v-show="wizardStep >= 2"
          ref="leadsRef"
          :inbox-id="selectedInboxId"
          :sender-user-id="selectedSenderId"
          :mode="sendMode"
          :config-ready="configReady"
          :step="wizardStep"
          :preselect="reuseData"
          @sent="onLeadsSent"
          @validity="onLeadsValidity"
        />

        <!-- CSV source: subir (paso 2) · guía plantilla (paso 3) · preview+enviar (paso 4) -->
        <section
          v-else
          v-show="wizardStep >= 2"
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm space-y-4"
        >
          <!-- Sample CSV (paso 2) -->
          <div
            v-show="wizardStep === 2"
            class="flex items-center justify-between gap-3 rounded-lg bg-n-alpha-1 px-3 py-2.5"
          >
            <div class="flex items-center gap-2 min-w-0">
              <span
                class="i-lucide-file-spreadsheet size-4 text-n-slate-10 shrink-0"
                aria-hidden="true"
              />
              <span class="text-xs text-n-slate-11 truncate">
                {{
                  sendMode
                    ? t('JABVOX_BULK_WA.SEND.SAMPLE_HINT')
                    : t('JABVOX_BULK_WA.SEND.SAMPLE_SELECT_INBOX')
                }}
              </span>
            </div>
            <button
              type="button"
              class="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 shrink-0 disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="!sendMode"
              @click="downloadSample"
            >
              <span class="i-lucide-download size-3.5" aria-hidden="true" />
              {{
                sendMode === 'text'
                  ? t('JABVOX_BULK_WA.SEND.DOWNLOAD_SAMPLE_TEXT')
                  : t('JABVOX_BULK_WA.SEND.DOWNLOAD_SAMPLE_TEMPLATE')
              }}
            </button>
          </div>

          <!-- File (paso 2) -->
          <div v-show="wizardStep === 2" class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_BULK_WA.SEND.FILE')
            }}</label>
            <input
              ref="fileInput"
              type="file"
              accept=".csv,text/csv"
              class="reset-base text-sm rounded-lg border border-dashed border-n-weak bg-n-alpha-1 px-3 py-2 file:mr-3 file:rounded-md file:border-0 file:bg-n-brand file:text-white file:px-3 file:py-1 file:text-xs"
              @change="onFileChange"
            />
            <span class="text-[11px] text-n-slate-9">
              {{ t('JABVOX_BULK_WA.SEND.FILE_HINT') }}
            </span>
          </div>

          <p
            v-if="parseError && wizardStep === 2"
            class="text-sm text-n-ruby-11 bg-n-ruby-3 rounded-lg px-3 py-2"
          >
            {{ parseError }}
          </p>

          <!-- Paso 3 (CSV): la plantilla e idioma van en las columnas del CSV -->
          <div
            v-show="wizardStep === 3"
            class="rounded-lg bg-n-alpha-1 px-3 py-2.5 text-xs text-n-slate-11"
          >
            {{ t('JABVOX_BULK_WA.SEND.CSV_TEMPLATE_INFO') }}
          </div>

          <!-- Preview (pasos 3 y 4) -->
          <div v-if="parsedPreview.length && wizardStep >= 3" class="space-y-2">
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_BULK_WA.SEND.PREVIEW_COUNT', parsedPreview.length) }}
            </p>
            <div class="overflow-x-auto rounded-lg border border-n-weak">
              <table class="w-full text-sm">
                <thead class="bg-n-alpha-1 text-n-slate-11">
                  <tr>
                    <th class="text-left px-3 py-2 font-medium">
                      {{ t('JABVOX_BULK_WA.COLS.NAME') }}
                    </th>
                    <th class="text-left px-3 py-2 font-medium">
                      {{ t('JABVOX_BULK_WA.COLS.NUMBER') }}
                    </th>
                    <th class="text-left px-3 py-2 font-medium">
                      {{ t('JABVOX_BULK_WA.COLS.TEMPLATE') }}
                    </th>
                    <th class="text-left px-3 py-2 font-medium">
                      {{ t('JABVOX_BULK_WA.COLS.LANGUAGE') }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(row, idx) in parsedPreview.slice(0, 8)"
                    :key="idx"
                    class="border-t border-n-weak text-n-slate-12"
                  >
                    <td class="px-3 py-1.5">{{ row.nombre }}</td>
                    <td class="px-3 py-1.5">{{ row.numero }}</td>
                    <td class="px-3 py-1.5">{{ row.template }}</td>
                    <td class="px-3 py-1.5">{{ row.idioma }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p
              v-if="parsedPreview.length > 8"
              class="text-[11px] text-n-slate-9"
            >
              {{
                t('JABVOX_BULK_WA.SEND.PREVIEW_MORE', parsedPreview.length - 8)
              }}
            </p>
          </div>
        </section>

        <!-- Navegación del wizard: Atrás / Siguiente (no salta pasos ni avanza
             con datos incompletos). El envío final vive en el Paso 4. -->
        <div class="flex items-center justify-between pt-1">
          <button
            v-show="wizardStep > 1"
            type="button"
            class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            @click="prevStep"
          >
            <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
            {{ t('JABVOX_BULK_WA.WIZARD.BACK') }}
          </button>
          <span class="text-xs text-n-slate-10">
            {{
              t('JABVOX_BULK_WA.WIZARD.STEP_OF', {
                current: wizardStep,
                total: 4,
              })
            }}
          </span>
          <button
            v-show="wizardStep < 4"
            type="button"
            class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50"
            :disabled="!canGoNext"
            @click="nextStep"
          >
            {{ t('JABVOX_BULK_WA.WIZARD.NEXT') }}
            <span class="i-lucide-arrow-right size-4" aria-hidden="true" />
          </button>
          <!-- Envío final unificado (paso 4): CSV o leads según el origen. -->
          <button
            v-show="wizardStep === 4"
            type="button"
            class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50"
            :disabled="!canSubmitStep4 || sending"
            @click="submitWizard"
          >
            <span
              v-if="sending"
              class="i-lucide-loader-2 size-4 animate-spin"
              aria-hidden="true"
            />
            <span v-else class="i-lucide-send size-4" aria-hidden="true" />
            {{ t('JABVOX_BULK_WA.SEND.SUBMIT') }}
          </button>
        </div>
      </div>

      <!-- HISTORY -->
      <div v-else-if="activeTab === 'history'" class="mx-auto w-full max-w-4xl">
        <p v-if="loadingBatches" class="text-sm text-n-slate-10">
          {{ t('JABVOX_BULK_WA.HISTORY.LOADING') }}
        </p>
        <p
          v-else-if="!batches.length"
          class="text-sm text-n-slate-10 text-center py-10"
        >
          {{ t('JABVOX_BULK_WA.HISTORY.EMPTY') }}
        </p>
        <div
          v-else
          class="overflow-x-auto rounded-2xl border border-n-weak bg-n-solid-1"
        >
          <table class="w-full text-sm">
            <thead class="bg-n-alpha-1 text-n-slate-11">
              <tr>
                <th class="text-left px-4 py-2.5 font-medium">
                  {{ t('JABVOX_BULK_WA.HISTORY.FILE') }}
                </th>
                <th class="text-left px-4 py-2.5 font-medium">
                  {{ t('JABVOX_BULK_WA.HISTORY.INBOX') }}
                </th>
                <th class="text-left px-4 py-2.5 font-medium">
                  {{ t('JABVOX_BULK_WA.HISTORY.MODE') }}
                </th>
                <th class="text-left px-4 py-2.5 font-medium">
                  {{ t('JABVOX_BULK_WA.HISTORY.SENDER') }}
                </th>
                <th class="text-left px-4 py-2.5 font-medium">
                  {{ t('JABVOX_BULK_WA.HISTORY.ROWS') }}
                </th>
                <th class="text-left px-4 py-2.5 font-medium">
                  {{ t('JABVOX_BULK_WA.HISTORY.STATUS') }}
                </th>
                <th class="text-left px-4 py-2.5 font-medium">
                  {{ t('JABVOX_BULK_WA.HISTORY.DATE') }}
                </th>
                <th class="px-4 py-2.5" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="b in batches"
                :key="b.id"
                class="border-t border-n-weak text-n-slate-12"
              >
                <td class="px-4 py-2.5">{{ b.file_name_jabvox || '—' }}</td>
                <td class="px-4 py-2.5">{{ b.inbox_name || '—' }}</td>
                <td class="px-4 py-2.5">
                  <span
                    class="inline-flex rounded-full px-2 py-0.5 text-[11px] font-medium"
                    :class="
                      b.mode_jabvox === 'text'
                        ? 'bg-n-blue-3 text-n-blue-11'
                        : 'bg-n-teal-3 text-n-teal-11'
                    "
                  >
                    {{
                      b.mode_jabvox === 'text'
                        ? t('JABVOX_BULK_WA.HISTORY.MODE_TEXT')
                        : t('JABVOX_BULK_WA.HISTORY.MODE_TEMPLATE')
                    }}
                  </span>
                </td>
                <td class="px-4 py-2.5">{{ b.sender_name || '—' }}</td>
                <td class="px-4 py-2.5">
                  {{ `${b.valid_rows_jabvox} / ${b.total_rows_jabvox}` }}
                </td>
                <td class="px-4 py-2.5">
                  <span
                    class="inline-flex rounded-full px-2 py-0.5 text-[11px] font-medium"
                    :class="statusClass(b.status_jabvox)"
                  >
                    {{
                      t(
                        `JABVOX_BULK_WA.STATUS.${b.status_jabvox.toUpperCase()}`
                      )
                    }}
                  </span>
                  <span
                    v-if="b.error_jabvox"
                    class="block text-[11px] text-n-ruby-11 mt-0.5"
                    :title="b.error_jabvox"
                  >
                    {{ b.error_jabvox }}
                  </span>
                </td>
                <td class="px-4 py-2.5 text-n-slate-10">
                  {{ formatDate(b.sent_at_jabvox || b.created_at) }}
                </td>
                <td class="px-4 py-2.5 text-right">
                  <button
                    type="button"
                    class="text-n-brand hover:underline text-xs font-medium"
                    @click="openReport(b)"
                  >
                    {{ t('JABVOX_BULK_WA.REPORT.TITLE') }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- REPORTS (agregados: totales + serie por envío/día/semana) -->
      <AnalyticsTab v-else-if="activeTab === 'reports'" />

      <!-- SETTINGS -->
      <div v-else class="mx-auto w-full max-w-2xl">
        <section
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm space-y-4"
        >
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_BULK_WA.SETTINGS.WEBHOOK_URL')
            }}</label>
            <input
              v-model="webhookUrl"
              type="url"
              :placeholder="t('JABVOX_BULK_WA.SETTINGS.WEBHOOK_PLACEHOLDER')"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
            />
            <span class="text-[11px] text-n-slate-9">
              {{ t('JABVOX_BULK_WA.SETTINGS.WEBHOOK_HINT') }}
            </span>
          </div>

          <div class="flex justify-end">
            <button
              type="button"
              class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50"
              :disabled="savingConfig"
              @click="saveConfig"
            >
              <span
                v-if="savingConfig"
                class="i-lucide-loader-2 size-4 animate-spin"
                aria-hidden="true"
              />
              {{ t('JABVOX_BULK_WA.SETTINGS.SAVE') }}
            </button>
          </div>
        </section>
      </div>
    </div>

    <!-- Report dialog (fuera del switch de tabs para no romper el v-if/v-else) -->
    <BatchReportDialog ref="reportDialog" @reused="onBatchReused" />
  </div>
</template>
