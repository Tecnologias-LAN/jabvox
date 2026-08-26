<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  hermesAgentsAPI,
  hermesConnectionsAPI,
} from 'dashboard/api/jabvox/aiChat';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const dash = '—';

const agents = ref([]);
const connections = ref([]); // agentes Hermes disponibles en la cuenta
const loading = ref(false);
const accountUsers = useMapGetter('agents/getAgents');

const showForm = ref(false);
const editing = ref(null);
const form = ref({ user_id: null, name: '', connection_ids: [] });

const usersWithoutAgent = computed(() => {
  const taken = new Set(agents.value.map(a => a.user_id));
  return (accountUsers.value || []).filter(
    u => !taken.has(u.id) || (editing.value && editing.value.user_id === u.id)
  );
});

const fetchAll = async () => {
  loading.value = true;
  try {
    const [a, c] = await Promise.all([
      hermesAgentsAPI.getAll(),
      hermesConnectionsAPI.getAll(),
    ]);
    agents.value = a.data;
    connections.value = c.data;
  } catch {
    useAlert(t('JABVOX_AI_CHAT.AGENTS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  fetchAll();
});

const openCreate = () => {
  editing.value = null;
  form.value = { user_id: null, name: '', connection_ids: [] };
  showForm.value = true;
};

const openEdit = agent => {
  editing.value = agent;
  form.value = {
    user_id: agent.user_id,
    name: agent.name,
    connection_ids: [...(agent.connection_ids || [])],
  };
  showForm.value = true;
};

const toggleConnection = id => {
  const idx = form.value.connection_ids.indexOf(id);
  if (idx === -1) form.value.connection_ids.push(id);
  else form.value.connection_ids.splice(idx, 1);
};

const save = async () => {
  if (!form.value.user_id) return useAlert(t('JABVOX_AI_CHAT.AGENTS.ERR_USER'));
  if (!form.value.name.trim())
    return useAlert(t('JABVOX_AI_CHAT.AGENTS.ERR_NAME'));
  try {
    if (editing.value) {
      await hermesAgentsAPI.update(editing.value.id, form.value);
    } else {
      await hermesAgentsAPI.create(form.value);
    }
    useAlert(t('JABVOX_AI_CHAT.AGENTS.SAVED'));
    showForm.value = false;
    fetchAll();
  } catch (e) {
    useAlert(
      e?.response?.data?.errors?.join(', ') ||
        t('JABVOX_AI_CHAT.AGENTS.SAVE_ERROR')
    );
  }
  return undefined;
};

const removeAgent = async agent => {
  if (agent.is_default)
    return useAlert(t('JABVOX_AI_CHAT.AGENTS.CANT_DELETE_DEFAULT'));
  if (
    !window.confirm(
      t('JABVOX_AI_CHAT.AGENTS.CONFIRM_DELETE', { name: agent.name })
    )
  ) {
    return undefined;
  }
  try {
    await hermesAgentsAPI.destroy(agent.id);
    fetchAll();
  } catch {
    useAlert(t('JABVOX_AI_CHAT.AGENTS.DELETE_ERROR'));
  }
  return undefined;
};

// Nombre del usuario del agente: usa el que trae el backend; si no, el store.
const userName = agent =>
  agent.user_name ||
  (accountUsers.value || []).find(u => u.id === agent.user_id)?.name ||
  `#${agent.user_id}`;
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex items-center justify-between">
      <div>
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('JABVOX_AI_CHAT.AGENTS.TITLE') }}
        </h3>
        <p class="mt-0.5 text-sm text-n-slate-11">
          {{ t('JABVOX_AI_CHAT.AGENTS.SUBTITLE') }}
        </p>
      </div>
      <Button
        icon="i-lucide-plus"
        :label="t('JABVOX_AI_CHAT.AGENTS.NEW')"
        @click="openCreate"
      />
    </div>

    <div v-if="loading" class="py-8 text-center text-sm text-n-slate-10">
      {{ t('JABVOX_AI_CHAT.AGENTS.LOADING') }}
    </div>
    <div
      v-else-if="!agents.length"
      class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
    >
      {{ t('JABVOX_AI_CHAT.AGENTS.EMPTY') }}
    </div>
    <div v-else class="overflow-hidden rounded-xl border border-n-weak">
      <table class="w-full text-sm">
        <thead class="bg-n-alpha-1 text-left text-n-slate-11">
          <tr>
            <th class="px-4 py-2.5 font-medium">
              {{ t('JABVOX_AI_CHAT.AGENTS.COL_NAME') }}
            </th>
            <th class="px-4 py-2.5 font-medium">
              {{ t('JABVOX_AI_CHAT.AGENTS.COL_USER') }}
            </th>
            <th class="px-4 py-2.5 font-medium">
              {{ t('JABVOX_AI_CHAT.AGENTS.COL_HERMES') }}
            </th>
            <th class="px-4 py-2.5" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="agent in agents"
            :key="agent.id"
            class="border-t border-n-weak"
          >
            <td class="px-4 py-3">
              <span class="font-medium text-n-slate-12">{{ agent.name }}</span>
              <span
                v-if="agent.is_default"
                class="ml-2 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11"
              >
                {{ t('JABVOX_AI_CHAT.AGENTS.DEFAULT') }}
              </span>
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ userName(agent) }}
            </td>
            <td class="px-4 py-3">
              <span
                v-for="c in agent.hermes_connections"
                :key="c.id"
                class="mr-1 inline-block rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-11"
              >
                {{ c.name }}
              </span>
              <span
                v-if="!(agent.hermes_connections || []).length"
                class="text-xs text-n-slate-9"
              >
                {{ dash }}
              </span>
            </td>
            <td class="px-4 py-3 text-right">
              <Button
                variant="ghost"
                size="sm"
                icon="i-lucide-pencil"
                @click="openEdit(agent)"
              />
              <Button
                variant="ghost"
                color="ruby"
                size="sm"
                icon="i-lucide-trash-2"
                @click="removeAgent(agent)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Formulario (crear/editar) -->
    <div
      v-if="showForm"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-16"
      @click.self="showForm = false"
    >
      <div
        class="w-full max-w-lg rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <h3 class="mb-4 text-base font-medium text-n-slate-12">
          {{
            editing
              ? t('JABVOX_AI_CHAT.AGENTS.EDIT')
              : t('JABVOX_AI_CHAT.AGENTS.NEW')
          }}
        </h3>
        <div class="flex flex-col gap-3">
          <div>
            <label class="mb-1 block text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.AGENTS.USER') }}
            </label>
            <select
              v-model="form.user_id"
              :disabled="!!editing"
              class="block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
            >
              <option :value="null">{{ dash }}</option>
              <option v-for="u in usersWithoutAgent" :key="u.id" :value="u.id">
                {{ u.name }}
              </option>
            </select>
          </div>
          <div>
            <label class="mb-1 block text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.AGENTS.NAME') }}
            </label>
            <input
              v-model="form.name"
              type="text"
              class="block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
            />
          </div>
          <div>
            <label class="mb-1 block text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.AGENTS.HERMES_AGENTS') }}
            </label>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="c in connections"
                :key="c.id"
                type="button"
                class="rounded-full px-2.5 py-1 text-xs font-medium"
                :class="
                  form.connection_ids.includes(c.id)
                    ? 'bg-n-brand text-white'
                    : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
                "
                @click="toggleConnection(c.id)"
              >
                {{ c.name }}
              </button>
              <span v-if="!connections.length" class="text-xs text-n-slate-10">
                {{ t('JABVOX_AI_CHAT.AGENTS.NO_HERMES') }}
              </span>
            </div>
          </div>
        </div>
        <div class="mt-5 flex justify-end gap-2">
          <Button
            variant="outline"
            :label="t('JABVOX_AI_CHAT.AGENTS.CANCEL')"
            @click="showForm = false"
          />
          <Button :label="t('JABVOX_AI_CHAT.AGENTS.SAVE')" @click="save" />
        </div>
      </div>
    </div>
  </div>
</template>
