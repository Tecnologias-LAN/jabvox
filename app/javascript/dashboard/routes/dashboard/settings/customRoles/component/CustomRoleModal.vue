<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import {
  JABVOX_PERMISSION_GROUPS,
  MANAGE_ALL_CONVERSATION_PERMISSIONS,
  CONVERSATION_UNASSIGNED_PERMISSIONS,
  CONVERSATION_PARTICIPATING_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  mode: {
    type: String,
    default: 'add',
    validator: value => ['add', 'edit'].includes(value),
  },
  selectedRole: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['close']);

// Maps each Jabvox permission group's `module` to the account feature flag that
// enables it. Modules NOT listed here have no per-account toggle (they are always
// available), so they are never filtered out.
const MODULE_FEATURE_FLAG = {
  leads: FEATURE_FLAGS.JABVOX_LEADS,
  kanban: FEATURE_FLAGS.JABVOX_KANBAN,
  tasks: FEATURE_FLAGS.JABVOX_TASKS,
  cdr: FEATURE_FLAGS.JABVOX_CDR,
  audio: FEATURE_FLAGS.JABVOX_AUDIO_ANALYSIS,
  ai_chat: FEATURE_FLAGS.JABVOX_AI_CHAT,
  whatsapp_templates: FEATURE_FLAGS.JABVOX_WHATSAPP_TEMPLATES,
  analytics: FEATURE_FLAGS.JABVOX_ANALYTICS,
  lead_import: FEATURE_FLAGS.JABVOX_LEAD_IMPORT,
  data_export: FEATURE_FLAGS.JABVOX_DATA_EXPORT,
  bulk_whatsapp: FEATURE_FLAGS.JABVOX_BULK_WHATSAPP,
  custom_data: FEATURE_FLAGS.JABVOX_CUSTOMIZATION,
  dialer: FEATURE_FLAGS.JABVOX_DIALER,
  click_to_call: FEATURE_FLAGS.JABVOX_CLICK_TO_CALL,
  internal_chat: FEATURE_FLAGS.JABVOX_INTERNAL_CHAT,
  calendar: FEATURE_FLAGS.JABVOX_CALENDAR,
  response_bot: FEATURE_FLAGS.JABVOX_RESPONSE_BOT,
  forms: FEATURE_FLAGS.JABVOX_FORMS,
  sms: FEATURE_FLAGS.JABVOX_SMS,
  email: FEATURE_FLAGS.JABVOX_EMAIL,
  saldo: FEATURE_FLAGS.JABVOX_SALDO,
  voip: FEATURE_FLAGS.JABVOX_VOIP,
  products: FEATURE_FLAGS.JABVOX_PRODUCTS,
  affiliates: FEATURE_FLAGS.JABVOX_AFFILIATES,
  // management_states, integrations, ip_whitelist, typifications,
  // field_visibilities, campaigns, app_states, reports: no per-account module
  // toggle in the backend's enabled_features → always shown. (Mapping a
  // non-existent feature here would hide the group forever.)
};

const BASE_CUSTOM_ROLE_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
  'contact_manage',
  'report_manage',
  'knowledge_base_manage',
];

const store = useStore();
const { t } = useI18n();

const name = ref('');
const description = ref('');
const selectedPermissions = ref([]);

// Only show permission groups for modules that are ENABLED on the account, so a
// role can't be given permissions for a module the account doesn't have. Groups
// whose module has no per-account toggle (not in the map) are always shown.
const accountId = computed(() => store.getters.getCurrentAccountId);
const visibleJabvoxGroups = computed(() =>
  JABVOX_PERMISSION_GROUPS.filter(group => {
    const flag = MODULE_FEATURE_FLAG[group.module];
    // Module with no account toggle → always available.
    if (!flag) return true;
    // Enabled on the account → show it.
    if (
      store.getters['accounts/isFeatureEnabledonAccount'](accountId.value, flag)
    ) {
      return true;
    }
    // Disabled, BUT keep it visible when editing a role that already holds one of
    // its permissions, so those grants aren't silently hidden/dropped.
    return group.permissions.some(p => selectedPermissions.value.includes(p));
  })
);

const nameInput = ref(null);

const addCustomRole = reactive({
  showLoading: false,
  message: '',
});

const rules = computed(() => ({
  name: { required, minLength: minLength(2) },
  description: { required },
  selectedPermissions: { required, minLength: minLength(1) },
}));

const v$ = useVuelidate(rules, { name, description, selectedPermissions });

const resetForm = () => {
  name.value = '';
  description.value = '';
  selectedPermissions.value = [];
  v$.value.$reset();
};

const populateEditForm = () => {
  name.value = props.selectedRole.name || '';
  description.value = props.selectedRole.description || '';
  selectedPermissions.value = props.selectedRole.permissions || [];
};

watch(
  selectedPermissions,
  (newValue, oldValue) => {
    // Check if manage all conversation permission is added or removed
    const hasAddedManageAllConversation =
      newValue.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS) &&
      !oldValue.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS);
    const hasRemovedManageAllConversation =
      oldValue.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS) &&
      !newValue.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS);

    if (hasAddedManageAllConversation) {
      // If manage all conversation permission is added,
      // then add unassigned and participating permissions automatically
      selectedPermissions.value = [
        ...new Set([
          ...selectedPermissions.value,
          CONVERSATION_UNASSIGNED_PERMISSIONS,
          CONVERSATION_PARTICIPATING_PERMISSIONS,
        ]),
      ];
    } else if (hasRemovedManageAllConversation) {
      // If manage all conversation permission is removed,
      // then only remove manage all conversation permission
      selectedPermissions.value = selectedPermissions.value.filter(
        p => p !== MANAGE_ALL_CONVERSATION_PERMISSIONS
      );
    }
  },
  { deep: true }
);

onMounted(() => {
  if (props.mode === 'edit') {
    populateEditForm();
  }
  // Focus the name input when mounted
  nameInput.value?.focus();
});

const getTranslationKey = base => {
  return props.mode === 'edit'
    ? `CUSTOM_ROLE.EDIT.${base}`
    : `CUSTOM_ROLE.ADD.${base}`;
};

const modalTitle = computed(() => t(getTranslationKey('TITLE')));
const modalDescription = computed(() => t(getTranslationKey('DESC')));
const submitButtonText = computed(() => t(getTranslationKey('SUBMIT')));

const handleCustomRole = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  addCustomRole.showLoading = true;
  try {
    const roleData = {
      name: name.value,
      description: description.value,
      permissions: selectedPermissions.value,
    };

    if (props.mode === 'edit') {
      await store.dispatch('customRole/updateCustomRole', {
        id: props.selectedRole.id,
        ...roleData,
      });
      useAlert(t('CUSTOM_ROLE.EDIT.API.SUCCESS_MESSAGE'));
    } else {
      await store.dispatch('customRole/createCustomRole', roleData);
      useAlert(t('CUSTOM_ROLE.ADD.API.SUCCESS_MESSAGE'));
    }

    resetForm();
    emit('close');
  } catch (error) {
    const errorMessage =
      error?.message || t(`CUSTOM_ROLE.FORM.API.ERROR_MESSAGE`);
    useAlert(errorMessage);
  } finally {
    addCustomRole.showLoading = false;
  }
};

const isSubmitDisabled = computed(
  () => v$.value.$invalid || addCustomRole.showLoading
);
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="modalTitle"
      :header-content="modalDescription"
    />
    <form class="flex flex-col w-full" @submit.prevent="handleCustomRole">
      <div class="w-full">
        <label :class="{ error: v$.name.$error }">
          {{ $t('CUSTOM_ROLE.FORM.NAME.LABEL') }}
          <input
            ref="nameInput"
            v-model.trim="name"
            type="text"
            :placeholder="$t('CUSTOM_ROLE.FORM.NAME.PLACEHOLDER')"
            @blur="v$.name.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.description.$error }">
          {{ $t('CUSTOM_ROLE.FORM.DESCRIPTION.LABEL') }}

          <textarea
            v-model="description"
            :rows="3"
            :placeholder="$t('CUSTOM_ROLE.FORM.DESCRIPTION.PLACEHOLDER')"
            @blur="v$.description.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ 'text-n-ruby-9': v$.selectedPermissions.$error }">
          {{ $t('CUSTOM_ROLE.FORM.PERMISSIONS.LABEL') }}
        </label>
        <div class="flex flex-col gap-4 mb-4 mt-2">
          <div class="flex flex-col gap-2.5">
            <h4 class="text-sm font-medium text-n-slate-12 mb-0">
              {{ $t('CUSTOM_ROLE.PERMISSIONS.MODULES.GENERAL') }}
            </h4>
            <div
              v-for="permission in BASE_CUSTOM_ROLE_PERMISSIONS"
              :key="permission"
              class="flex items-center"
            >
              <input
                :id="permission"
                v-model="selectedPermissions"
                type="checkbox"
                :value="permission"
                name="permissions"
                class="ltr:mr-2 rtl:ml-2"
              />
              <label :for="permission" class="text-sm font-normal">
                {{ $t(`CUSTOM_ROLE.PERMISSIONS.${permission.toUpperCase()}`) }}
              </label>
            </div>
          </div>

          <div
            v-for="group in visibleJabvoxGroups"
            :key="group.module"
            class="flex flex-col gap-2.5"
          >
            <h4 class="text-sm font-medium text-n-slate-12 mb-0">
              {{
                $t(
                  `CUSTOM_ROLE.PERMISSIONS.MODULES.${group.module.toUpperCase()}`
                )
              }}
            </h4>
            <div
              v-for="permission in group.permissions"
              :key="permission"
              class="flex items-center"
            >
              <input
                :id="permission"
                v-model="selectedPermissions"
                type="checkbox"
                :value="permission"
                name="permissions"
                class="ltr:mr-2 rtl:ml-2"
              />
              <label :for="permission" class="text-sm font-normal">
                {{ $t(`CUSTOM_ROLE.PERMISSIONS.${permission.toUpperCase()}`) }}
              </label>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <Button
          faded
          slate
          type="reset"
          :label="$t('CUSTOM_ROLE.FORM.CANCEL_BUTTON_TEXT')"
          @click.prevent="emit('close')"
        />
        <Button
          type="submit"
          :label="submitButtonText"
          :disabled="isSubmitDisabled"
          :is-loading="addCustomRole.showLoading"
        />
      </div>
    </form>
  </div>
</template>
