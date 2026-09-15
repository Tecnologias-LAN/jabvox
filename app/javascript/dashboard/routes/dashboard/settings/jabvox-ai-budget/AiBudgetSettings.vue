<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { aiBudgetAPI } from 'dashboard/api/jabvox/aiBudget';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

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
// Team sin tope en el proveedor: el consumo no está limitado por saldo. Mostrarlo como
// "$0.00" diría justo lo contrario (agotado).
const unlimited = computed(() => !!balance.value.unlimited);
// La key sobre la que se está ejecutando una acción (para deshabilitar sus botones).
const busyKey = ref(null);

const refreshKeys = async () => {
  const res = await aiBudgetAPI.keys();
  keys.value = res.data?.keys || [];
};

const fetchAll = async () => {
  loading.value = true;
  try {
    const { data } = await aiBudgetAPI.get();
    balance.value = data || { connected: false };
    if (connected.value) await refreshKeys();
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
    await refreshKeys();
  } catch (e) {
    const msg = e?.response?.data?.error || t('JABVOX_AI_BUDGET.KEY_ERROR');
    useAlert(msg);
  } finally {
    creating.value = false;
  }
};

const money = v => `$${Number(v || 0).toFixed(2)}`;
// Un tope nulo significa "sin límite", no cero.
const moneyOrDash = v => (v === null || v === undefined ? '—' : money(v));

// Acciones sobre una key concreta. El token_id es el hash, nunca la key en claro.
// `outcome` es 'blocked' | 'unblocked' | 'updated'; cada rama usa una clave i18n literal
// para que el extractor de traducciones pueda detectarlas.
const successMessage = outcome => {
  if (outcome === 'blocked') return t('JABVOX_AI_BUDGET.KEY_BLOCKED');
  if (outcome === 'unblocked') return t('JABVOX_AI_BUDGET.KEY_UNBLOCKED');
  return t('JABVOX_AI_BUDGET.KEY_UPDATED');
};

const runKeyAction = async (tokenId, action, outcome) => {
  busyKey.value = tokenId;
  try {
    await action();
    useAlert(successMessage(outcome));
    await refreshKeys();
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('JABVOX_AI_BUDGET.KEY_ACTION_ERROR')
    );
  } finally {
    busyKey.value = null;
  }
};

// --- Bloquear / desbloquear ---
const blockDialog = ref(null);
const targetKey = ref(null);

const toggleBlock = k => {
  if (!k.token_id) return;
  targetKey.value = k;
  // Desbloquear no es destructivo: se aplica directo. Bloquear sí pide confirmación.
  if (k.blocked) {
    runKeyAction(
      k.token_id,
      () => aiBudgetAPI.unblockKey(k.token_id),
      'unblocked'
    );
    return;
  }
  blockDialog.value?.open();
};

const confirmBlock = () => {
  const k = targetKey.value;
  if (!k?.token_id) return;
  runKeyAction(k.token_id, () => aiBudgetAPI.blockKey(k.token_id), 'blocked');
};

// --- Cambiar el tope de una key ---
const budgetDialog = ref(null);
const budgetValue = ref('');

const editBudget = k => {
  if (!k.token_id) return;
  targetKey.value = k;
  budgetValue.value = k.max_budget != null ? String(k.max_budget) : '';
  budgetDialog.value?.open();
};

const confirmBudget = () => {
  const k = targetKey.value;
  const value = Number(budgetValue.value);
  if (!k?.token_id) return;
  if (!Number.isFinite(value) || value <= 0) {
    useAlert(t('JABVOX_AI_BUDGET.KEY_ACTION_ERROR'));
    return;
  }
  runKeyAction(
    k.token_id,
    () => aiBudgetAPI.updateKey(k.token_id, value),
    'updated'
  );
  budgetDialog.value?.close();
};

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
            {{
              unlimited
                ? t('JABVOX_AI_BUDGET.UNLIMITED')
                : money(balance.total_budget_usd)
            }}
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
            {{
              unlimited
                ? t('JABVOX_AI_BUDGET.UNLIMITED')
                : money(balance.remaining_usd)
            }}
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

      <!-- Aviso: el team no tiene tope en el proveedor -->
      <div
        v-if="connected && unlimited"
        class="p-3 text-sm border rounded-lg border-n-amber-6 bg-n-amber-2 text-n-slate-11"
      >
        {{ t('JABVOX_AI_BUDGET.UNLIMITED_HINT') }}
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

      <!-- Sin keys todavía -->
      <div
        v-if="connected && !keys.length"
        class="p-4 text-sm border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-11"
      >
        {{ t('JABVOX_AI_BUDGET.NO_KEYS') }}
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
              <th class="p-3">{{ t('JABVOX_AI_BUDGET.COL_ACTIONS') }}</th>
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
                {{
                  k.max_budget != null
                    ? money(k.max_budget)
                    : t('JABVOX_AI_BUDGET.UNLIMITED')
                }}
              </td>
              <td class="p-3 text-n-slate-11">{{ moneyOrDash(k.spend) }}</td>
              <td class="p-3">
                <span :class="k.blocked ? 'text-n-ruby-11' : 'text-n-teal-11'">
                  {{
                    k.blocked
                      ? t('JABVOX_AI_BUDGET.BLOCKED')
                      : t('JABVOX_AI_BUDGET.ACTIVE')
                  }}
                </span>
              </td>
              <td class="p-3">
                <div class="flex gap-2">
                  <Button
                    size="sm"
                    variant="faded"
                    :label="t('JABVOX_AI_BUDGET.EDIT_BUDGET')"
                    :disabled="!k.token_id || busyKey === k.token_id"
                    @click="editBudget(k)"
                  />
                  <Button
                    size="sm"
                    variant="faded"
                    :color="k.blocked ? 'teal' : 'ruby'"
                    :label="
                      k.blocked
                        ? t('JABVOX_AI_BUDGET.UNBLOCK')
                        : t('JABVOX_AI_BUDGET.BLOCK')
                    "
                    :disabled="!k.token_id || busyKey === k.token_id"
                    @click="toggleBlock(k)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <!-- Confirmación de bloqueo: la key deja de funcionar de inmediato. -->
    <Dialog
      ref="blockDialog"
      type="alert"
      :title="t('JABVOX_AI_BUDGET.BLOCK')"
      :description="t('JABVOX_AI_BUDGET.CONFIRM_BLOCK')"
      :confirm-button-label="t('JABVOX_AI_BUDGET.BLOCK')"
      @confirm="confirmBlock"
    />

    <!-- Cambiar el tope de una key -->
    <Dialog
      ref="budgetDialog"
      :title="t('JABVOX_AI_BUDGET.EDIT_BUDGET')"
      :confirm-button-label="t('JABVOX_AI_BUDGET.EDIT_BUDGET')"
      @confirm="confirmBudget"
    >
      <Input
        v-model="budgetValue"
        type="number"
        min="0"
        step="0.01"
        :label="t('JABVOX_AI_BUDGET.EDIT_BUDGET_PROMPT')"
        placeholder="USD"
      />
    </Dialog>
  </div>
</template>
