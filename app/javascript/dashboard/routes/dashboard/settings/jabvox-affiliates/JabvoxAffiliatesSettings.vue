<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import affiliatesAPI from 'dashboard/api/jabvox/affiliates';

const store = useStore();
const { t } = useI18n();

const affiliates = useMapGetter('jabvoxAffiliates/getAffiliates');
const portalLoginUrl = useMapGetter('jabvoxAffiliates/getPortalLoginUrl');
const uiFlags = useMapGetter('jabvoxAffiliates/getUIFlags');

const showForm = ref(false);
const formName = ref('');
const createdAffiliate = ref(null);
const confirmDeleteId = ref(null);
const visibleCredentials = ref(new Set());
const showPortalUrl = ref(false);

const toggleCredential = id => {
  const next = new Set(visibleCredentials.value);
  if (next.has(id)) {
    next.delete(id);
  } else {
    next.add(id);
  }
  visibleCredentials.value = next;
};

const isVisible = id => visibleCredentials.value.has(id);
const mask = val => (val ? '••••••••••••' : '');
const maskCode = val => (val ? val.slice(0, 4) + '••••••••' : '');

onMounted(() => {
  store.dispatch('jabvoxAffiliates/fetchAffiliates');
  store.dispatch('jabvoxAffiliates/fetchPortalLoginUrl');
});

const openNew = () => {
  formName.value = '';
  createdAffiliate.value = null;
  showForm.value = true;
};

const cancelForm = () => {
  showForm.value = false;
  formName.value = '';
  createdAffiliate.value = null;
};

const onSubmit = async () => {
  if (!formName.value.trim()) return;
  try {
    const result = await store.dispatch('jabvoxAffiliates/createAffiliate', {
      name: formName.value.trim(),
    });
    createdAffiliate.value = result;
    formName.value = '';
    useAlert(t('JABVOX_AFFILIATES.CREATED'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.ERROR'));
  }
};

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

const onRegenerateToken = async affiliate => {
  try {
    await store.dispatch('jabvoxAffiliates/regenerateToken', affiliate.id);
    useAlert(t('JABVOX_AFFILIATES.TOKEN_REGENERATED'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.ERROR'));
  }
};

const onRegenerateCode = async affiliate => {
  try {
    await store.dispatch('jabvoxAffiliates/regenerateCode', affiliate.id);
    useAlert(t('JABVOX_AFFILIATES.CODE_REGENERATED'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.ERROR'));
  }
};

const onDelete = async id => {
  try {
    await store.dispatch('jabvoxAffiliates/deleteAffiliate', id);
    confirmDeleteId.value = null;
    useAlert(t('JABVOX_AFFILIATES.DELETED'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.ERROR'));
  }
};

const copyToClipboard = async text => {
  await navigator.clipboard.writeText(text);
  useAlert(t('JABVOX_AFFILIATES.COPIED'));
};

const createdCode = computed(() => createdAffiliate.value?.account_code ?? '');
const createdToken = computed(() => createdAffiliate.value?.auth_token ?? '');

// --- IP whitelist per affiliate ---
const expandedIpAffiliate = ref(null);
const ipLists = ref({});
const ipLoadingId = ref(null);
const ipForm = ref({ ip: '', comment: '' });
const ipAdding = ref(false);
const ipError = ref('');

const toggleIpPanel = async affiliate => {
  if (expandedIpAffiliate.value === affiliate.id) {
    expandedIpAffiliate.value = null;
    return;
  }
  expandedIpAffiliate.value = affiliate.id;
  if (!ipLists.value[affiliate.id]) {
    ipLoadingId.value = affiliate.id;
    try {
      const { data } = await affiliatesAPI.getIpWhitelist(affiliate.id);
      ipLists.value = { ...ipLists.value, [affiliate.id]: data };
    } finally {
      ipLoadingId.value = null;
    }
  }
  ipForm.value = { ip: '', comment: '' };
  ipError.value = '';
};

const IPV4_RE = /^(\d{1,3}\.){3}\d{1,3}$/;

const onAddIp = async affiliateId => {
  const ip = ipForm.value.ip.trim();
  if (!IPV4_RE.test(ip)) {
    ipError.value = t('JABVOX_AFFILIATES.IP.INVALID');
    return;
  }
  ipError.value = '';
  ipAdding.value = true;
  try {
    const { data } = await affiliatesAPI.addIp(affiliateId, {
      ip,
      comment: ipForm.value.comment.trim() || null,
      is_active: true,
    });
    ipLists.value = {
      ...ipLists.value,
      [affiliateId]: [...(ipLists.value[affiliateId] ?? []), data],
    };
    ipForm.value = { ip: '', comment: '' };
    useAlert(t('JABVOX_AFFILIATES.IP.CREATE_SUCCESS'));
  } catch {
    ipError.value = t('JABVOX_AFFILIATES.IP.ERROR');
  } finally {
    ipAdding.value = false;
  }
};

const onToggleIp = async (affiliateId, entry) => {
  try {
    const { data } = await affiliatesAPI.updateIp(affiliateId, entry.id, {
      is_active: !entry.is_active,
    });
    ipLists.value = {
      ...ipLists.value,
      [affiliateId]: ipLists.value[affiliateId].map(e =>
        e.id === entry.id ? data : e
      ),
    };
  } catch {
    useAlert(t('JABVOX_AFFILIATES.IP.ERROR'));
  }
};

const onDeleteIp = async (affiliateId, entry) => {
  if (!window.confirm(t('JABVOX_AFFILIATES.IP.CONFIRM_DELETE'))) return;
  try {
    await affiliatesAPI.destroyIp(affiliateId, entry.id);
    ipLists.value = {
      ...ipLists.value,
      [affiliateId]: ipLists.value[affiliateId].filter(e => e.id !== entry.id),
    };
    useAlert(t('JABVOX_AFFILIATES.IP.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.IP.ERROR'));
  }
};
</script>

<template>
  <div class="flex-1 overflow-auto p-6 sm:p-8">
    <!-- Header -->
    <div class="mb-6">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('JABVOX_AFFILIATES.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11 mt-1">
        {{ t('JABVOX_AFFILIATES.DESCRIPTION') }}
      </p>
    </div>

    <!-- New Affiliate Button -->
    <div class="mb-4 flex justify-end">
      <Button
        :label="t('JABVOX_AFFILIATES.NEW_AFFILIATE')"
        icon="i-lucide-plus"
        color="blue"
        @click="openNew"
      />
    </div>

    <!-- Create Form -->
    <div
      v-if="showForm"
      class="mb-6 rounded-xl border border-n-weak bg-n-surface-2 p-5"
    >
      <h2 class="text-base font-semibold text-n-slate-12 mb-1">
        {{ t('JABVOX_AFFILIATES.FORM.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11 mb-4">
        {{ t('JABVOX_AFFILIATES.FORM.SUBTITLE') }}
      </p>

      <!-- After creation: show generated credentials -->
      <template v-if="createdAffiliate">
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1">
              {{ t('JABVOX_AFFILIATES.FORM.ACCOUNT_CODE') }}
            </label>
            <div class="flex items-center gap-2">
              <code
                class="flex-1 rounded-lg bg-n-alpha-black2 px-3 py-2 text-sm font-mono text-n-slate-12"
              >
                {{ createdCode }}
              </code>
              <Button
                variant="ghost"
                size="sm"
                icon="i-lucide-copy"
                @click="copyToClipboard(createdCode)"
              />
            </div>
          </div>
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1">
              {{ t('JABVOX_AFFILIATES.FORM.TOKEN') }}
            </label>
            <div class="flex items-center gap-2">
              <code
                class="flex-1 rounded-lg bg-n-alpha-black2 px-3 py-2 text-sm font-mono text-n-slate-12"
              >
                {{ createdToken }}
              </code>
              <Button
                variant="ghost"
                size="sm"
                icon="i-lucide-copy"
                @click="copyToClipboard(createdToken)"
              />
            </div>
          </div>
        </div>
        <div class="mt-4 flex justify-end">
          <Button
            :label="t('JABVOX_AFFILIATES.FORM.DONE')"
            color="blue"
            @click="cancelForm"
          />
        </div>
      </template>

      <!-- Name input before creation -->
      <template v-else>
        <div class="mb-4">
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ t('JABVOX_AFFILIATES.FORM.NAME_LABEL') }}
            <span class="text-n-ruby-9">*</span>
          </label>
          <input
            v-model="formName"
            type="text"
            :placeholder="t('JABVOX_AFFILIATES.FORM.NAME_PLACEHOLDER')"
            class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @keydown.enter="onSubmit"
          />
        </div>
        <div class="flex items-center gap-3">
          <Button
            :label="t('JABVOX_AFFILIATES.FORM.CANCEL')"
            variant="link"
            @click="cancelForm"
          />
          <Button
            :label="t('JABVOX_AFFILIATES.FORM.SUBMIT')"
            color="blue"
            :disabled="!formName.trim()"
            :is-loading="uiFlags.isSaving"
            @click="onSubmit"
          />
        </div>
      </template>
    </div>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetching"
      class="py-16 text-center text-sm text-n-slate-10 animate-pulse"
    >
      {{ t('JABVOX_AFFILIATES.LOADING') }}
    </div>

    <!-- Empty -->
    <div
      v-else-if="!affiliates.length && !showForm"
      class="py-16 text-center text-sm text-n-slate-10"
    >
      {{ t('JABVOX_AFFILIATES.EMPTY') }}
    </div>

    <!-- Affiliates Table -->
    <div
      v-else-if="affiliates.length"
      class="rounded-2xl border border-n-weak bg-n-surface-1 overflow-hidden overflow-x-auto"
    >
      <table class="w-full text-sm border-collapse min-w-[900px]">
        <thead>
          <tr class="bg-n-surface-2 border-b border-n-weak">
            <th
              class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
            >
              {{ t('JABVOX_AFFILIATES.TABLE.NAME') }}
            </th>
            <th
              class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
            >
              {{ t('JABVOX_AFFILIATES.TABLE.PORTAL_URL') }}
            </th>
            <th
              class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
            >
              {{ t('JABVOX_AFFILIATES.TABLE.ACCOUNT_CODE') }}
            </th>
            <th
              class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
            >
              {{ t('JABVOX_AFFILIATES.TABLE.TOKEN') }}
            </th>
            <th
              class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
            >
              {{ t('JABVOX_AFFILIATES.TABLE.STATUS') }}
            </th>
            <th
              class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
            >
              {{ t('JABVOX_AFFILIATES.TABLE.CREATED_AT') }}
            </th>
            <th
              class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
            >
              {{ t('JABVOX_AFFILIATES.TABLE.ACTIONS') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <template v-for="affiliate in affiliates" :key="affiliate.id">
            <tr class="hover:bg-n-surface-2/50 transition-colors">
              <td class="px-4 py-3 font-medium text-n-slate-12">
                {{ affiliate.name }}
              </td>
              <td class="px-4 py-3">
                <div class="flex items-center gap-1.5">
                  <code
                    class="text-xs font-mono text-n-brand select-none truncate max-w-[180px]"
                  >
                    {{
                      isVisible(affiliate.id)
                        ? affiliate.portal_url
                        : mask(affiliate.portal_url)
                    }}
                  </code>
                  <button
                    class="text-n-slate-10 hover:text-n-brand transition-colors shrink-0"
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
                    @click="copyToClipboard(affiliate.portal_url)"
                  >
                    <span class="i-lucide-copy size-3.5" />
                  </button>
                </div>
              </td>
              <td class="px-4 py-3">
                <div class="flex items-center gap-1.5">
                  <code class="text-xs font-mono text-n-slate-11 select-none">
                    {{
                      isVisible(affiliate.id)
                        ? affiliate.account_code
                        : maskCode(affiliate.account_code)
                    }}
                  </code>
                  <button
                    class="text-n-slate-10 hover:text-n-brand transition-colors"
                    :title="isVisible(affiliate.id) ? 'Ocultar' : 'Ver'"
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
                    @click="copyToClipboard(affiliate.account_code)"
                  >
                    <span class="i-lucide-copy size-3.5" />
                  </button>
                  <button
                    class="text-n-slate-10 hover:text-n-brand transition-colors"
                    :title="t('JABVOX_AFFILIATES.REGENERATE_CODE')"
                    @click="onRegenerateCode(affiliate)"
                  >
                    <span class="i-lucide-refresh-cw size-3.5" />
                  </button>
                </div>
              </td>
              <td class="px-4 py-3">
                <div class="flex items-center gap-1.5">
                  <code class="text-xs font-mono text-n-slate-11 select-none">
                    {{
                      isVisible(affiliate.id)
                        ? affiliate.auth_token
                        : mask(affiliate.auth_token)
                    }}
                  </code>
                  <button
                    class="text-n-slate-10 hover:text-n-brand transition-colors"
                    :title="isVisible(affiliate.id) ? 'Ocultar' : 'Ver'"
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
                    @click="copyToClipboard(affiliate.auth_token)"
                  >
                    <span class="i-lucide-copy size-3.5" />
                  </button>
                  <button
                    class="text-n-slate-10 hover:text-n-brand transition-colors"
                    :title="t('JABVOX_AFFILIATES.REGENERATE_TOKEN')"
                    @click="onRegenerateToken(affiliate)"
                  >
                    <span class="i-lucide-refresh-cw size-3.5" />
                  </button>
                </div>
              </td>
              <td class="px-4 py-3">
                <button
                  class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors"
                  :class="
                    affiliate.active
                      ? 'bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4'
                      : 'bg-n-alpha-black2 text-n-slate-10 hover:bg-n-alpha-black3'
                  "
                  @click="onToggleActive(affiliate)"
                >
                  {{
                    affiliate.active
                      ? t('JABVOX_AFFILIATES.TABLE.ACTIVE')
                      : t('JABVOX_AFFILIATES.TABLE.INACTIVE')
                  }}
                </button>
              </td>
              <td class="px-4 py-3 text-n-slate-11 text-xs">
                {{ new Date(affiliate.created_at).toLocaleDateString('es') }}
              </td>
              <td class="px-4 py-3">
                <template v-if="confirmDeleteId === affiliate.id">
                  <div class="flex items-center gap-2">
                    <span class="text-xs text-n-ruby-9">{{
                      t('JABVOX_AFFILIATES.CONFIRM_DELETE')
                    }}</span>
                    <button
                      class="text-xs text-n-ruby-9 hover:underline"
                      @click="onDelete(affiliate.id)"
                    >
                      {{ t('JABVOX_AFFILIATES.YES') }}
                    </button>
                    <button
                      class="text-xs text-n-slate-10 hover:underline"
                      @click="confirmDeleteId = null"
                    >
                      {{ t('JABVOX_AFFILIATES.NO') }}
                    </button>
                  </div>
                </template>
                <template v-else>
                  <div class="flex items-center gap-2">
                    <button
                      class="transition-colors"
                      :class="
                        expandedIpAffiliate === affiliate.id
                          ? 'text-n-brand'
                          : 'text-n-slate-10 hover:text-n-brand'
                      "
                      :title="t('JABVOX_AFFILIATES.IP.BUTTON')"
                      @click="toggleIpPanel(affiliate)"
                    >
                      <span class="i-lucide-shield size-4" />
                    </button>
                    <button
                      class="text-n-ruby-9 hover:text-n-ruby-11 transition-colors"
                      @click="confirmDeleteId = affiliate.id"
                    >
                      <span class="i-lucide-trash-2 size-4" />
                    </button>
                  </div>
                </template>
              </td>
            </tr>

            <!-- IP whitelist panel -->
            <tr v-if="expandedIpAffiliate === affiliate.id">
              <td colspan="7" class="bg-n-surface-2/40 border-b border-n-weak">
                <div class="px-6 py-5 max-w-2xl">
                  <!-- Header -->
                  <div class="flex items-start gap-3 mb-4">
                    <span
                      class="i-lucide-shield-check size-4 text-n-brand mt-0.5 shrink-0"
                    />
                    <div>
                      <p class="text-sm font-semibold text-n-slate-12">
                        {{
                          t('JABVOX_AFFILIATES.IP.TITLE', {
                            name: affiliate.name,
                          })
                        }}
                      </p>
                      <p class="text-xs text-n-slate-10 mt-0.5">
                        {{ t('JABVOX_AFFILIATES.IP.HINT') }}
                      </p>
                    </div>
                  </div>

                  <div
                    v-if="ipLoadingId === affiliate.id"
                    class="text-xs text-n-slate-10 animate-pulse py-2"
                  >
                    {{ t('JABVOX_AFFILIATES.LOADING') }}
                  </div>

                  <template v-else>
                    <!-- IP list -->
                    <div
                      v-if="(ipLists[affiliate.id] ?? []).length"
                      class="mb-4 rounded-xl border border-n-weak overflow-hidden"
                    >
                      <div
                        v-for="entry in ipLists[affiliate.id]"
                        :key="entry.id"
                        class="flex items-center gap-3 px-4 py-2.5 bg-n-surface-1 text-xs border-b border-n-weak last:border-0"
                      >
                        <code
                          class="font-mono text-sm text-n-slate-12 w-32 shrink-0"
                        >
                          {{ entry.ip }}
                        </code>
                        <span class="text-n-slate-10 flex-1 truncate italic">
                          {{ entry.comment || '—' }}
                        </span>
                        <button
                          class="rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors shrink-0"
                          :class="
                            entry.is_active
                              ? 'bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4'
                              : 'bg-n-alpha-black2 text-n-slate-10 hover:bg-n-alpha-black3'
                          "
                          @click="onToggleIp(affiliate.id, entry)"
                        >
                          {{
                            entry.is_active
                              ? t('JABVOX_AFFILIATES.TABLE.ACTIVE')
                              : t('JABVOX_AFFILIATES.TABLE.INACTIVE')
                          }}
                        </button>
                        <button
                          class="text-n-slate-10 hover:text-n-ruby-9 transition-colors shrink-0"
                          @click="onDeleteIp(affiliate.id, entry)"
                        >
                          <span class="i-lucide-trash-2 size-3.5" />
                        </button>
                      </div>
                    </div>

                    <div
                      v-else
                      class="mb-4 flex items-center gap-2 rounded-xl border border-n-weak bg-n-ruby-3/50 px-4 py-3"
                    >
                      <span
                        class="i-lucide-shield-off size-3.5 text-n-ruby-9 shrink-0"
                      />
                      <p class="text-xs text-n-ruby-9">
                        {{ t('JABVOX_AFFILIATES.IP.EMPTY') }}
                      </p>
                    </div>

                    <!-- Add IP form -->
                    <div
                      class="rounded-xl border border-n-weak bg-n-surface-1 p-4"
                    >
                      <p class="text-xs font-medium text-n-slate-11 mb-3">
                        {{ t('JABVOX_AFFILIATES.IP.ADD') }}
                      </p>
                      <div class="flex items-center gap-2">
                        <div class="flex flex-col gap-1 w-40 shrink-0">
                          <input
                            v-model="ipForm.ip"
                            type="text"
                            :placeholder="
                              t('JABVOX_AFFILIATES.IP.ADD_PLACEHOLDER')
                            "
                            class="h-9 rounded-lg border border-n-weak bg-n-surface-2 px-3 text-xs text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-brand"
                            @keydown.enter="onAddIp(affiliate.id)"
                          />
                        </div>
                        <div class="flex flex-col gap-1 flex-1">
                          <input
                            v-model="ipForm.comment"
                            type="text"
                            :placeholder="
                              t('JABVOX_AFFILIATES.IP.COMMENT_PLACEHOLDER')
                            "
                            class="h-9 rounded-lg border border-n-weak bg-n-surface-2 px-3 text-xs text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-brand"
                            @keydown.enter="onAddIp(affiliate.id)"
                          />
                        </div>
                        <button
                          :disabled="ipAdding"
                          class="h-9 px-4 rounded-lg bg-n-brand text-white text-xs font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors shrink-0"
                          @click="onAddIp(affiliate.id)"
                        >
                          {{
                            ipAdding
                              ? t('JABVOX_AFFILIATES.IP.ADDING')
                              : t('JABVOX_AFFILIATES.IP.ADD')
                          }}
                        </button>
                      </div>
                      <p
                        v-if="ipError"
                        class="mt-2 text-xs text-n-ruby-9 flex items-center gap-1"
                      >
                        <span class="i-lucide-alert-circle size-3" />
                        {{ ipError }}
                      </p>
                    </div>
                  </template>
                </div>
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </div>
  </div>
</template>
