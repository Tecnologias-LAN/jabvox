<script setup>
// Global floating banner for the dialer, mounted once in Dashboard.vue. It shows
// while the agent has a live dialer call (or wrap-up) AND is NOT on the dialer
// page, so navigating to a conversation never loses the call: one tap returns to
// the dialer with everything intact. Mirrors the click-to-call floating widget.
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useDialerLiveSession } from 'dashboard/composables/jabvox/useDialerLiveSession';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const { activeCall, dialingCall, inWrapup, hasLiveCall, hydrateFromStorage } =
  useDialerLiveSession();

// After a full page reload the DialerPage isn't mounted, so the singleton starts
// empty; rebuild it from the persisted session so the banner still shows.
hydrateFromStorage();

// Hide when already on the dialer page (the full UI is there).
const onDialerPage = computed(() => route.name === 'jabvox_dialer_index');
const visible = computed(() => hasLiveCall.value && !onDialerPage.value);

const title = computed(() => {
  if (activeCall.value) {
    return (
      activeCall.value.contact_name ||
      activeCall.value.contact_phone ||
      t('JABVOX_DIALER.CALL.IN_CALL')
    );
  }
  if (dialingCall.value) return t('JABVOX_DIALER.DIALING');
  if (inWrapup.value) return t('JABVOX_DIALER.WRAPUP.TITLE');
  return '';
});

const statusLabel = computed(() => {
  if (activeCall.value) return t('JABVOX_DIALER.CALL.IN_CALL');
  if (dialingCall.value) return t('JABVOX_DIALER.DIALING');
  if (inWrapup.value) return t('JABVOX_DIALER.WRAPUP.TITLE');
  return '';
});

const goToDialer = () => {
  router.push(accountScopedRoute('jabvox_dialer_index'));
};
</script>

<template>
  <div
    v-if="visible"
    class="fixed bottom-5 right-5 z-[9999] w-80 max-w-[calc(100vw-2.5rem)] rounded-2xl border border-n-brand/40 bg-n-solid-1 shadow-xl p-4"
  >
    <div class="flex items-start gap-3">
      <span
        class="i-lucide-phone-call size-6 shrink-0 text-n-brand animate-pulse mt-0.5"
      />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-semibold text-n-slate-12 truncate">
          {{ title }}
        </p>
        <p class="text-xs text-n-brand mt-0.5">
          {{ statusLabel }}
        </p>
      </div>
    </div>
    <button
      type="button"
      class="mt-3 w-full inline-flex items-center justify-center gap-1.5 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white hover:opacity-90 transition-opacity"
      @click="goToDialer"
    >
      <span class="i-lucide-corner-up-left size-4" />
      {{ t('JABVOX_DIALER.BANNER.RETURN') }}
    </button>
  </div>
</template>
