<script>
import { mapGetters } from 'vuex';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAccount } from 'dashboard/composables/useAccount';
import BillingAPI from 'dashboard/api/jabvox/billing';
import PublicPlansAPI from 'dashboard/api/jabvox/publicPlans';
import Auth from 'dashboard/api/auth';

// Modal de bloqueo NO cerrable: se muestra cuando la cuenta no está activa
// (payment_pending o suspended). Obliga a pagar para usar la plataforma.
//   - Admin: ve los planes y puede iniciar el checkout (redirige a la pasarela).
//   - No admin: ve un aviso para que contacte a su administrador.
// La activación real ocurre por el webhook firmado de la pasarela, nunca aquí.
export default {
  name: 'JabvoxPaymentBlockingModal',
  setup() {
    const { isAdmin } = useAdmin();
    const { accountId } = useAccount();
    return { isAdmin, accountId };
  },
  data() {
    return {
      plans: [],
      loadingPlans: false,
      checkoutPlanId: null,
      error: null,
      // Deep-link desde jabvox.com: ?plan=slug preselecciona/resalta ese plan.
      preselectedSlug: new URLSearchParams(window.location.search).get('plan'),
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      currentUser: 'getCurrentUser',
    }),
    account() {
      return this.getAccount(this.accountId) || {};
    },
    // Otras cuentas del usuario (distintas a la actual). Si tiene más de una, el modal
    // ofrece cambiar a ellas: solo se bloquea la cuenta actual sin plan, no al usuario.
    otherAccounts() {
      const accounts = this.currentUser?.accounts || [];
      return accounts.filter(a => Number(a.id) !== Number(this.accountId));
    },
    hasOtherAccounts() {
      return this.otherAccounts.length > 0;
    },
    // La cuenta debe pagar cuando NO está activa. status viene del API (_account.json.jbuilder).
    requiresPayment() {
      const status = this.account?.status;
      return status === 'payment_pending' || status === 'suspended';
    },
    isSuspended() {
      return this.account?.status === 'suspended';
    },
    title() {
      return this.isSuspended
        ? this.$t('JABVOX_BILLING.MODAL.TITLE_SUSPENDED')
        : this.$t('JABVOX_BILLING.MODAL.TITLE_PENDING');
    },
    description() {
      return this.isSuspended
        ? this.$t('JABVOX_BILLING.MODAL.DESC_SUSPENDED')
        : this.$t('JABVOX_BILLING.MODAL.DESC_PENDING');
    },
    headerIcon() {
      return this.isSuspended ? '⏳' : '🚀';
    },
    // Planes con el preseleccionado (deep-link) primero.
    sortedPlans() {
      if (!this.preselectedSlug) return this.plans;
      const preferred = this.plans.filter(p => p.slug === this.preselectedSlug);
      const rest = this.plans.filter(p => p.slug !== this.preselectedSlug);
      return [...preferred, ...rest];
    },
  },
  watch: {
    requiresPayment: {
      immediate: true,
      handler(needsPayment) {
        if (needsPayment && this.isAdmin && this.plans.length === 0) {
          this.fetchPlans();
        }
      },
    },
  },
  methods: {
    async fetchPlans() {
      this.loadingPlans = true;
      this.error = null;
      try {
        const { data } = await PublicPlansAPI.getAll();
        this.plans = data || [];
      } catch (e) {
        this.error = this.$t('JABVOX_BILLING.MODAL.PLANS_ERROR');
      } finally {
        this.loadingPlans = false;
      }
    },
    formatPrice(plan) {
      if (plan.price_formatted) return plan.price_formatted;
      const value = (plan.price_cents || 0) / 100;
      return `$${value.toLocaleString('es-CO')}`;
    },
    async selectPlan(plan) {
      if (this.checkoutPlanId) return; // ya hay un checkout en curso
      this.checkoutPlanId = plan.id;
      this.error = null;
      try {
        const { data } = await BillingAPI.createCheckout(plan.id);
        if (data?.checkout_url) {
          // Redirige a la pasarela (Bold). Al volver, el webhook ya habrá activado
          // la cuenta si el pago fue aprobado.
          window.location.href = data.checkout_url;
        } else {
          this.error = this.$t('JABVOX_BILLING.MODAL.CHECKOUT_ERROR');
          this.checkoutPlanId = null;
        }
      } catch (e) {
        this.error = this.$t('JABVOX_BILLING.MODAL.CHECKOUT_ERROR');
        this.checkoutPlanId = null;
      }
    },
    logout() {
      Auth.logout();
    },
    switchAccount(accountId) {
      // Cambia a otra cuenta del usuario (útil si tiene varias y solo una está sin
      // pagar): navega a esa cuenta; el modal desaparece si esa cuenta está activa.
      window.location.href = `/app/accounts/${accountId}/dashboard`;
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="requiresPayment"
    class="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
  >
    <div
      class="flex flex-col w-full max-w-2xl max-h-[90vh] overflow-hidden bg-n-background rounded-xl shadow-2xl"
    >
      <!-- Header -->
      <div class="px-8 pt-8 pb-4 text-center">
        <div
          class="flex items-center justify-center w-16 h-16 mx-auto mb-4 rounded-full bg-n-amber-3"
        >
          <span class="text-3xl">{{ headerIcon }}</span>
        </div>
        <h2 class="mb-2 text-xl font-semibold text-n-slate-12">
          {{ title }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ description }}
        </p>
      </div>

      <!-- Admin: lista de planes -->
      <div v-if="isAdmin" class="flex-1 px-8 pb-6 overflow-y-auto">
        <div
          v-if="loadingPlans"
          class="py-8 text-sm text-center text-n-slate-11"
        >
          {{ $t('JABVOX_BILLING.MODAL.LOADING_PLANS') }}
        </div>

        <div
          v-else-if="error"
          class="p-3 mb-4 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
        >
          {{ error }}
        </div>

        <div v-else class="grid gap-3 sm:grid-cols-2">
          <button
            v-for="plan in sortedPlans"
            :key="plan.id"
            type="button"
            :disabled="!!checkoutPlanId"
            class="flex flex-col p-4 text-left transition-all border rounded-lg hover:border-n-brand hover:shadow-md disabled:opacity-50 disabled:cursor-not-allowed"
            :class="
              plan.slug === preselectedSlug
                ? 'border-n-brand ring-2 ring-n-brand/40'
                : 'border-n-weak'
            "
            @click="selectPlan(plan)"
          >
            <span class="text-base font-semibold text-n-slate-12">
              {{ plan.name }}
            </span>
            <span class="mt-1 text-lg font-bold text-n-brand">
              {{ formatPrice(plan) }}
              <span class="text-xs font-normal text-n-slate-10">
                {{
                  $t('JABVOX_BILLING.MODAL.PER_DAYS', {
                    days: plan.duration_days,
                  })
                }}
              </span>
            </span>
            <span
              v-if="checkoutPlanId === plan.id"
              class="mt-2 text-xs text-n-slate-11"
            >
              {{ $t('JABVOX_BILLING.MODAL.REDIRECTING') }}
            </span>
            <span v-else class="mt-2 text-xs text-n-slate-10">
              {{ (plan.modules || []).length }}
              {{ $t('JABVOX_BILLING.MODAL.MODULES') }}
            </span>
          </button>
        </div>
      </div>

      <!-- No admin: aviso para contactar al administrador -->
      <div v-else class="px-8 pb-6">
        <div class="p-4 text-sm rounded-lg text-n-amber-11 bg-n-amber-3">
          {{ $t('JABVOX_BILLING.MODAL.CONTACT_ADMIN') }}
        </div>
      </div>

      <!-- Footer -->
      <!-- Cambiar de cuenta: si el usuario tiene otras cuentas, puede ir a ellas sin
           quedar atrapado por la cuenta actual sin plan. -->
      <div v-if="hasOtherAccounts" class="px-8 pb-4">
        <p class="mb-2 text-xs text-n-slate-11">
          {{ $t('JABVOX_BILLING.MODAL.SWITCH_ACCOUNT') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="acc in otherAccounts"
            :key="acc.id"
            type="button"
            class="px-3 py-1.5 text-xs font-medium transition-colors border rounded-lg border-n-weak text-n-slate-12 hover:border-n-brand hover:text-n-brand"
            @click="switchAccount(acc.id)"
          >
            {{ acc.name }}
          </button>
        </div>
      </div>

      <div
        class="flex items-center justify-between px-8 py-4 border-t border-n-weak"
      >
        <span class="text-xs text-n-slate-10">
          {{ account.name }}
        </span>
        <button
          type="button"
          class="text-xs underline text-n-slate-11 hover:text-n-slate-12"
          @click="logout"
        >
          {{ $t('JABVOX_BILLING.MODAL.LOGOUT') }}
        </button>
      </div>
    </div>
  </div>
</template>
