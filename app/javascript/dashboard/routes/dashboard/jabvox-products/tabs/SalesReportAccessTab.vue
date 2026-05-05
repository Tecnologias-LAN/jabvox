<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const store = useStore();
const { t } = useI18n();

const accesses = useMapGetter('jabvoxProducts/getSalesReportAccesses');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const agentsUIFlags = useMapGetter('agents/getUIFlags');

const savingUserId = ref(null);
const isLoading = computed(
  () => uiFlags.value.isFetchingAccesses || agentsUIFlags.value.isFetching
);

onMounted(() => {
  store.dispatch('jabvoxProducts/fetchSalesReportAccesses');
  store.dispatch('agents/get');
});

const isGranted = userId => {
  const access = accesses.value.find(a => a.user_id === userId);
  return access?.can_view_reports ?? false;
};

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
  <div class="max-w-2xl space-y-4">
    <div>
      <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_PRODUCTS.REPORTS.PERMISSIONS_TITLE') }}
      </h2>
      <p class="text-sm text-slate-500 mt-1">
        {{ $t('JABVOX_PRODUCTS.REPORTS.PERMISSIONS_DESC') }}
      </p>
    </div>

    <div
      v-if="isLoading"
      class="text-sm text-slate-400 animate-pulse py-6 text-center"
    >
      {{ $t('JABVOX_PRODUCTS.LOADING') }}
    </div>

    <div
      v-else-if="!agents.length"
      class="text-sm text-slate-400 text-center py-8"
    >
      {{ $t('JABVOX_PRODUCTS.REPORTS.NO_AGENTS') }}
    </div>

    <div
      v-else
      class="rounded-2xl border border-slate-200 dark:border-slate-700 overflow-hidden"
    >
      <table
        class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
      >
        <thead>
          <tr
            class="bg-slate-50 dark:bg-slate-800 text-left text-slate-500 dark:text-slate-400"
          >
            <th class="px-5 py-3 font-medium">
              {{ $t('JABVOX_PRODUCTS.REPORTS.COLS.AGENT') }}
            </th>
            <th class="px-5 py-3 font-medium">
              {{ $t('JABVOX_PRODUCTS.REPORTS.COLS.EMAIL') }}
            </th>
            <th class="px-5 py-3 font-medium">
              {{ $t('JABVOX_PRODUCTS.REPORTS.COLS.ACCESS') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
          <tr
            v-for="agent in agents"
            :key="agent.id"
            class="hover:bg-slate-50 dark:hover:bg-slate-800/30"
          >
            <td
              class="px-5 py-3 font-medium text-slate-800 dark:text-slate-100"
            >
              {{ agent.name }}
            </td>
            <td class="px-5 py-3 text-slate-500">{{ agent.email }}</td>
            <td class="px-5 py-3">
              <button
                class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors"
                :class="[
                  isGranted(agent.id)
                    ? 'bg-woot-600'
                    : 'bg-slate-200 dark:bg-slate-700',
                ]"
                :disabled="savingUserId === agent.id"
                @click="toggleAccess(agent)"
              >
                <span
                  class="inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform"
                  :class="[
                    isGranted(agent.id) ? 'translate-x-6' : 'translate-x-1',
                  ]"
                />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
