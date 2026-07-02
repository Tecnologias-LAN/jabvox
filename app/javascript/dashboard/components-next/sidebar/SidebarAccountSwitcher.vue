<script setup>
import { computed, ref, nextTick, onBeforeUnmount } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import ButtonNext from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import Logo from 'next/icon/Logo.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

defineProps({
  isCollapsed: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['showCreateAccountModal']);

const { t } = useI18n();
const { accountId, currentAccount } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const globalConfig = useMapGetter('globalConfig/get');
const isRTL = useMapGetter('accounts/isRTL');

const userAccounts = useMapGetter('getUserAccounts');

const showAccountSwitcher = computed(
  () => userAccounts.value.length > 1 && currentAccount.value.name
);

const sortedCurrentUserAccounts = computed(() => {
  return [...(currentUser.value.accounts || [])].sort((a, b) =>
    a.name.localeCompare(b.name)
  );
});

// Dropdown state. The panel is teleported to <body> so it escapes the sidebar's
// stacking context (z-40) and always renders above module views (Tasks,
// Analytics, AI Chat, Internal Chat, Calendar) whose sub-navs also use z-40.
const isOpen = ref(false);
const triggerRef = ref(null);
const panelRef = ref(null);
const panelStyle = ref({});

const positionPanel = () => {
  const el = triggerRef.value;
  if (!el) return;
  const rect = el.getBoundingClientRect();
  const viewportHeight = window.innerHeight;
  // Prefer opening upward from the trigger (the switcher sits at the sidebar
  // footer), clamping so the panel never overflows the viewport.
  const estimatedHeight = panelRef.value?.offsetHeight || 320;
  const bottom = Math.max(8, viewportHeight - rect.top + 8);
  const clampedBottom = Math.min(bottom, viewportHeight - estimatedHeight - 8);
  panelStyle.value = {
    [isRTL.value ? 'right' : 'left']: `${rect.left}px`,
    bottom: `${Math.max(8, clampedBottom)}px`,
    minWidth: `${Math.max(rect.width, 320)}px`,
  };
};

const closeMenu = () => {
  isOpen.value = false;
};

const toggle = async () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    await nextTick();
    positionPanel();
  }
};

onClickOutside(panelRef, () => closeMenu(), { ignore: [triggerRef] });

const onScrollOrResize = () => {
  if (isOpen.value) positionPanel();
};
window.addEventListener('resize', onScrollOrResize);
window.addEventListener('scroll', onScrollOrResize, true);
onBeforeUnmount(() => {
  window.removeEventListener('resize', onScrollOrResize);
  window.removeEventListener('scroll', onScrollOrResize, true);
});

const onChangeAccount = newId => {
  const accountUrl = `/app/accounts/${newId}/dashboard`;
  window.location.href = accountUrl;
};

const emitNewAccount = () => {
  closeMenu();
  emit('showCreateAccountModal');
};
</script>

<template>
  <div class="relative">
    <!-- Collapsed view: Logo trigger -->
    <button
      v-if="isCollapsed"
      ref="triggerRef"
      class="grid flex-shrink-0 place-content-center p-2 rounded-lg cursor-pointer hover:bg-n-alpha-1"
      :class="{ 'bg-n-alpha-1': isOpen }"
      :title="currentAccount.name"
      @click="toggle"
    >
      <Logo class="size-7" />
    </button>
    <!-- Expanded view: Account name trigger -->
    <button
      v-else
      id="sidebar-account-switcher"
      ref="triggerRef"
      :data-account-id="accountId"
      aria-haspopup="listbox"
      aria-controls="account-options"
      class="flex items-center gap-2 justify-between w-full rounded-lg px-2"
      :class="[
        isOpen && 'bg-n-alpha-1',
        showAccountSwitcher
          ? 'hover:bg-n-alpha-1 cursor-pointer'
          : 'cursor-default',
      ]"
      @click="() => showAccountSwitcher && toggle()"
    >
      <span
        class="text-sm font-medium leading-5 text-n-slate-12 truncate"
        aria-live="polite"
      >
        {{ currentAccount.name }}
      </span>

      <span
        v-if="showAccountSwitcher"
        aria-hidden="true"
        class="i-lucide-chevron-down size-4 text-n-slate-10 flex-shrink-0"
      />
    </button>

    <TeleportWithDirection>
      <div
        v-if="isOpen && (showAccountSwitcher || isCollapsed)"
        id="account-options"
        ref="panelRef"
        class="fixed z-[100] max-w-[90vw]"
        :style="panelStyle"
      >
        <div
          class="text-sm bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak rounded-xl shadow-lg py-2 px-2 gap-2 grid list-none"
        >
          <div class="grid gap-1">
            <div
              class="px-2 py-1.5 text-xs font-medium text-n-slate-11 uppercase tracking-wider"
            >
              {{ t('SIDEBAR_ITEMS.SWITCH_ACCOUNT') }}
            </div>
            <button
              v-for="account in sortedCurrentUserAccounts"
              :id="`account-${account.id}`"
              :key="account.id"
              class="flex items-center justify-between gap-2 px-2 py-1.5 w-full rounded-lg cursor-pointer hover:bg-n-alpha-2 text-left rtl:text-right"
              @click="onChangeAccount(account.id)"
            >
              <div class="flex gap-2 items-center min-w-0">
                <span
                  class="text-n-slate-12 max-w-36 truncate min-w-0"
                  :title="account.name"
                >
                  {{ account.name }}
                </span>
                <div class="flex-shrink-0 w-px h-3 bg-n-strong" />
                <span
                  class="text-n-slate-11 max-w-24 truncate capitalize"
                  :title="account.name"
                >
                  {{ account.custom_role?.name || account.role }}
                </span>
              </div>
              <Icon
                v-show="account.id === accountId"
                icon="i-lucide-check"
                class="text-n-teal-11 size-5 flex-shrink-0"
              />
            </button>
          </div>
          <ButtonNext
            v-if="globalConfig.createNewAccountFromDashboard"
            color="slate"
            variant="faded"
            class="w-full"
            size="sm"
            @click="emitNewAccount"
          >
            {{ t('CREATE_ACCOUNT.NEW_ACCOUNT') }}
          </ButtonNext>
        </div>
      </div>
    </TeleportWithDirection>
  </div>
</template>
