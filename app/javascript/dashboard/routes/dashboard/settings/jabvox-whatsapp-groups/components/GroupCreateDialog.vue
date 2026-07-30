<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import whatsappGroupsAPI from 'dashboard/api/jabvox/whatsappGroups';

const emit = defineEmits(['created']);
const { t } = useI18n();

const MAX_MEMBERS = 8;
const show = ref(false);
const saving = ref(false);
const inboxId = ref(null);
const name = ref('');
const description = ref('');
// Initial members entered one phone per line; enforced ≤8 (Meta hard cap).
const membersText = ref('');

const memberPhones = computed(() =>
  membersText.value
    .split('\n')
    .map(l => l.replace(/\D/g, ''))
    .filter(Boolean)
);

const tooManyMembers = computed(() => memberPhones.value.length > MAX_MEMBERS);
const canSubmit = computed(
  () => name.value.trim() && !tooManyMembers.value && !saving.value
);

const open = id => {
  inboxId.value = id;
  name.value = '';
  description.value = '';
  membersText.value = '';
  show.value = true;
};

const close = () => {
  show.value = false;
};

const submit = async () => {
  if (!canSubmit.value) return;
  saving.value = true;
  try {
    await whatsappGroupsAPI.createGroup({
      name: name.value.trim(),
      description: description.value.trim(),
      inboxId: inboxId.value,
      memberPhones: memberPhones.value,
    });
    useAlert(t('JABVOX_WHATSAPP_GROUPS.CREATE.SUCCESS'));
    emit('created');
    close();
  } catch (error) {
    const reason = error?.response?.data?.reason;
    const msg = reason
      ? t(`JABVOX_WHATSAPP_GROUPS.ELIGIBILITY.REASONS.${reason.toUpperCase()}`)
      : error?.response?.data?.error ||
        t('JABVOX_WHATSAPP_GROUPS.CREATE.ERROR');
    useAlert(msg);
  } finally {
    saving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <woot-modal v-model:show="show" :on-close="close">
    <div class="flex flex-col gap-4 p-6">
      <h2 class="text-lg font-medium">
        {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.TITLE') }}
      </h2>

      <label class="text-sm">
        {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.NAME') }}
        <input v-model="name" type="text" class="w-full" />
      </label>

      <label class="text-sm">
        {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.DESCRIPTION') }}
        <textarea v-model="description" rows="2" class="w-full" />
      </label>

      <label class="text-sm">
        {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.MEMBERS') }}
        <textarea
          v-model="membersText"
          rows="4"
          class="w-full font-mono text-xs"
          :placeholder="t('JABVOX_WHATSAPP_GROUPS.CREATE.MEMBERS_PLACEHOLDER')"
        />
        <span
          class="text-xs"
          :class="tooManyMembers ? 'text-red-600' : 'text-slate-500'"
        >
          {{ memberPhones.length }} / {{ MAX_MEMBERS }}
        </span>
      </label>
      <p v-if="tooManyMembers" class="text-xs text-red-600">
        {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.TOO_MANY', { max: MAX_MEMBERS }) }}
      </p>

      <div class="flex justify-end gap-2">
        <woot-button variant="clear" @click="close">
          {{ t('JABVOX_WHATSAPP_GROUPS.CANCEL') }}
        </woot-button>
        <woot-button
          :is-disabled="!canSubmit"
          :is-loading="saving"
          @click="submit"
        >
          {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.CONFIRM') }}
        </woot-button>
      </div>
    </div>
  </woot-modal>
</template>
