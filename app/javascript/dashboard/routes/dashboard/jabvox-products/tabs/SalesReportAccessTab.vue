<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SearchInput from '../components/SearchInput.vue';

const store = useStore();
const { t } = useI18n();

const accesses = useMapGetter('jabvoxProducts/getSalesReportAccesses');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const agentsUIFlags = useMapGetter('agents/getUIFlags');

const savingUserId = ref(null);
const search = ref('');
const isLoading = computed(
  () => uiFlags.value.isFetchingAccesses || agentsUIFlags.value.isFetching
);

const isGranted = userId =>
  accesses.value.find(a => a.user_id === userId)?.can_view_reports ?? false;

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

onMounted(() => {
  store.dispatch('jabvoxProducts/fetchSalesReportAccesses');
  store.dispatch('agents/get');
});

const toggleAccess = async agent => {
  savingUserId.value = agent.id;
  try {
    await store.dispatch('jabvoxProducts/updateSalesReportAccess', {
      userId: agent.id,
      canView: !isGranted(agent.id),
    });
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  } finally {
    savingUserId.value = null;
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('JABVOX_PRODUCTS.REPORTS.PERMISSIONS_TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11 max-w-2xl">
        {{ t('JABVOX_PRODUCTS.REPORTS.PERMISSIONS_DESC') }}
      </p>
    </div>

    <div
      v-if="isLoading"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <div
      v-else-if="!agents.length"
      class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
    >
      {{ t('JABVOX_PRODUCTS.REPORTS.NO_AGENTS') }}
    </div>

    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <SearchInput
          v-model="search"
          :placeholder="t('JABVOX_PRODUCTS.REPORTS.SEARCH_PLACEHOLDER')"
        />
        <span class="text-xs text-n-slate-10">
          {{ grantedCount }} / {{ agents.length }}
          {{ t('JABVOX_PRODUCTS.REPORTS.GRANTED') }}
        </span>
      </div>

      <div
        v-if="!filtered.length"
        class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_PRODUCTS.NO_RESULTS') }}
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
            :size="32"
            rounded-full
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ agent.name }}
            </p>
            <p class="text-xs text-n-slate-10 truncate">{{ agent.email }}</p>
          </div>
          <Spinner v-if="savingUserId === agent.id" :size="16" />
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
