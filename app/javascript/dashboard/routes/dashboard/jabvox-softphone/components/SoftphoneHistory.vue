<script setup>
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useSoftphone } from 'dashboard/composables/jabvox/useSoftphone';

const emit = defineEmits(['dial']);
// Pestaña de historial dentro del teléfono: a quién se llamó, número, duración y hace
// cuánto. Permite volver a marcar tocando una entrada.
const { t } = useI18n();
const { callLogs, loadCallLogs, call } = useSoftphone();

onMounted(loadCallLogs);

const fmtDuration = seconds => {
  const s = Number(seconds) || 0;
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}:${String(r).padStart(2, '0')}`;
};

// "hace cuánto" en formato corto.
const fmtAgo = iso => {
  if (!iso) return '';
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (diff < 60) return t('JABVOX_SOFTPHONE.HISTORY.NOW');
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  return `${Math.floor(diff / 86400)}d`;
};

const redial = log => {
  emit('dial');
  call(log.phone_number, { name: log.contact_name });
};

const iconFor = log => {
  if (log.status === 'missed') return 'i-lucide-phone-missed text-n-ruby-9';
  if (log.direction === 'inbound')
    return 'i-lucide-phone-incoming text-n-teal-9';
  return 'i-lucide-phone-outgoing text-n-slate-11';
};
</script>

<template>
  <div class="flex flex-col max-h-64 overflow-y-auto">
    <p
      v-if="!callLogs.length"
      class="px-3 py-6 text-center text-xs text-n-slate-10"
    >
      {{ t('JABVOX_SOFTPHONE.HISTORY.EMPTY') }}
    </p>
    <button
      v-for="log in callLogs"
      :key="log.id"
      type="button"
      class="flex items-center gap-2 px-3 py-2 text-left border-b border-n-weak hover:bg-n-alpha-1"
      @click="redial(log)"
    >
      <span :class="iconFor(log)" class="text-base shrink-0" />
      <span class="flex-1 min-w-0">
        <span class="block text-sm text-n-slate-12 truncate">
          {{ log.contact_name || log.phone_number }}
        </span>
        <span class="block text-xs text-n-slate-10 truncate">
          {{ log.phone_number }} · {{ fmtDuration(log.duration_seconds) }}
        </span>
      </span>
      <span class="text-xs text-n-slate-10 shrink-0">{{
        fmtAgo(log.created_at)
      }}</span>
    </button>
  </div>
</template>
