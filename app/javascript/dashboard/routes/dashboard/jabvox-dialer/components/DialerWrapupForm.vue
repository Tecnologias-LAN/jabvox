<script setup>
// Reusable typification form for the dialer: management-state picker (flat or
// two-level Estado→Subestado), dynamic questions for the chosen state, the
// typification select and the note textarea. Shared by the in-call panel and the
// wrap-up panel so the logic never diverges between them.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ManagementQuestionsForm from 'dashboard/components/jabvox/managementStates/ManagementQuestionsForm.vue';
import {
  stateGroups,
  statesInGroup,
  hasGroups,
} from 'dashboard/composables/jabvox/useManagementState';

const props = defineProps({
  managementStates: { type: Array, default: () => [] },
  typifications: { type: Array, default: () => [] },
  // v-model bindings
  stateId: { type: [Number, String], default: null },
  group: { type: [String, null], default: null },
  answers: { type: Object, default: () => ({}) },
  typificationId: { type: [Number, String], default: null },
  note: { type: String, default: '' },
  hasConversation: { type: Boolean, default: true },
});

const emit = defineEmits([
  'update:stateId',
  'update:group',
  'update:answers',
  'update:typificationId',
  'update:note',
]);

const { t } = useI18n();

const managementHasGroups = computed(() => hasGroups(props.managementStates));
const managementGroups = computed(() => stateGroups(props.managementStates));
const groupStates = computed(() =>
  props.group === null ? [] : statesInGroup(props.managementStates, props.group)
);
const selectedState = computed(() =>
  (props.managementStates || []).find(s => s.id === props.stateId)
);

const selectGroup = g => {
  emit('update:group', props.group === g ? null : g);
};
const selectState = id => {
  emit('update:stateId', props.stateId === id ? null : id);
};
</script>

<template>
  <div class="space-y-3">
    <div v-if="managementStates.length > 0" class="space-y-2">
      <!-- Two-level picker: Estado (grupo) → Subestado -->
      <template v-if="managementHasGroups">
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="g in managementGroups"
            :key="`group-${g}`"
            class="text-sm px-3 py-1.5 rounded-full border transition-colors"
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
        <div v-if="group !== null" class="flex flex-wrap gap-1.5">
          <button
            v-for="s in groupStates"
            :key="s.id"
            class="text-sm px-3 py-1.5 rounded-full border transition-colors"
            :class="
              stateId === s.id
                ? 'text-white border-transparent'
                : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
            "
            :style="
              stateId === s.id
                ? {
                    backgroundColor: s.color_jabvox || '#6b7280',
                    borderColor: s.color_jabvox || '#6b7280',
                  }
                : {}
            "
            @click="selectState(s.id)"
          >
            {{ s.name_jabvox }}
          </button>
        </div>
      </template>
      <!-- Flat picker (accounts without groups) -->
      <div v-else class="flex flex-wrap gap-1.5">
        <button
          v-for="s in managementStates"
          :key="s.id"
          class="text-sm px-3 py-1.5 rounded-full border transition-colors"
          :class="
            stateId === s.id
              ? 'text-white border-transparent'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
          "
          :style="
            stateId === s.id
              ? {
                  backgroundColor: s.color_jabvox || '#6b7280',
                  borderColor: s.color_jabvox || '#6b7280',
                }
              : {}
          "
          @click="selectState(s.id)"
        >
          {{ s.name_jabvox }}
        </button>
      </div>
      <p
        v-if="selectedState?.usage_info_jabvox"
        class="text-xs text-n-slate-10"
      >
        {{ selectedState.usage_info_jabvox }}
      </p>
    </div>

    <ManagementQuestionsForm
      v-if="selectedState"
      :model-value="answers"
      :state="selectedState"
      @update:model-value="emit('update:answers', $event)"
    />

    <select
      v-if="typifications.length"
      :value="typificationId"
      class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
      @change="
        emit(
          'update:typificationId',
          $event.target.value ? Number($event.target.value) : null
        )
      "
    >
      <option :value="null">
        {{ t('JABVOX_DIALER.WRAPUP.TYPIFICATION_PLACEHOLDER') }}
      </option>
      <option v-for="tp in typifications" :key="tp.id" :value="tp.id">
        {{ tp.name }}
      </option>
    </select>

    <textarea
      :value="note"
      rows="3"
      class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm text-n-slate-12 placeholder:text-n-slate-9 resize-none focus:outline-none focus:ring-2 focus:ring-n-brand"
      :placeholder="t('JABVOX_DIALER.WRAPUP.NOTE_PLACEHOLDER')"
      @input="emit('update:note', $event.target.value)"
    />
    <p v-if="!hasConversation" class="text-xs text-n-slate-10">
      {{ t('JABVOX_DIALER.WRAPUP.NO_CONVERSATION') }}
    </p>
  </div>
</template>
