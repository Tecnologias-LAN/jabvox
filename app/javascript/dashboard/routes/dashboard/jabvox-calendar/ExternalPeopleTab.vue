<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const store = useStore();

const people = useMapGetter('jabvoxCalendar/getExternalPeople');
const uiFlags = useMapGetter('jabvoxCalendar/getUIFlags');

const showForm = ref(false);
const editing = ref(null);
const form = ref({
  name: '',
  email: '',
  phone_number: '',
  notes: '',
  color: '#0EA5E9',
});
const isSaving = ref(false);

onMounted(() => store.dispatch('jabvoxCalendar/fetchExternalPeople'));

function openCreate() {
  editing.value = null;
  form.value = {
    name: '',
    email: '',
    phone_number: '',
    notes: '',
    color: '#0EA5E9',
  };
  showForm.value = true;
}
function openEdit(person) {
  editing.value = person;
  form.value = {
    name: person.name,
    email: person.email || '',
    phone_number: person.phone_number || '',
    notes: person.notes || '',
    color: person.color || '#0EA5E9',
  };
  showForm.value = true;
}

async function save() {
  if (!form.value.name.trim()) return;
  isSaving.value = true;
  try {
    if (editing.value) {
      await store.dispatch('jabvoxCalendar/updateExternalPerson', {
        id: editing.value.id,
        ...form.value,
      });
    } else {
      await store.dispatch('jabvoxCalendar/createExternalPerson', form.value);
    }
    showForm.value = false;
    useAlert(t('JABVOX_CALENDAR.SETTINGS.SAVED'));
  } catch {
    useAlert(t('JABVOX_CALENDAR.ERRORS.SAVE_FAILED'));
  } finally {
    isSaving.value = false;
  }
}

async function remove(person) {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('JABVOX_CALENDAR.SETTINGS.DELETE_CONFIRM'))) return;
  await store.dispatch('jabvoxCalendar/deleteExternalPerson', person.id);
  useAlert(t('JABVOX_CALENDAR.SETTINGS.DELETED'));
}
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto p-6">
    <div class="max-w-3xl mx-auto">
      <div class="flex items-center justify-between mb-1">
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{ t('JABVOX_CALENDAR.SETTINGS.TITLE') }}
        </h2>
        <button
          class="flex items-center gap-2 px-3 h-9 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 transition-colors"
          @click="openCreate"
        >
          <span class="i-lucide-user-plus size-4" />
          {{ t('JABVOX_CALENDAR.SETTINGS.NEW_PERSON') }}
        </button>
      </div>
      <p class="text-sm text-n-slate-10 mb-5">
        {{ t('JABVOX_CALENDAR.SETTINGS.SUBTITLE') }}
      </p>

      <div
        v-if="uiFlags.isFetchingPeople"
        class="text-sm text-n-slate-10 py-8 text-center"
      >
        {{ t('JABVOX_CALENDAR.LOADING') }}
      </div>
      <div
        v-else-if="people.length === 0"
        class="text-sm text-n-slate-10 py-12 text-center border border-dashed border-n-weak rounded-xl"
      >
        {{ t('JABVOX_CALENDAR.SETTINGS.EMPTY') }}
      </div>

      <div v-else class="space-y-2">
        <div
          v-for="person in people"
          :key="person.id"
          class="flex items-center gap-3 p-3 rounded-xl border border-n-weak bg-n-surface-2 group"
        >
          <span
            class="size-9 rounded-full flex items-center justify-center text-white text-sm font-medium shrink-0"
            :style="{ background: person.color }"
          >
            {{ person.name.charAt(0).toUpperCase() }}
          </span>
          <div class="flex-1 min-w-0">
            <p class="font-medium text-n-slate-12 truncate">
              {{ person.name }}
            </p>
            <p class="text-xs text-n-slate-10 truncate">
              <span v-if="person.email">{{ person.email }}</span>
              <span v-if="person.email && person.phone_number"> · </span>
              <span v-if="person.phone_number">{{ person.phone_number }}</span>
            </p>
          </div>
          <span class="text-xs text-n-slate-10 shrink-0">
            {{
              t('JABVOX_CALENDAR.SETTINGS.EVENTS_COUNT', {
                count: person.events_count || 0,
              })
            }}
          </span>
          <div
            class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
          >
            <button
              class="p-1.5 rounded hover:bg-n-alpha-black2"
              @click="openEdit(person)"
            >
              <span class="i-lucide-pencil size-4 text-n-slate-11" />
            </button>
            <button
              class="p-1.5 rounded hover:bg-n-ruby-3"
              @click="remove(person)"
            >
              <span class="i-lucide-trash-2 size-4 text-n-ruby-9" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Person form modal -->
    <Teleport to="body">
      <div
        v-if="showForm"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4"
        @click.self="showForm = false"
      >
        <div
          class="w-full max-w-md rounded-2xl bg-n-surface-2 border border-n-weak shadow-xl"
        >
          <div
            class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
          >
            <h2 class="font-semibold text-n-slate-12">
              {{
                editing
                  ? t('JABVOX_CALENDAR.SETTINGS.EDIT_PERSON')
                  : t('JABVOX_CALENDAR.SETTINGS.NEW_PERSON')
              }}
            </h2>
            <button
              class="p-1.5 rounded hover:bg-n-alpha-black2"
              @click="showForm = false"
            >
              <span class="i-lucide-x size-4 text-n-slate-11" />
            </button>
          </div>
          <form class="p-5 space-y-4" @submit.prevent="save">
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.SETTINGS.NAME_LABEL') }}
              </label>
              <input
                v-model="form.name"
                type="text"
                class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-n-slate-12 mb-1">
                  {{ t('JABVOX_CALENDAR.SETTINGS.EMAIL_LABEL') }}
                </label>
                <input
                  v-model="form.email"
                  type="email"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-n-slate-12 mb-1">
                  {{ t('JABVOX_CALENDAR.SETTINGS.PHONE_LABEL') }}
                </label>
                <input
                  v-model="form.phone_number"
                  type="text"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                />
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JABVOX_CALENDAR.SETTINGS.NOTES_LABEL') }}
              </label>
              <textarea
                v-model="form.notes"
                rows="2"
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 resize-none focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>
            <div class="flex justify-end gap-2 pt-1">
              <button
                type="button"
                class="px-4 h-9 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-black2 transition-colors"
                @click="showForm = false"
              >
                {{ t('JABVOX_CALENDAR.CANCEL') }}
              </button>
              <button
                type="submit"
                :disabled="isSaving || !form.name.trim()"
                class="px-4 h-9 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
              >
                {{ isSaving ? '...' : t('JABVOX_CALENDAR.SAVE') }}
              </button>
            </div>
          </form>
        </div>
      </div>
    </Teleport>
  </div>
</template>
