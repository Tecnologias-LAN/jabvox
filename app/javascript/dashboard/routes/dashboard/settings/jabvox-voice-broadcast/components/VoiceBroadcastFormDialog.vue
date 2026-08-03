<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import voiceBroadcastAPI from 'dashboard/api/jabvox/voiceBroadcast';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
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
});

const isEditing = computed(() => editingId.value != null);

const hoursValid = computed(() => {
  const { calling_hours_start_jabvox: s, calling_hours_end_jabvox: e } =
    form.value;
  return (!s || HOUR_RE.test(s)) && (!e || HOUR_RE.test(e));
});

const canSubmit = computed(
  () =>
    form.value.name_jabvox.trim() &&
    (isEditing.value || form.value.jabvox_dialer_campaign_id) &&
    Number(form.value.max_concurrent_jabvox) > 0 &&
    Number(form.value.cps_jabvox) > 0 &&
    hoursValid.value &&
    !saving.value
);

const loadCampaigns = async () => {
  try {
    const { data } = await dialerCampaignsAPI.getAll();
    campaigns.value = data || [];
  } catch (e) {
    campaigns.value = [];
  }
};

const open = row => {
  editingId.value = row?.id ?? null;
  form.value = {
    name_jabvox: row?.name || '',
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
  };
  show.value = true;
  if (!isEditing.value) loadCampaigns();
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

          <label v-if="!isEditing" class="flex flex-col gap-1">
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
