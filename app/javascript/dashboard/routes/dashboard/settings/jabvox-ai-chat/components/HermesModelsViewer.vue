<script setup>
// Muestra, por cada agente de Hermes conectado, los modelos que ese agente ofrece
// (GET .../p/<agente>/api/model/options). Solo lectura: los modelos los gestiona Hermes.
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { hermesConnectionsAPI } from 'dashboard/api/jabvox/aiChat';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SectionCard from './SectionCard.vue';

const { t } = useI18n();

const connections = ref([]);
const modelsByConn = ref({}); // { [connId]: { loading, error, items: [] } }

const TXT = {
  title: 'Modelos por agente de Hermes',
  desc: 'Modelos que ofrece cada agente conectado. Los gestiona Hermes; aquí solo se consultan.',
  empty: 'No hay agentes de Hermes conectados.',
  none: 'Este agente no reporta modelos disponibles.',
};

// Aplana la respuesta de model/options a una lista de etiquetas. Formato real de Hermes:
// { providers: [{ name, models: [...] }] }. Soporta también array u objeto plano.
const flattenModels = data => {
  const out = [];
  const push = (provider, model) => {
    const label = model?.id || model?.name || model?.slug || model;
    if (label) out.push({ provider, label: String(label) });
  };
  let providers = [];
  if (Array.isArray(data?.providers)) providers = data.providers;
  else if (Array.isArray(data)) providers = data;
  if (providers.length) {
    providers.forEach(p =>
      (p.models || p.options || []).forEach(m => push(p.name || p.provider, m))
    );
  } else if (data && typeof data === 'object') {
    Object.entries(data).forEach(([prov, val]) => {
      const list = Array.isArray(val) ? val : val?.models || [];
      list.forEach(m => push(prov, m));
    });
  }
  return out;
};

const loadModels = async conn => {
  modelsByConn.value[conn.id] = { loading: true, error: '', items: [] };
  try {
    const { data } = await hermesConnectionsAPI.modelOptions(conn.id);
    modelsByConn.value[conn.id] = {
      loading: false,
      error: '',
      items: flattenModels(data),
    };
  } catch (e) {
    modelsByConn.value[conn.id] = {
      loading: false,
      error: e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'),
      items: [],
    };
  }
};

const load = async () => {
  const { data } = await hermesConnectionsAPI.getAll();
  connections.value = data;
  data.forEach(loadModels);
};

onMounted(load);
</script>

<template>
  <SectionCard :title="TXT.title" :description="TXT.desc">
    <p v-if="!connections.length" class="text-sm text-n-slate-10 py-2">
      {{ TXT.empty }}
    </p>

    <div
      v-for="conn in connections"
      :key="conn.id"
      class="rounded-xl border border-n-weak p-3 mb-2"
    >
      <div class="flex items-center justify-between mb-2">
        <span class="font-medium text-n-slate-12">{{ conn.name }}</span>
        <span class="text-xs text-n-slate-10 font-mono">{{
          conn.hermes_agent
        }}</span>
      </div>

      <div
        v-if="modelsByConn[conn.id]?.loading"
        class="flex items-center gap-2 text-sm text-n-slate-10"
      >
        <Spinner :size="16" />
      </div>
      <div
        v-else-if="modelsByConn[conn.id]?.error"
        class="flex items-center gap-2 text-sm text-red-500"
      >
        <span>{{ modelsByConn[conn.id].error }}</span>
        <Button
          size="sm"
          variant="ghost"
          label="Reintentar"
          @click="loadModels(conn)"
        />
      </div>
      <div
        v-else-if="!modelsByConn[conn.id]?.items?.length"
        class="text-sm text-n-slate-10"
      >
        {{ TXT.none }}
      </div>
      <div v-else class="flex flex-wrap gap-1.5">
        <span
          v-for="(m, i) in modelsByConn[conn.id].items"
          :key="`${conn.id}-${i}`"
          class="inline-block rounded bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11 font-mono"
        >
          {{ m.label }}
        </span>
      </div>
    </div>
  </SectionCard>
</template>
