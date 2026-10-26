<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';

// Mapeo responsable -> contacto para WhatsApp. Un responsable (assignee) es un usuario
// sin teléfono; para que la plantilla salga se le asigna un contacto real (con número).
// El modelo v-model es un objeto { "<userId>": <contactId> }.
defineProps({
  assignees: { type: Array, default: () => [] }, // [{ id, name }]
});

const map = defineModel({ type: Object, default: () => ({}) });

const { t } = useI18n();

// Estado de búsqueda por responsable: { userId: { query, results, selectedLabel } }
const search = ref({});

const ensureState = userId => {
  if (!search.value[userId]) {
    search.value[userId] = { query: '', results: [], label: '' };
  }
  return search.value[userId];
};

const onSearch = async (userId, term) => {
  const state = ensureState(userId);
  state.query = term;
  if (!term || term.length < 2) {
    state.results = [];
    return;
  }
  try {
    const { data } = await ContactAPI.search(term);
    state.results = (data?.payload || []).map(c => ({
      id: c.id,
      name: c.name,
      phone: c.phone_number,
    }));
  } catch {
    state.results = [];
  }
};

const selectContact = (userId, contact) => {
  map.value = { ...map.value, [String(userId)]: contact.id };
  const state = ensureState(userId);
  state.label = `${contact.name}${contact.phone ? ` · ${contact.phone}` : ''}`;
  state.results = [];
  state.query = '';
};

const clearContact = userId => {
  const next = { ...map.value };
  delete next[String(userId)];
  map.value = next;
  const state = ensureState(userId);
  state.label = '';
};

// Etiqueta a mostrar para un responsable ya mapeado (al reabrir el formulario).
const mappedLabel = userId => {
  const state = search.value[userId];
  if (state?.label) return state.label;
  const contactId = map.value[String(userId)];
  return contactId
    ? t('JABVOX_TASKS.AUTOMATION.ASSIGNEE_MAP.MAPPED', { id: contactId })
    : '';
};
</script>

<template>
  <div class="grid gap-3">
    <p class="text-xs text-n-slate-11">
      {{ t('JABVOX_TASKS.AUTOMATION.ASSIGNEE_MAP.HELP') }}
    </p>
    <p v-if="!assignees.length" class="text-xs text-n-amber-11">
      {{ t('JABVOX_TASKS.AUTOMATION.ASSIGNEE_MAP.NO_ASSIGNEES') }}
    </p>
    <div
      v-for="u in assignees"
      :key="u.id"
      class="p-2 border rounded-lg border-n-weak"
    >
      <div class="flex items-center justify-between mb-1">
        <span class="text-sm font-medium text-n-slate-12">{{ u.name }}</span>
        <button
          v-if="map[String(u.id)]"
          type="button"
          class="text-xs text-n-ruby-11"
          @click="clearContact(u.id)"
        >
          {{ t('JABVOX_TASKS.AUTOMATION.ASSIGNEE_MAP.CLEAR') }}
        </button>
      </div>
      <p v-if="mappedLabel(u.id)" class="mb-1 text-xs text-n-teal-11">
        {{ t('JABVOX_TASKS.AUTOMATION.ASSIGNEE_MAP.CURRENT') }}:
        {{ mappedLabel(u.id) }}
      </p>
      <input
        :value="search[u.id]?.query || ''"
        type="text"
        class="w-full h-8 px-2 py-1 text-sm border rounded-lg border-n-weak bg-n-alpha-black2 text-n-slate-12"
        :placeholder="t('JABVOX_TASKS.AUTOMATION.ASSIGNEE_MAP.SEARCH')"
        @input="onSearch(u.id, $event.target.value)"
      />
      <ul
        v-if="search[u.id]?.results?.length"
        class="mt-1 overflow-y-auto border rounded-lg max-h-40 border-n-weak"
      >
        <li
          v-for="c in search[u.id].results"
          :key="c.id"
          class="px-2 py-1 text-sm cursor-pointer hover:bg-n-alpha-2 text-n-slate-12"
          @click="selectContact(u.id, c)"
        >
          {{ c.name
          }}<span v-if="c.phone" class="text-n-slate-11"> · {{ c.phone }}</span>
        </li>
      </ul>
    </div>
  </div>
</template>
