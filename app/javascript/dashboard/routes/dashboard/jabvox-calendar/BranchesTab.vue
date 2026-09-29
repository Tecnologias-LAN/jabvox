<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';
import calendarAPI from 'dashboard/api/jabvox/calendar';

// Sedes donde se atiende: consultorio, sucursal, local… el nombre lo pone cada cliente.
//
// Cada sede aporta dos cosas a la agenda: su ZONA HORARIA y su HORARIO COMERCIAL, que se
// sombrea en las vistas de semana y día. Los agentes cubren tramos dentro de ese horario,
// así que la sede dice cuándo está abierto y la disponibilidad del agente cuándo está él.
//
// Solo el administrador puede crear y editar; el resto las ve para poder filtrar.
const { t } = useI18n();
const { isAdmin } = useAdmin();
const agents = useMapGetter('agents/getAgents');

const branches = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const editing = ref(null);

const DAYS = [0, 1, 2, 3, 4, 5, 6];
const DAY_KEYS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

// Solo las zonas que se usan de verdad: una lista con las 400 de IANA no ayuda a nadie.
const TIMEZONES = [
  'America/Bogota',
  'America/Mexico_City',
  'America/Lima',
  'America/Santiago',
  'America/Argentina/Buenos_Aires',
  'America/New_York',
  'Europe/Madrid',
  'UTC',
];

const minutesToTime = m =>
  `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

const timeToMinutes = value => {
  const [h, m] = String(value || '0:0')
    .split(':')
    .map(Number);
  return h * 60 + (m || 0);
};

// Una fila por día con sus franjas. Sin franjas = cerrado ese día.
const emptyHours = () => DAYS.map(day => ({ day, ranges: [] }));

const buildForm = branch => ({
  id: branch?.id || null,
  name_jabvox: branch?.name_jabvox || '',
  timezone_jabvox: branch?.timezone_jabvox || 'America/Bogota',
  color_jabvox: branch?.color_jabvox || '#6366F1',
  address_jabvox: branch?.address_jabvox || '',
  active_jabvox: branch?.active_jabvox ?? true,
  manager_ids: [...(branch?.manager_ids || [])],
  hours: emptyHours().map(row => ({
    ...row,
    ranges: (branch?.hours || [])
      .filter(h => h.day_of_week === row.day)
      .map(h => ({
        open: minutesToTime(h.open_minute),
        close: minutesToTime(h.close_minute),
      })),
  })),
});

const form = ref(buildForm(null));

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await calendarAPI.getBranches();
    branches.value = data;
  } catch {
    useAlert(t('JABVOX_CALENDAR.BRANCHES.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);

const openCreate = () => {
  editing.value = 'new';
  form.value = buildForm(null);
};

const openEdit = branch => {
  editing.value = branch.id;
  form.value = buildForm(branch);
};

// Jornada partida: cada día admite varias franjas (mañana y tarde con pausa de comida).
const addRange = row => {
  row.ranges.push({ open: '09:00', close: '18:00' });
};

const removeRange = (row, idx) => {
  row.ranges.splice(idx, 1);
};

const toggleManager = id => {
  const idx = form.value.manager_ids.indexOf(id);
  if (idx === -1) form.value.manager_ids.push(id);
  else form.value.manager_ids.splice(idx, 1);
};

const payload = computed(() => ({
  branch: {
    name_jabvox: form.value.name_jabvox.trim(),
    timezone_jabvox: form.value.timezone_jabvox,
    color_jabvox: form.value.color_jabvox,
    address_jabvox: form.value.address_jabvox,
    active_jabvox: form.value.active_jabvox,
  },
  manager_ids: form.value.manager_ids,
  hours: form.value.hours.flatMap(row =>
    row.ranges.map(r => ({
      day_of_week: row.day,
      open_minute: timeToMinutes(r.open),
      close_minute: timeToMinutes(r.close),
    }))
  ),
}));

const save = async () => {
  if (!form.value.name_jabvox.trim() || isSaving.value) return;
  isSaving.value = true;
  try {
    if (form.value.id) {
      await calendarAPI.updateBranch(form.value.id, payload.value);
    } else {
      await calendarAPI.createBranch(payload.value);
    }
    editing.value = null;
    await load();
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.[0] ||
        t('JABVOX_CALENDAR.BRANCHES.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const remove = async branch => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('JABVOX_CALENDAR.BRANCHES.DELETE_CONFIRM', { name: branch.name_jabvox })
    )
  )
    return;
  try {
    await calendarAPI.destroyBranch(branch.id);
    await load();
  } catch {
    useAlert(t('JABVOX_CALENDAR.BRANCHES.DELETE_ERROR'));
  }
};

const summary = branch => {
  const days = new Set((branch.hours || []).map(h => h.day_of_week));
  return t('JABVOX_CALENDAR.BRANCHES.SUMMARY', { count: days.size });
};
</script>

<template>
  <div class="flex flex-col h-full min-h-0 overflow-y-auto p-4 sm:p-5">
    <div class="flex flex-wrap items-center justify-between gap-2 mb-4">
      <div class="min-w-0">
        <h2 class="text-base font-semibold text-n-slate-12">
          {{ t('JABVOX_CALENDAR.BRANCHES.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-10 mt-0.5">
          {{ t('JABVOX_CALENDAR.BRANCHES.SUBTITLE') }}
        </p>
      </div>
      <button
        v-if="isAdmin"
        type="button"
        class="flex items-center gap-1.5 px-3 h-9 rounded-lg bg-n-brand text-white text-sm font-medium"
        @click="openCreate"
      >
        <span class="i-lucide-plus size-4" aria-hidden="true" />
        {{ t('JABVOX_CALENDAR.BRANCHES.NEW') }}
      </button>
    </div>

    <p v-if="isLoading" class="text-sm text-n-slate-10">
      {{ t('JABVOX_CALENDAR.BRANCHES.LOADING') }}
    </p>

    <!-- Sin sedes el calendario funciona igual: se usa cuando hay más de un sitio. -->
    <div
      v-else-if="!branches.length && editing === null"
      class="flex flex-col items-center justify-center py-12 text-center gap-2"
    >
      <span class="i-lucide-map-pin size-8 text-n-slate-8" aria-hidden="true" />
      <p class="text-sm text-n-slate-10">
        {{ t('JABVOX_CALENDAR.BRANCHES.EMPTY') }}
      </p>
    </div>

    <div v-else class="space-y-2">
      <div
        v-for="branch in branches"
        :key="branch.id"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-3"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex items-start gap-2.5 min-w-0">
            <span
              class="size-3 rounded-full mt-1 shrink-0"
              :style="{ background: branch.color_jabvox }"
            />
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ branch.name_jabvox }}
                <span
                  v-if="!branch.active_jabvox"
                  class="ml-1 text-[10px] px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-10"
                >
                  {{ t('JABVOX_CALENDAR.BRANCHES.INACTIVE') }}
                </span>
              </p>
              <p class="text-[11px] text-n-slate-10">
                {{ branch.timezone_jabvox }} · {{ summary(branch) }}
              </p>
              <p
                v-if="branch.manager_names?.length"
                class="text-[11px] text-n-slate-10 truncate"
              >
                {{ t('JABVOX_CALENDAR.BRANCHES.MANAGERS') }}:
                {{ branch.manager_names.join(', ') }}
              </p>
            </div>
          </div>
          <div v-if="isAdmin" class="flex items-center gap-1 shrink-0">
            <button
              type="button"
              class="p-1.5 rounded text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('JABVOX_CALENDAR.BRANCHES.EDIT')"
              @click="openEdit(branch)"
            >
              <span class="i-lucide-pencil size-4" aria-hidden="true" />
            </button>
            <button
              type="button"
              class="p-1.5 rounded text-n-ruby-11 hover:bg-n-alpha-2"
              :title="t('JABVOX_CALENDAR.BRANCHES.DELETE')"
              @click="remove(branch)"
            >
              <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Formulario -->
    <div
      v-if="editing !== null"
      class="mt-4 rounded-xl border border-n-brand/30 bg-n-solid-1 p-4 space-y-4"
    >
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{
          form.id
            ? t('JABVOX_CALENDAR.BRANCHES.EDIT_TITLE')
            : t('JABVOX_CALENDAR.BRANCHES.NEW_TITLE')
        }}
      </h3>

      <div class="grid gap-3 sm:grid-cols-2">
        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1">
            {{ t('JABVOX_CALENDAR.BRANCHES.NAME') }}
          </label>
          <input
            v-model="form.name_jabvox"
            type="text"
            :placeholder="t('JABVOX_CALENDAR.BRANCHES.NAME_PLACEHOLDER')"
            class="w-full h-9 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2.5"
          />
        </div>
        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1">
            {{ t('JABVOX_CALENDAR.BRANCHES.TIMEZONE') }}
          </label>
          <select
            v-model="form.timezone_jabvox"
            class="w-full h-9 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2"
          >
            <option v-for="tz in TIMEZONES" :key="tz" :value="tz">
              {{ tz }}
            </option>
          </select>
        </div>
        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1">
            {{ t('JABVOX_CALENDAR.BRANCHES.ADDRESS') }}
          </label>
          <input
            v-model="form.address_jabvox"
            type="text"
            class="w-full h-9 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2.5"
          />
        </div>
        <div class="flex items-end gap-3">
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1">
              {{ t('JABVOX_CALENDAR.BRANCHES.COLOR') }}
            </label>
            <input
              v-model="form.color_jabvox"
              type="color"
              class="h-9 w-14 rounded-lg border border-n-weak bg-n-alpha-1"
            />
          </div>
          <label
            class="flex items-center gap-2 text-sm text-n-slate-11 h-9 cursor-pointer"
          >
            <input
              v-model="form.active_jabvox"
              type="checkbox"
              class="rounded accent-n-brand"
            />
            {{ t('JABVOX_CALENDAR.BRANCHES.ACTIVE') }}
          </label>
        </div>
      </div>

      <!-- Responsables: informativo, no concede permisos sobre las citas. -->
      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1">
          {{ t('JABVOX_CALENDAR.BRANCHES.MANAGERS') }}
          <span class="font-normal text-n-slate-10">
            ({{ t('JABVOX_CALENDAR.BRANCHES.MANAGERS_HINT') }})
          </span>
        </label>
        <div class="flex flex-wrap gap-2">
          <label
            v-for="a in agents"
            :key="a.id"
            class="flex items-center gap-1.5 text-xs text-n-slate-11 px-2 py-1 rounded-lg border border-n-weak cursor-pointer"
            :class="
              form.manager_ids.includes(a.id)
                ? 'bg-n-brand/10 border-n-brand/40'
                : ''
            "
          >
            <input
              type="checkbox"
              class="rounded accent-n-brand"
              :checked="form.manager_ids.includes(a.id)"
              @change="toggleManager(a.id)"
            />
            {{ a.name }}
          </label>
        </div>
      </div>

      <!-- Horario comercial: varias franjas por día para la jornada partida. -->
      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-2">
          {{ t('JABVOX_CALENDAR.BRANCHES.HOURS') }}
          <span class="font-normal text-n-slate-10">
            ({{ t('JABVOX_CALENDAR.BRANCHES.HOURS_HINT') }})
          </span>
        </label>
        <div class="space-y-1.5">
          <div
            v-for="row in form.hours"
            :key="row.day"
            class="flex flex-wrap items-center gap-2 py-1"
          >
            <span class="w-20 shrink-0 text-xs text-n-slate-11">
              {{ t(`JABVOX_CALENDAR.DAYS.${DAY_KEYS[row.day]}`) }}
            </span>
            <div
              v-for="(range, idx) in row.ranges"
              :key="idx"
              class="flex items-center gap-1"
            >
              <input
                v-model="range.open"
                type="time"
                class="h-8 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-xs text-n-slate-12 px-1.5"
              />
              <span class="text-xs text-n-slate-10">–</span>
              <input
                v-model="range.close"
                type="time"
                class="h-8 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-xs text-n-slate-12 px-1.5"
              />
              <button
                type="button"
                class="p-1 rounded text-n-ruby-11 hover:bg-n-alpha-2"
                @click="removeRange(row, idx)"
              >
                <span class="i-lucide-x size-3.5" aria-hidden="true" />
              </button>
            </div>
            <button
              type="button"
              class="flex items-center gap-1 text-[11px] text-n-brand hover:underline"
              @click="addRange(row)"
            >
              <span class="i-lucide-plus size-3" aria-hidden="true" />
              {{
                row.ranges.length
                  ? t('JABVOX_CALENDAR.BRANCHES.ADD_RANGE')
                  : t('JABVOX_CALENDAR.BRANCHES.CLOSED')
              }}
            </button>
          </div>
        </div>
      </div>

      <div class="flex justify-end gap-2 pt-1">
        <button
          type="button"
          class="px-3 h-9 rounded-lg border border-n-weak text-sm text-n-slate-11"
          @click="editing = null"
        >
          {{ t('JABVOX_CALENDAR.CANCEL') }}
        </button>
        <button
          type="button"
          class="px-4 h-9 rounded-lg bg-n-brand text-white text-sm font-medium disabled:opacity-50"
          :disabled="!form.name_jabvox.trim() || isSaving"
          @click="save"
        >
          {{ isSaving ? '…' : t('JABVOX_CALENDAR.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>
