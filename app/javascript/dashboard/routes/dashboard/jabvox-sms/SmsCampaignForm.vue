<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
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
const isEdit = computed(() => !!props.campaign);

const leadCampaignOptions = computed(() =>
  (leadCampaigns.value || []).map(c => ({ value: c.id, label: c.name }))
);
const affiliateOptions = computed(() =>
  (affiliates.value || []).map(a => ({ value: a.id, label: a.name }))
);
const inboxOptions = computed(() =>
  (inboxes.value || []).map(i => ({ value: i.id, label: i.name }))
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
  <div class="space-y-5">
    <div>
      <h3 class="text-base font-semibold text-n-slate-12">
        {{
          isEdit
            ? t('JABVOX_SMS.CAMPAIGNS.EDIT_TITLE')
            : t('JABVOX_SMS.CAMPAIGNS.NEW_TITLE')
        }}
      </h3>
      <p class="text-sm text-n-slate-10 mt-1">
        {{ t('JABVOX_SMS.CAMPAIGNS.SUBTITLE') }}
      </p>
    </div>

    <!-- Name -->
    <div class="space-y-1">
      <label class="block text-xs font-medium text-n-slate-11">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.NAME') }} *
      </label>
      <input
        v-model="form.name"
        type="text"
        :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.NAME_PLACEHOLDER')"
        class="w-full rounded-lg border border-n-weak bg-white dark:bg-n-surface-2 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
      />
    </div>

    <!-- Description -->
    <div class="space-y-1">
      <label class="block text-xs font-medium text-n-slate-11">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.DESCRIPTION') }}
      </label>
      <input
        v-model="form.description"
        type="text"
        :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.DESCRIPTION_PLACEHOLDER')"
        class="w-full rounded-lg border border-n-weak bg-white dark:bg-n-surface-2 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
      />
    </div>

    <!-- Provider -->
    <div class="space-y-1">
      <label class="block text-xs font-medium text-n-slate-11">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.PROVIDER') }} *
      </label>
      <select
        v-model="form.jabvox_sms_provider_id"
        class="w-full rounded-lg border border-n-weak bg-white dark:bg-n-surface-2 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
      >
        <option :value="null">
          {{ t('JABVOX_SMS.CAMPAIGNS.FORM.SELECT_PROVIDER') }}
        </option>
        <option
          v-for="p in providers"
          :key="p.id"
          :value="p.id"
          :disabled="!p.active"
        >
          {{ p.name }}{{ !p.active ? ' (inactivo)' : '' }}
        </option>
      </select>
    </div>

    <!-- Message -->
    <div class="space-y-2">
      <label class="block text-xs font-medium text-n-slate-11">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.MESSAGE') }} *
      </label>
      <div class="flex gap-2 flex-wrap">
        <span
          v-for="v in VARIABLES"
          :key="v"
          draggable="true"
          class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-woot-50 text-woot-700 dark:bg-woot-900 dark:text-woot-300 cursor-grab select-none border border-woot-200 dark:border-woot-700 hover:bg-woot-100 transition-colors"
          @dragstart="onDragStart($event, v)"
          @click="insertVariable(v)"
        >
          {{ v }}
        </span>
      </div>
      <p class="text-xs text-n-slate-9">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.VARIABLES_HINT') }}
      </p>
      <textarea
        ref="textareaRef"
        v-model="form.message"
        rows="4"
        :placeholder="t('JABVOX_SMS.CAMPAIGNS.FORM.MESSAGE_PLACEHOLDER')"
        class="w-full rounded-lg border border-n-weak bg-white dark:bg-n-surface-2 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500 resize-none"
        @dragover.prevent
        @drop="onDrop"
      />
    </div>

    <div class="border-t border-n-weak pt-4 space-y-4">
      <p class="text-xs font-semibold text-n-slate-11 uppercase tracking-wide">
        {{ t('JABVOX_SMS.CAMPAIGNS.FORM.FILTERS_SECTION') }}
      </p>

      <!-- Lead campaign -->
      <div class="space-y-1">
        <label class="block text-xs font-medium text-n-slate-11">
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

      <!-- Affiliates -->
      <div class="space-y-1">
        <label class="block text-xs font-medium text-n-slate-11">
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

      <!-- Inboxes -->
      <div class="space-y-1">
        <label class="block text-xs font-medium text-n-slate-11">
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

    <!-- Lead count -->
    <div
      class="rounded-xl border border-n-weak bg-n-surface-2 px-4 py-3 grid grid-cols-2 gap-4"
    >
      <div class="text-center">
        <p class="text-xl font-bold text-n-slate-12">
          <span v-if="loadingCount" class="text-n-slate-8 animate-pulse">
            ...
          </span>
          <span v-else>{{ leadCount?.total_count ?? '—' }}</span>
        </p>
        <p class="text-xs text-n-slate-9 mt-0.5">
          {{ t('JABVOX_SMS.CAMPAIGNS.FORM.TOTAL_LEADS') }}
        </p>
      </div>
      <div class="text-center">
        <p class="text-xl font-bold text-woot-600 dark:text-woot-400">
          <span v-if="loadingCount" class="text-n-slate-8 animate-pulse">
            ...
          </span>
          <span v-else>{{ leadCount?.with_phone_count ?? '—' }}</span>
        </p>
        <p class="text-xs text-n-slate-9 mt-0.5">
          {{ t('JABVOX_SMS.CAMPAIGNS.FORM.WITH_PHONE') }}
        </p>
      </div>
    </div>

    <!-- Actions -->
    <div class="flex justify-end gap-3 pt-2">
      <Button
        variant="clear"
        :label="t('JABVOX_SMS.CANCEL')"
        @click="emit('cancel')"
      />
      <Button
        :label="
          uiFlags.isSaving ? t('JABVOX_PRODUCTS.LOADING') : t('JABVOX_SMS.SAVE')
        "
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
