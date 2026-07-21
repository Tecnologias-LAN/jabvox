<script setup>
// Notes tab for a conversation. A note is a PRIVATE message; here (unlike the
// chat reply box) it carries the gestión (management-state) picker. Mirrors the
// notes composer from the lead detail so both behave identically.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import messageAPI from 'dashboard/api/inbox/message';
import ManagementQuestionsForm from 'dashboard/components/jabvox/managementStates/ManagementQuestionsForm.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  isManagementValid,
  buildManagementContentAttributes,
  stateGroups,
  statesInGroup,
  hasGroups,
  CALL_SOURCES,
} from 'dashboard/composables/jabvox/useManagementState';

// contactId is passed by the tab host for interface consistency but notes are
// keyed by conversation. conversationDisplayId is what the messages API needs
// (the display_id, not the internal PK).
const props = defineProps({
  contactId: { type: [Number, String], default: null },
  conversationId: { type: [Number, String], default: null },
  conversationDisplayId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const store = useStore();

// Live contact for lead-field autofill in management questions.
const contact = computed(() =>
  props.contactId
    ? store.getters['contacts/getContactById'](props.contactId)
    : null
);

const managementStates = computed(
  () => store.getters['jabvoxManagementStates/getActiveStates'] || []
);

const notes = ref([]);
const loading = ref(false);
const sending = ref(false);
const noteContent = ref('');
const stateId = ref(null);
const group = ref(null);
const answers = ref({});

const selectedState = computed(() =>
  managementStates.value.find(s => s.id === stateId.value)
);
const useGroups = computed(() => hasGroups(managementStates.value));
const groups = computed(() => stateGroups(managementStates.value));
const groupStates = computed(() =>
  group.value === null
    ? managementStates.value
    : statesInGroup(managementStates.value, group.value)
);

// The messages API resolves a conversation by its display_id. Prefer the
// explicit prop; fall back to the selected chat's display_id.
const displayId = computed(
  () =>
    props.conversationDisplayId ||
    store.getters.getSelectedChat?.display_id ||
    props.conversationId
);

const loadNotes = async () => {
  if (!displayId.value) return;
  loading.value = true;
  try {
    const { data } = await messageAPI.getPreviousMessages({
      conversationId: displayId.value,
    });
    const list = data?.payload || [];
    notes.value = list.filter(m => m.private || m.message_type === 2);
  } catch {
    notes.value = [];
  } finally {
    loading.value = false;
  }
};

watch(displayId, loadNotes, { immediate: true });

const selectGroup = g => {
  group.value = group.value === g ? null : g;
  stateId.value = null;
};

watch(stateId, () => {
  answers.value = {};
});

const reset = () => {
  noteContent.value = '';
  stateId.value = null;
  group.value = null;
  answers.value = {};
};

const save = async () => {
  const content = noteContent.value.trim();
  if (!content || sending.value) return;
  // If states exist, a gestión must be chosen for a note here.
  if (managementStates.value.length > 0 && !stateId.value) {
    useAlert(t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.REQUIRED'));
    return;
  }
  if (
    selectedState.value &&
    !isManagementValid(selectedState.value, answers.value, content)
  ) {
    useAlert(t('JABVOX_MANAGEMENT_STATES.QUESTIONS.INCOMPLETE'));
    return;
  }
  sending.value = true;
  try {
    const payload = {
      conversationId: displayId.value,
      message: content,
      private: true,
      echo_id: `jabvox_note_${Date.now()}`,
    };
    if (stateId.value) {
      payload.contentAttributes = buildManagementContentAttributes(
        selectedState.value,
        answers.value,
        CALL_SOURCES.CONVERSATIONS
      );
    }
    await messageAPI.create(payload);
    reset();
    await loadNotes();
    useAlert(t('JABVOX_CUSTOMIZATION.LEAD_ROWS.SAVED'));
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.SEND_ERROR'));
  } finally {
    sending.value = false;
  }
};

const noteState = m =>
  m.content_attributes?.jabvox_management_state_name || null;
const noteColor = m =>
  m.content_attributes?.jabvox_management_state_color || '#6b7280';
</script>

<template>
  <div class="flex flex-col h-full min-h-0 bg-n-background">
    <!-- Existing notes -->
    <div class="flex-1 overflow-y-auto p-4 space-y-3">
      <p v-if="loading" class="text-sm text-n-slate-10 text-center py-6">
        {{ t('JABVOX_CUSTOMIZATION.LOADING') }}
      </p>
      <p
        v-else-if="!notes.length"
        class="text-sm text-n-slate-10 text-center py-6"
      >
        {{ t('JABVOX_CUSTOMIZATION.LEAD_ROWS.NOTES_EMPTY') }}
      </p>
      <template v-else>
        <div
          v-for="note in notes"
          :key="note.id"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-3"
        >
          <div
            v-if="noteState(note)"
            class="flex items-center gap-1.5 mb-1.5 text-xs font-medium"
          >
            <span
              class="inline-block size-2 rounded-full shrink-0"
              :style="{ backgroundColor: noteColor(note) }"
            />
            <span class="text-n-slate-11">{{ noteState(note) }}</span>
          </div>
          <p class="text-sm text-n-slate-12 whitespace-pre-wrap break-words">
            {{ note.content }}
          </p>
        </div>
      </template>
    </div>

    <!-- Composer with gestión -->
    <div class="shrink-0 border-t border-n-weak bg-n-solid-1 p-3 space-y-2">
      <div v-if="managementStates.length > 0" class="space-y-1.5">
        <template v-if="useGroups">
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="g in groups"
              :key="`g-${g}`"
              type="button"
              class="text-xs px-2.5 py-1 rounded-full border transition-colors"
              :class="
                group === g
                  ? 'bg-n-brand text-white border-transparent'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
              "
              @click="selectGroup(g)"
            >
              {{ g || t('JABVOX_MANAGEMENT_STATES.UNGROUPED') }}
            </button>
          </div>
        </template>
        <select
          v-model="stateId"
          class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
        >
          <option :value="null">
            {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_PLACEHOLDER') }}
          </option>
          <option v-for="s in groupStates" :key="s.id" :value="s.id">
            {{ s.name_jabvox }}
          </option>
        </select>
        <ManagementQuestionsForm
          v-if="selectedState"
          v-model="answers"
          :state="selectedState"
          :contact="contact"
        />
      </div>

      <textarea
        v-model="noteContent"
        rows="3"
        class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 resize-none"
        :placeholder="t('JABVOX_CUSTOMIZATION.LEAD_ROWS.NOTE_PLACEHOLDER')"
      />
      <div class="flex justify-end">
        <Button
          size="sm"
          :label="t('JABVOX_CUSTOMIZATION.LEAD_ROWS.SAVE')"
          :is-loading="sending"
          :disabled="!noteContent.trim()"
          @click="save"
        />
      </div>
    </div>
  </div>
</template>
