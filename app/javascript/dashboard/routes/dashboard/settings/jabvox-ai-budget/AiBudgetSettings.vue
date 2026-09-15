<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { aiBudgetAPI } from 'dashboard/api/jabvox/aiBudget';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();

const loading = ref(true);
const balance = ref({ connected: false });
const keys = ref([]);
const creating = ref(false);
const newKeyAlias = ref('');
const newKeyBudget = ref('');
const search = ref('');
// La key recién creada se muestra UNA vez; se limpia al recargar.
const createdKey = ref(null);

const connected = computed(() => !!balance.value.connected);
// Team sin tope en el proveedor: el consumo no está limitado por saldo. Mostrarlo como
// "$0.00" diría justo lo contrario (agotado).
const unlimited = computed(() => !!balance.value.unlimited);
// La key sobre la que se está ejecutando una acción (para deshabilitar sus botones).
const busyKey = ref(null);

const filteredKeys = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return keys.value;
  return keys.value.filter(k => (k.alias || '').toLowerCase().includes(q));
});

// Porcentaje consumido del tope. Null cuando no hay tope (nada que llenar).
const usagePercent = computed(() => {
  const total = Number(balance.value.total_budget_usd || 0);
  if (unlimited.value || total <= 0) return null;
  const spent = Number(balance.value.cached_spend_usd || 0);
  return Math.min(100, Math.round((spent / total) * 100));
});

// Color de la barra según lo consumido: verde → ámbar → rojo.
const usageBarClass = computed(() => {
  const p = usagePercent.value;
  if (p === null) return 'bg-n-teal-9';
  if (p >= 90) return 'bg-n-ruby-9';
  if (p >= 70) return 'bg-n-amber-9';
  return 'bg-n-teal-9';
});

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

const copyCreatedKey = async () => {
  try {
    await navigator.clipboard.writeText(createdKey.value);
    useAlert(t('JABVOX_AI_BUDGET.COPIED'));
  } catch (e) {
    useAlert(t('JABVOX_AI_BUDGET.KEY_ACTION_ERROR'));
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
  <div class="w-full h-full overflow-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-4xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-start gap-3">
        <span
          class="i-lucide-sparkles size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0 flex-1">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_AI_BUDGET.TITLE') }}
          </h1>
          <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_AI_BUDGET.SUBTITLE') }}
          </p>
        </div>
      </div>

      <!-- Cargando -->
      <div v-if="loading" class="flex items-center justify-center py-16">
        <Spinner :size="20" />
      </div>

      <template v-else>
        <!-- Sin aprovisionar -->
        <div
          v-if="!connected"
          class="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-n-weak px-6 py-12 text-center"
        >
          <span
            class="flex size-12 items-center justify-center rounded-2xl bg-n-alpha-2 text-n-slate-10"
          >
            <span class="i-lucide-wallet-cards size-6" />
          </span>
          <p class="max-w-md text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_AI_BUDGET.NOT_PROVISIONED') }}
          </p>
        </div>

        <template v-else>
          <!-- KPIs -->
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <div
              class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
            >
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
              >
                <span class="i-lucide-wallet size-5" />
              </span>
              <div class="min-w-0">
                <p
                  class="truncate text-xl font-semibold tabular-nums text-n-slate-12"
                >
                  {{
                    unlimited
                      ? t('JABVOX_AI_BUDGET.UNLIMITED')
                      : money(balance.total_budget_usd)
                  }}
                </p>
                <p class="text-xs text-n-slate-11">
                  {{ t('JABVOX_AI_BUDGET.ACQUIRED') }}
                </p>
              </div>
            </div>

            <div
              class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
            >
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
              >
                <span class="i-lucide-trending-up size-5" />
              </span>
              <div class="min-w-0">
                <p
                  class="truncate text-xl font-semibold tabular-nums text-n-slate-12"
                >
                  {{ money(balance.cached_spend_usd) }}
                </p>
                <p class="text-xs text-n-slate-11">
                  {{ t('JABVOX_AI_BUDGET.SPENT') }}
                </p>
              </div>
            </div>

            <div
              class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
            >
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-teal-3 text-n-teal-11"
              >
                <span class="i-lucide-piggy-bank size-5" />
              </span>
              <div class="min-w-0">
                <p
                  class="truncate text-xl font-semibold tabular-nums text-n-teal-11"
                >
                  {{
                    unlimited
                      ? t('JABVOX_AI_BUDGET.UNLIMITED')
                      : money(balance.remaining_usd)
                  }}
                </p>
                <p class="text-xs text-n-slate-11">
                  {{ t('JABVOX_AI_BUDGET.REMAINING') }}
                </p>
              </div>
            </div>

            <div
              class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
            >
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
              >
                <span class="i-lucide-calendar-sync size-5" />
              </span>
              <div class="min-w-0">
                <p
                  class="truncate text-xl font-semibold tabular-nums text-n-slate-12"
                >
                  {{ money(balance.plan_budget_usd) }}
                </p>
                <p class="text-xs text-n-slate-11">
                  {{ t('JABVOX_AI_BUDGET.PLAN_MONTHLY') }}
                </p>
              </div>
            </div>
          </div>

          <!-- Barra de consumo (solo si hay un tope contra el que medir) -->
          <div
            v-if="usagePercent !== null"
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
          >
            <div class="flex items-baseline justify-between gap-3">
              <p class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_AI_BUDGET.USAGE_TITLE') }}
              </p>
              <p class="text-xs tabular-nums text-n-slate-11">
                {{ money(balance.cached_spend_usd) }}
                {{ t('JABVOX_AI_BUDGET.USAGE_OF') }}
                {{ money(balance.total_budget_usd) }}
                <span class="ml-1 font-medium text-n-slate-12">
                  {{ `(${usagePercent}%)` }}
                </span>
              </p>
            </div>
            <div
              class="mt-3 h-2 w-full overflow-hidden rounded-full bg-n-alpha-2"
            >
              <div
                class="h-full rounded-full transition-all duration-500"
                :class="usageBarClass"
                :style="{ width: `${usagePercent}%` }"
              />
            </div>
          </div>

          <!-- Aviso: el team no tiene tope en el proveedor -->
          <div
            v-if="unlimited"
            class="flex items-start gap-3 rounded-2xl border border-n-amber-6 bg-n-amber-2 px-4 py-3"
          >
            <span
              class="i-lucide-infinity size-5 shrink-0 text-n-amber-11 mt-0.5"
            />
            <p class="text-sm leading-relaxed text-n-slate-12">
              {{ t('JABVOX_AI_BUDGET.UNLIMITED_HINT') }}
            </p>
          </div>

          <!-- Crear virtual key -->
          <div
            class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
          >
            <div class="border-b border-n-weak px-5 py-4 sm:px-6">
              <h2 class="text-base font-semibold text-n-slate-12">
                {{ t('JABVOX_AI_BUDGET.CREATE_KEY_TITLE') }}
              </h2>
              <p class="mt-0.5 text-sm leading-relaxed text-n-slate-11">
                {{ t('JABVOX_AI_BUDGET.CREATE_KEY_HINT') }}
              </p>
            </div>
            <div class="flex flex-col gap-4 px-5 py-5 sm:px-6">
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Input
                  v-model="newKeyAlias"
                  :label="t('JABVOX_AI_BUDGET.KEY_ALIAS')"
                  :placeholder="t('JABVOX_AI_BUDGET.KEY_ALIAS_PH')"
                  @keydown.enter="createKey"
                />
                <Input
                  v-model="newKeyBudget"
                  type="number"
                  min="0"
                  step="0.01"
                  :label="t('JABVOX_AI_BUDGET.KEY_BUDGET')"
                  placeholder="USD"
                  @keydown.enter="createKey"
                />
              </div>
              <div class="flex justify-end">
                <Button
                  icon="i-lucide-plus"
                  :label="t('JABVOX_AI_BUDGET.CREATE_KEY')"
                  :is-loading="creating"
                  class="w-full sm:w-auto"
                  @click="createKey"
                />
              </div>

              <!-- Key recién creada: se muestra UNA vez -->
              <div
                v-if="createdKey"
                class="rounded-xl border border-n-teal-6 bg-n-teal-2 p-4"
              >
                <div class="flex items-start gap-2">
                  <span
                    class="i-lucide-key-round size-4 shrink-0 text-n-teal-11 mt-0.5"
                  />
                  <p class="text-xs font-medium leading-relaxed text-n-teal-11">
                    {{ t('JABVOX_AI_BUDGET.KEY_ONCE') }}
                  </p>
                </div>
                <div
                  class="mt-3 flex flex-col gap-2 sm:flex-row sm:items-center"
                >
                  <code
                    class="min-w-0 flex-1 break-all rounded-lg bg-n-solid-1 px-3 py-2 font-mono text-xs text-n-slate-12"
                  >
                    {{ createdKey }}
                  </code>
                  <Button
                    icon="i-lucide-copy"
                    variant="faded"
                    size="sm"
                    :label="t('JABVOX_AI_BUDGET.COPY')"
                    class="shrink-0"
                    @click="copyCreatedKey"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- Lista de keys -->
          <div class="flex flex-col gap-4">
            <!-- Sin keys todavía -->
            <div
              v-if="!keys.length"
              class="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-n-weak px-6 py-12 text-center"
            >
              <span
                class="flex size-12 items-center justify-center rounded-2xl bg-n-alpha-2 text-n-slate-10"
              >
                <span class="i-lucide-key-round size-6" />
              </span>
              <div>
                <p class="text-sm font-medium text-n-slate-12">
                  {{ t('JABVOX_AI_BUDGET.EMPTY_KEYS_TITLE') }}
                </p>
                <p class="mt-1 text-sm text-n-slate-11">
                  {{ t('JABVOX_AI_BUDGET.NO_KEYS') }}
                </p>
              </div>
            </div>

            <template v-else>
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div class="relative w-full sm:w-64">
                  <Input
                    v-model="search"
                    :placeholder="t('JABVOX_AI_BUDGET.SEARCH_KEYS')"
                    custom-input-class="!pl-9"
                  >
                    <template #prefix>
                      <span
                        class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                      />
                    </template>
                  </Input>
                </div>
                <span class="text-xs text-n-slate-10">
                  {{ t('JABVOX_AI_BUDGET.KEYS_COUNT', { count: keys.length }) }}
                </span>
              </div>

              <!-- Sin resultados de búsqueda -->
              <div
                v-if="!filteredKeys.length"
                class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
              >
                {{ t('JABVOX_AI_BUDGET.NO_RESULTS') }}
              </div>

              <!-- Filas (no tabla: así colapsa bien en móvil) -->
              <div
                v-else
                class="divide-y divide-n-weak overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
              >
                <div
                  v-for="(k, i) in filteredKeys"
                  :key="k.token_id || i"
                  class="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-3 transition-colors hover:bg-n-alpha-1"
                >
                  <span
                    class="i-lucide-key-round size-5 shrink-0 text-n-slate-10 hidden sm:block"
                  />

                  <!-- Nombre + tope/gasto en móvil -->
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-medium text-n-slate-12">
                      {{ k.alias || '—' }}
                    </p>
                    <p class="text-xs tabular-nums text-n-slate-10 sm:hidden">
                      {{ moneyOrDash(k.spend) }}
                      <span v-if="k.max_budget != null">
                        {{ t('JABVOX_AI_BUDGET.USAGE_OF') }}
                        {{ money(k.max_budget) }}
                      </span>
                      <span v-else>
                        {{ `· ${t('JABVOX_AI_BUDGET.UNLIMITED')}` }}
                      </span>
                    </p>
                  </div>

                  <!-- Tope y gasto: solo desde sm (en móvil van bajo el nombre) -->
                  <div class="hidden sm:block shrink-0 text-right">
                    <p class="text-sm tabular-nums text-n-slate-12">
                      {{
                        k.max_budget != null
                          ? money(k.max_budget)
                          : t('JABVOX_AI_BUDGET.UNLIMITED')
                      }}
                    </p>
                    <p class="text-xs text-n-slate-10">
                      {{ t('JABVOX_AI_BUDGET.COL_BUDGET') }}
                    </p>
                  </div>
                  <div class="hidden md:block shrink-0 text-right">
                    <p class="text-sm tabular-nums text-n-slate-12">
                      {{ moneyOrDash(k.spend) }}
                    </p>
                    <p class="text-xs text-n-slate-10">
                      {{ t('JABVOX_AI_BUDGET.COL_SPENT') }}
                    </p>
                  </div>

                  <Label
                    :label="
                      k.blocked
                        ? t('JABVOX_AI_BUDGET.BLOCKED')
                        : t('JABVOX_AI_BUDGET.ACTIVE')
                    "
                    :color="k.blocked ? 'ruby' : 'teal'"
                    compact
                  />

                  <div class="flex shrink-0 items-center gap-1">
                    <Button
                      icon="i-lucide-pencil"
                      variant="ghost"
                      size="sm"
                      :title="t('JABVOX_AI_BUDGET.EDIT_BUDGET')"
                      :disabled="!k.token_id || busyKey === k.token_id"
                      @click="editBudget(k)"
                    />
                    <Button
                      :icon="k.blocked ? 'i-lucide-lock-open' : 'i-lucide-ban'"
                      variant="ghost"
                      :color="k.blocked ? 'teal' : 'ruby'"
                      size="sm"
                      :title="
                        k.blocked
                          ? t('JABVOX_AI_BUDGET.UNBLOCK')
                          : t('JABVOX_AI_BUDGET.BLOCK')
                      "
                      :disabled="!k.token_id || busyKey === k.token_id"
                      @click="toggleBlock(k)"
                    />
                  </div>
                </div>
              </div>
            </template>
          </div>
        </template>
      </template>
    </div>

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
