<script setup>
import { ref, computed } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  inbox: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:show', 'confirm', 'close']);

const allInboxes = useMapGetter('inboxes/getInboxes');

const DELETE_MODES = [
  'inbox_only',
  'inbox_conversations',
  'inbox_leads_conversations',
];

const MODE_KEYS = {
  inbox_only: {
    label: 'INBOX_MGMT.DELETE.MODE.INBOX_ONLY',
    desc: 'INBOX_MGMT.DELETE.MODE.INBOX_ONLY_DESC',
  },
  inbox_conversations: {
    label: 'INBOX_MGMT.DELETE.MODE.INBOX_CONVERSATIONS',
    desc: 'INBOX_MGMT.DELETE.MODE.INBOX_CONVERSATIONS_DESC',
  },
  inbox_leads_conversations: {
    label: 'INBOX_MGMT.DELETE.MODE.INBOX_LEADS_CONVERSATIONS',
    desc: 'INBOX_MGMT.DELETE.MODE.INBOX_LEADS_CONVERSATIONS_DESC',
  },
};

const selectedMode = ref('inbox_conversations');
const nameInput = ref('');
const targetInboxId = ref('auto');

const otherInboxes = computed(() =>
  (allInboxes.value || []).filter(i => i.id !== props.inbox.id)
);

const v$ = useVuelidate(
  {
    nameInput: {
      required,
      isEqual: value =>
        (value || '').trim() === (props.inbox.name || '').trim(),
    },
  },
  { nameInput }
);

const localShow = computed({
  get: () => props.show,
  set: val => emit('update:show', val),
});

const closeModal = () => {
  nameInput.value = '';
  selectedMode.value = 'inbox_conversations';
  targetInboxId.value = 'auto';
  v$.value.$reset();
  emit('close');
};

const onConfirm = () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;
  emit('confirm', {
    deleteMode: selectedMode.value,
    targetInboxId:
      selectedMode.value === 'inbox_only' ? targetInboxId.value : null,
  });
  closeModal();
};
</script>

<template>
  <Modal v-model:show="localShow" :on-close="closeModal">
    <woot-modal-header
      :header-title="$t('INBOX_MGMT.DELETE.CONFIRM.TITLE')"
      :header-content="`${$t('INBOX_MGMT.DELETE.CONFIRM.MESSAGE')} ${inbox.name}?`"
    />
    <form class="flex flex-col gap-4" @submit.prevent="onConfirm">
      <div class="flex flex-col gap-2">
        <p class="text-sm font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.DELETE.MODE.TITLE') }}
        </p>
        <label
          v-for="mode in DELETE_MODES"
          :key="mode"
          class="flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors"
          :class="
            selectedMode === mode
              ? 'border-n-ruby-8 bg-n-ruby-2'
              : 'border-n-weak bg-n-alpha-1 hover:bg-n-alpha-2'
          "
        >
          <input
            v-model="selectedMode"
            type="radio"
            :value="mode"
            class="mt-0.5 accent-n-ruby-9"
          />
          <div class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t(MODE_KEYS[mode].label) }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{ $t(MODE_KEYS[mode].desc) }}
            </span>
          </div>
        </label>
      </div>

      <div v-if="selectedMode === 'inbox_only'" class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.DELETE.MODE.INBOX_ONLY_TARGET_LABEL') }}
        </label>
        <select
          v-model="targetInboxId"
          class="w-full rounded-lg border px-3 py-2 text-sm bg-n-alpha-1 border-n-weak text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-ruby-8"
        >
          <option value="auto">
            {{ $t('INBOX_MGMT.DELETE.MODE.INBOX_ONLY_TARGET_AUTO') }}
          </option>
          <option v-for="ib in otherInboxes" :key="ib.id" :value="ib.id">
            {{ ib.name }}
          </option>
        </select>
      </div>

      <woot-input
        v-model="nameInput"
        type="text"
        :class="{ error: v$.nameInput.$error }"
        :placeholder="
          $t('INBOX_MGMT.DELETE.CONFIRM.PLACE_HOLDER', {
            inboxName: inbox.name,
          })
        "
        @blur="v$.nameInput.$touch"
      />

      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="reset"
          :label="`${$t('INBOX_MGMT.DELETE.CONFIRM.NO')} ${inbox.name}`"
          @click.prevent="closeModal"
        />
        <Button
          ruby
          type="submit"
          :label="`${$t('INBOX_MGMT.DELETE.CONFIRM.YES')} ${inbox.name}`"
          :disabled="v$.nameInput.$invalid"
        />
      </div>
    </form>
  </Modal>
</template>
