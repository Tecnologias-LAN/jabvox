<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { OnClickOutside } from '@vueuse/components';
import leadsAPI from 'dashboard/api/jabvox/leads';

const props = defineProps({
  modelValue: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const open = ref(false);
const search = ref('');
const isLoading = ref(false);
const leads = ref([]);
// The currently selected lead, kept so we can render its label even when it is
// not part of the latest search results.
const selectedLead = ref(null);

const leadLabel = lead => {
  if (!lead) return '';
  const name = lead.contact?.name || '';
  return `#${lead.lead_number} · ${name}`;
};

const selectedLabel = computed(() =>
  selectedLead.value ? leadLabel(selectedLead.value) : ''
);

const fetchLeads = async term => {
  isLoading.value = true;
  try {
    const { data } = await leadsAPI.getAll({ q: term });
    leads.value = data?.data || [];
  } catch {
    leads.value = [];
  } finally {
    isLoading.value = false;
  }
};

const debouncedFetch = useDebounceFn(term => {
  fetchLeads(term);
}, 300);

const onInput = () => {
  open.value = true;
  debouncedFetch(search.value);
};

const openDropdown = () => {
  open.value = true;
  if (!leads.value.length) fetchLeads('');
};

const selectLead = lead => {
  selectedLead.value = lead;
  emit('update:modelValue', lead.id);
  open.value = false;
  search.value = '';
};

const clear = () => {
  selectedLead.value = null;
  emit('update:modelValue', null);
  search.value = '';
};

// Resolve the label for an externally-provided id (e.g. on edit prefill).
const resolveSelected = async id => {
  if (!id) {
    selectedLead.value = null;
    return;
  }
  if (selectedLead.value && selectedLead.value.id === Number(id)) return;
  const existing = leads.value.find(l => l.id === Number(id));
  if (existing) {
    selectedLead.value = existing;
    return;
  }
  try {
    const { data } = await leadsAPI.getById(id);
    selectedLead.value = data || null;
  } catch {
    selectedLead.value = null;
  }
};

watch(
  () => props.modelValue,
  id => resolveSelected(id),
  { immediate: true }
);
</script>

<template>
  <OnClickOutside @trigger="open = false">
    <div class="relative w-full">
      <div
        class="flex items-center gap-1 w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak"
      >
        <span
          class="i-lucide-search size-4 text-n-slate-10"
          aria-hidden="true"
        />
        <input
          v-if="!selectedLabel"
          v-model="search"
          type="text"
          :placeholder="t('JABVOX_TASKS.LEAD_SELECT.PLACEHOLDER')"
          class="flex-1 min-w-0 bg-transparent text-n-slate-12 focus:outline-none"
          @focus="openDropdown"
          @input="onInput"
        />
        <span v-else class="flex-1 min-w-0 truncate text-n-slate-12">
          {{ selectedLabel }}
        </span>
        <button
          v-if="selectedLabel"
          type="button"
          class="p-0.5 rounded text-n-slate-10 hover:text-n-slate-12"
          :title="t('JABVOX_TASKS.LEAD_SELECT.CLEAR')"
          @click="clear"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </div>

      <div
        v-if="open && !selectedLabel"
        class="absolute z-10 mt-1 w-full max-h-56 overflow-y-auto rounded-lg bg-n-solid-1 border border-n-weak shadow-lg py-1"
      >
        <p v-if="isLoading" class="px-3 py-2 text-sm text-n-slate-10">
          {{ t('JABVOX_TASKS.LEAD_SELECT.LOADING') }}
        </p>
        <p
          v-else-if="leads.length === 0"
          class="px-3 py-2 text-sm text-n-slate-10"
        >
          {{ t('JABVOX_TASKS.LEAD_SELECT.EMPTY') }}
        </p>
        <template v-else>
          <button
            v-for="lead in leads"
            :key="lead.id"
            type="button"
            class="flex flex-col w-full px-3 py-2 text-left text-sm hover:bg-n-alpha-1"
            @click="selectLead(lead)"
          >
            <span class="text-n-slate-12 truncate">
              {{ leadLabel(lead) }}
            </span>
            <span
              v-if="lead.contact?.email"
              class="text-[11px] text-n-slate-10 truncate"
            >
              {{ lead.contact.email }}
            </span>
          </button>
        </template>
      </div>
    </div>
  </OnClickOutside>
</template>
