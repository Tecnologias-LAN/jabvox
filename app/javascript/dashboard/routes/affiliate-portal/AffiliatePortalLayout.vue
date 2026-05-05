<script setup>
import { computed, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const portalAccountId = computed(() => route.params.portalAccountId);
const affiliateSlug = computed(() => route.params.affiliateSlug);

const clearSession = () => {
  localStorage.removeItem('jabvox_affiliate_token');
  localStorage.removeItem('jabvox_affiliate_name');
  localStorage.removeItem('jabvox_affiliate_expires');
  localStorage.removeItem('jabvox_affiliate_slug');
};

onMounted(() => {
  const token = localStorage.getItem('jabvox_affiliate_token');
  const expires = Number(localStorage.getItem('jabvox_affiliate_expires') ?? 0);
  if (!token || Date.now() > expires) {
    clearSession();
    router.replace({
      name: 'affiliate_portal_login',
      params: {
        portalAccountId: portalAccountId.value,
        affiliateSlug: affiliateSlug.value,
      },
    });
  }
});

const affiliateName = computed(
  () => localStorage.getItem('jabvox_affiliate_name') ?? 'Afiliado'
);

const navItems = computed(() => [
  {
    name: 'affiliate_portal_manual',
    icon: 'i-lucide-user-plus',
    label: t('JABVOX_AFFILIATE_PORTAL.NAV_MANUAL'),
  },
  {
    name: 'affiliate_portal_bulk',
    icon: 'i-lucide-upload',
    label: t('JABVOX_AFFILIATE_PORTAL.NAV_BULK'),
  },
  {
    name: 'affiliate_portal_history',
    icon: 'i-lucide-history',
    label: t('JABVOX_AFFILIATE_PORTAL.NAV_HISTORY'),
  },
  {
    name: 'affiliate_portal_leads',
    icon: 'i-lucide-users',
    label: t('JABVOX_AFFILIATE_PORTAL.NAV_LEADS'),
  },
]);

const isActive = itemName => route.name === itemName;

const navigate = name => {
  router.push({
    name,
    params: {
      portalAccountId: portalAccountId.value,
      affiliateSlug: affiliateSlug.value,
    },
  });
};

const logout = () => {
  const slug = affiliateSlug.value;
  clearSession();
  router.push({
    name: 'affiliate_portal_login',
    params: { portalAccountId: portalAccountId.value, affiliateSlug: slug },
  });
};
</script>

<template>
  <div class="flex h-screen bg-n-surface-1">
    <!-- Sidebar -->
    <aside
      class="w-56 shrink-0 border-r border-n-weak bg-n-surface-2 flex flex-col"
    >
      <div class="p-4 border-b border-n-weak">
        <div class="flex items-center gap-2">
          <div
            class="w-8 h-8 rounded-full bg-n-brand/10 flex items-center justify-center"
          >
            <span class="i-lucide-users text-n-brand size-4" />
          </div>
          <div class="min-w-0">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AFFILIATE_PORTAL.PORTAL_LABEL') }}
            </p>
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ affiliateName }}
            </p>
          </div>
        </div>
      </div>

      <nav class="flex-1 p-2 space-y-0.5">
        <button
          v-for="item in navItems"
          :key="item.name"
          class="w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm transition-colors"
          :class="
            isActive(item.name)
              ? 'bg-n-brand/10 text-n-brand font-medium'
              : 'text-n-slate-11 hover:bg-n-alpha-black2'
          "
          @click="navigate(item.name)"
        >
          <span class="size-4 shrink-0" :class="[item.icon]" />
          {{ item.label }}
        </button>
      </nav>

      <div class="p-2 border-t border-n-weak">
        <button
          class="w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-black2 transition-colors"
          @click="logout"
        >
          <span class="i-lucide-log-out size-4 shrink-0" />
          {{ t('JABVOX_AFFILIATE_PORTAL.LOGOUT') }}
        </button>
      </div>
    </aside>

    <!-- Main content -->
    <main class="flex-1 overflow-auto">
      <RouterView />
    </main>
  </div>
</template>
