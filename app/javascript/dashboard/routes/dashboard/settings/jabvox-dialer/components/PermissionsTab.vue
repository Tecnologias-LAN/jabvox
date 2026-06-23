<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SearchInput from './SearchInput.vue';

const store = useStore();
const { t } = useI18n();

const agents = useMapGetter('agents/getAgents');
const dialerAccesses = useMapGetter('jabvoxDialer/getDialerAccesses');
const uiFlags = useMapGetter('jabvoxDialer/getUIFlags');

const search = ref('');
const savingId = ref(null);

const isGranted = userId =>
  dialerAccesses.value.find(x => x.user_id === userId)?.can_access ?? false;

const grantedCount = computed(
  () => agents.value.filter(a => isGranted(a.id)).length
);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return agents.value;
  return agents.value.filter(
    a => a.name?.toLowerCase().includes(q) || a.email?.toLowerCase().includes(q)
  );
});

const toggleAccess = async agent => {
  savingId.value = agent.id;
  try {
    await store.dispatch('jabvoxDialer/updateDialerAccess', {
      userId: agent.id,
      canAccess: !isGranted(agent.id),
    });
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  } finally {
    savingId.value = null;
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('JABVOX_DIALER.PERMISSIONS.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11 max-w-2xl">
        {{ t('JABVOX_DIALER.PERMISSIONS.DESCRIPTION') }}
      </p>
    </div>

    <div
      v-if="uiFlags.isFetchingAccesses"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <div
      v-else-if="!agents.length"
      class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
    >
      {{ t('JABVOX_DIALER.PERMISSIONS.NO_AGENTS') }}
    </div>

    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <SearchInput
          v-model="search"
          :placeholder="t('JABVOX_DIALER.PERMISSIONS.SEARCH_PLACEHOLDER')"
        />
        <span class="text-xs text-n-slate-10">
          {{ grantedCount }} / {{ agents.length }}
          {{ t('JABVOX_DIALER.PERMISSIONS.GRANTED') }}
        </span>
      </div>

      <div
        v-if="!filtered.length"
        class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_DIALER.PERMISSIONS.NO_RESULTS') }}
      </div>

      <div
        v-else
        class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm divide-y divide-n-weak overflow-hidden"
      >
        <div
          v-for="agent in filtered"
          :key="agent.id"
          class="flex items-center gap-3 px-4 py-3"
        >
          <Avatar
            :name="agent.name"
            :src="agent.thumbnail"
            :size="36"
            rounded-full
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ agent.name }}
            </p>
            <p class="text-xs text-n-slate-10 truncate">{{ agent.email }}</p>
          </div>
          <Spinner v-if="savingId === agent.id" :size="16" />
          <Switch
            v-else
            :model-value="isGranted(agent.id)"
            @update:model-value="toggleAccess(agent)"
          />
        </div>
      </div>
    </template>
  </div>
</template>
