<script setup>
// Gestor de conexión de un Hermes ya existente a la cuenta (sin aprovisionar
// desde el super admin). Al montar hace GET del estado del handoff; si está
// "ready" muestra los datos y permite sincronizar modelos; si no, muestra el
// formulario de conexión. Nunca silencia errores (useAlert + mensajes visibles).
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { aiChatHermesAPI } from 'dashboard/api/jabvox/aiChat';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SectionCard from './SectionCard.vue';

const { t } = useI18n();

// ─── estado ───
const isLoading = ref(false);
const loadError = ref('');
const status = ref(null); // respuesta completa del GET status
const isConnecting = ref(false);
const isSyncing = ref(false);
// Fuerza mostrar el formulario aunque esté conectado (reconfigurar).
const showForm = ref(false);

const form = ref({
  contextforge_base_url: '',
  virtual_server_id: '',
  scoped_token: '',
  team_id: '',
  hermes_instance_id: '',
});
const formErrors = ref({
  contextforge_base_url: '',
  virtual_server_id: '',
  scoped_token: '',
});

// ─── derivados ───
const handoff = computed(() => status.value?.handoff || null);
const isConnected = computed(() => handoff.value?.status === 'ready');
const lastError = computed(() => handoff.value?.last_error || '');
const mcpServersCount = computed(() => {
  const servers = handoff.value?.mcp_servers;
  if (Array.isArray(servers)) return servers.length;
  return 0;
});

// El formulario se muestra cuando no hay conexión o el usuario pide reconfigurar.
const showConnectForm = computed(() => !isConnected.value || showForm.value);

// ─── carga ───
const fetchStatus = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await aiChatHermesAPI.getStatus();
    status.value = data;
    showForm.value = false;
    // Precarga los campos conocidos para facilitar la reconfiguración.
    if (data?.handoff) {
      form.value.contextforge_base_url =
        data.handoff.contextforge_base_url || '';
      form.value.virtual_server_id = data.handoff.virtual_server_id || '';
      form.value.hermes_instance_id = data.handoff.hermes_instance_id || '';
    }
  } catch (e) {
    loadError.value =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_AI_CHAT.HERMES.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

// ─── conectar ───
const validateForm = () => {
  formErrors.value = {
    contextforge_base_url: '',
    virtual_server_id: '',
    scoped_token: '',
  };
  let ok = true;
  if (!form.value.contextforge_base_url.trim()) {
    formErrors.value.contextforge_base_url = t(
      'JABVOX_AI_CHAT.HERMES.FORM.BASE_URL_REQUIRED'
    );
    ok = false;
  }
  if (!form.value.virtual_server_id.trim()) {
    formErrors.value.virtual_server_id = t(
      'JABVOX_AI_CHAT.HERMES.FORM.VSID_REQUIRED'
    );
    ok = false;
  }
  if (!form.value.scoped_token.trim()) {
    formErrors.value.scoped_token = t(
      'JABVOX_AI_CHAT.HERMES.FORM.TOKEN_REQUIRED'
    );
    ok = false;
  }
  return ok;
};

const connect = async () => {
  if (!validateForm()) return;
  isConnecting.value = true;
  try {
    // Campos opcionales vacíos se envían como undefined (no cadena vacía).
    const payload = {
      contextforge_base_url: form.value.contextforge_base_url.trim(),
      virtual_server_id: form.value.virtual_server_id.trim(),
      scoped_token: form.value.scoped_token.trim(),
      team_id: form.value.team_id.trim() || undefined,
      hermes_instance_id: form.value.hermes_instance_id.trim() || undefined,
    };
    await aiChatHermesAPI.connect(payload);
    // El token no se conserva en el cliente tras conectar.
    form.value.scoped_token = '';
    useAlert(t('JABVOX_AI_CHAT.HERMES.CONNECT_OK'));
    await fetchStatus();
  } catch (e) {
    const msg =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_AI_CHAT.HERMES.CONNECT_ERROR');
    useAlert(msg);
  } finally {
    isConnecting.value = false;
  }
};

// ─── sincronizar modelos ───
const syncModels = async () => {
  isSyncing.value = true;
  try {
    const { data } = await aiChatHermesAPI.syncModels();
    useAlert(
      t('JABVOX_AI_CHAT.HERMES.SYNC_OK', {
        pushed: data?.pushed ?? 0,
        pulled: data?.pulled ?? 0,
      })
    );
    await fetchStatus();
  } catch (e) {
    const msg =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_AI_CHAT.HERMES.SYNC_ERROR');
    useAlert(msg);
  } finally {
    isSyncing.value = false;
  }
};

onMounted(fetchStatus);
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- ── Banner de estado ── -->
    <SectionCard
      :title="t('JABVOX_AI_CHAT.HERMES.TITLE')"
      :description="t('JABVOX_AI_CHAT.HERMES.SECTION_DESC')"
      icon="i-lucide-plug"
    >
      <!-- Cargando -->
      <div
        v-if="isLoading"
        class="flex items-center justify-center gap-2 py-10 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_AI_CHAT.HERMES.LOADING') }}
      </div>

      <!-- Error de carga -->
      <div
        v-else-if="loadError"
        class="flex flex-col items-center gap-3 rounded-xl border border-n-ruby-6 bg-n-ruby-2 px-4 py-8 text-center"
      >
        <span class="i-lucide-circle-x size-6 text-n-ruby-11" />
        <p class="text-sm text-n-ruby-11">{{ loadError }}</p>
        <Button
          :label="t('JABVOX_AI_CHAT.HERMES.RETRY')"
          icon="i-lucide-refresh-cw"
          variant="outline"
          color="slate"
          size="sm"
          @click="fetchStatus"
        />
      </div>

      <template v-else>
        <!-- Conectado -->
        <div
          v-if="isConnected"
          class="flex items-start gap-3 rounded-xl border border-n-teal-6 bg-n-teal-2 px-4 py-3"
        >
          <span
            class="i-lucide-circle-check size-5 shrink-0 text-n-teal-11 mt-0.5"
          />
          <div class="min-w-0">
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.HERMES.CONNECTED') }}
            </p>
            <p class="mt-0.5 text-sm text-n-slate-11">
              {{ t('JABVOX_AI_CHAT.HERMES.CONNECTED_DESC') }}
            </p>
          </div>
        </div>

        <!-- No conectado -->
        <div
          v-else
          class="flex items-start gap-3 rounded-xl border border-n-amber-6 bg-n-amber-2 px-4 py-3"
        >
          <span class="i-lucide-info size-5 shrink-0 text-n-amber-11 mt-0.5" />
          <div class="min-w-0">
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.HERMES.NOT_CONNECTED') }}
            </p>
            <p class="mt-0.5 text-sm text-n-slate-11">
              {{ t('JABVOX_AI_CHAT.HERMES.NOT_CONNECTED_DESC') }}
            </p>
            <p v-if="lastError" class="mt-1 text-sm text-n-ruby-11">
              {{ t('JABVOX_AI_CHAT.HERMES.LAST_ERROR', { error: lastError }) }}
            </p>
          </div>
        </div>

        <!-- Detalles + sincronizar (solo conectado) -->
        <div v-if="isConnected" class="mt-5 flex flex-col gap-4">
          <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-10">
                {{ t('JABVOX_AI_CHAT.HERMES.FIELD.BASE_URL') }}
              </dt>
              <dd class="text-sm font-medium text-n-slate-12 break-all">
                {{ handoff.contextforge_base_url || '—' }}
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-10">
                {{ t('JABVOX_AI_CHAT.HERMES.FIELD.VSID') }}
              </dt>
              <dd class="text-sm font-medium text-n-slate-12 break-all">
                {{ handoff.virtual_server_id || '—' }}
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-10">
                {{ t('JABVOX_AI_CHAT.HERMES.FIELD.MCP_SERVERS') }}
              </dt>
              <dd class="text-sm font-medium text-n-slate-12">
                {{ mcpServersCount }}
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-10">
                {{ t('JABVOX_AI_CHAT.HERMES.FIELD.HERMES_MODELS') }}
              </dt>
              <dd class="text-sm font-medium text-n-slate-12">
                {{ status?.hermes_models_count ?? 0 }}
              </dd>
            </div>
          </dl>

          <div
            class="flex flex-wrap items-center justify-end gap-2 border-t border-n-weak pt-4"
          >
            <Button
              :label="t('JABVOX_AI_CHAT.HERMES.RECONFIGURE')"
              icon="i-lucide-pencil"
              variant="outline"
              color="slate"
              size="sm"
              @click="showForm = true"
            />
            <Button
              :label="
                isSyncing
                  ? t('JABVOX_AI_CHAT.HERMES.SYNCING')
                  : t('JABVOX_AI_CHAT.HERMES.SYNC')
              "
              icon="i-lucide-refresh-cw"
              size="sm"
              :is-loading="isSyncing"
              @click="syncModels"
            />
          </div>
        </div>
      </template>
    </SectionCard>

    <!-- ── Formulario de conexión ── -->
    <SectionCard
      v-if="!isLoading && !loadError && showConnectForm"
      :title="t('JABVOX_AI_CHAT.HERMES.FORM.TITLE')"
      :description="t('JABVOX_AI_CHAT.HERMES.FORM.DESC')"
      icon="i-lucide-link"
    >
      <form class="flex flex-col gap-4" @submit.prevent="connect">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Input
            v-model="form.contextforge_base_url"
            :label="t('JABVOX_AI_CHAT.HERMES.FORM.BASE_URL')"
            :placeholder="t('JABVOX_AI_CHAT.HERMES.FORM.BASE_URL_PLACEHOLDER')"
            :message="formErrors.contextforge_base_url"
            :message-type="formErrors.contextforge_base_url ? 'error' : 'info'"
          />
          <Input
            v-model="form.virtual_server_id"
            :label="t('JABVOX_AI_CHAT.HERMES.FORM.VSID')"
            :placeholder="t('JABVOX_AI_CHAT.HERMES.FORM.VSID_PLACEHOLDER')"
            :message="formErrors.virtual_server_id"
            :message-type="formErrors.virtual_server_id ? 'error' : 'info'"
          />
        </div>

        <Input
          v-model="form.scoped_token"
          type="password"
          :label="t('JABVOX_AI_CHAT.HERMES.FORM.TOKEN')"
          :placeholder="t('JABVOX_AI_CHAT.HERMES.FORM.TOKEN_PLACEHOLDER')"
          :message="
            formErrors.scoped_token ||
            t('JABVOX_AI_CHAT.HERMES.FORM.TOKEN_HINT')
          "
          :message-type="formErrors.scoped_token ? 'error' : 'info'"
        />

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Input
            v-model="form.team_id"
            :label="t('JABVOX_AI_CHAT.HERMES.FORM.TEAM_ID')"
            :placeholder="t('JABVOX_AI_CHAT.HERMES.FORM.TEAM_ID_PLACEHOLDER')"
          />
          <Input
            v-model="form.hermes_instance_id"
            :label="t('JABVOX_AI_CHAT.HERMES.FORM.INSTANCE_ID')"
            :placeholder="
              t('JABVOX_AI_CHAT.HERMES.FORM.INSTANCE_ID_PLACEHOLDER')
            "
          />
        </div>

        <div class="flex flex-wrap items-center justify-end gap-2">
          <Button
            v-if="isConnected"
            :label="t('JABVOX_AI_CHAT.HERMES.FORM.CANCEL')"
            variant="ghost"
            color="slate"
            size="sm"
            @click="showForm = false"
          />
          <Button
            type="submit"
            :label="
              isConnecting
                ? t('JABVOX_AI_CHAT.HERMES.FORM.CONNECTING')
                : t('JABVOX_AI_CHAT.HERMES.FORM.SUBMIT')
            "
            icon="i-lucide-plug"
            size="sm"
            :is-loading="isConnecting"
            @click="connect"
          />
        </div>
      </form>
    </SectionCard>
  </div>
</template>
