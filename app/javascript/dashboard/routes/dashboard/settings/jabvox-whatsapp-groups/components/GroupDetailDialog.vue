<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import whatsappGroupsAPI from 'dashboard/api/jabvox/whatsappGroups';

const emit = defineEmits(['updated']);
const { t } = useI18n();

const show = ref(false);
const group = ref(null);
const newPhone = ref('');
const messageText = ref('');
const busy = ref(false);

const activeMembers = computed(
  () =>
    group.value?.members?.filter(m =>
      ['pending', 'joined'].includes(m.invite_status)
    ) || []
);

const atCapacity = computed(
  () => group.value && activeMembers.value.length >= group.value.max_members
);

const reload = async () => {
  const { data } = await whatsappGroupsAPI.getGroup(group.value.id);
  group.value = data;
  emit('updated');
};

const open = async id => {
  show.value = true;
  const { data } = await whatsappGroupsAPI.getGroup(id);
  group.value = data;
};

const close = () => {
  show.value = false;
  group.value = null;
};

const addMember = async () => {
  const phone = newPhone.value.replace(/\D/g, '');
  if (!phone || atCapacity.value) return;
  busy.value = true;
  try {
    await whatsappGroupsAPI.addMember(group.value.id, {
      phoneNumber: phone,
      role: 'member',
    });
    newPhone.value = '';
    await reload();
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('JABVOX_WHATSAPP_GROUPS.DETAIL.ADD_ERROR')
    );
  } finally {
    busy.value = false;
  }
};

const removeMember = async member => {
  busy.value = true;
  try {
    await whatsappGroupsAPI.removeMember(group.value.id, member.id);
    await reload();
  } finally {
    busy.value = false;
  }
};

const toggleRole = async member => {
  const role = member.role === 'admin' ? 'member' : 'admin';
  busy.value = true;
  try {
    await whatsappGroupsAPI.updateMemberRole(group.value.id, member.id, role);
    await reload();
  } finally {
    busy.value = false;
  }
};

const refreshInvite = async () => {
  busy.value = true;
  try {
    const { data } = await whatsappGroupsAPI.refreshInvite(group.value.id);
    group.value.invite_link = data.invite_link;
  } finally {
    busy.value = false;
  }
};

const copyInvite = () => {
  if (group.value?.invite_link) {
    copyTextToClipboard(group.value.invite_link);
    useAlert(t('JABVOX_WHATSAPP_GROUPS.DETAIL.INVITE_COPIED'));
  }
};

const sendMessage = async () => {
  if (!messageText.value.trim()) return;
  busy.value = true;
  try {
    await whatsappGroupsAPI.sendMessage(
      group.value.id,
      messageText.value.trim()
    );
    messageText.value = '';
    useAlert(t('JABVOX_WHATSAPP_GROUPS.DETAIL.MESSAGE_SENT'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('JABVOX_WHATSAPP_GROUPS.DETAIL.MESSAGE_ERROR')
    );
  } finally {
    busy.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <woot-modal v-model:show="show" :on-close="close">
    <div v-if="group" class="flex flex-col gap-4 p-6">
      <h2 class="text-lg font-medium">{{ group.name }}</h2>

      <!-- Invite link (invite-only join) -->
      <section class="flex flex-col gap-1">
        <span class="text-sm font-medium">
          {{ t('JABVOX_WHATSAPP_GROUPS.DETAIL.INVITE_LINK') }}
        </span>
        <div class="flex items-center gap-2">
          <input :value="group.invite_link" readonly class="flex-1 text-xs" />
          <woot-button
            size="tiny"
            variant="clear"
            :is-disabled="!group.invite_link"
            @click="copyInvite"
          >
            {{ t('JABVOX_WHATSAPP_GROUPS.DETAIL.COPY') }}
          </woot-button>
          <woot-button size="tiny" :is-loading="busy" @click="refreshInvite">
            {{ t('JABVOX_WHATSAPP_GROUPS.DETAIL.REFRESH') }}
          </woot-button>
        </div>
      </section>

      <!-- Members -->
      <section class="flex flex-col gap-2">
        <span class="text-sm font-medium">
          {{ t('JABVOX_WHATSAPP_GROUPS.DETAIL.MEMBERS') }}
          ({{ activeMembers.length }} / {{ group.max_members }})
        </span>
        <ul class="flex flex-col gap-1">
          <li
            v-for="m in group.members"
            :key="m.id"
            class="flex items-center justify-between text-sm border-b border-slate-100 dark:border-slate-700 py-1"
          >
            <span>
              {{ m.name || m.phone_number }}
              <span class="text-xs text-slate-400">
                ·
                {{ t(`JABVOX_WHATSAPP_GROUPS.ROLE.${m.role.toUpperCase()}`) }} ·
                {{
                  t(
                    `JABVOX_WHATSAPP_GROUPS.INVITE_STATUS.${m.invite_status.toUpperCase()}`
                  )
                }}
              </span>
            </span>
            <span class="flex gap-1">
              <woot-button size="tiny" variant="clear" @click="toggleRole(m)">
                {{
                  m.role === 'admin'
                    ? t('JABVOX_WHATSAPP_GROUPS.DETAIL.DEMOTE')
                    : t('JABVOX_WHATSAPP_GROUPS.DETAIL.PROMOTE')
                }}
              </woot-button>
              <woot-button
                size="tiny"
                variant="clear"
                color-scheme="alert"
                @click="removeMember(m)"
              >
                {{ t('JABVOX_WHATSAPP_GROUPS.DETAIL.REMOVE') }}
              </woot-button>
            </span>
          </li>
        </ul>

        <div class="flex items-center gap-2">
          <input
            v-model="newPhone"
            type="text"
            class="flex-1 text-sm"
            :disabled="atCapacity"
            :placeholder="t('JABVOX_WHATSAPP_GROUPS.DETAIL.ADD_PLACEHOLDER')"
          />
          <woot-button
            size="tiny"
            :is-disabled="atCapacity || busy"
            @click="addMember"
          >
            {{ t('JABVOX_WHATSAPP_GROUPS.DETAIL.ADD') }}
          </woot-button>
        </div>
        <p v-if="atCapacity" class="text-xs text-yellow-600">
          {{
            t('JABVOX_WHATSAPP_GROUPS.DETAIL.AT_CAPACITY', {
              max: group.max_members,
            })
          }}
        </p>
      </section>

      <!-- Send a message to the group -->
      <section class="flex flex-col gap-1">
        <span class="text-sm font-medium">
          {{ t('JABVOX_WHATSAPP_GROUPS.DETAIL.SEND_MESSAGE') }}
        </span>
        <textarea v-model="messageText" rows="2" class="w-full text-sm" />
        <div class="flex justify-end">
          <woot-button
            size="tiny"
            :is-loading="busy"
            :is-disabled="!messageText.trim()"
            @click="sendMessage"
          >
            {{ t('JABVOX_WHATSAPP_GROUPS.DETAIL.SEND') }}
          </woot-button>
        </div>
      </section>

      <div class="flex justify-end">
        <woot-button variant="clear" @click="close">
          {{ t('JABVOX_WHATSAPP_GROUPS.CLOSE') }}
        </woot-button>
      </div>
    </div>
  </woot-modal>
</template>
