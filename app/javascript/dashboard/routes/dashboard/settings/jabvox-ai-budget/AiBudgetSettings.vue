<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { aiBudgetAPI } from 'dashboard/api/jabvox/aiBudget';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const loading = ref(true);
const balance = ref({ connected: false });
const keys = ref([]);
const creating = ref(false);
const newKeyAlias = ref('');
const newKeyBudget = ref('');
// La key recién creada se muestra UNA vez; se limpia al recargar.
const createdKey = ref(null);

const connected = computed(() => !!balance.value.connected);

const fetchAll = async () => {
  loading.value = true;
  try {
    const { data } = await aiBudgetAPI.get();
    balance.value = data || { connected: false };
    if (connected.value) {
      const res = await aiBudgetAPI.keys();
      keys.value = res.data?.keys || [];
    }
  } catch (e) {
    useAlert(t('JABVOX_AI_BUDGET.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const createKey = async () => {
  creating.value = true;
  createdKey.value = null;
  try {
    const payload = { key_alias: newKeyAlias.value || undefined };
    if (newKeyBudget.value) payload.max_budget_usd = Number(newKeyBudget.value);
    const { data } = await aiBudgetAPI.createKey(payload);
    createdKey.value = data.key;
    newKeyAlias.value = '';
    newKeyBudget.value = '';
    useAlert(t('JABVOX_AI_BUDGET.KEY_CREATED'));
    // Refrescar la lista (sin la key en claro).
    const res = await aiBudgetAPI.keys();
    keys.value = res.data?.keys || [];
  } catch (e) {
    const msg = e?.response?.data?.error || t('JABVOX_AI_BUDGET.KEY_ERROR');
    useAlert(msg);
  } finally {
    creating.value = false;
  }
};

const money = v => `$${Number(v || 0).toFixed(2)}`;

onMounted(fetchAll);
</script>

<template>
  <div class="flex flex-col gap-6 p-6 overflow-auto">
    <div>
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('JABVOX_AI_BUDGET.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('JABVOX_AI_BUDGET.DESCRIPTION') }}
      </p>
    </div>

    <div v-if="loading" class="flex justify-center py-10">
      <Spinner />
    </div>

    <template v-else>
      <!-- Sin aprovisionar -->
      <div
        v-if="!connected"
        class="p-4 border rounded-lg border-n-weak bg-n-solid-2 text-sm text-n-slate-11"
      >
        {{ t('JABVOX_AI_BUDGET.NOT_PROVISIONED') }}
      </div>

      <!-- Saldo -->
      <div v-else class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div class="p-4 border rounded-lg border-n-weak bg-n-solid-2">
          <div class="text-xs text-n-slate-11">
            {{ t('JABVOX_AI_BUDGET.ACQUIRED') }}
          </div>
          <div class="mt-1 text-lg font-semibold text-n-slate-12">
            {{ money(balance.total_budget_usd) }}
          </div>
        </div>
        <div class="p-4 border rounded-lg border-n-weak bg-n-solid-2">
          <div class="text-xs text-n-slate-11">
            {{ t('JABVOX_AI_BUDGET.SPENT') }}
          </div>
          <div class="mt-1 text-lg font-semibold text-n-slate-12">
            {{ money(balance.cached_spend_usd) }}
          </div>
        </div>
        <div class="p-4 border rounded-lg border-n-weak bg-n-solid-2">
          <div class="text-xs text-n-slate-11">
            {{ t('JABVOX_AI_BUDGET.REMAINING') }}
          </div>
          <div class="mt-1 text-lg font-semibold text-n-teal-11">
            {{ money(balance.remaining_usd) }}
          </div>
        </div>
        <div class="p-4 border rounded-lg border-n-weak bg-n-solid-2">
          <div class="text-xs text-n-slate-11">
            {{ t('JABVOX_AI_BUDGET.PLAN_MONTHLY') }}
          </div>
          <div class="mt-1 text-lg font-semibold text-n-slate-12">
            {{ money(balance.plan_budget_usd) }}
          </div>
        </div>
      </div>

      <!-- Crear virtual key -->
      <div v-if="connected" class="p-4 border rounded-lg border-n-weak">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('JABVOX_AI_BUDGET.CREATE_KEY_TITLE') }}
        </h2>
        <p class="mt-1 mb-3 text-sm text-n-slate-11">
          {{ t('JABVOX_AI_BUDGET.CREATE_KEY_HINT') }}
        </p>
        <div class="flex flex-wrap items-end gap-3">
          <Input
            v-model="newKeyAlias"
            :label="t('JABVOX_AI_BUDGET.KEY_ALIAS')"
            :placeholder="t('JABVOX_AI_BUDGET.KEY_ALIAS_PH')"
          />
          <Input
            v-model="newKeyBudget"
            type="number"
            :label="t('JABVOX_AI_BUDGET.KEY_BUDGET')"
            placeholder="USD"
          />
          <Button
            :label="t('JABVOX_AI_BUDGET.CREATE_KEY')"
            :is-loading="creating"
            @click="createKey"
          />
        </div>

        <!-- Key recién creada: se muestra UNA vez -->
        <div
          v-if="createdKey"
          class="p-3 mt-4 border rounded-md border-n-teal-6 bg-n-teal-2"
        >
          <p class="mb-1 text-xs font-medium text-n-teal-11">
            {{ t('JABVOX_AI_BUDGET.KEY_ONCE') }}
          </p>
          <code class="block p-2 text-sm break-all rounded bg-n-solid-1">{{
            createdKey
          }}</code>
        </div>
      </div>

      <!-- Lista de keys (metadatos, sin la key en claro) -->
      <div
        v-if="connected && keys.length"
        class="border rounded-lg border-n-weak"
      >
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left border-b border-n-weak text-n-slate-11">
              <th class="p-3">{{ t('JABVOX_AI_BUDGET.COL_ALIAS') }}</th>
              <th class="p-3">{{ t('JABVOX_AI_BUDGET.COL_BUDGET') }}</th>
              <th class="p-3">{{ t('JABVOX_AI_BUDGET.COL_SPENT') }}</th>
              <th class="p-3">{{ t('JABVOX_AI_BUDGET.COL_STATUS') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(k, i) in keys"
              :key="i"
              class="border-b border-n-weak last:border-0"
            >
              <td class="p-3 text-n-slate-12">{{ k.alias || '—' }}</td>
              <td class="p-3 text-n-slate-11">
                {{ k.max_budget != null ? money(k.max_budget) : '—' }}
              </td>
              <td class="p-3 text-n-slate-11">{{ money(k.spend) }}</td>
              <td class="p-3">
                <span :class="k.blocked ? 'text-n-ruby-11' : 'text-n-teal-11'">
                  {{
                    k.blocked
                      ? t('JABVOX_AI_BUDGET.BLOCKED')
                      : t('JABVOX_AI_BUDGET.ACTIVE')
                  }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
