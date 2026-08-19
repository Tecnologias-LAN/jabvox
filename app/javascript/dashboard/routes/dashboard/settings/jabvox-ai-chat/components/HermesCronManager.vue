<script setup>
// Gestor de cron jobs de Hermes.
// Al montar hace GET de los cron jobs de la cuenta y permite crear, alternar
// (enabled) y eliminar. Contempla el estado "cuenta no aprovisionada" (el GET
// devuelve 422 con {error}) mostrando un banner informativo en lugar de la
// tabla, y nunca silencia los errores.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { aiChatHermesCronAPI } from 'dashboard/api/jabvox/aiChat';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SectionCard from './SectionCard.vue';
import ConfirmDialog from './ConfirmDialog.vue';

const { t } = useI18n();

// ─── estado ───
const jobs = ref([]);
const isLoading = ref(false);
// Error de carga genérico (mensaje visible + botón reintentar).
const loadError = ref('');
// Cuenta no aprovisionada: el backend devuelve 422 en el GET.
const notProvisioned = ref(false);
// Ids de cron jobs con una operación (toggle/eliminar) en curso.
const busyIds = ref(new Set());
const deleteDialog = ref(null);

// Formulario de creación.
const form = ref({ name: '', schedule: '', prompt: '', enabled: true });
const formErrors = ref({ name: '', schedule: '' });
const isCreating = ref(false);

const hasJobs = computed(() => jobs.value.length > 0);

// ─── helpers ───
// Muestra fecha/hora legible o "Nunca" si el backend no la envía.
const formatDateTime = value => {
  if (!value) return t('JABVOX_AI_CHAT.CRON.NEVER');
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleString();
};

const isBusy = id => busyIds.value.has(id);

const setBusy = (id, on) => {
  const next = new Set(busyIds.value);
  if (on) next.add(id);
  else next.delete(id);
  busyIds.value = next;
};

// ─── carga ───
const fetchJobs = async () => {
  isLoading.value = true;
  loadError.value = '';
  notProvisioned.value = false;
  try {
    const { data } = await aiChatHermesCronAPI.getCronJobs();
    jobs.value = data?.jobs || [];
  } catch (e) {
    // 422 => la cuenta no está aprovisionada; se muestra como banner, no error.
    if (e?.response?.status === 422) {
      notProvisioned.value = true;
      jobs.value = [];
    } else {
      loadError.value =
        e?.response?.data?.error ||
        e?.message ||
        t('JABVOX_AI_CHAT.CRON.ERROR');
    }
  } finally {
    isLoading.value = false;
  }
};

// ─── alternar enabled ───
const toggleJob = async job => {
  const nextEnabled = !job.enabled;
  setBusy(job.id, true);
  try {
    const { data } = await aiChatHermesCronAPI.toggleCronJob(
      job.id,
      nextEnabled
    );
    // Reemplaza el job con la versión devuelta por el backend.
    const updated = data?.job || { ...job, enabled: nextEnabled };
    jobs.value = jobs.value.map(j => (j.id === job.id ? updated : j));
  } catch (e) {
    const msg =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_AI_CHAT.CRON.TOGGLE_ERROR');
    useAlert(msg);
  } finally {
    setBusy(job.id, false);
  }
};

// ─── eliminar (con confirmación) ───
const askDelete = job => {
  deleteDialog.value?.open({
    title: t('JABVOX_AI_CHAT.CRON.DELETE_TITLE'),
    description: t('JABVOX_AI_CHAT.CRON.DELETE_BODY', { name: job.name }),
    data: { id: job.id },
  });
};

const onConfirmDelete = async ({ id }) => {
  setBusy(id, true);
  try {
    await aiChatHermesCronAPI.deleteCronJob(id);
    jobs.value = jobs.value.filter(j => j.id !== id);
  } catch (e) {
    const msg =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_AI_CHAT.CRON.DELETE_ERROR');
    useAlert(msg);
  } finally {
    setBusy(id, false);
  }
};

// ─── crear ───
const validateForm = () => {
  formErrors.value = { name: '', schedule: '' };
  let ok = true;
  if (!form.value.name.trim()) {
    formErrors.value.name = t('JABVOX_AI_CHAT.CRON.FORM.NAME_REQUIRED');
    ok = false;
  }
  if (!form.value.schedule.trim()) {
    formErrors.value.schedule = t('JABVOX_AI_CHAT.CRON.FORM.SCHEDULE_REQUIRED');
    ok = false;
  }
  return ok;
};

const createJob = async () => {
  if (!validateForm()) return;
  isCreating.value = true;
  try {
    const { data } = await aiChatHermesCronAPI.createCronJob({
      name: form.value.name.trim(),
      schedule: form.value.schedule.trim(),
      prompt: form.value.prompt.trim() || undefined,
      enabled: form.value.enabled,
    });
    if (data?.job) jobs.value = [...jobs.value, data.job];
    // Reinicia el formulario tras crear.
    form.value = { name: '', schedule: '', prompt: '', enabled: true };
    formErrors.value = { name: '', schedule: '' };
    useAlert(t('JABVOX_AI_CHAT.CRON.FORM.CREATED'));
  } catch (e) {
    const msg =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_AI_CHAT.CRON.FORM.CREATE_ERROR');
    useAlert(msg);
  } finally {
    isCreating.value = false;
  }
};

onMounted(fetchJobs);
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- ── Listado de cron jobs ── -->
    <SectionCard
      :title="t('JABVOX_AI_CHAT.CRON.TITLE')"
      :description="t('JABVOX_AI_CHAT.CRON.SECTION_DESC')"
      icon="i-lucide-clock"
    >
      <template v-if="hasJobs && !isLoading && !notProvisioned" #actions>
        <span class="text-xs text-n-slate-10">
          {{ t('JABVOX_AI_CHAT.CRON.COUNT', { count: jobs.length }) }}
        </span>
      </template>

      <!-- Cargando -->
      <div
        v-if="isLoading"
        class="flex items-center justify-center gap-2 py-10 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_AI_CHAT.CRON.LOADING') }}
      </div>

      <!-- Cuenta no aprovisionada -->
      <div
        v-else-if="notProvisioned"
        class="flex items-start gap-3 rounded-xl border border-n-amber-6 bg-n-amber-2 px-4 py-3"
      >
        <span class="i-lucide-info size-5 shrink-0 text-n-amber-11 mt-0.5" />
        <div class="min-w-0">
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AI_CHAT.CRON.NOT_PROVISIONED_TITLE') }}
          </p>
          <p class="mt-0.5 text-sm text-n-slate-11">
            {{ t('JABVOX_AI_CHAT.CRON.NOT_PROVISIONED_DESC') }}
          </p>
        </div>
      </div>

      <!-- Error de carga -->
      <div
        v-else-if="loadError"
        class="flex flex-col items-center gap-3 rounded-xl border border-n-ruby-6 bg-n-ruby-2 px-4 py-8 text-center"
      >
        <span class="i-lucide-circle-x size-6 text-n-ruby-11" />
        <p class="text-sm text-n-ruby-11">{{ loadError }}</p>
        <Button
          :label="t('JABVOX_AI_CHAT.CRON.RETRY')"
          icon="i-lucide-refresh-cw"
          variant="outline"
          color="slate"
          size="sm"
          @click="fetchJobs"
        />
      </div>

      <!-- Vacío -->
      <div
        v-else-if="!hasJobs"
        class="rounded-xl border border-dashed border-n-weak py-10 text-center"
      >
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_AI_CHAT.CRON.EMPTY_TITLE') }}
        </p>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('JABVOX_AI_CHAT.CRON.EMPTY') }}
        </p>
      </div>

      <!-- Tabla de cron jobs (scroll horizontal en móvil) -->
      <div v-else class="overflow-x-auto">
        <table class="w-full min-w-[640px] text-sm">
          <thead>
            <tr
              class="border-b border-n-weak text-left text-xs text-n-slate-10"
            >
              <th class="px-3 py-2 font-medium">
                {{ t('JABVOX_AI_CHAT.CRON.TABLE.NAME') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('JABVOX_AI_CHAT.CRON.TABLE.SCHEDULE') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('JABVOX_AI_CHAT.CRON.TABLE.STATUS') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('JABVOX_AI_CHAT.CRON.TABLE.LAST_RUN') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('JABVOX_AI_CHAT.CRON.TABLE.NEXT_RUN') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('JABVOX_AI_CHAT.CRON.TABLE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr v-for="job in jobs" :key="job.id" class="align-middle">
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ job.name }}
              </td>
              <td class="px-3 py-3">
                <code
                  class="rounded bg-n-alpha-1 px-1.5 py-0.5 font-mono text-xs text-n-slate-11"
                >
                  {{ job.schedule }}
                </code>
              </td>
              <td class="px-3 py-3">
                <label
                  class="inline-flex items-center gap-2 cursor-pointer"
                  :title="
                    job.enabled
                      ? t('JABVOX_AI_CHAT.CRON.TOGGLE_DISABLE')
                      : t('JABVOX_AI_CHAT.CRON.TOGGLE_ENABLE')
                  "
                >
                  <Switch
                    :model-value="job.enabled"
                    :disabled="isBusy(job.id)"
                    @update:model-value="toggleJob(job)"
                  />
                  <span
                    class="text-xs"
                    :class="job.enabled ? 'text-n-teal-11' : 'text-n-slate-10'"
                  >
                    {{
                      job.enabled
                        ? t('JABVOX_AI_CHAT.CRON.ENABLED')
                        : t('JABVOX_AI_CHAT.CRON.DISABLED')
                    }}
                  </span>
                </label>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ formatDateTime(job.last_run) }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ formatDateTime(job.next_run) }}
              </td>
              <td class="px-3 py-3 text-right">
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  :is-loading="isBusy(job.id)"
                  :title="t('JABVOX_AI_CHAT.CRON.DELETE')"
                  @click="askDelete(job)"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </SectionCard>

    <!-- ── Formulario de creación ── -->
    <SectionCard
      v-if="!isLoading && !notProvisioned && !loadError"
      :title="t('JABVOX_AI_CHAT.CRON.FORM.TITLE')"
      icon="i-lucide-plus-circle"
    >
      <form class="flex flex-col gap-4" @submit.prevent="createJob">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div class="flex flex-col gap-1.5">
            <Input
              v-model="form.name"
              :label="t('JABVOX_AI_CHAT.CRON.FORM.NAME')"
              :placeholder="t('JABVOX_AI_CHAT.CRON.FORM.NAME_PLACEHOLDER')"
              :message="formErrors.name"
              :message-type="formErrors.name ? 'error' : 'info'"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <Input
              v-model="form.schedule"
              :label="t('JABVOX_AI_CHAT.CRON.FORM.SCHEDULE')"
              :placeholder="t('JABVOX_AI_CHAT.CRON.FORM.SCHEDULE_PLACEHOLDER')"
              :message="
                formErrors.schedule ||
                t('JABVOX_AI_CHAT.CRON.FORM.SCHEDULE_HINT')
              "
              :message-type="formErrors.schedule ? 'error' : 'info'"
              custom-input-class="font-mono"
            />
          </div>
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AI_CHAT.CRON.FORM.PROMPT') }}
          </label>
          <textarea
            v-model="form.prompt"
            rows="3"
            :placeholder="t('JABVOX_AI_CHAT.CRON.FORM.PROMPT_PLACEHOLDER')"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>

        <div class="flex flex-wrap items-center justify-between gap-3">
          <label class="flex items-center gap-2 cursor-pointer">
            <Switch v-model="form.enabled" />
            <span class="text-sm text-n-slate-12">
              {{ t('JABVOX_AI_CHAT.CRON.FORM.ENABLED') }}
            </span>
          </label>
          <Button
            type="submit"
            :label="
              isCreating
                ? t('JABVOX_AI_CHAT.CRON.FORM.CREATING')
                : t('JABVOX_AI_CHAT.CRON.FORM.SUBMIT')
            "
            icon="i-lucide-plus"
            size="sm"
            :is-loading="isCreating"
            @click="createJob"
          />
        </div>
      </form>
    </SectionCard>

    <ConfirmDialog ref="deleteDialog" @confirm="onConfirmDelete" />
  </div>
</template>
