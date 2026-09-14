<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import affiliatesAPI from 'dashboard/api/jabvox/affiliates';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import AffiliateFormDialog from './components/AffiliateFormDialog.vue';
import ConfirmDeleteDialog from './components/ConfirmDeleteDialog.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';
import IpWhitelistPanel from './components/IpWhitelistPanel.vue';

const store = useStore();
const { t } = useI18n();

const affiliates = useMapGetter('jabvoxAffiliates/getAffiliates');
const portalLoginUrl = useMapGetter('jabvoxAffiliates/getPortalLoginUrl');
const uiFlags = useMapGetter('jabvoxAffiliates/getUIFlags');

const search = ref('');
const visibleCredentials = ref(new Set());
const expandedIpAffiliate = ref(null);

const formDialog = ref(null);
const deleteAffiliateDialog = ref(null);
const deleteIpDialog = ref(null);
const regenerateDialog = ref(null);
const pendingIpDelete = ref(null);
const pendingRegenerate = ref(null);

onMounted(() => {
  store.dispatch('jabvoxAffiliates/fetchAffiliates');
  store.dispatch('jabvoxAffiliates/fetchPortalLoginUrl');
});

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return affiliates.value;
  return affiliates.value.filter(
    a =>
      a.name?.toLowerCase().includes(q) ||
      a.account_code?.toLowerCase().includes(q)
  );
});

// --- credential visibility ---
const isVisible = id => visibleCredentials.value.has(id);
const toggleCredential = id => {
  const next = new Set(visibleCredentials.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  visibleCredentials.value = next;
};
const mask = val => (val ? '••••••••••••' : '');
const maskCode = val => (val ? `${val.slice(0, 4)}••••••••` : '');

const copyToClipboard = async text => {
  await navigator.clipboard.writeText(text);
  useAlert(t('JABVOX_AFFILIATES.COPIED'));
};

const formatDate = value => new Date(value).toLocaleDateString('es');

// --- create ---
const openNew = () => formDialog.value?.open();

const onSubmitCreate = async name => {
  try {
    const result = await store.dispatch('jabvoxAffiliates/createAffiliate', {
      name,
    });
    formDialog.value?.showCredentials(result);
    useAlert(t('JABVOX_AFFILIATES.CREATED'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.ERROR'));
  }
};

// --- row actions ---
const onToggleActive = async affiliate => {
  try {
    await store.dispatch('jabvoxAffiliates/updateAffiliate', {
      id: affiliate.id,
      active: !affiliate.active,
    });
    useAlert(t('JABVOX_AFFILIATES.UPDATED'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.ERROR'));
  }
};

// Regenerating a token/code invalidates the current one, so confirm first.
const askRegenerateToken = affiliate => {
  pendingRegenerate.value = { type: 'token', affiliate };
  regenerateDialog.value?.open({
    title: t('JABVOX_AFFILIATES.REGENERATE_TOKEN_TITLE'),
    description: t('JABVOX_AFFILIATES.REGENERATE_TOKEN_CONFIRM'),
    confirmLabel: t('JABVOX_AFFILIATES.REGENERATE'),
  });
};

const askRegenerateCode = affiliate => {
  pendingRegenerate.value = { type: 'code', affiliate };
  regenerateDialog.value?.open({
    title: t('JABVOX_AFFILIATES.REGENERATE_CODE_TITLE'),
    description: t('JABVOX_AFFILIATES.REGENERATE_CODE_CONFIRM'),
    confirmLabel: t('JABVOX_AFFILIATES.REGENERATE'),
  });
};

const doRegenerate = async () => {
  const pending = pendingRegenerate.value;
  if (!pending) return;
  try {
    if (pending.type === 'token') {
      await store.dispatch(
        'jabvoxAffiliates/regenerateToken',
        pending.affiliate.id
      );
      useAlert(t('JABVOX_AFFILIATES.TOKEN_REGENERATED'));
    } else {
      await store.dispatch(
        'jabvoxAffiliates/regenerateCode',
        pending.affiliate.id
      );
      useAlert(t('JABVOX_AFFILIATES.CODE_REGENERATED'));
    }
  } catch {
    useAlert(t('JABVOX_AFFILIATES.ERROR'));
  } finally {
    pendingRegenerate.value = null;
  }
};

const askDeleteAffiliate = affiliate => {
  deleteAffiliateDialog.value?.open({
    title: t('JABVOX_AFFILIATES.DELETE'),
    description: t('JABVOX_AFFILIATES.DELETE_CONFIRM_BODY', {
      name: affiliate.name,
    }),
    data: affiliate.id,
  });
};

const doDeleteAffiliate = async id => {
  try {
    await store.dispatch('jabvoxAffiliates/deleteAffiliate', id);
    useAlert(t('JABVOX_AFFILIATES.DELETED'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.ERROR'));
  }
};

const toggleIpPanel = affiliate => {
  expandedIpAffiliate.value =
    expandedIpAffiliate.value === affiliate.id ? null : affiliate.id;
};

// IP deletion: panel requests it, we confirm via dialog, then call its callback.
const onRequestDeleteIp = ({ affiliateId, entry, remove }) => {
  pendingIpDelete.value = { affiliateId, entry, remove };
  deleteIpDialog.value?.open({
    title: t('JABVOX_AFFILIATES.IP.DELETE_TITLE'),
    description: t('JABVOX_AFFILIATES.IP.CONFIRM_DELETE'),
    data: entry.id,
  });
};

const doDeleteIp = async () => {
  const pending = pendingIpDelete.value;
  if (!pending) return;
  try {
    await affiliatesAPI.destroyIp(pending.affiliateId, pending.entry.id);
    pending.remove();
    useAlert(t('JABVOX_AFFILIATES.IP.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.IP.ERROR'));
  } finally {
    pendingIpDelete.value = null;
  }
};
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-handshake size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_AFFILIATES.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_AFFILIATES.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <Button
          :label="t('JABVOX_AFFILIATES.NEW_AFFILIATE')"
          icon="i-lucide-plus"
          class="shrink-0"
          @click="openNew"
        />
      </div>

      <!-- Portal URL card -->
      <div
        v-if="portalLoginUrl"
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span class="i-lucide-link size-5 text-n-slate-11 shrink-0 mt-0.5" />
          <div class="min-w-0">
            <p class="text-sm font-semibold text-n-slate-12">
              {{ t('JABVOX_AFFILIATES.PORTAL_CARD_TITLE') }}
            </p>
            <code class="text-xs font-mono text-n-brand break-all">
              {{ portalLoginUrl }}
            </code>
            <p class="text-xs text-n-slate-10 mt-1">
              {{ t('JABVOX_AFFILIATES.PORTAL_CARD_HINT') }}
            </p>
          </div>
        </div>
        <Button
          :label="t('JABVOX_AFFILIATES.COPY')"
          icon="i-lucide-copy"
          variant="outline"
          color="slate"
          size="sm"
          class="shrink-0"
          @click="copyToClipboard(portalLoginUrl)"
        />
      </div>

      <!-- Loading -->
      <div
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_AFFILIATES.LOADING') }}
      </div>

      <!-- Empty -->
      <EmptyStateLayout
        v-else-if="!affiliates.length"
        :title="t('JABVOX_AFFILIATES.EMPTY_TITLE')"
        :subtitle="t('JABVOX_AFFILIATES.EMPTY')"
      >
        <template #actions>
          <Button
            :label="t('JABVOX_AFFILIATES.NEW_AFFILIATE')"
            icon="i-lucide-plus"
            size="sm"
            @click="openNew"
          />
        </template>
      </EmptyStateLayout>

      <template v-else>
        <!-- Search + count -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="relative w-full sm:w-64">
            <Input
              v-model="search"
              :placeholder="t('JABVOX_AFFILIATES.SEARCH_PLACEHOLDER')"
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
            {{ t('JABVOX_AFFILIATES.COUNT', { count: affiliates.length }) }}
          </span>
        </div>

        <!-- No search results -->
        <div
          v-if="!filtered.length"
          class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_AFFILIATES.NO_RESULTS') }}
        </div>

        <template v-else>
          <!-- ===== Desktop table ===== -->
          <div
            class="hidden lg:block rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
          >
            <div class="overflow-x-auto">
              <table class="w-full text-sm border-collapse">
                <thead>
                  <tr class="bg-n-alpha-1 border-b border-n-weak">
                    <th
                      class="text-left px-4 py-3 text-[11px] font-semibold text-n-slate-10 uppercase tracking-wide"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.NAME') }}
                    </th>
                    <th
                      class="text-left px-4 py-3 text-[11px] font-semibold text-n-slate-10 uppercase tracking-wide"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.PORTAL_URL') }}
                    </th>
                    <th
                      class="text-left px-4 py-3 text-[11px] font-semibold text-n-slate-10 uppercase tracking-wide"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.ACCOUNT_CODE') }}
                    </th>
                    <th
                      class="text-left px-4 py-3 text-[11px] font-semibold text-n-slate-10 uppercase tracking-wide"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.TOKEN') }}
                    </th>
                    <th
                      class="text-center px-4 py-3 text-[11px] font-semibold text-n-slate-10 uppercase tracking-wide"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.STATUS') }}
                    </th>
                    <th
                      class="text-left px-4 py-3 text-[11px] font-semibold text-n-slate-10 uppercase tracking-wide"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.CREATED_AT') }}
                    </th>
                    <th
                      class="text-right px-4 py-3 text-[11px] font-semibold text-n-slate-10 uppercase tracking-wide"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.ACTIONS') }}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-n-weak">
                  <template v-for="affiliate in filtered" :key="affiliate.id">
                    <tr class="hover:bg-n-alpha-1 transition-colors">
                      <td class="px-4 py-3 font-medium text-n-slate-12">
                        {{ affiliate.name }}
                        <span
                          v-if="affiliate.owned"
                          class="ml-2 rounded px-1.5 py-0.5 text-[10px] font-medium bg-n-alpha-2 text-n-slate-11 align-middle"
                        >
                          {{ t('JABVOX_AFFILIATES.OWNED_BADGE') }}
                        </span>
                      </td>
                      <td class="px-4 py-3">
                        <div class="flex items-center gap-1.5">
                          <code
                            class="text-xs font-mono text-n-brand select-none truncate max-w-[200px]"
                          >
                            {{
                              isVisible(affiliate.id)
                                ? affiliate.portal_url
                                : mask(affiliate.portal_url)
                            }}
                          </code>
                          <button
                            class="text-n-slate-10 hover:text-n-brand transition-colors shrink-0"
                            :title="
                              isVisible(affiliate.id)
                                ? t('JABVOX_AFFILIATES.HIDE')
                                : t('JABVOX_AFFILIATES.SHOW')
                            "
                            @click="toggleCredential(affiliate.id)"
                          >
                            <span
                              :class="
                                isVisible(affiliate.id)
                                  ? 'i-lucide-eye-off'
                                  : 'i-lucide-eye'
                              "
                              class="size-3.5"
                            />
                          </button>
                          <button
                            class="text-n-slate-10 hover:text-n-brand transition-colors shrink-0"
                            :title="t('JABVOX_AFFILIATES.COPY')"
                            @click="copyToClipboard(affiliate.portal_url)"
                          >
                            <span class="i-lucide-copy size-3.5" />
                          </button>
                        </div>
                      </td>
                      <td class="px-4 py-3">
                        <div class="flex items-center gap-1.5">
                          <code
                            class="text-xs font-mono text-n-slate-11 select-none"
                          >
                            {{
                              isVisible(affiliate.id)
                                ? affiliate.account_code
                                : maskCode(affiliate.account_code)
                            }}
                          </code>
                          <button
                            class="text-n-slate-10 hover:text-n-brand transition-colors"
                            :title="
                              isVisible(affiliate.id)
                                ? t('JABVOX_AFFILIATES.HIDE')
                                : t('JABVOX_AFFILIATES.SHOW')
                            "
                            @click="toggleCredential(affiliate.id)"
                          >
                            <span
                              :class="
                                isVisible(affiliate.id)
                                  ? 'i-lucide-eye-off'
                                  : 'i-lucide-eye'
                              "
                              class="size-3.5"
                            />
                          </button>
                          <button
                            class="text-n-slate-10 hover:text-n-brand transition-colors"
                            :title="t('JABVOX_AFFILIATES.COPY')"
                            @click="copyToClipboard(affiliate.account_code)"
                          >
                            <span class="i-lucide-copy size-3.5" />
                          </button>
                          <button
                            class="text-n-slate-10 hover:text-n-brand transition-colors"
                            :title="t('JABVOX_AFFILIATES.REGENERATE_CODE')"
                            @click="askRegenerateCode(affiliate)"
                          >
                            <span class="i-lucide-refresh-cw size-3.5" />
                          </button>
                        </div>
                      </td>
                      <td class="px-4 py-3">
                        <div class="flex items-center gap-1.5">
                          <code
                            class="text-xs font-mono text-n-slate-11 select-none"
                          >
                            {{
                              isVisible(affiliate.id)
                                ? affiliate.auth_token
                                : mask(affiliate.auth_token)
                            }}
                          </code>
                          <button
                            class="text-n-slate-10 hover:text-n-brand transition-colors"
                            :title="
                              isVisible(affiliate.id)
                                ? t('JABVOX_AFFILIATES.HIDE')
                                : t('JABVOX_AFFILIATES.SHOW')
                            "
                            @click="toggleCredential(affiliate.id)"
                          >
                            <span
                              :class="
                                isVisible(affiliate.id)
                                  ? 'i-lucide-eye-off'
                                  : 'i-lucide-eye'
                              "
                              class="size-3.5"
                            />
                          </button>
                          <button
                            class="text-n-slate-10 hover:text-n-brand transition-colors"
                            :title="t('JABVOX_AFFILIATES.COPY')"
                            @click="copyToClipboard(affiliate.auth_token)"
                          >
                            <span class="i-lucide-copy size-3.5" />
                          </button>
                          <button
                            class="text-n-slate-10 hover:text-n-brand transition-colors"
                            :title="t('JABVOX_AFFILIATES.REGENERATE_TOKEN')"
                            @click="askRegenerateToken(affiliate)"
                          >
                            <span class="i-lucide-refresh-cw size-3.5" />
                          </button>
                        </div>
                      </td>
                      <td class="px-4 py-3">
                        <div class="flex justify-center">
                          <Switch
                            :model-value="affiliate.active"
                            @update:model-value="onToggleActive(affiliate)"
                          />
                        </div>
                      </td>
                      <td
                        class="px-4 py-3 text-n-slate-11 text-xs whitespace-nowrap"
                      >
                        {{ formatDate(affiliate.created_at) }}
                      </td>
                      <td class="px-4 py-3">
                        <div class="flex items-center justify-end gap-1">
                          <Button
                            icon="i-lucide-shield"
                            :variant="
                              expandedIpAffiliate === affiliate.id
                                ? 'solid'
                                : 'ghost'
                            "
                            :color="
                              expandedIpAffiliate === affiliate.id
                                ? 'blue'
                                : 'slate'
                            "
                            size="sm"
                            :title="t('JABVOX_AFFILIATES.IP.MANAGE')"
                            @click="toggleIpPanel(affiliate)"
                          />
                          <!-- El afiliado propio de la cuenta no se elimina:
                               representa los leads sin afiliado externo. -->
                          <Button
                            v-if="!affiliate.owned"
                            icon="i-lucide-trash-2"
                            variant="ghost"
                            color="ruby"
                            size="sm"
                            :title="t('JABVOX_AFFILIATES.DELETE')"
                            @click="askDeleteAffiliate(affiliate)"
                          />
                        </div>
                      </td>
                    </tr>
                    <tr v-if="expandedIpAffiliate === affiliate.id">
                      <td
                        colspan="7"
                        class="bg-n-alpha-1 border-t border-n-weak"
                      >
                        <div class="px-6 py-5">
                          <IpWhitelistPanel
                            :affiliate="affiliate"
                            @request-delete="onRequestDeleteIp"
                          />
                        </div>
                      </td>
                    </tr>
                  </template>
                </tbody>
              </table>
            </div>
          </div>

          <!-- ===== Mobile / tablet cards ===== -->
          <div class="flex flex-col gap-3 lg:hidden">
            <div
              v-for="affiliate in filtered"
              :key="affiliate.id"
              class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
            >
              <div class="p-4 flex flex-col gap-3">
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0">
                    <p class="text-sm font-semibold text-n-slate-12 truncate">
                      {{ affiliate.name }}
                      <span
                        v-if="affiliate.owned"
                        class="ml-1 rounded px-1.5 py-0.5 text-[10px] font-medium bg-n-alpha-2 text-n-slate-11"
                      >
                        {{ t('JABVOX_AFFILIATES.OWNED_BADGE') }}
                      </span>
                    </p>
                    <p class="text-xs text-n-slate-10 mt-0.5">
                      {{ formatDate(affiliate.created_at) }}
                    </p>
                  </div>
                  <Switch
                    :model-value="affiliate.active"
                    @update:model-value="onToggleActive(affiliate)"
                  />
                </div>

                <!-- Credentials -->
                <div class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-3">
                  <div class="flex items-center justify-between gap-2">
                    <span
                      class="text-[11px] font-medium uppercase tracking-wide text-n-slate-10"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.PORTAL_URL') }}
                    </span>
                    <div class="flex items-center gap-1.5 min-w-0">
                      <code class="text-xs font-mono text-n-brand truncate">
                        {{
                          isVisible(affiliate.id)
                            ? affiliate.portal_url
                            : mask(affiliate.portal_url)
                        }}
                      </code>
                      <button
                        class="text-n-slate-10 hover:text-n-brand shrink-0"
                        :title="
                          isVisible(affiliate.id)
                            ? t('JABVOX_AFFILIATES.HIDE')
                            : t('JABVOX_AFFILIATES.SHOW')
                        "
                        @click="toggleCredential(affiliate.id)"
                      >
                        <span
                          :class="
                            isVisible(affiliate.id)
                              ? 'i-lucide-eye-off'
                              : 'i-lucide-eye'
                          "
                          class="size-3.5"
                        />
                      </button>
                      <button
                        class="text-n-slate-10 hover:text-n-brand shrink-0"
                        :title="t('JABVOX_AFFILIATES.COPY')"
                        @click="copyToClipboard(affiliate.portal_url)"
                      >
                        <span class="i-lucide-copy size-3.5" />
                      </button>
                    </div>
                  </div>
                  <div class="flex items-center justify-between gap-2">
                    <span
                      class="text-[11px] font-medium uppercase tracking-wide text-n-slate-10"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.ACCOUNT_CODE') }}
                    </span>
                    <div class="flex items-center gap-1.5 min-w-0">
                      <code class="text-xs font-mono text-n-slate-11 truncate">
                        {{
                          isVisible(affiliate.id)
                            ? affiliate.account_code
                            : maskCode(affiliate.account_code)
                        }}
                      </code>
                      <button
                        class="text-n-slate-10 hover:text-n-brand shrink-0"
                        :title="
                          isVisible(affiliate.id)
                            ? t('JABVOX_AFFILIATES.HIDE')
                            : t('JABVOX_AFFILIATES.SHOW')
                        "
                        @click="toggleCredential(affiliate.id)"
                      >
                        <span
                          :class="
                            isVisible(affiliate.id)
                              ? 'i-lucide-eye-off'
                              : 'i-lucide-eye'
                          "
                          class="size-3.5"
                        />
                      </button>
                      <button
                        class="text-n-slate-10 hover:text-n-brand shrink-0"
                        :title="t('JABVOX_AFFILIATES.COPY')"
                        @click="copyToClipboard(affiliate.account_code)"
                      >
                        <span class="i-lucide-copy size-3.5" />
                      </button>
                      <button
                        class="text-n-slate-10 hover:text-n-brand shrink-0"
                        :title="t('JABVOX_AFFILIATES.REGENERATE_CODE')"
                        @click="askRegenerateCode(affiliate)"
                      >
                        <span class="i-lucide-refresh-cw size-3.5" />
                      </button>
                    </div>
                  </div>
                  <div class="flex items-center justify-between gap-2">
                    <span
                      class="text-[11px] font-medium uppercase tracking-wide text-n-slate-10"
                    >
                      {{ t('JABVOX_AFFILIATES.TABLE.TOKEN') }}
                    </span>
                    <div class="flex items-center gap-1.5 min-w-0">
                      <code class="text-xs font-mono text-n-slate-11 truncate">
                        {{
                          isVisible(affiliate.id)
                            ? affiliate.auth_token
                            : mask(affiliate.auth_token)
                        }}
                      </code>
                      <button
                        class="text-n-slate-10 hover:text-n-brand shrink-0"
                        :title="
                          isVisible(affiliate.id)
                            ? t('JABVOX_AFFILIATES.HIDE')
                            : t('JABVOX_AFFILIATES.SHOW')
                        "
                        @click="toggleCredential(affiliate.id)"
                      >
                        <span
                          :class="
                            isVisible(affiliate.id)
                              ? 'i-lucide-eye-off'
                              : 'i-lucide-eye'
                          "
                          class="size-3.5"
                        />
                      </button>
                      <button
                        class="text-n-slate-10 hover:text-n-brand shrink-0"
                        :title="t('JABVOX_AFFILIATES.COPY')"
                        @click="copyToClipboard(affiliate.auth_token)"
                      >
                        <span class="i-lucide-copy size-3.5" />
                      </button>
                    </div>
                  </div>
                </div>

                <!-- Actions -->
                <div class="flex items-center gap-2">
                  <Button
                    :label="t('JABVOX_AFFILIATES.IP.MANAGE')"
                    icon="i-lucide-shield"
                    :variant="
                      expandedIpAffiliate === affiliate.id ? 'solid' : 'outline'
                    "
                    :color="
                      expandedIpAffiliate === affiliate.id ? 'blue' : 'slate'
                    "
                    size="sm"
                    @click="toggleIpPanel(affiliate)"
                  />
                  <Button
                    icon="i-lucide-refresh-cw"
                    :label="t('JABVOX_AFFILIATES.REGENERATE_TOKEN')"
                    variant="ghost"
                    color="slate"
                    size="sm"
                    @click="askRegenerateToken(affiliate)"
                  />
                  <div class="flex-1" />
                  <!-- El afiliado propio no se elimina (ver tabla de escritorio). -->
                  <Button
                    v-if="!affiliate.owned"
                    icon="i-lucide-trash-2"
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    @click="askDeleteAffiliate(affiliate)"
                  />
                </div>
              </div>

              <!-- IP panel -->
              <div
                v-if="expandedIpAffiliate === affiliate.id"
                class="border-t border-n-weak bg-n-alpha-1 p-4"
              >
                <IpWhitelistPanel
                  :affiliate="affiliate"
                  @request-delete="onRequestDeleteIp"
                />
              </div>
            </div>
          </div>
        </template>
      </template>
    </div>

    <!-- Dialogs -->
    <AffiliateFormDialog
      ref="formDialog"
      :is-saving="uiFlags.isSaving"
      @submit="onSubmitCreate"
    />
    <ConfirmDeleteDialog
      ref="deleteAffiliateDialog"
      @confirm="doDeleteAffiliate"
    />
    <ConfirmDeleteDialog ref="deleteIpDialog" @confirm="doDeleteIp" />
    <ConfirmDialog ref="regenerateDialog" @confirm="doRegenerate" />
  </div>
</template>
