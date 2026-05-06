<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import userExtensionAPI from 'dashboard/api/jabvox/userExtension';
import agentsAPI from 'dashboard/api/agents';

const store = useStore();
const { t } = useI18n();

const config = useMapGetter('jabvoxVoip/getConfig');
const status = useMapGetter('jabvoxVoip/getStatus');
const uiFlags = useMapGetter('jabvoxVoip/getUIFlags');
const currentUserRole = useMapGetter('getCurrentRole');

const isAdmin = computed(() => currentUserRole.value === 'administrator');
const isConnected = computed(() => status.value?.connected === true);

const buildForm = cfg => ({
  host: cfg?.host || '',
  port: cfg?.port || 5038,
  username: cfg?.username || '',
  password: '',
  context: cfg?.context || 'clicktocall',
  dialer_context: cfg?.dialer_context || '',
  dialer_trunk: cfg?.dialer_trunk || '',
});

const form = ref(buildForm(config.value?.id ? config.value : null));

const isNew = computed(() => !config.value?.id);

const extensions = ref([]);
const agents = ref([]);
const newExtUserId = ref('');
const newExtValue = ref('');
const extSaving = ref(false);

const usedUserIds = computed(() => extensions.value.map(e => e.user_id));
const availableAgents = computed(() =>
  agents.value.filter(a => !usedUserIds.value.includes(a.id))
);

const loadExtensions = async () => {
  try {
    const { data } = await userExtensionAPI.getAll();
    extensions.value = data;
  } catch {
    // non-admin, skip
  }
};

onMounted(async () => {
  if (!config.value?.id) {
    await store.dispatch('jabvoxVoip/fetchConfig');
    if (config.value?.id) form.value = buildForm(config.value);
  }
  store.dispatch('jabvoxVoip/fetchStatus');
  if (isAdmin.value) {
    loadExtensions();
    const { data } = await agentsAPI.get();
    agents.value = data;
  }
});

const onSave = async () => {
  try {
    await store.dispatch('jabvoxVoip/updateConfig', { ...form.value });
    form.value.password = '';
    useAlert(t('JABVOX_VOIP.SAVE_SUCCESS'));
    store.dispatch('jabvoxVoip/fetchStatus');
  } catch {
    useAlert(t('JABVOX_VOIP.ERROR'));
  }
};

const onRefreshStatus = () => store.dispatch('jabvoxVoip/fetchStatus');

const onAddExtension = async () => {
  if (!newExtUserId.value || !newExtValue.value.trim()) return;
  extSaving.value = true;
  try {
    const { data } = await userExtensionAPI.create(
      newExtUserId.value,
      newExtValue.value.trim()
    );
    extensions.value.push(data);
    newExtUserId.value = '';
    newExtValue.value = '';
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_VOIP.ERROR'));
  } finally {
    extSaving.value = false;
  }
};

const onRemoveExtension = async ext => {
  try {
    await userExtensionAPI.destroy(ext.id);
    extensions.value = extensions.value.filter(e => e.id !== ext.id);
  } catch {
    useAlert(t('JABVOX_VOIP.ERROR'));
  }
};
</script>

<template>
  <SettingsLayout>
    <BaseSettingsHeader
      :title="$t('JABVOX_VOIP.TITLE')"
      :description="$t('JABVOX_VOIP.DESCRIPTION')"
    />

    <div class="mt-6 max-w-3xl mx-auto space-y-6">
      <!-- Connection status banner -->
      <div
        class="rounded-2xl border p-4 flex items-center justify-between gap-4"
        :class="
          status === null
            ? 'bg-slate-50 dark:bg-slate-800 border-slate-200 dark:border-slate-700'
            : isConnected
              ? 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
              : 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
        "
      >
        <div class="flex items-center gap-3">
          <span
            class="w-3 h-3 rounded-full flex-shrink-0"
            :class="
              status === null
                ? 'bg-slate-300'
                : isConnected
                  ? 'bg-green-500'
                  : 'bg-red-500'
            "
          />
          <div>
            <p
              class="text-sm font-semibold"
              :class="
                status === null
                  ? 'text-slate-500'
                  : isConnected
                    ? 'text-green-700 dark:text-green-400'
                    : 'text-red-600 dark:text-red-400'
              "
            >
              {{
                status === null
                  ? $t('JABVOX_VOIP.STATUS.LOADING')
                  : isConnected
                    ? $t('JABVOX_VOIP.STATUS.CONNECTED')
                    : $t('JABVOX_VOIP.STATUS.DISCONNECTED')
              }}
            </p>
            <p
              v-if="status?.message"
              class="text-xs text-slate-500 dark:text-slate-400 mt-0.5"
            >
              {{ status.message }}
            </p>
          </div>
        </div>
        <Button
          variant="clear"
          size="small"
          :icon="
            uiFlags.isCheckingStatus
              ? 'i-lucide-loader-circle'
              : 'i-lucide-refresh-cw'
          "
          :class="{ 'animate-spin': uiFlags.isCheckingStatus }"
          :label="$t('JABVOX_VOIP.STATUS.REFRESH')"
          :disabled="uiFlags.isCheckingStatus"
          @click="onRefreshStatus"
        />
      </div>

      <!-- Config card -->
      <div
        class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 p-6 space-y-5"
      >
        <h3 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
          {{ $t('JABVOX_VOIP.FORM.TITLE') }}
        </h3>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div class="sm:col-span-2 space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.FORM.HOST') }} *
            </label>
            <input
              v-model="form.host"
              type="text"
              :placeholder="$t('JABVOX_VOIP.FORM.HOST_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.FORM.PORT') }} *
            </label>
            <input
              v-model.number="form.port"
              type="number"
              min="1"
              max="65535"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.FORM.USERNAME') }} *
            </label>
            <input
              v-model="form.username"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.FORM.PASSWORD') }}
              <span v-if="!isNew" class="font-normal text-slate-400">
                {{ $t('JABVOX_VOIP.FORM.PASSWORD_HINT') }}
              </span>
            </label>
            <input
              v-model="form.password"
              type="password"
              autocomplete="new-password"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.FORM.CONTEXT') }} *
            </label>
            <input
              v-model="form.context"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
            <p class="text-xs text-slate-400">
              {{ $t('JABVOX_VOIP.FORM.CONTEXT_HELP') }}
            </p>
          </div>
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.FORM.DIALER_CONTEXT') }}
            </label>
            <input
              v-model="form.dialer_context"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
            <p class="text-xs text-slate-400">
              {{ $t('JABVOX_VOIP.FORM.DIALER_CONTEXT_HELP') }}
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.FORM.DIALER_TRUNK') }}
            </label>
            <input
              v-model="form.dialer_trunk"
              type="text"
              :placeholder="$t('JABVOX_VOIP.FORM.DIALER_TRUNK_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
            <p class="text-xs text-slate-400">
              {{ $t('JABVOX_VOIP.FORM.DIALER_TRUNK_HELP') }}
            </p>
          </div>
        </div>

        <Button
          :label="
            uiFlags.isSaving
              ? $t('JABVOX_PRODUCTS.LOADING')
              : $t('JABVOX_VOIP.SAVE')
          "
          :disabled="
            uiFlags.isSaving || !form.host || !form.username || !form.context
          "
          @click="onSave"
        />
      </div>

      <!-- Extensions card (admin only) -->
      <div
        v-if="isAdmin"
        class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 p-6 space-y-5"
      >
        <h3 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
          {{ $t('JABVOX_VOIP.EXTENSIONS.TITLE') }}
        </h3>

        <div class="flex gap-3 items-end flex-wrap">
          <div class="space-y-1 flex-1 min-w-[180px]">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.EXTENSIONS.USER') }}
            </label>
            <select
              v-model="newExtUserId"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option value="">
                {{ $t('JABVOX_VOIP.EXTENSIONS.SELECT_USER') }}
              </option>
              <option v-for="a in availableAgents" :key="a.id" :value="a.id">
                {{ a.name }} ({{ a.email }})
              </option>
            </select>
          </div>
          <div class="space-y-1 w-28">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_VOIP.EXTENSIONS.EXTENSION') }}
            </label>
            <input
              v-model="newExtValue"
              type="text"
              :placeholder="$t('JABVOX_VOIP.EXTENSIONS.PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              @keydown.enter="onAddExtension"
            />
          </div>
          <Button
            :label="$t('JABVOX_VOIP.EXTENSIONS.ADD')"
            :disabled="extSaving || !newExtUserId || !newExtValue.trim()"
            @click="onAddExtension"
          />
        </div>

        <div
          v-if="extensions.length"
          class="overflow-x-auto overflow-y-auto max-h-64 rounded-xl border border-slate-100 dark:border-slate-700"
        >
          <table class="w-full text-sm">
            <thead>
              <tr class="bg-slate-50 dark:bg-slate-700/40 text-left">
                <th class="px-4 py-2.5 text-xs font-medium text-slate-500">
                  {{ $t('JABVOX_VOIP.EXTENSIONS.COL_USER') }}
                </th>
                <th class="px-4 py-2.5 text-xs font-medium text-slate-500">
                  {{ $t('JABVOX_VOIP.EXTENSIONS.COL_EMAIL') }}
                </th>
                <th class="px-4 py-2.5 text-xs font-medium text-slate-500">
                  {{ $t('JABVOX_VOIP.EXTENSIONS.COL_EXT') }}
                </th>
                <th class="px-4 py-2.5" />
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
              <tr
                v-for="ext in extensions"
                :key="ext.id"
                class="hover:bg-slate-50 dark:hover:bg-slate-700/20"
              >
                <td
                  class="px-4 py-2.5 font-medium text-slate-800 dark:text-slate-100"
                >
                  {{ ext.user_name }}
                </td>
                <td class="px-4 py-2.5 text-slate-500">{{ ext.user_email }}</td>
                <td class="px-4 py-2.5">
                  <span
                    class="px-2 py-0.5 rounded-full text-xs font-mono font-bold bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300"
                  >
                    {{ ext.extension }}
                  </span>
                </td>
                <td class="px-4 py-2.5 text-right">
                  <button
                    class="text-xs text-red-400 hover:text-red-600 transition-colors"
                    @click="onRemoveExtension(ext)"
                  >
                    {{ $t('JABVOX_VOIP.EXTENSIONS.REMOVE') }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="text-xs text-slate-400">
          {{ $t('JABVOX_VOIP.EXTENSIONS.EMPTY') }}
        </p>
      </div>
    </div>
  </SettingsLayout>
</template>
