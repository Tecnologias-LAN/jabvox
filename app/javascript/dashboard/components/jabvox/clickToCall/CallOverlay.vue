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
const { phase, hangup, submitTypification, close } = useClickToCall();
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

// Saved-mid-call marker: when the agent already accepted DURING the call, the
// overlay closes itself at hang-up instead of asking again.
const savedDuringCall = ref(false);

// The form is available from the moment the call starts (typify while talking),
// and its values survive the calling → typify transition (reset only on close).
watch(phase, value => {
  if (value === 'calling' || value === 'typify') loadTypifications();
  if (value === 'typify' && savedDuringCall.value) {
    close();
    return;
  }
  if (value === null) {
    selectedTypificationId.value = null;
    managementStateId.value = null;
    managementGroup.value = null;
    managementAnswers.value = {};
    note.value = '';
    savedDuringCall.value = false;
  }
});

// Reset answers/note when switching management state so stale answers don't leak across states.
watch(managementStateId, () => {
  managementAnswers.value = {};
});

// Any edit after a mid-call save invalidates the marker, so the typify phase
// reopens at hang-up and the agent can re-save the changes.
watch(
  [selectedTypificationId, managementStateId, managementAnswers, note],
  () => {
    savedDuringCall.value = false;
  }
);

const accept = async () => {
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
  const duringCall = phase.value === 'calling';
  const ok = await submitTypification(
    {
      typificationId: selectedTypificationId.value,
      note: note.value,
      management,
    },
    { keepOpen: duringCall }
  );
  if (ok && duringCall) savedDuringCall.value = true;
};
</script>

<template>
  <div
    v-show="phase"
    class="fixed bottom-6 right-6 z-50 w-96 rounded-xl bg-n-solid-2 shadow-xl border border-n-weak overflow-hidden"
  >
    <!-- Un solo cuadro: el formulario de tipificación está disponible DESDE que
         inicia la llamada (se tipifica mientras se habla) y conserva lo escrito
         al colgar. Sin bloque de info del cliente (se llamó desde su ficha). -->
    <template v-if="phase">
      <div
        class="px-4 py-2.5 flex items-center justify-between gap-2"
        :class="
          phase === 'calling'
            ? 'bg-n-brand text-white'
            : 'border-b border-n-weak'
        "
      >
        <p
          class="text-sm font-medium"
          :class="phase === 'calling' ? '' : 'text-n-slate-12'"
        >
          {{
            phase === 'calling'
              ? t('JABVOX_CLICK_TO_CALL.IN_CALL')
              : t('JABVOX_CLICK_TO_CALL.TYPIFY_TITLE')
          }}
        </p>
        <button
          v-if="phase === 'calling'"
          class="px-3 py-1.5 rounded-lg bg-n-ruby-9 text-white text-xs font-medium shrink-0"
          @click="hangup"
        >
          {{ t('JABVOX_CLICK_TO_CALL.HANG_UP') }}
        </button>
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

        <!-- Dynamic questions for the chosen management state.
             The overlay body already scrolls, so let the form flow (no inner cap). -->
        <ManagementQuestionsForm
          v-if="selectedManagementState"
          v-model="managementAnswers"
          :state="selectedManagementState"
          max-body-height="none"
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
      <div
        class="p-4 flex items-center justify-between gap-2 border-t border-n-weak"
      >
        <!-- Guardada en medio de la llamada: al colgar el cuadro se cierra solo -->
        <span
          v-if="savedDuringCall"
          class="inline-flex items-center gap-1 text-xs text-n-teal-11"
        >
          <span class="i-lucide-check-circle size-3.5" />
          {{ t('JABVOX_CLICK_TO_CALL.SAVED_DURING_CALL') }}
        </span>
        <span v-else />
        <div class="flex items-center gap-2">
          <button
            v-if="phase === 'typify'"
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
            {{
              phase === 'calling'
                ? t('JABVOX_CLICK_TO_CALL.SAVE_DURING_CALL')
                : t('JABVOX_CLICK_TO_CALL.ACCEPT')
            }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
