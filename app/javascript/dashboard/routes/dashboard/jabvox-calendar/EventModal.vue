<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import calendarAPI from 'dashboard/api/jabvox/calendar';

const props = defineProps({
  event: { type: Object, default: null },
  initialDate: { type: Date, default: () => new Date() },
  agents: { type: Array, default: () => [] },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const externalPeople = useMapGetter('jabvoxCalendar/getExternalPeople');

// Sedes para elegir dónde se atiende. Con una sola no se pregunta: el selector se oculta
// y la cita se queda sin sede, que es lo correcto cuando no hay nada que distinguir.
const branches = ref([]);
onMounted(async () => {
  try {
    const { data } = await calendarAPI.getBranches();
    branches.value = data.filter(b => b.active_jabvox);
  } catch {
    // Sin sedes el formulario funciona igual.
  }
});

const isEditing = computed(() => !!props.event);

// La cita de otro agente se abre en solo lectura: el backend ya devuelve `can_manage` y
// rechaza la mutación con 403, así que aquí no se decide el permiso, solo se refleja. Una
// cita nueva siempre es editable.
const isReadOnly = computed(
  () => isEditing.value && props.event?.can_manage === false
);

const pad = n => String(n).padStart(2, '0');
function dateStr(d) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
function timeStr(d) {
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function slotFromDate(d) {
  // La hora de fin se calcula sumando una hora a la fecha, no al número de horas: con
  // `getHours() + 1` a las 23:30 salía "24:30", que el input de tipo hora rechaza y
  // dejaba vacío, y de ahí una fecha inválida al guardar.
  const end = new Date(d.getTime() + 60 * 60 * 1000);
  return {
    date: dateStr(d),
    start_time: timeStr(d),
    end_time: timeStr(end),
  };
}

// ─── form ──────────────────────────────────────────────────────────────────
const COLOR_OPTIONS = [
  '#3B82F6',
  '#10B981',
  '#F59E0B',
  '#EF4444',
  '#8B5CF6',
  '#EC4899',
  '#06B6D4',
  '#84CC16',
];

function buildInitial() {
  if (props.event) {
    const d = new Date(props.event.start_at);
    const de = new Date(props.event.end_at);
    return {
      title: props.event.title,
      description: props.event.description || '',
      note: props.event.note || '',
      event_type: props.event.event_type,
      status: props.event.status,
      color: props.event.color,
      branch_id: props.event.branch_id || null,
      all_day: props.event.all_day,
      slots: [
        {
          date: dateStr(d),
          start_time: timeStr(d),
          end_time: timeStr(de),
        },
      ],
      participants: (props.event.participants || []).map(p => ({
        user_id: p.user_id,
        external_person_id: p.external_person_id,
        kind: p.kind,
        name: p.name,
        note: p.note || '',
      })),
    };
  }
  return {
    title: '',
    description: '',
    note: '',
    event_type: 'appointment',
    status: 'pending',
    color: '#3B82F6',
    branch_id: null,
    all_day: false,
    slots: [slotFromDate(props.initialDate)],
    participants: [],
  };
}

const form = ref(buildInitial());
const formError = ref('');
const isSaving = ref(false);

// ─── slots (multi-franja) ────────────────────────────────────────────────────
function addSlot() {
  const last = form.value.slots[form.value.slots.length - 1];
  form.value.slots.push({ ...last });
}
function removeSlot(idx) {
  if (form.value.slots.length > 1) form.value.slots.splice(idx, 1);
}

// ─── participants ────────────────────────────────────────────────────────────
const addParticipantType = ref('team'); // team | external
const selectedAgentId = ref(null);
const selectedExternalId = ref(null);

const availableAgents = computed(() =>
  props.agents.filter(
    a => !form.value.participants.some(p => p.user_id === a.id)
  )
);
const availableExternals = computed(() =>
  externalPeople.value.filter(
    e => !form.value.participants.some(p => p.external_person_id === e.id)
  )
);

function addParticipant() {
  if (addParticipantType.value === 'team' && selectedAgentId.value) {
    const agent = props.agents.find(a => a.id === selectedAgentId.value);
    form.value.participants.push({
      user_id: agent.id,
      kind: 'team',
      name: agent.name,
      note: '',
    });
    selectedAgentId.value = null;
  } else if (
    addParticipantType.value === 'external' &&
    selectedExternalId.value
  ) {
    const person = externalPeople.value.find(
      e => e.id === selectedExternalId.value
    );
    form.value.participants.push({
      external_person_id: person.id,
      kind: 'external',
      name: person.name,
      note: '',
    });
    selectedExternalId.value = null;
  }
}
function removeParticipant(idx) {
  form.value.participants.splice(idx, 1);
}

// ─── save ──────────────────────────────────────────────────────────────────
function buildSlots() {
  return form.value.slots.map(s => {
    // Un evento de todo el día ocupa el día entero: 00:00 a 23:59. Antes se guardaba con
    // la hora que hubiera quedado en el formulario —los selectores se ocultan pero su
    // valor no se limpia—, así que empezaba a media tarde.
    const startAt = form.value.all_day
      ? new Date(`${s.date}T00:00:00`)
      : new Date(`${s.date}T${s.start_time}:00`);
    const endAt = form.value.all_day
      ? new Date(`${s.date}T23:59:00`)
      : new Date(`${s.date}T${s.end_time}:00`);
    return {
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
      all_day: form.value.all_day,
    };
  });
}

function buildParticipants() {
  return form.value.participants.map(p => ({
    user_id: p.user_id || null,
    external_person_id: p.external_person_id || null,
    note: p.note || form.value.note || '',
  }));
}

async function save() {
  if (!form.value.title.trim()) {
    formError.value = t('JABVOX_CALENDAR.ERRORS.TITLE_REQUIRED');
    return;
  }
  formError.value = '';
  isSaving.value = true;
  try {
    const base = {
      title: form.value.title.trim(),
      description: form.value.description,
      note: form.value.note,
      event_type: form.value.event_type,
      status: form.value.status,
      color: form.value.color,
      branch_id: form.value.branch_id,
      all_day: form.value.all_day,
    };

    if (isEditing.value) {
      const slot = buildSlots()[0];
      await store.dispatch('jabvoxCalendar/updateEvent', {
        id: props.event.id,
        ...base,
        start_at: slot.start_at,
        end_at: slot.end_at,
        participants: buildParticipants(),
      });
    } else {
      const created = await store.dispatch('jabvoxCalendar/createEvent', {
        ...base,
        slots: buildSlots(),
        participants: buildParticipants(),
      });
      if (created.length > 1) {
        useAlert(
          t('JABVOX_CALENDAR.CREATED_MULTIPLE', { count: created.length })
        );
      }
    }
    emit('close');
  } catch {
    formError.value = t('JABVOX_CALENDAR.ERRORS.SAVE_FAILED');
  } finally {
    isSaving.value = false;
  }
}

async function remove() {
  await store.dispatch('jabvoxCalendar/deleteEvent', {
    id: props.event.id,
    scope: props.event.recurrence_group_id ? 'group' : null,
  });
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4 py-6 overflow-y-auto"
      @click.self="emit('close')"
    >
      <div
        class="w-full max-w-lg rounded-2xl bg-n-surface-2 border border-n-weak shadow-xl my-auto"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <h2 class="font-semibold text-n-slate-12">
            {{
              isEditing
                ? t('JABVOX_CALENDAR.EDIT_EVENT')
                : t('JABVOX_CALENDAR.NEW_EVENT')
            }}
          </h2>
          <button
            class="p-1.5 rounded hover:bg-n-alpha-black2"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-4 text-n-slate-11" />
          </button>
        </div>

        <form
          class="p-5 space-y-4 max-h-[70vh] overflow-y-auto"
          @submit.prevent="save"
        >
          <!-- Un solo fieldset deshabilita los 13 campos de golpe cuando la cita es de
               otro: ir campo por campo se rompe en cuanto se añade uno nuevo. -->
          <fieldset :disabled="isReadOnly" class="space-y-4 border-0 p-0 m-0">
            <p
              v-if="isReadOnly"
              class="flex items-center gap-2 text-xs text-n-slate-11 bg-n-alpha-black2 rounded-lg px-3 py-2"
            >
              <span class="i-lucide-eye size-4 shrink-0" />
              {{ t('JABVOX_CALENDAR.READ_ONLY') }}
            </p>

            <!-- Title -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.FORM.TITLE_LABEL') }}
              </label>
              <input
                v-model="form.title"
                type="text"
                :placeholder="t('JABVOX_CALENDAR.FORM.TITLE_PLACEHOLDER')"
                class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>

            <!-- Type + Status -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-n-slate-12 mb-1">
                  {{ t('JABVOX_CALENDAR.FORM.TYPE_LABEL') }}
                </label>
                <select
                  v-model="form.event_type"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option value="reminder">
                    {{ t('JABVOX_CALENDAR.TYPES.reminder') }}
                  </option>
                  <option value="appointment">
                    {{ t('JABVOX_CALENDAR.TYPES.appointment') }}
                  </option>
                  <option value="task">
                    {{ t('JABVOX_CALENDAR.TYPES.task') }}
                  </option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-n-slate-12 mb-1">
                  {{ t('JABVOX_CALENDAR.FORM.STATUS_LABEL') }}
                </label>
                <select
                  v-model="form.status"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option value="pending">
                    {{ t('JABVOX_CALENDAR.STATUS.pending') }}
                  </option>
                  <option value="done">
                    {{ t('JABVOX_CALENDAR.STATUS.done') }}
                  </option>
                  <option value="cancelled">
                    {{ t('JABVOX_CALENDAR.STATUS.cancelled') }}
                  </option>
                </select>
              </div>
            </div>

            <!-- All day -->
            <label class="flex items-center gap-2 cursor-pointer">
              <input v-model="form.all_day" type="checkbox" class="rounded" />
              <span class="text-sm text-n-slate-12">{{
                t('JABVOX_CALENDAR.FORM.ALL_DAY')
              }}</span>
            </label>

            <!-- Slots (multi-franja) -->
            <div>
              <div class="flex items-center justify-between mb-1.5">
                <label class="block text-sm font-medium text-n-slate-12">
                  {{ t('JABVOX_CALENDAR.FORM.SLOTS_LABEL') }}
                </label>
                <button
                  v-if="!isEditing"
                  type="button"
                  class="flex items-center gap-1 text-xs text-n-brand hover:underline"
                  @click="addSlot"
                >
                  <span class="i-lucide-plus size-3.5" />
                  {{ t('JABVOX_CALENDAR.FORM.ADD_SLOT') }}
                </button>
              </div>
              <div
                v-for="(slot, idx) in form.slots"
                :key="idx"
                class="flex items-center gap-2 mb-2"
              >
                <input
                  v-model="slot.date"
                  type="date"
                  class="flex-1 h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                />
                <template v-if="!form.all_day">
                  <input
                    v-model="slot.start_time"
                    type="time"
                    class="w-24 h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                  />
                  <span class="text-n-slate-10">–</span>
                  <input
                    v-model="slot.end_time"
                    type="time"
                    class="w-24 h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                  />
                </template>
                <button
                  v-if="form.slots.length > 1"
                  type="button"
                  class="p-1.5 rounded hover:bg-n-ruby-3 shrink-0"
                  @click="removeSlot(idx)"
                >
                  <span class="i-lucide-trash-2 size-4 text-n-ruby-9" />
                </button>
              </div>
              <p v-if="!isEditing" class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_CALENDAR.FORM.SLOTS_HINT') }}
              </p>
            </div>

            <!-- Participants -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1.5">
                {{ t('JABVOX_CALENDAR.FORM.PARTICIPANTS_LABEL') }}
              </label>
              <!-- chips -->
              <div
                v-if="form.participants.length"
                class="flex flex-col gap-1.5 mb-2"
              >
                <div
                  v-for="(p, idx) in form.participants"
                  :key="idx"
                  class="flex items-center gap-2"
                >
                  <span
                    class="inline-flex items-center gap-1 text-xs px-2 py-1 rounded-full shrink-0"
                    :class="
                      p.kind === 'team'
                        ? 'bg-n-brand/10 text-n-brand'
                        : 'bg-n-teal-3 text-n-teal-11'
                    "
                  >
                    <span
                      class="size-3"
                      :class="
                        p.kind === 'team'
                          ? 'i-lucide-user'
                          : 'i-lucide-user-plus'
                      "
                    />
                    {{ p.name }}
                  </span>
                  <input
                    v-model="p.note"
                    type="text"
                    :placeholder="t('JABVOX_CALENDAR.FORM.PARTICIPANT_NOTE')"
                    class="flex-1 h-8 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-xs text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
                  />
                  <button
                    type="button"
                    class="p-1 rounded hover:bg-n-ruby-3 shrink-0"
                    @click="removeParticipant(idx)"
                  >
                    <span class="i-lucide-x size-3.5 text-n-ruby-9" />
                  </button>
                </div>
              </div>
              <!-- add row -->
              <div class="flex items-center gap-2">
                <select
                  v-model="addParticipantType"
                  class="w-24 h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option value="team">
                    {{ t('JABVOX_CALENDAR.FORM.TEAM') }}
                  </option>
                  <option value="external">
                    {{ t('JABVOX_CALENDAR.FORM.EXTERNAL') }}
                  </option>
                </select>
                <select
                  v-if="addParticipantType === 'team'"
                  v-model="selectedAgentId"
                  class="flex-1 h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option :value="null">
                    {{ t('JABVOX_CALENDAR.FORM.SELECT_AGENT') }}
                  </option>
                  <option
                    v-for="a in availableAgents"
                    :key="a.id"
                    :value="a.id"
                  >
                    {{ a.name }}
                  </option>
                </select>
                <select
                  v-else
                  v-model="selectedExternalId"
                  class="flex-1 h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option :value="null">
                    {{ t('JABVOX_CALENDAR.FORM.SELECT_EXTERNAL') }}
                  </option>
                  <option
                    v-for="e in availableExternals"
                    :key="e.id"
                    :value="e.id"
                  >
                    {{ e.name }}
                  </option>
                </select>
                <button
                  type="button"
                  class="h-9 px-3 rounded-lg bg-n-alpha-black2 text-sm text-n-slate-12 hover:bg-n-alpha-black3 shrink-0"
                  @click="addParticipant"
                >
                  {{ t('JABVOX_CALENDAR.FORM.ADD') }}
                </button>
              </div>
            </div>

            <!-- Note (auto-attached to participants) -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.FORM.NOTE_LABEL') }}
              </label>
              <textarea
                v-model="form.note"
                rows="2"
                :placeholder="t('JABVOX_CALENDAR.FORM.NOTE_PLACEHOLDER')"
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 resize-none focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>

            <!-- Description -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.FORM.DESCRIPTION_LABEL') }}
              </label>
              <textarea
                v-model="form.description"
                rows="2"
                :placeholder="t('JABVOX_CALENDAR.FORM.DESCRIPTION_PLACEHOLDER')"
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 resize-none focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>

            <!-- Sede: con una sola no se pregunta, no hay nada que elegir. -->
            <div v-if="branches.length > 1">
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.FORM.BRANCH_LABEL') }}
              </label>
              <select
                v-model="form.branch_id"
                class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              >
                <option :value="null">
                  {{ t('JABVOX_CALENDAR.FORM.BRANCH_NONE') }}
                </option>
                <option v-for="b in branches" :key="b.id" :value="b.id">
                  {{ b.name_jabvox }}
                </option>
              </select>
            </div>

            <!-- Color -->
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-2">
                {{ t('JABVOX_CALENDAR.FORM.COLOR_LABEL') }}
              </label>
              <div class="flex gap-2 flex-wrap">
                <button
                  v-for="c in COLOR_OPTIONS"
                  :key="c"
                  type="button"
                  class="w-6 h-6 rounded-full transition-all"
                  :style="{ background: c }"
                  :class="
                    form.color === c ? 'ring-2 ring-n-brand ring-offset-1' : ''
                  "
                  @click="form.color = c"
                />
              </div>
            </div>

            <p
              v-if="formError"
              class="text-sm text-n-ruby-9 rounded-lg bg-n-ruby-3 px-3 py-2"
            >
              {{ formError }}
            </p>
          </fieldset>

          <!-- Sin permiso no se ofrecen acciones que el backend va a rechazar: solo se
               cierra la ficha. -->
          <div v-if="isReadOnly" class="flex justify-end pt-1">
            <button
              type="button"
              class="px-4 h-9 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-black2 transition-colors"
              @click="emit('close')"
            >
              {{ t('JABVOX_CALENDAR.CLOSE') }}
            </button>
          </div>

          <div v-else class="flex items-center justify-between pt-1">
            <button
              v-if="isEditing"
              type="button"
              class="flex items-center gap-1.5 text-sm text-n-ruby-9 hover:text-n-ruby-10"
              @click="remove"
            >
              <span class="i-lucide-trash-2 size-4" />
              {{ t('JABVOX_CALENDAR.DELETE_EVENT') }}
            </button>
            <div v-else />
            <div class="flex gap-2">
              <button
                type="button"
                class="px-4 h-9 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-black2 transition-colors"
                @click="emit('close')"
              >
                {{ t('JABVOX_CALENDAR.CANCEL') }}
              </button>
              <button
                type="submit"
                :disabled="isSaving"
                class="px-4 h-9 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
              >
                {{ isSaving ? '...' : t('JABVOX_CALENDAR.SAVE') }}
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  </Teleport>
</template>
