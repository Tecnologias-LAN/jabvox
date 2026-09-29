<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ManagementQuestionsForm from 'dashboard/components/jabvox/managementStates/ManagementQuestionsForm.vue';
import contactDetailAPI from 'dashboard/api/jabvox/contactDetail';
import {
  isManagementValid,
  buildManagementContentAttributes,
  noteRule,
  stateGroups,
  statesInGroup,
  hasGroups,
  CALL_SOURCES,
} from 'dashboard/composables/jabvox/useManagementState';

// Diálogo para tipificar una gestión desde la ficha del contacto. Reutiliza la misma
// maquinaria que el detalle de lead, el dialer y kanban (estados agrupados, preguntas
// condicionales, regla de nota), así que una gestión creada aquí es indistinguible de una
// creada desde cualquier otro origen salvo por su `jabvox_call_source`.
const props = defineProps({
  contactId: { type: [Number, String], required: true },
  contact: { type: Object, default: null },
  states: { type: Array, default: () => [] },
});

const emit = defineEmits(['created', 'close']);

const { t } = useI18n();

const group = ref(null);
const stateId = ref(null);
const answers = ref({});
const note = ref('');
const isSaving = ref(false);

const grouped = computed(() => hasGroups(props.states));
const groups = computed(() => stateGroups(props.states));
const statesForGroup = computed(() =>
  grouped.value ? statesInGroup(props.states, group.value) : props.states
);
const selectedState = computed(
  () => props.states.find(s => s.id === stateId.value) || null
);
const rule = computed(() => noteRule(selectedState.value));

// Cambiar de grupo invalida el subestado elegido: pertenecía al grupo anterior.
watch(group, () => {
  stateId.value = null;
  answers.value = {};
});
watch(stateId, () => {
  answers.value = {};
});

const canSave = computed(() => {
  if (isSaving.value) return false;
  if (props.states.length && !stateId.value) return false;
  return isManagementValid(selectedState.value, answers.value, note.value);
});

const save = async () => {
  if (!canSave.value) return;
  isSaving.value = true;
  try {
    const { data } = await contactDetailAPI.createManagement(props.contactId, {
      content: note.value.trim() || selectedState.value?.name_jabvox || '',
      content_attributes: buildManagementContentAttributes(
        selectedState.value,
        answers.value,
        CALL_SOURCES.CONTACT_DETAIL
      ),
    });
    useAlert(t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.SAVED'));
    emit('created', data.management);
    emit('close');
  } catch {
    useAlert(t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
    @click.self="emit('close')"
  >
    <div
      class="flex flex-col w-full max-w-md max-h-[85vh] rounded-xl bg-n-solid-1 border border-n-weak shadow-lg"
    >
      <header
        class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak flex-shrink-0"
      >
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.TITLE') }}
        </h3>
        <Button
          icon="i-lucide-x"
          variant="ghost"
          size="xs"
          :aria-label="t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.CLOSE')"
          @click="emit('close')"
        />
      </header>

      <div class="flex-1 overflow-y-auto min-h-0 px-4 py-3 flex flex-col gap-3">
        <!-- Estado agrupado: primero el grupo, luego el subestado -->
        <div v-if="grouped" class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.GROUP') }}
          </label>
          <select
            v-model="group"
            class="w-full h-9 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-3"
          >
            <option :value="null">
              {{ t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.SELECT') }}
            </option>
            <option v-for="g in groups" :key="g" :value="g">
              {{ g || t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.NO_GROUP') }}
            </option>
          </select>
        </div>

        <div v-if="states.length" class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.STATE') }}
          </label>
          <select
            v-model="stateId"
            :disabled="grouped && !group"
            class="w-full h-9 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-3 disabled:opacity-50"
          >
            <option :value="null">
              {{ t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.SELECT') }}
            </option>
            <option v-for="s in statesForGroup" :key="s.id" :value="s.id">
              {{ s.name_jabvox }}
            </option>
          </select>
        </div>

        <ManagementQuestionsForm
          v-if="selectedState"
          v-model="answers"
          :state="selectedState"
          :contact="contact"
          max-body-height="18rem"
        />

        <div v-if="!rule.hidden" class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{
              rule.required
                ? t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.NOTE_REQUIRED')
                : t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.NOTE')
            }}
          </label>
          <textarea
            v-model="note"
            rows="3"
            class="w-full rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-3 py-2 resize-none"
            :placeholder="t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.NOTE_HINT')"
          />
        </div>
      </div>

      <footer
        class="flex items-center justify-end gap-2 px-4 py-3 border-t border-n-weak flex-shrink-0"
      >
        <Button
          :label="t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.CANCEL')"
          variant="faded"
          size="sm"
          @click="emit('close')"
        />
        <Button
          :label="t('JABVOX_CONTACTS.DETAIL.MANAGEMENT.SAVE')"
          size="sm"
          :is-loading="isSaving"
          :disabled="!canSave"
          @click="save"
        />
      </footer>
    </div>
  </div>
</template>
