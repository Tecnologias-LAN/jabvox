<script>
import { mapGetters } from 'vuex';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAccount } from 'dashboard/composables/useAccount';
import BillingAPI from 'dashboard/api/jabvox/billing';

// Pop-up de recordatorio de renovación (CERRABLE): aparece al iniciar sesión cuando al
// plan le faltan <= 2 días para vencer y la cuenta SIGUE activa. No bloquea el uso.
// Se muestra como MUCHO una vez al día por usuario admin (recordado en localStorage).
const DISMISS_KEY = 'jabvox_renewal_reminder_dismissed';

export default {
  name: 'JabvoxRenewalReminder',
  setup() {
    const { isAdmin } = useAdmin();
    const { accountId } = useAccount();
    return { isAdmin, accountId };
  },
  data() {
    return {
      visible: false,
      daysLeft: null,
      planName: null,
      checkoutLoading: false,
      clockIcon: '⏰',
      closeIcon: '✕',
    };
  },
  computed: {
    ...mapGetters({ currentUser: 'getCurrentUser' }),
    message() {
      if (this.daysLeft === 0) {
        return this.$t('JABVOX_BILLING.RENEWAL.EXPIRES_TODAY');
      }
      if (this.daysLeft === 1) {
        return this.$t('JABVOX_BILLING.RENEWAL.EXPIRES_TOMORROW');
      }
      return this.$t('JABVOX_BILLING.RENEWAL.EXPIRES_IN_DAYS', {
        days: this.daysLeft,
      });
    },
  },
  watch: {
    accountId: {
      immediate: true,
      handler(id) {
        if (id && this.isAdmin) this.maybeShow();
      },
    },
  },
  methods: {
    // Clave por usuario+cuenta+día: así solo se muestra una vez al día por admin.
    dismissKeyForToday() {
      const today = new Date().toISOString().slice(0, 10);
      const uid = this.currentUser?.id || 'anon';
      return `${DISMISS_KEY}_${uid}_${this.accountId}_${today}`;
    },
    alreadyDismissedToday() {
      try {
        return window.localStorage.getItem(this.dismissKeyForToday()) === '1';
      } catch (e) {
        return false;
      }
    },
    async maybeShow() {
      if (this.alreadyDismissedToday()) return;
      try {
        const { data } = await BillingAPI.getStatus();
        if (data && data.expiring_soon) {
          this.daysLeft = data.days_until_expiration;
          this.planName = data.plan_name;
          this.visible = true;
        }
      } catch (e) {
        // silencioso: no molestar si falla la consulta
      }
    },
    dismiss() {
      try {
        window.localStorage.setItem(this.dismissKeyForToday(), '1');
      } catch (e) {
        // ignorar si localStorage no está disponible
      }
      this.visible = false;
    },
    async renewNow() {
      // Lleva al modal/flujo de pago. Reusa el checkout del plan actual si existe.
      if (this.checkoutLoading) return;
      this.checkoutLoading = true;
      try {
        const planId = this.$store.getters['accounts/getAccount'](
          this.accountId
        )?.jabvox_billing?.plan?.id;
        if (!planId) {
          // Sin plan resoluble: manda a ajustes de facturación.
          this.goToBilling();
          return;
        }
        const { data } = await BillingAPI.createCheckout(planId);
        if (data?.checkout_url) {
          window.location.href = data.checkout_url;
        } else {
          this.goToBilling();
        }
      } catch (e) {
        this.goToBilling();
      } finally {
        this.checkoutLoading = false;
      }
    },
    goToBilling() {
      this.dismiss();
      this.$router.push(`/app/accounts/${this.accountId}/settings/billing`);
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="visible"
    class="fixed z-[9998] bottom-6 right-6 w-full max-w-sm p-5 bg-n-background rounded-xl shadow-2xl border border-n-weak"
  >
    <div class="flex items-start gap-3">
      <span class="text-2xl">{{ clockIcon }}</span>
      <div class="flex-1">
        <h3 class="mb-1 text-sm font-semibold text-n-slate-12">
          {{ $t('JABVOX_BILLING.RENEWAL.TITLE') }}
        </h3>
        <p class="mb-1 text-sm text-n-slate-11">{{ message }}</p>
        <p v-if="planName" class="mb-3 text-xs text-n-slate-10">
          {{ $t('JABVOX_BILLING.RENEWAL.CURRENT_PLAN') }}: {{ planName }}
        </p>
        <div class="flex gap-2">
          <button
            type="button"
            :disabled="checkoutLoading"
            class="px-3 py-1.5 text-xs font-medium text-white rounded-lg bg-n-brand hover:opacity-90 disabled:opacity-60"
            @click="renewNow"
          >
            {{ $t('JABVOX_BILLING.RENEWAL.RENEW_NOW') }}
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-medium rounded-lg text-n-slate-11 hover:text-n-slate-12"
            @click="dismiss"
          >
            {{ $t('JABVOX_BILLING.RENEWAL.LATER') }}
          </button>
        </div>
      </div>
      <button
        type="button"
        class="text-n-slate-10 hover:text-n-slate-12"
        :aria-label="$t('JABVOX_BILLING.RENEWAL.LATER')"
        @click="dismiss"
      >
        {{ closeIcon }}
      </button>
    </div>
  </div>
</template>
