<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useClickToCall } from 'dashboard/composables/jabvox/useClickToCall';
import { voipConfigAPI } from 'dashboard/api/jabvox/products';
import userExtensionAPI from 'dashboard/api/jabvox/userExtension';

const props = defineProps({
  phone: { type: String, default: '' },
  contactId: { type: Number, default: null },
  leadId: { type: Number, default: null },
  conversationId: { type: Number, default: null },
  contactName: { type: String, default: '' },
  showLabel: { type: Boolean, default: false },
});

const { t } = useI18n();
const { phase, initiateCall } = useClickToCall();

const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

// Click-to-call drives the overlay + typification flow; plain VoIP is the fallback.
const isClickToCallEnabled = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.JABVOX_CLICK_TO_CALL
  )
);
const isVoipEnabled = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.JABVOX_VOIP)
);
const isEnabled = computed(
  () => isClickToCallEnabled.value || isVoipEnabled.value
);

// --- Plain VoIP fallback state (only used when click-to-call is off) ---
const open = ref(false);
const calling = ref(false);
const callResult = ref(null);
const userExtension = ref('');
const extension = ref('');

onMounted(async () => {
  if (isClickToCallEnabled.value || !isVoipEnabled.value) return;
  try {
    const { data } = await userExtensionAPI.getMine();
    if (data.extension) {
      userExtension.value = data.extension;
      extension.value = data.extension;
    }
  } catch {
    // no extension assigned
  }
});

// Click-to-call: one active call at a time across the app.
const isBusy = computed(() => phase.value !== null);

// Entry point. Click-to-call → overlay flow; otherwise toggle the VoIP popover.
const onClick = () => {
  if (isClickToCallEnabled.value) {
    initiateCall({
      contactId: props.contactId,
      leadId: props.leadId,
      conversationId: props.conversationId,
      name: props.contactName,
      phone: props.phone,
    });
    return;
  }
  open.value = !open.value;
  callResult.value = null;
};

// Plain VoIP originate (no overlay, no typification) — legacy behaviour.
const voipCall = async () => {
  const ext = userExtension.value || extension.value.trim();
  if (!ext) return;
  if (!userExtension.value) localStorage.setItem('jabvox_voip_ext', ext);
  calling.value = true;
  callResult.value = null;
  try {
    const { data } = await voipConfigAPI.originate(
      props.phone,
      ext,
      props.contactName || null,
      props.contactId
    );
    callResult.value = data.success ? 'success' : 'error';
    if (data.success) {
      setTimeout(() => {
        open.value = false;
        callResult.value = null;
      }, 2000);
    }
  } catch {
    callResult.value = 'error';
  } finally {
    calling.value = false;
  }
};
</script>

<template>
  <div v-show="isEnabled" class="relative inline-flex">
    <button
      v-if="showLabel"
      class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium transition-colors disabled:opacity-50"
      :title="t('JABVOX_VOIP.CALL_BUTTON.TITLE')"
      :disabled="isClickToCallEnabled && isBusy"
      @click="onClick"
    >
      <fluent-icon icon="call" size="16" />
      <span>{{ t('JABVOX_VOIP.CALL_BUTTON.CALL') }}</span>
    </button>
    <button
      v-else
      class="flex items-center justify-center w-8 h-8 rounded-lg hover:bg-n-alpha-2 text-n-slate-11 hover:text-woot-600 transition-colors disabled:opacity-50"
      :title="t('JABVOX_VOIP.CALL_BUTTON.TITLE')"
      :disabled="isClickToCallEnabled && isBusy"
      @click="onClick"
    >
      <fluent-icon icon="call" size="16" />
    </button>

    <!-- VoIP fallback popover (only when click-to-call is disabled) -->
    <div
      v-if="open && !isClickToCallEnabled"
      class="absolute right-0 top-10 z-50 w-60 bg-white dark:bg-n-solid-3 border border-n-weak rounded-lg shadow-lg p-3"
    >
      <p class="text-xs font-medium text-n-slate-12 mb-2">
        {{
          phone && phone !== '***'
            ? t('JABVOX_VOIP.CALL_BUTTON.CALL_TO', { phone })
            : contactName || t('JABVOX_VOIP.CALL_BUTTON.TITLE')
        }}
      </p>

      <template v-if="userExtension">
        <div
          class="flex items-center gap-2 px-2 py-1.5 mb-2 rounded-lg bg-slate-100 dark:bg-slate-700"
        >
          <span class="i-lucide-phone size-3.5 text-slate-400" />
          <span
            class="text-sm font-mono font-medium text-slate-700 dark:text-slate-200"
          >
            {{ userExtension }}
          </span>
          <span class="text-xs text-green-600 ml-auto">
            {{ t('JABVOX_VOIP.CALL_BUTTON.EXTENSION_FROM_PROFILE') }}
          </span>
        </div>
        <button
          :disabled="calling"
          class="w-full py-1.5 rounded bg-woot-600 text-white text-sm font-medium disabled:opacity-50 hover:bg-woot-700 transition-colors"
          @click="voipCall"
        >
          {{
            calling
              ? t('JABVOX_VOIP.CALL_BUTTON.CALLING')
              : t('JABVOX_VOIP.CALL_BUTTON.CALL')
          }}
        </button>
      </template>

      <template v-else>
        <div
          class="flex items-center gap-2 px-3 py-2.5 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700"
        >
          <span
            class="i-lucide-triangle-alert size-4 text-amber-500 shrink-0"
          />
          <p class="text-xs text-amber-700 dark:text-amber-400">
            {{ t('JABVOX_VOIP.CALL_BUTTON.NO_EXTENSION') }}
          </p>
        </div>
      </template>

      <p
        v-if="callResult === 'success'"
        class="text-xs text-green-600 mt-1.5 text-center"
      >
        {{ t('JABVOX_VOIP.CALL_BUTTON.SUCCESS') }}
      </p>
      <p
        v-if="callResult === 'error'"
        class="text-xs text-red-500 mt-1.5 text-center"
      >
        {{ t('JABVOX_VOIP.CALL_BUTTON.ERROR') }}
      </p>
    </div>
  </div>
</template>
