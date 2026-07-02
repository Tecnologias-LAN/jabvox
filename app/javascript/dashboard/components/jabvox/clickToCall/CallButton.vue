<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useClickToCall } from 'dashboard/composables/jabvox/useClickToCall';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
  leadId: { type: [Number, String], default: null },
  conversationId: { type: [Number, String], default: null },
  name: { type: String, default: '' },
  phone: { type: String, default: '' },
});

const { t } = useI18n();
const { phase, initiateCall } = useClickToCall();

const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const isEnabled = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.JABVOX_CLICK_TO_CALL
  )
);

// Only one active call at a time.
const isBusy = computed(() => phase.value !== null);

const onClick = () => {
  initiateCall({
    contactId: props.contactId,
    leadId: props.leadId,
    conversationId: props.conversationId,
    name: props.name,
    phone: props.phone,
  });
};
</script>

<template>
  <button
    v-show="isEnabled"
    v-tooltip="t('JABVOX_CLICK_TO_CALL.CALL')"
    class="flex items-center gap-1 px-2 py-1 rounded-lg text-sm bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 disabled:opacity-50"
    :disabled="isBusy"
    @click="onClick"
  >
    <span class="i-lucide-phone text-base" />
    {{ t('JABVOX_CLICK_TO_CALL.CALL') }}
  </button>
</template>
