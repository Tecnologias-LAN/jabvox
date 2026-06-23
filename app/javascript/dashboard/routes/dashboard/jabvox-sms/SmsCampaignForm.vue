<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { smsCampaignsAPI } from 'dashboard/api/jabvox/sms';

const props = defineProps({
  campaign: { type: Object, default: null },
});
const emit = defineEmits(['save', 'cancel']);

const store = useStore();
const { t } = useI18n();

const providers = useMapGetter('jabvoxSms/getProviders');
const uiFlags = useMapGetter('jabvoxSms/getUIFlags');
const leadCampaigns = useMapGetter('jabvoxCampaigns/getCampaigns');
const affiliates = useMapGetter('jabvoxAffiliates/getAffiliates');
const inboxes = useMapGetter('inboxes/getInboxes');

const form = ref({
  name: '',
  description: '',
  message: '',
  jabvox_sms_provider_id: null,
  jabvox_campaign_id: null,
  inbox_ids_sms: [],
  affiliate_ids_sms: [],
});

const textareaRef = ref(null);

const leadCampaignOptions = computed(() =>
  (leadCampaigns.value || []).map(c => ({ value: c.id, label: c.name }))
);
const affiliateOptions = computed(() =>
  (affiliates.value || []).map(a => ({ value: a.id, label: a.name }))
);
const inboxOptions = computed(() =>
  (inboxes.value || []).map(i => ({ value: i.id, label: i.name }))
);
const providerOptions = computed(() =>
  (providers.value || []).map(p => ({
    value: p.id,
    label: p.active ? p.name : `${p.name} (inactivo)`,
    disabled: !p.active,
  }))
);

// Lead count
const leadCount = ref(null);
const loadingCount = ref(false);
let countTimer = null;

const fetchLeadCount = async () => {
  loadingCount.value = true;
  try {
    const { data } = await smsCampaignsAPI.leadCount({
      jabvox_campaign_id: form.value.jabvox_campaign_id,
      affiliate_ids: form.value.affiliate_ids_sms,
      inbox_ids: form.value.inbox_ids_sms,
    });
    leadCount.value = data;
  } catch {
    leadCount.value = null;
  } finally {
    loadingCount.value = false;
  }
};

const debouncedFetch = () => {
  clearTimeout(countTimer);
  countTimer = setTimeout(fetchLeadCount, 400);
};

watch(
  () => [
    form.value.jabvox_campaign_id,
    form.value.affiliate_ids_sms.length,
    form.value.inbox_ids_sms.length,
  ],
  debouncedFetch,
  { immediate: true }
);

onMounted(() => {
  store.dispatch('jabvoxCampaigns/fetchCampaigns');
  store.dispatch('jabvoxAffiliates/fetchAffiliates');
  store.dispatch('inboxes/get');
  if (props.campaign) {
    form.value = {
      name: props.campaign.name || '',
      description: props.campaign.description || '',
      message: props.campaign.message || '',
      jabvox_sms_provider_id: props.campaign.jabvox_sms_provider_id || null,
      jabvox_campaign_id: props.campaign.jabvox_campaign_id || null,
      inbox_ids_sms: [...(props.campaign.inbox_ids_sms || [])],
      affiliate_ids_sms: [...(props.campaign.affiliate_ids_sms || [])],
    };
  }
});

const VARIABLES = ['{nombre}', '{apellido}', '{telefono}'];

const insertVariable = variable => {
  const el = textareaRef.value;
  if (!el) {
    form.value.message += variable;
    return;
  }
  const start = el.selectionStart;
  const end = el.selectionEnd;
  form.value.message =
    form.value.message.slice(0, start) +
    variable +
    form.value.message.slice(end);
  el.focus();
};

const onDragStart = (e, variable) =>
  e.dataTransfer.setData('text/plain', variable);
const onDrop = e => {
  e.preventDefault();
  insertVariable(e.dataTransfer.getData('text/plain'));
};

const onSave = () => emit('save', { ...form.value });
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- General -->
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <Input
        v-model="form.name"
        :label="`${t('JABVOX_SMS.CAMPAIGNS.FORM.NAME')} *`"
        :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.NAME_PLACEHOLDER')"
        autofocus
      />
      <Input
        v-model="form.description"
        :label="t('JABVOX_SMS.CAMPAIGNS.FORM.DESCRIPTION')"
        :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.DESCRIPTION_PLACEHOLDER')"
      />
    </div>

    <div class="flex flex-col gap-1.5">
      <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.PROVIDER') }}
        <span class="text-n-ruby-11">*</span>
      </label>
      <Select
        v-model="form.jabvox_sms_provider_id"
        :options="providerOptions"
        :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.SELECT_PROVIDER')"
      />
    </div>

    <!-- Message -->
    <div class="flex flex-col gap-2">
      <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.MESSAGE') }}
        <span class="text-n-ruby-11">*</span>
      </label>
      <div class="flex gap-1.5 flex-wrap">
        <span
          v-for="v in VARIABLES"
          :key="v"
          draggable="true"
          class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-mono font-medium bg-n-alpha-2 text-n-brand border border-n-weak cursor-grab select-none hover:bg-n-alpha-3 transition-colors"
          @dragstart="onDragStart($event, v)"
          @click="insertVariable(v)"
        >
          {{ v }}
        </span>
      </div>
      <textarea
        ref="textareaRef"
        v-model="form.message"
        rows="4"
        :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.MESSAGE_PLACEHOLDER')"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y"
        @dragover.prevent
        @drop="onDrop"
      />
      <p class="text-xs text-n-slate-10">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.VARIABLES_HINT') }}
      </p>
    </div>

    <!-- Filters -->
    <div class="flex flex-col gap-4 border-t border-n-weak pt-5">
      <p class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.FILTERS_SECTION') }}
      </p>
      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_SMS.CAMPAIGNS.FORM.LEAD_CAMPAIGN') }}
        </label>
        <ComboBox
          v-model="form.jabvox_campaign_id"
          :options="leadCampaignOptions"
          :placeholder="
            t('JABVOX_SMS.CAMPAIGNS.FORM.LEAD_CAMPAIGN_PLACEHOLDER')
          "
          :search-placeholder="
            t('JABVOX_SMS.CAMPAIGNS.FORM.LEAD_CAMPAIGN_PLACEHOLDER')
          "
        />
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_SMS.CAMPAIGNS.FORM.AFFILIATES') }}
          </label>
          <TagMultiSelectComboBox
            v-model="form.affiliate_ids_sms"
            :options="affiliateOptions"
            :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.AFFILIATES_PLACEHOLDER')"
            :search-placeholder="
              t('JABVOX_SMS.CAMPAIGNS.FORM.AFFILIATES_PLACEHOLDER')
            "
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_SMS.CAMPAIGNS.FORM.INBOXES') }}
          </label>
          <TagMultiSelectComboBox
            v-model="form.inbox_ids_sms"
            :options="inboxOptions"
            :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.INBOXES_PLACEHOLDER')"
            :search-placeholder="
              t('JABVOX_SMS.CAMPAIGNS.FORM.INBOXES_PLACEHOLDER')
            "
          />
        </div>
      </div>
    </div>

    <!-- Lead count preview -->
    <div
      class="grid grid-cols-2 gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-4"
    >
      <div class="text-center">
        <p class="text-xl font-bold text-n-slate-12 tabular-nums">
          <Spinner v-if="loadingCount" :size="16" class="mx-auto" />
          <span v-else>{{ leadCount?.total_count ?? '—' }}</span>
        </p>
        <p class="text-xs text-n-slate-10 mt-0.5">
          {{ t('JABVOX_SMS.CAMPAIGNS.FORM.TOTAL_LEADS') }}
        </p>
      </div>
      <div class="text-center">
        <p class="text-xl font-bold text-n-brand tabular-nums">
          <Spinner v-if="loadingCount" :size="16" class="mx-auto" />
          <span v-else>{{ leadCount?.with_phone_count ?? '—' }}</span>
        </p>
        <p class="text-xs text-n-slate-10 mt-0.5">
          {{ t('JABVOX_SMS.CAMPAIGNS.FORM.WITH_PHONE') }}
        </p>
      </div>
    </div>

    <!-- Actions -->
    <div class="flex justify-end gap-2 pt-1">
      <Button
        variant="outline"
        color="slate"
        :label="t('JABVOX_SMS.COMMON.CANCEL')"
        @click="emit('cancel')"
      />
      <Button
        :label="t('JABVOX_SMS.SAVE')"
        :is-loading="uiFlags.isSaving"
        :disabled="
          uiFlags.isSaving ||
          !form.name ||
          !form.message ||
          !form.jabvox_sms_provider_id
        "
        @click="onSave"
      />
    </div>
  </div>
</template>
