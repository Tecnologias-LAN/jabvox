<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { OnClickOutside } from '@vueuse/components';

const props = defineProps({
  // Single mode: Number|String|null. Multiple mode: Array of ids.
  modelValue: {
    type: [Number, String, Array],
    default: null,
  },
  multiple: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const store = useStore();

const agents = useMapGetter('agents/getAgents');

const open = ref(false);
const search = ref('');

// Normalized list of selected ids (works for both single and multiple modes).
const selectedIds = computed(() => {
  if (props.multiple) return (props.modelValue || []).map(Number);
  return props.modelValue ? [Number(props.modelValue)] : [];
});

const selectedAgents = computed(() =>
  selectedIds.value
    .map(id => agents.value.find(a => a.id === id))
    .filter(Boolean)
);

// In single mode, the resolved single agent (or null) — drives the legacy collapsed UI.
const selectedAgent = computed(() =>
  props.multiple ? null : selectedAgents.value[0] || null
);

const filteredAgents = computed(() => {
  const term = search.value.trim().toLowerCase();
  const available = props.multiple
    ? agents.value.filter(a => !selectedIds.value.includes(a.id))
    : agents.value;
  if (!term) return available;
  return available.filter(a => (a.name || '').toLowerCase().includes(term));
});

const openDropdown = () => {
  open.value = true;
};

const selectAgent = agent => {
  if (props.multiple) {
    emit('update:modelValue', [...selectedIds.value, agent.id]);
    search.value = '';
    return;
  }
  emit('update:modelValue', agent.id);
  open.value = false;
  search.value = '';
};

const removeAgent = id => {
  emit(
    'update:modelValue',
    selectedIds.value.filter(selected => selected !== id)
  );
};

const clear = () => {
  emit('update:modelValue', props.multiple ? [] : null);
  search.value = '';
};

onMounted(() => {
  store.dispatch('agents/get');
});
</script>

<template>
  <OnClickOutside @trigger="open = false">
    <div class="relative w-full">
      <!-- Selected chips (multiple mode) -->
      <div
        v-if="multiple && selectedAgents.length"
        class="flex flex-wrap gap-1 mb-1"
      >
        <span
          v-for="agent in selectedAgents"
          :key="agent.id"
          class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-12"
        >
          <img
            v-if="agent.thumbnail"
            :src="agent.thumbnail"
            :alt="agent.name"
            class="size-3.5 rounded-full shrink-0"
          />
          <span class="truncate max-w-[10rem]">{{ agent.name }}</span>
          <button
            type="button"
            class="p-0.5 rounded text-n-slate-10 hover:text-n-slate-12"
            :title="t('JABVOX_TASKS.AGENT_SELECT.REMOVE')"
            @click="removeAgent(agent.id)"
          >
            <span class="i-lucide-x size-3" aria-hidden="true" />
          </button>
        </span>
      </div>

      <div
        class="flex items-center gap-1 w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak"
      >
        <span
          class="i-lucide-circle-user size-4 text-n-slate-10"
          aria-hidden="true"
        />
        <input
          v-if="multiple || !selectedAgent"
          v-model="search"
          type="text"
          :placeholder="
            multiple
              ? t('JABVOX_TASKS.AGENT_SELECT.PLACEHOLDER_MULTI')
              : t('JABVOX_TASKS.AGENT_SELECT.PLACEHOLDER')
          "
          class="flex-1 min-w-0 bg-transparent text-n-slate-12 focus:outline-none"
          @focus="openDropdown"
        />
        <span v-else class="flex-1 min-w-0 truncate text-n-slate-12">
          {{ selectedAgent.name }}
        </span>
        <button
          v-if="!multiple && selectedAgent"
          type="button"
          class="p-0.5 rounded text-n-slate-10 hover:text-n-slate-12"
          :title="t('JABVOX_TASKS.AGENT_SELECT.CLEAR')"
          @click="clear"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </div>

      <div
        v-if="open && (multiple || !selectedAgent)"
        class="absolute z-10 mt-1 w-full max-h-56 overflow-y-auto rounded-lg bg-n-solid-1 border border-n-weak shadow-lg py-1"
      >
        <p
          v-if="filteredAgents.length === 0"
          class="px-3 py-2 text-sm text-n-slate-10"
        >
          {{ t('JABVOX_TASKS.AGENT_SELECT.EMPTY') }}
        </p>
        <template v-else>
          <button
            v-for="agent in filteredAgents"
            :key="agent.id"
            type="button"
            class="flex items-center gap-2 w-full px-3 py-2 text-left text-sm hover:bg-n-alpha-1"
            @click="selectAgent(agent)"
          >
            <img
              v-if="agent.thumbnail"
              :src="agent.thumbnail"
              :alt="agent.name"
              class="size-4 rounded-full shrink-0"
            />
            <span class="text-n-slate-12 truncate">{{ agent.name }}</span>
          </button>
        </template>
      </div>
    </div>
  </OnClickOutside>
</template>
