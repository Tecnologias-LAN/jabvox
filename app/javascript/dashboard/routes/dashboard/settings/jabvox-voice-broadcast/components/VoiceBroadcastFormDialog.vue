<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import voiceBroadcastAPI from 'dashboard/api/jabvox/voiceBroadcast';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
import { managementStatesAPI } from 'dashboard/api/jabvox/managementStates';
import affiliatesAPI from 'dashboard/api/jabvox/affiliates';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

// Crear/editar una campaña de voz. Al crear exige elegir una campaña del marcador
// (de ahí sale la lista de contactos). Al editar, la campaña ya no cambia y los
// controles quedan bloqueados si el broadcast está corriendo (el backend también
// lo impide).
const emit = defineEmits(['saved']);
const { t } = useI18n();

const show = ref(false);
const saving = ref(false);
const editingId = ref(null);
const campaigns = ref([]);

const HOUR_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

const form = ref({
  name_jabvox: '',
  // 'leads' = filtra sus propios leads (como el marcador); 'campaign' = reusa una campaña.
  source_jabvox: 'leads',
  jabvox_dialer_campaign_id: null,
  caller_id_jabvox: '',
  max_concurrent_jabvox: 5,
  cps_jabvox: 1,
  max_retries_jabvox: 0,
  retry_interval_jabvox: 300,
  amd_enabled_jabvox: true,
  dtmf_enabled_jabvox: false,
  dtmf_optout_digit_jabvox: '9',
  calling_hours_start_jabvox: '',
  calling_hours_end_jabvox: '',
  // Filtros de leads (source 'leads').
  management_state_ids_jabvox: [],
  countries_jabvox: [],
  affiliate_ids_jabvox: [],
});

// Catálogos para los filtros de leads.
const managementStates = ref([]);
const affiliates = ref([]);

const isEditing = computed(() => editingId.value != null);

const hoursValid = computed(() => {
  const { calling_hours_start_jabvox: s, calling_hours_end_jabvox: e } =
    form.value;
  return (!s || HOUR_RE.test(s)) && (!e || HOUR_RE.test(e));
});

const canSubmit = computed(() => {
  const f = form.value;
  // Con source 'campaign' se exige la campaña; con 'leads' basta con los filtros (pueden
  // estar vacíos = todos los leads con teléfono).
  const sourceOk =
    isEditing.value ||
    f.source_jabvox === 'leads' ||
    (f.source_jabvox === 'campaign' && f.jabvox_dialer_campaign_id);
  return (
    f.name_jabvox.trim() &&
    sourceOk &&
    Number(f.max_concurrent_jabvox) > 0 &&
    Number(f.cps_jabvox) > 0 &&
    hoursValid.value &&
    !saving.value
  );
});

const loadCampaigns = async () => {
  try {
    const { data } = await dialerCampaignsAPI.getAll();
    campaigns.value = data || [];
  } catch (e) {
    campaigns.value = [];
  }
};

// Catálogos para los filtros de leads (reusa los mismos endpoints que el marcador).
const loadFilterCatalogs = async () => {
  try {
    const [ms, aff] = await Promise.all([
      managementStatesAPI.getAll(),
      affiliatesAPI.getAll(),
    ]);
    managementStates.value = ms.data || [];
    affiliates.value = aff.data || [];
  } catch (e) {
    managementStates.value = [];
    affiliates.value = [];
  }
};

// Conteo de leads en vivo (para source 'leads'). Debounced simple.
const leadCount = ref(null);
let leadCountTimer = null;
const refreshLeadCount = async id => {
  if (form.value.source_jabvox !== 'leads') {
    leadCount.value = null;
    return;
  }
  clearTimeout(leadCountTimer);
  leadCountTimer = setTimeout(async () => {
    try {
      if (!id && !editingId.value) {
        leadCount.value = null;
        return;
      }
      const { data } = await voiceBroadcastAPI.leadCount(id || editingId.value);
      leadCount.value = data.count;
    } catch (e) {
      leadCount.value = null;
    }
  }, 300);
};

const open = row => {
  editingId.value = row?.id ?? null;
  form.value = {
    name_jabvox: row?.name || '',
    source_jabvox: row?.source || 'leads',
    jabvox_dialer_campaign_id: row?.campaign_id || null,
    caller_id_jabvox: row?.caller_id || '',
    max_concurrent_jabvox: row?.max_concurrent ?? 5,
    cps_jabvox: row?.cps ?? 1,
    max_retries_jabvox: row?.max_retries ?? 0,
    retry_interval_jabvox: row?.retry_interval ?? 300,
    amd_enabled_jabvox: row?.amd_enabled ?? true,
    dtmf_enabled_jabvox: row?.dtmf_enabled ?? false,
    dtmf_optout_digit_jabvox: row?.dtmf_optout_digit || '9',
    calling_hours_start_jabvox: row?.calling_hours_start || '',
    calling_hours_end_jabvox: row?.calling_hours_end || '',
    management_state_ids_jabvox: row?.management_state_ids || [],
    countries_jabvox: row?.countries || [],
    affiliate_ids_jabvox: row?.affiliate_ids || [],
  };
  show.value = true;
  loadFilterCatalogs();
  if (!isEditing.value) loadCampaigns();
  refreshLeadCount(row?.id);
};

const close = () => {
  show.value = false;
};

const submit = async () => {
  if (!canSubmit.value) return;
  saving.value = true;
  try {
    if (isEditing.value) {
      await voiceBroadcastAPI.update(editingId.value, form.value);
    } else {
      await voiceBroadcastAPI.create(form.value);
    }
    useAlert(t('JABVOX_VOICE_BROADCAST.FORM.SAVED'));
    emit('saved');
    close();
  } catch (e) {
    const msg =
      e?.response?.data?.error ||
      e?.response?.data?.errors?.join(', ') ||
      t('JABVOX_VOICE_BROADCAST.FORM.ERROR');
    useAlert(msg);
  } finally {
    saving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      @click.self="close"
    >
      <div
        class="flex flex-col w-full max-w-lg max-h-[88vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <h3 class="text-base font-semibold text-n-slate-12">
            {{
              isEditing
                ? t('JABVOX_VOICE_BROADCAST.FORM.EDIT_TITLE')
                : t('JABVOX_VOICE_BROADCAST.FORM.NEW_TITLE')
            }}
          </h3>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            @click="close"
          />
        </div>

        <div class="flex-1 overflow-y-auto px-5 py-4 flex flex-col gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_VOICE_BROADCAST.FORM.NAME') }}
            </span>
            <Input v-model="form.name_jabvox" />
          </label>

          <!-- Fuente de destinatarios: filtrar leads (como el marcador) o reusar campaña -->
          <label v-if="!isEditing" class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_VOICE_BROADCAST.FORM.SOURCE') }}
            </span>
            <select
              v-model="form.source_jabvox"
              class="px-3 py-2 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12"
            >
              <option value="leads">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.SOURCE_LEADS') }}
              </option>
              <option value="campaign">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.SOURCE_CAMPAIGN') }}
              </option>
            </select>
          </label>

          <!-- Campaña del marcador (source campaign) -->
          <label
            v-if="!isEditing && form.source_jabvox === 'campaign'"
            class="flex flex-col gap-1"
          >
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_VOICE_BROADCAST.FORM.CAMPAIGN') }}
            </span>
            <select
              v-model="form.jabvox_dialer_campaign_id"
              class="px-3 py-2 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12"
            >
              <option :value="null" disabled>
                {{ t('JABVOX_VOICE_BROADCAST.FORM.CAMPAIGN_PLACEHOLDER') }}
              </option>
              <option v-for="c in campaigns" :key="c.id" :value="c.id">
                {{ c.name }}
              </option>
            </select>
          </label>

          <!-- Filtros de leads (source leads) -->
          <div
            v-if="form.source_jabvox === 'leads'"
            class="flex flex-col gap-3 rounded-lg border border-n-weak p-3 bg-n-alpha-1"
          >
            <div class="flex items-center justify-between">
              <span class="text-xs font-semibold text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTERS_TITLE') }}
              </span>
              <span v-if="leadCount != null" class="text-xs text-n-slate-10">
                {{ leadCount }}
                {{ t('JABVOX_VOICE_BROADCAST.FORM.LEADS_WITH_PHONE') }}
              </span>
            </div>
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_STATES') }}
              </span>
              <select
                v-model="form.management_state_ids_jabvox"
                multiple
                class="px-2 py-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 min-h-[70px]"
                @change="refreshLeadCount(editingId)"
              >
                <option v-for="s in managementStates" :key="s.id" :value="s.id">
                  {{ s.name_jabvox || s.name }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_AFFILIATES') }}
              </span>
              <select
                v-model="form.affiliate_ids_jabvox"
                multiple
                class="px-2 py-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 min-h-[60px]"
                @change="refreshLeadCount(editingId)"
              >
                <option v-for="a in affiliates" :key="a.id" :value="a.id">
                  {{ a.name }}
                </option>
              </select>
            </label>
            <p class="text-xs text-n-slate-9">
              {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_HINT') }}
            </p>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.CALLER_ID') }}
              </span>
              <Input v-model="form.caller_id_jabvox" />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.MAX_CONCURRENT') }}
              </span>
              <Input
                v-model.number="form.max_concurrent_jabvox"
                type="number"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.CPS') }}
              </span>
              <Input v-model.number="form.cps_jabvox" type="number" />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.MAX_RETRIES') }}
              </span>
              <Input v-model.number="form.max_retries_jabvox" type="number" />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.RETRY_INTERVAL') }}
              </span>
              <Input
                v-model.number="form.retry_interval_jabvox"
                type="number"
              />
            </label>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.HOURS_START') }}
              </span>
              <Input
                v-model="form.calling_hours_start_jabvox"
                placeholder="08:00"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.HOURS_END') }}
              </span>
              <Input
                v-model="form.calling_hours_end_jabvox"
                placeholder="20:00"
              />
            </label>
          </div>
          <p v-if="!hoursValid" class="text-xs text-n-ruby-11 -mt-2">
            {{ t('JABVOX_VOICE_BROADCAST.FORM.HOURS_INVALID') }}
          </p>

          <div class="flex flex-col gap-2">
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input v-model="form.amd_enabled_jabvox" type="checkbox" />
              {{ t('JABVOX_VOICE_BROADCAST.FORM.AMD') }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input v-model="form.dtmf_enabled_jabvox" type="checkbox" />
              {{ t('JABVOX_VOICE_BROADCAST.FORM.DTMF') }}
            </label>
            <label
              v-if="form.dtmf_enabled_jabvox"
              class="flex flex-col gap-1 max-w-[120px]"
            >
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.DTMF_DIGIT') }}
              </span>
              <Input v-model="form.dtmf_optout_digit_jabvox" maxlength="1" />
            </label>
          </div>
        </div>

        <div
          class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak"
        >
          <Button
            :label="t('JABVOX_VOICE_BROADCAST.FORM.CANCEL')"
            variant="outline"
            color="slate"
            size="sm"
            @click="close"
          />
          <Button
            :label="t('JABVOX_VOICE_BROADCAST.FORM.SAVE')"
            size="sm"
            :disabled="!canSubmit"
            @click="submit"
          />
        </div>
      </div>
    </div>
  </teleport>
</template>
