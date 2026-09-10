<script setup>
// Gestor de conexiones a los agentes del Hermes de la cuenta. Todos comparten el mismo
// host:puerto (un solo Hermes por cuenta), y cada agente tiene su prefijo/URL + token.
// Muestra la lista con estado de conexión, y permite agregar/editar/verificar/eliminar.
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { hermesConnectionsAPI } from 'dashboard/api/jabvox/aiChat';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SectionCard from './SectionCard.vue';

const { t } = useI18n();

const isLoading = ref(false);
const connections = ref([]);
const isSaving = ref(false);
const verifyingId = ref(null);
const showForm = ref(false);
const editingId = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  hermes_agent_name_jabvox: '',
  base_url_jabvox: '',
  token_jabvox: '',
});
const form = ref(emptyForm());

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await hermesConnectionsAPI.getAll();
    connections.value = data;
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const openCreate = () => {
  editingId.value = null;
  form.value = emptyForm();
  showForm.value = true;
};

const openEdit = conn => {
  editingId.value = conn.id;
  form.value = {
    name_jabvox: conn.name,
    hermes_agent_name_jabvox: conn.hermes_agent,
    base_url_jabvox: conn.base_url,
    token_jabvox: '', // en blanco = conservar
  };
  showForm.value = true;
};

const save = async () => {
  isSaving.value = true;
  try {
    const payload = { ...form.value };
    if (editingId.value && !payload.token_jabvox) delete payload.token_jabvox;
    if (editingId.value) {
      await hermesConnectionsAPI.update(editingId.value, payload);
    } else {
      await hermesConnectionsAPI.create(payload);
    }
    showForm.value = false;
    await load();
  } catch (e) {
    useAlert(
      e?.response?.data?.errors?.join(', ') ||
        e?.response?.data?.error ||
        t('JABVOX_AI_CHAT.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const verify = async conn => {
  verifyingId.value = conn.id;
  try {
    await hermesConnectionsAPI.verify(conn.id);
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  } finally {
    verifyingId.value = null;
  }
};

const remove = async conn => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`¿Eliminar el agente "${conn.name}"?`)) return;
  try {
    await hermesConnectionsAPI.destroy(conn.id);
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  }
};

const statusColor = s => {
  if (s === 'ok') return 'text-green-600';
  if (s === 'error') return 'text-red-500';
  return 'text-n-slate-10';
};

// Textos estáticos (evita el lint de raw-text en el template).
const TXT = {
  title: 'Agentes de Hermes',
  desc: 'Conecta uno o varios agentes del Hermes de la cuenta. Todos deben usar el mismo host y puerto (mismo Hermes), cada uno con su URL de agente y su token.',
  empty: 'No hay agentes de Hermes conectados todavía.',
};

onMounted(load);
</script>

<template>
  <SectionCard :title="TXT.title" :description="TXT.desc">
    <div v-if="isLoading" class="flex justify-center py-6">
      <Spinner />
    </div>

    <template v-else>
      <!-- Lista de agentes conectados -->
      <div
        v-for="conn in connections"
        :key="conn.id"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak p-3 mb-2"
      >
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-medium text-n-slate-12">{{ conn.name }}</span>
            <span class="text-xs text-n-slate-10 font-mono">{{
              conn.hermes_agent
            }}</span>
            <span class="text-xs font-medium" :class="statusColor(conn.status)">
              {{ `● ${conn.status}` }}
            </span>
          </div>
          <div class="text-xs text-n-slate-10 font-mono truncate">
            {{ conn.base_url }}
          </div>
          <div v-if="conn.last_error" class="text-xs text-red-500 mt-0.5">
            {{ conn.last_error }}
          </div>
        </div>
        <div class="flex items-center gap-2">
          <Button
            size="sm"
            variant="ghost"
            label="Probar"
            :is-loading="verifyingId === conn.id"
            @click="verify(conn)"
          />
          <Button
            size="sm"
            variant="ghost"
            label="Editar"
            @click="openEdit(conn)"
          />
          <Button
            size="sm"
            variant="ghost"
            color="ruby"
            label="Eliminar"
            @click="remove(conn)"
          />
        </div>
      </div>

      <p v-if="!connections.length" class="text-sm text-n-slate-10 py-2">
        {{ TXT.empty }}
      </p>

      <!-- Formulario agregar/editar -->
      <div
        v-if="showForm"
        class="rounded-xl border border-n-weak p-4 mt-3 flex flex-col gap-3"
      >
        <Input
          v-model="form.name_jabvox"
          label="Nombre visible"
          placeholder="Mi agente"
        />
        <Input
          v-model="form.hermes_agent_name_jabvox"
          label="Nombre del agente en Hermes"
          placeholder="mi-agente"
          custom-input-class="font-mono"
        />
        <Input
          v-model="form.base_url_jabvox"
          label="URL del agente"
          placeholder="http://tu-hermes.ejemplo:PUERTO/p/mi-agente/v1"
          message="Mismo host:puerto que los demás agentes. Incluye el prefijo /p/<agente>/v1."
          custom-input-class="font-mono"
        />
        <Input
          v-model="form.token_jabvox"
          type="password"
          label="Token del agente"
          :placeholder="
            editingId ? '(en blanco = conservar)' : 'Bearer token del agente'
          "
          custom-input-class="font-mono"
        />
        <div class="flex gap-2 justify-end">
          <Button variant="ghost" label="Cancelar" @click="showForm = false" />
          <Button label="Guardar" :is-loading="isSaving" @click="save" />
        </div>
      </div>

      <div v-else class="mt-3">
        <Button
          icon="i-lucide-plus"
          label="Agregar agente"
          @click="openCreate"
        />
      </div>
    </template>
  </SectionCard>
</template>
