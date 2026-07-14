<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import userExtensionAPI from 'dashboard/api/jabvox/userExtension';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
import agentsAPI from 'dashboard/api/agents';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SectionCard from './components/SectionCard.vue';
import SaveBar from './components/SaveBar.vue';
import ExtensionDialog from './components/ExtensionDialog.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();
const { isDirty, markDirty, markClean } = useUnsavedChanges();

const config = useMapGetter('jabvoxVoip/getConfig');
const status = useMapGetter('jabvoxVoip/getStatus');
const uiFlags = useMapGetter('jabvoxVoip/getUIFlags');
const currentUserRole = useMapGetter('getCurrentRole');

const isAdmin = computed(() => currentUserRole.value === 'administrator');
const isConnected = computed(() => status.value?.connected === true);
const showPassword = ref(false);

const buildForm = cfg => ({
  host: cfg?.host || '',
  port: cfg?.port || 5038,
  username: cfg?.username || '',
  password: '',
  context: cfg?.context || 'clicktocall',
  dialer_context: cfg?.dialer_context || '',
  dialer_trunk: cfg?.dialer_trunk || '',
  dial_field_jabvox: cfg?.dial_field_jabvox || '',
  dial_prefix_jabvox: cfg?.dial_prefix_jabvox || '',
});

// Fields the call can dial: the contact phone (default) + each lead custom
// column, so the user can pick e.g. "movil_2_c" instead of the WhatsApp number.
const dialFieldOptions = ref([{ value: '', label: '' }]);
const loadDialFields = async () => {
  const base = [
    { value: '', label: t('JABVOX_VOIP.DIAL.FIELD_PHONE_DEFAULT') },
  ];
  try {
    const { data } = await dialerCampaignsAPI.getLeadFields();
    const custom = (data.custom || []).map(c => ({
      value: c.key,
      label: c.label,
    }));
    dialFieldOptions.value = [...base, ...custom];
  } catch {
    dialFieldOptions.value = base;
  }
};

const form = ref(buildForm(config.value?.id ? config.value : null));
watch(form, () => markDirty(), { deep: true });

const isNew = computed(() => !config.value?.id);
const isValid = computed(
  () => !!form.value.host && !!form.value.username && !!form.value.context
);

// ── status tone ──
const statusColor = computed(() => {
  if (status.value === null) return 'slate';
  return isConnected.value ? 'teal' : 'ruby';
});
const statusLabel = computed(() => {
  if (status.value === null) return t('JABVOX_VOIP.STATUS.LOADING');
  return isConnected.value
    ? t('JABVOX_VOIP.STATUS.CONNECTED')
    : t('JABVOX_VOIP.STATUS.DISCONNECTED');
});

// ── extensions ──
const extensions = ref([]);
const agents = ref([]);
const extSaving = ref(false);
const extSearch = ref('');
const extensionDialog = ref(null);
const deleteDialog = ref(null);

const usedUserIds = computed(() => extensions.value.map(e => e.user_id));
const availableAgents = computed(() =>
  agents.value.filter(a => !usedUserIds.value.includes(a.id))
);
const filteredExtensions = computed(() => {
  const q = extSearch.value.trim().toLowerCase();
  if (!q) return extensions.value;
  return extensions.value.filter(
    e =>
      e.user_name?.toLowerCase().includes(q) ||
      e.user_email?.toLowerCase().includes(q) ||
      String(e.extension).includes(q)
  );
});

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
  loadDialFields();
  store.dispatch('jabvoxVoip/fetchStatus');
  if (isAdmin.value) {
    loadExtensions();
    const { data } = await agentsAPI.get();
    agents.value = data;
  }
  await nextTick();
  markClean();
});

const onSave = async () => {
  if (!isValid.value) return;
  try {
    await store.dispatch('jabvoxVoip/updateConfig', { ...form.value });
    form.value.password = '';
    await nextTick();
    markClean();
    useAlert(t('JABVOX_VOIP.SAVE_SUCCESS'));
    store.dispatch('jabvoxVoip/fetchStatus');
  } catch {
    useAlert(t('JABVOX_VOIP.ERROR'));
  }
};

const onDiscard = async () => {
  form.value = buildForm(config.value?.id ? config.value : null);
  await nextTick();
  markClean();
};

const onRefreshStatus = () => store.dispatch('jabvoxVoip/fetchStatus');

const onSubmitExtension = async ({ userId, extension }) => {
  extSaving.value = true;
  try {
    const { data } = await userExtensionAPI.create(userId, extension);
    extensions.value.push(data);
    extensionDialog.value?.close();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_VOIP.ERROR'));
  } finally {
    extSaving.value = false;
  }
};

const askRemoveExtension = ext => {
  deleteDialog.value?.open({
    title: t('JABVOX_VOIP.EXTENSIONS.DELETE_TITLE'),
    description: t('JABVOX_VOIP.EXTENSIONS.DELETE_BODY', {
      ext: ext.extension,
      name: ext.user_name,
    }),
    data: ext,
  });
};

const doRemoveExtension = async ext => {
  try {
    await userExtensionAPI.destroy(ext.id);
    extensions.value = extensions.value.filter(e => e.id !== ext.id);
  } catch {
    useAlert(t('JABVOX_VOIP.ERROR'));
  }
};
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-4xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-start gap-3">
        <span
          class="i-lucide-phone-call size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_VOIP.TITLE') }}
          </h1>
          <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_VOIP.SUBTITLE') }}
          </p>
        </div>
      </div>

      <!-- Status banner -->
      <div
        class="flex items-center justify-between gap-3 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm p-4 sm:p-5"
      >
        <div class="flex items-center gap-3 min-w-0">
          <span
            class="flex size-10 shrink-0 items-center justify-center rounded-xl"
            :class="{
              'bg-n-teal-3 text-n-teal-11': statusColor === 'teal',
              'bg-n-ruby-3 text-n-ruby-11': statusColor === 'ruby',
              'bg-n-alpha-2 text-n-slate-11': statusColor === 'slate',
            }"
          >
            <span class="i-lucide-server size-5" />
          </span>
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <p class="text-sm font-semibold text-n-slate-12">
                {{ statusLabel }}
              </p>
              <Label
                v-if="status !== null"
                :label="
                  isConnected
                    ? t('JABVOX_VOIP.STATUS.CONNECTED')
                    : t('JABVOX_VOIP.STATUS.DISCONNECTED')
                "
                :color="statusColor"
                compact
              />
            </div>
            <p
              v-if="status?.message"
              class="text-xs text-n-slate-11 mt-0.5 truncate"
            >
              {{ status.message }}
            </p>
          </div>
        </div>
        <Button
          :label="t('JABVOX_VOIP.STATUS.REFRESH')"
          icon="i-lucide-refresh-cw"
          variant="outline"
          color="slate"
          size="sm"
          class="shrink-0"
          :is-loading="uiFlags.isCheckingStatus"
          @click="onRefreshStatus"
        />
      </div>

      <!-- Config form -->
      <form class="flex flex-col gap-6" @submit.prevent>
        <!-- AMI connection -->
        <SectionCard
          :title="t('JABVOX_VOIP.FORM.SECTION_CONNECTION')"
          :description="t('JABVOX_VOIP.FORM.SECTION_CONNECTION_DESC')"
          icon="i-lucide-server"
        >
          <div class="flex flex-col gap-4">
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div class="sm:col-span-2">
                <Input
                  v-model="form.host"
                  :label="`${t('JABVOX_VOIP.FORM.HOST')} *`"
                  :placeholder="t('JABVOX_VOIP.FORM.HOST_PLACEHOLDER')"
                  custom-input-class="font-mono"
                />
              </div>
              <Input
                v-model.number="form.port"
                type="number"
                min="1"
                max="65535"
                :label="`${t('JABVOX_VOIP.FORM.PORT')} *`"
              />
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Input
                v-model="form.username"
                :label="`${t('JABVOX_VOIP.FORM.USERNAME')} *`"
              />
              <div class="flex flex-col gap-1.5">
                <label class="text-sm font-medium text-n-slate-12">
                  {{ t('JABVOX_VOIP.FORM.PASSWORD') }}
                </label>
                <div class="relative">
                  <Input
                    v-model="form.password"
                    :type="showPassword ? 'text' : 'password'"
                    autocomplete="new-password"
                    custom-input-class="!pr-10"
                    :placeholder="isNew ? '' : '••••••••'"
                  />
                  <button
                    type="button"
                    class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
                    @click="showPassword = !showPassword"
                  >
                    <span
                      :class="
                        showPassword ? 'i-lucide-eye-off' : 'i-lucide-eye'
                      "
                      class="size-4"
                    />
                  </button>
                </div>
                <p v-if="!isNew" class="text-xs text-n-slate-10">
                  {{ t('JABVOX_VOIP.FORM.PASSWORD_HINT') }}
                </p>
              </div>
            </div>
            <Input
              v-model="form.context"
              :label="`${t('JABVOX_VOIP.FORM.CONTEXT')} *`"
              :message="t('JABVOX_VOIP.FORM.CONTEXT_HELP')"
              custom-input-class="font-mono"
            />
          </div>
        </SectionCard>

        <!-- Dialer -->
        <SectionCard
          :title="t('JABVOX_VOIP.FORM.SECTION_DIALER')"
          :description="t('JABVOX_VOIP.FORM.SECTION_DIALER_DESC')"
          icon="i-lucide-phone-outgoing"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="form.dialer_context"
              :label="t('JABVOX_VOIP.FORM.DIALER_CONTEXT')"
              :message="t('JABVOX_VOIP.FORM.DIALER_CONTEXT_HELP')"
              custom-input-class="font-mono"
            />
            <Input
              v-model="form.dialer_trunk"
              :label="t('JABVOX_VOIP.FORM.DIALER_TRUNK')"
              :placeholder="t('JABVOX_VOIP.FORM.DIALER_TRUNK_PLACEHOLDER')"
              :message="t('JABVOX_VOIP.FORM.DIALER_TRUNK_HELP')"
              custom-input-class="font-mono"
            />
          </div>
        </SectionCard>

        <!-- Dial field (click-to-call): which number to dial + prefix -->
        <SectionCard
          :title="t('JABVOX_VOIP.DIAL.SECTION')"
          :description="t('JABVOX_VOIP.DIAL.SECTION_DESC')"
          icon="i-lucide-phone-call"
          allow-overflow
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1.5">
              <Label :label="t('JABVOX_VOIP.DIAL.FIELD_LABEL')" />
              <ComboBox
                v-model="form.dial_field_jabvox"
                :options="dialFieldOptions"
                :placeholder="t('JABVOX_VOIP.DIAL.FIELD_PHONE_DEFAULT')"
                :search-placeholder="t('JABVOX_VOIP.DIAL.FIELD_SEARCH')"
                :empty-state="t('JABVOX_VOIP.DIAL.FIELD_NO_RESULTS')"
              />
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_VOIP.DIAL.FIELD_HELP') }}
              </span>
            </div>
            <Input
              v-model="form.dial_prefix_jabvox"
              :label="t('JABVOX_VOIP.DIAL.PREFIX_LABEL')"
              :placeholder="t('JABVOX_VOIP.DIAL.PREFIX_PLACEHOLDER')"
              :message="t('JABVOX_VOIP.DIAL.PREFIX_HELP')"
              custom-input-class="font-mono"
            />
          </div>
        </SectionCard>

        <!-- First-time save button (no config yet → SaveBar baseline is clean) -->
        <div v-if="isNew" class="flex">
          <Button
            :label="t('JABVOX_VOIP.SAVE')"
            :is-loading="uiFlags.isSaving"
            :disabled="!isValid || uiFlags.isSaving"
            @click="onSave"
          />
        </div>

        <SaveBar
          :visible="!isNew && isDirty"
          :is-saving="uiFlags.isSaving"
          :disabled="!isValid"
          @save="onSave"
          @discard="onDiscard"
        />
      </form>

      <!-- Extensions (admin only) -->
      <div v-if="isAdmin" class="flex flex-col gap-5">
        <div
          class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
        >
          <div class="min-w-0">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_VOIP.EXTENSIONS.TITLE') }}
            </h2>
            <p class="mt-1 text-sm text-n-slate-11 max-w-2xl">
              {{ t('JABVOX_VOIP.EXTENSIONS.SUBTITLE') }}
            </p>
          </div>
          <Button
            :label="t('JABVOX_VOIP.EXTENSIONS.ADD')"
            icon="i-lucide-plus"
            size="sm"
            class="shrink-0"
            :disabled="!availableAgents.length"
            @click="extensionDialog?.open()"
          />
        </div>

        <!-- Empty -->
        <EmptyStateLayout
          v-if="!extensions.length"
          :title="t('JABVOX_VOIP.EXTENSIONS.EMPTY_TITLE')"
          :subtitle="t('JABVOX_VOIP.EXTENSIONS.EMPTY')"
        >
          <template #actions>
            <Button
              icon="i-lucide-plus"
              :label="t('JABVOX_VOIP.EXTENSIONS.ADD')"
              size="sm"
              :disabled="!availableAgents.length"
              @click="extensionDialog?.open()"
            />
          </template>
        </EmptyStateLayout>

        <template v-else>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="relative w-full sm:w-64">
              <Input
                v-model="extSearch"
                :placeholder="t('JABVOX_VOIP.EXTENSIONS.SEARCH_PLACEHOLDER')"
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
              {{
                t('JABVOX_VOIP.EXTENSIONS.COUNT', { count: extensions.length })
              }}
            </span>
          </div>

          <div
            v-if="!filteredExtensions.length"
            class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_VOIP.EXTENSIONS.NO_RESULTS') }}
          </div>

          <div
            v-else
            class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm divide-y divide-n-weak overflow-hidden"
          >
            <div
              v-for="ext in filteredExtensions"
              :key="ext.id"
              class="flex items-center gap-3 px-4 py-3 hover:bg-n-alpha-1 transition-colors"
            >
              <Avatar :name="ext.user_name" :size="32" rounded-full />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-n-slate-12 truncate">
                  {{ ext.user_name }}
                </p>
                <p class="text-xs text-n-slate-10 truncate">
                  {{ ext.user_email }}
                </p>
              </div>
              <code
                class="font-mono text-sm font-semibold text-n-brand bg-n-alpha-2 rounded-md px-2 py-0.5 shrink-0"
              >
                {{ ext.extension }}
              </code>
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                :title="t('JABVOX_VOIP.EXTENSIONS.REMOVE')"
                @click="askRemoveExtension(ext)"
              />
            </div>
          </div>
        </template>
      </div>
    </div>

    <!-- Dialogs -->
    <ExtensionDialog
      ref="extensionDialog"
      :available-agents="availableAgents"
      :is-saving="extSaving"
      @submit="onSubmitExtension"
    />
    <ConfirmDialog ref="deleteDialog" @confirm="doRemoveExtension" />
  </div>
</template>
