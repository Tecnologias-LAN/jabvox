<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  useClickToCall,
  useClickToCallListener,
} from 'dashboard/composables/jabvox/useClickToCall';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';
import ManagementQuestionsForm from 'dashboard/components/jabvox/managementStates/ManagementQuestionsForm.vue';
import {
  noteRule,
  isManagementValid,
  buildManagementContentAttributes,
  stateGroups,
  statesInGroup,
  hasGroups,
} from 'dashboard/composables/jabvox/useManagementState';

const { t } = useI18n();
const store = useStore();
const { phase, target, hangup, submitTypification, close } = useClickToCall();
useClickToCallListener();

const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');

const typifications = ref([]);
const selectedTypificationId = ref(null);
const managementStateId = ref(null);
const managementGroup = ref(null);
const managementAnswers = ref({});
const note = ref('');

const selectedManagementState = computed(
  () =>
    (managementStates.value || []).find(
      s => s.id === managementStateId.value
    ) || null
);

// Two-level picker (Estado → Subestado) when any active state has a group.
const managementHasGroups = computed(() => hasGroups(managementStates.value));
const managementGroups = computed(() => stateGroups(managementStates.value));
const managementGroupStates = computed(() =>
  managementGroup.value === null
    ? []
    : statesInGroup(managementStates.value, managementGroup.value)
);

// Changing the group invalidates a substate that belongs to another group.
watch(managementGroup, () => {
  const state = selectedManagementState.value;
  if (
    state &&
    (state.state_group_jabvox || '') !== (managementGroup.value || '')
  )
    managementStateId.value = null;
});

// The chosen management state decides whether the note is hidden / optional / required.
const noteVisible = computed(
  () => !noteRule(selectedManagementState.value).hidden
);
const noteRequired = computed(
  () => noteRule(selectedManagementState.value).required
);

// Accept needs a typification and, when a management state is chosen, valid answers + note.
const canAccept = computed(() => {
  if (!selectedTypificationId.value) return false;
  return isManagementValid(
    selectedManagementState.value,
    managementAnswers.value,
    note.value
  );
});

const loadTypifications = async () => {
  if (typifications.value.length) return;
  const { data } = await typificationsAPI.getAll(true);
  typifications.value = data.typifications || data || [];
};

onMounted(() => {
  store.dispatch('jabvoxManagementStates/fetchStates').catch(() => {});
});

// Load typifications when we enter the typify phase; reset the form when the overlay closes.
watch(phase, value => {
  if (value === 'typify') loadTypifications();
  if (value === null) {
    selectedTypificationId.value = null;
    managementStateId.value = null;
    managementGroup.value = null;
    managementAnswers.value = {};
    note.value = '';
  }
});

// Reset answers/note when switching management state so stale answers don't leak across states.
watch(managementStateId, () => {
  managementAnswers.value = {};
});

const accept = () => {
  if (!canAccept.value) return;
  if (
    selectedManagementState.value &&
    !isManagementValid(
      selectedManagementState.value,
      managementAnswers.value,
      note.value
    )
  ) {
    useAlert(t('JABVOX_MANAGEMENT_STATES.QUESTIONS.INCOMPLETE'));
    return;
  }
  const management = selectedManagementState.value
    ? buildManagementContentAttributes(
        selectedManagementState.value,
        managementAnswers.value
      )
    : null;
  submitTypification({
    typificationId: selectedTypificationId.value,
    note: note.value,
    management,
  });
};
</script>

<template>
  <div
    v-show="phase"
    class="fixed bottom-6 right-6 z-50 w-96 rounded-xl bg-n-solid-2 shadow-xl border border-n-weak overflow-hidden"
  >
    <!-- Calling phase -->
    <template v-if="phase === 'calling'">
      <div class="p-4 bg-n-brand text-white">
        <p class="text-sm opacity-90">
          {{ t('JABVOX_CLICK_TO_CALL.IN_CALL') }}
        </p>
        <p class="text-lg font-medium">{{ target.name || target.phone }}</p>
        <p class="text-xs opacity-80">{{ target.phone }}</p>
      </div>
      <div class="p-4 flex justify-center">
        <button
          class="px-6 py-2 rounded-lg bg-n-ruby-9 text-white text-sm font-medium"
          @click="hangup"
        >
          {{ t('JABVOX_CLICK_TO_CALL.HANG_UP') }}
        </button>
      </div>
    </template>

    <!-- Typify phase -->
    <template v-else-if="phase === 'typify'">
      <div class="p-4 border-b border-n-weak">
        <p class="text-base font-medium text-n-slate-12">
          {{ t('JABVOX_CLICK_TO_CALL.TYPIFY_TITLE') }}
        </p>
        <p class="text-xs text-n-slate-11">{{ target.name || target.phone }}</p>
      </div>
      <div class="p-4 space-y-3 max-h-[60vh] overflow-y-auto">
        <label class="flex flex-col text-xs text-n-slate-11">
          {{ t('JABVOX_CLICK_TO_CALL.TYPIFICATION_REQUIRED') }}
          <select
            v-model="selectedTypificationId"
            class="reset-base mt-1 text-sm"
          >
            <option :value="null" disabled>
              {{ t('JABVOX_CLICK_TO_CALL.SELECT_TYPIFICATION') }}
            </option>
            <option v-for="tp in typifications" :key="tp.id" :value="tp.id">
              {{ tp.name }}
            </option>
          </select>
        </label>

        <!-- Management type (gestión) — appears after typification -->
        <template v-if="managementStates.length">
          <!-- Two-level picker: Estado (grupo) → Subestado -->
          <template v-if="managementHasGroups">
            <label class="flex flex-col text-xs text-n-slate-11">
              {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.GROUP_LABEL') }}
              <select v-model="managementGroup" class="reset-base mt-1 text-sm">
                <option :value="null">
                  {{
                    t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.GROUP_PLACEHOLDER')
                  }}
                </option>
                <option v-for="g in managementGroups" :key="g" :value="g">
                  {{ g || t('JABVOX_MANAGEMENT_STATES.UNGROUPED') }}
                </option>
              </select>
            </label>
            <label class="flex flex-col text-xs text-n-slate-11">
              {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_LABEL') }}
              <select
                v-model="managementStateId"
                :disabled="managementGroup === null"
                class="reset-base mt-1 text-sm disabled:opacity-60"
              >
                <option :value="null">
                  {{
                    t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_PLACEHOLDER')
                  }}
                </option>
                <option
                  v-for="s in managementGroupStates"
                  :key="s.id"
                  :value="s.id"
                >
                  {{ s.name_jabvox }}
                </option>
              </select>
            </label>
          </template>
          <!-- Flat picker (accounts without groups) -->
          <label v-else class="flex flex-col text-xs text-n-slate-11">
            {{ t('JABVOX_CLICK_TO_CALL.MANAGEMENT_TYPE') }}
            <select v-model="managementStateId" class="reset-base mt-1 text-sm">
              <option :value="null">
                {{ t('JABVOX_CLICK_TO_CALL.SELECT_MANAGEMENT') }}
              </option>
              <option v-for="s in managementStates" :key="s.id" :value="s.id">
                {{ s.name_jabvox }}
              </option>
            </select>
          </label>
          <p
            v-if="selectedManagementState?.usage_info_jabvox"
            class="text-xs text-n-slate-10"
          >
            {{ selectedManagementState.usage_info_jabvox }}
          </p>
        </template>

        <!-- Dynamic questions for the chosen management state -->
        <ManagementQuestionsForm
          v-if="selectedManagementState"
          v-model="managementAnswers"
          :state="selectedManagementState"
        />

        <!-- Note: hidden / optional / required per the management state's rule -->
        <label v-if="noteVisible" class="flex flex-col text-xs text-n-slate-11">
          {{
            noteRequired
              ? t('JABVOX_CLICK_TO_CALL.NOTE_REQUIRED')
              : t('JABVOX_CLICK_TO_CALL.NOTE')
          }}
          <textarea
            v-model="note"
            rows="3"
            class="reset-base mt-1 text-sm"
            :placeholder="t('JABVOX_CLICK_TO_CALL.NOTE_PLACEHOLDER')"
          />
        </label>
      </div>
      <div class="p-4 flex justify-end gap-2 border-t border-n-weak">
        <button
          class="px-4 py-2 rounded-lg bg-n-alpha-2 text-n-slate-11 text-sm"
          @click="close"
        >
          {{ t('JABVOX_CLICK_TO_CALL.CANCEL') }}
        </button>
        <button
          class="px-4 py-2 rounded-lg bg-n-brand text-white text-sm disabled:opacity-50"
          :disabled="!canAccept"
          @click="accept"
        >
          {{ t('JABVOX_CLICK_TO_CALL.ACCEPT') }}
        </button>
      </div>
    </template>
  </div>
</template>
