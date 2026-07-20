<script setup>
import { ref, computed, nextTick, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const dialogRef = ref(null);
const campaign = ref(null);
const agents = ref([]);
const activeCalls = ref([]);
const counts = ref({ connected: 0, calling: 0 });
const status = ref(null);
const loading = ref(false);
const errored = ref(false);
const now = ref(Date.now());

const POLL_MS = 3000;
let pollTimer = null;
let tickTimer = null;

const title = computed(() =>
  campaign.value
    ? t('JABVOX_DIALER.LIVE.TITLE', { name: campaign.value.name_jabvox })
    : t('JABVOX_DIALER.LIVE.TITLE_PLAIN')
);

// Tiempo transcurrido desde un ISO, en formato compacto (m/s/h).
const elapsed = sinceIso => {
  if (!sinceIso) return '';
  const secs = Math.max(
    0,
    Math.floor((now.value - new Date(sinceIso).getTime()) / 1000)
  );
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h) return `${h}h ${m}m`;
  if (m) return `${m}m ${s}s`;
  return `${s}s`;
};

const stateLabel = agent => {
  if (agent.state === 'paused' && agent.pause_name) return agent.pause_name;
  return t(`JABVOX_DIALER.LIVE.STATE.${agent.state}`, agent.state);
};

// Glifos ligados para que no cuenten como texto plano en el template.
const LEAD_SEP = '· #';
const EXT_SEP = '· Ext. ';

const stateClass = state => {
  if (state === 'in_call') return 'text-n-teal-11 bg-n-teal-3';
  if (state === 'waiting') return 'text-n-blue-11 bg-n-blue-3';
  if (state === 'paused') return 'text-n-amber-11 bg-n-amber-3';
  if (state === 'in_wrapup') return 'text-n-violet-11 bg-n-violet-3';
  return 'text-n-slate-11 bg-n-alpha-2';
};

const fetch = async () => {
  if (!campaign.value) return;
  try {
    const { data } = await dialerCampaignsAPI.liveMonitor(campaign.value.id);
    agents.value = data.agents || [];
    activeCalls.value = data.active_calls || [];
    counts.value = data.counts || { connected: 0, calling: 0 };
    status.value = data.status;
    errored.value = false;
  } catch {
    errored.value = true;
  } finally {
    loading.value = false;
  }
};

const stopPolling = () => {
  clearInterval(pollTimer);
  clearInterval(tickTimer);
  pollTimer = null;
  tickTimer = null;
};

const open = c => {
  campaign.value = c;
  agents.value = [];
  activeCalls.value = [];
  counts.value = { connected: 0, calling: 0 };
  status.value = c?.status_jabvox;
  loading.value = true;
  errored.value = false;
  nextTick(() => dialogRef.value?.open());
  fetch();
  stopPolling();
  pollTimer = setInterval(fetch, POLL_MS);
  tickTimer = setInterval(() => {
    now.value = Date.now();
  }, 1000);
};

// Dialog cerrado (botón, ESC o backdrop): cortar el polling.
const onClose = () => stopPolling();

onUnmounted(stopPolling);

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :show-confirm-button="false"
    :cancel-button-label="t('JABVOX_DIALER.COMMON.CLOSE')"
    width="3xl"
    overflow-y-auto
    @close="onClose"
  >
    <div class="flex flex-col gap-4">
      <!-- Resumen -->
      <div class="flex flex-wrap items-center gap-3">
        <span
          class="inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-full"
          :class="
            status === 'active'
              ? 'text-n-teal-11 bg-n-teal-3'
              : 'text-n-slate-11 bg-n-alpha-2'
          "
        >
          <span class="i-lucide-radio size-3.5" />
          {{
            status === 'active'
              ? t('JABVOX_DIALER.LIVE.ACTIVE')
              : t('JABVOX_DIALER.LIVE.INACTIVE')
          }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t('JABVOX_DIALER.LIVE.CONNECTED_COUNT', { n: counts.connected }) }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t('JABVOX_DIALER.LIVE.CALLING_COUNT', { n: counts.calling }) }}
        </span>
        <span
          v-if="errored"
          class="ml-auto inline-flex items-center gap-1 text-[11px] text-n-amber-11"
        >
          <span class="i-lucide-wifi-off size-3" />
          {{ t('JABVOX_DIALER.LIVE.CONNECTION_LOST') }}
        </span>
        <span
          v-else-if="!loading"
          class="ml-auto inline-flex items-center gap-1 text-[11px] text-n-slate-9"
        >
          <span class="size-1.5 rounded-full bg-n-teal-9 animate-pulse" />
          {{ t('JABVOX_DIALER.LIVE.REALTIME') }}
        </span>
      </div>

      <div
        v-if="loading"
        class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_DIALER.COMMON.LOADING') }}
      </div>

      <template v-else>
        <!-- Llamadas que el marcador está sacando ahora -->
        <section class="flex flex-col gap-2">
          <h3
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_DIALER.LIVE.ACTIVE_CALLS') }}
          </h3>
          <div
            v-if="!activeCalls.length"
            class="text-xs text-n-slate-10 rounded-lg border border-dashed border-n-weak px-3 py-4 text-center"
          >
            {{ t('JABVOX_DIALER.LIVE.NO_ACTIVE_CALLS') }}
          </div>
          <div
            v-for="call in activeCalls"
            :key="call.dialer_contact_id"
            class="flex items-center gap-3 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
          >
            <span
              class="i-lucide-phone-outgoing size-4 text-n-teal-11 shrink-0 animate-pulse"
            />
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ call.name || call.phone || '—' }}
                <span
                  v-if="call.lead_number"
                  class="text-xs text-n-slate-10 font-normal"
                >
                  {{ LEAD_SEP }}{{ call.lead_number }}
                </span>
              </p>
              <p class="text-xs text-n-slate-10 font-mono truncate">
                {{ call.phone }}
              </p>
            </div>
            <span
              class="text-xs font-mono tabular-nums text-n-teal-11 shrink-0"
            >
              {{ elapsed(call.since) }}
            </span>
          </div>
        </section>

        <!-- Agentes conectados a la campaña con su estado -->
        <section class="flex flex-col gap-2">
          <h3
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_DIALER.LIVE.CONNECTED_AGENTS') }}
          </h3>
          <div
            v-if="!agents.length"
            class="text-xs text-n-slate-10 rounded-lg border border-dashed border-n-weak px-3 py-4 text-center"
          >
            {{ t('JABVOX_DIALER.LIVE.NO_AGENTS') }}
          </div>
          <div
            v-for="agent in agents"
            :key="agent.user_id"
            class="flex items-center gap-3 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2"
          >
            <Avatar
              :name="agent.name || agent.email || '?'"
              :src="agent.avatar_url"
              :size="32"
              rounded-full
            />
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ agent.name }}
                <span
                  v-if="agent.extension"
                  class="text-xs text-n-slate-10 font-normal"
                >
                  {{ EXT_SEP }}{{ agent.extension }}
                </span>
              </p>
              <p
                v-if="agent.state === 'in_call' && agent.calling_contact_name"
                class="text-xs text-n-teal-11 truncate inline-flex items-center gap-1"
              >
                <span class="i-lucide-phone-outgoing size-3" />
                {{ agent.calling_contact_name }}
                <span v-if="agent.calling_lead_number" class="text-n-slate-10">
                  {{ LEAD_SEP }}{{ agent.calling_lead_number }}
                </span>
                <span
                  v-if="agent.calling_contact_phone"
                  class="text-n-slate-10"
                >
                  {{ agent.calling_contact_phone }}
                </span>
              </p>
              <p v-else class="text-xs text-n-slate-10 truncate">
                {{ agent.email }}
              </p>
            </div>
            <div class="flex flex-col items-end gap-1 shrink-0">
              <span
                class="text-xs px-2 py-0.5 rounded-full font-semibold inline-flex items-center gap-1"
                :class="stateClass(agent.state)"
              >
                <span
                  v-if="agent.state === 'in_call'"
                  class="i-lucide-phone-call size-3"
                />
                {{ stateLabel(agent) }}
              </span>
              <span
                v-if="agent.since"
                class="text-[11px] font-mono tabular-nums text-n-slate-10"
              >
                {{ elapsed(agent.since) }}
              </span>
            </div>
          </div>
        </section>
      </template>
    </div>
  </Dialog>
</template>
