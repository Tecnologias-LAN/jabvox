<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import voiceBroadcastAPI from 'dashboard/api/jabvox/voiceBroadcast';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import VoiceBroadcastFormDialog from './components/VoiceBroadcastFormDialog.vue';
import VoiceBroadcastDetailDialog from './components/VoiceBroadcastDetailDialog.vue';

// Voice Broadcast: campañas de voz salientes (agente virtual). Lista, crea/edita
// y abre el detalle (audio, controles, monitor en vivo, reporte) de cada una.
const { t } = useI18n();

const broadcasts = ref([]);
const loading = ref(false);
const formDialog = ref(null);
const detailDialog = ref(null);

const STATUS_CLASS = {
  running: 'text-n-teal-11',
  paused: 'text-n-amber-11',
  stopped: 'text-n-ruby-11',
  completed: 'text-n-slate-11',
  draft: 'text-n-slate-10',
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await voiceBroadcastAPI.get();
    broadcasts.value = data || [];
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('JABVOX_VOICE_BROADCAST.LOAD_ERROR')
    );
  } finally {
    loading.value = false;
  }
};

const statusLabel = s =>
  t(`JABVOX_VOICE_BROADCAST.STATUS.${(s || 'draft').toUpperCase()}`);

const openCreate = () => formDialog.value?.open();
const openEdit = row => formDialog.value?.open(row);
const openDetail = row => detailDialog.value?.open(row);

const onSaved = () => load();
const onChanged = () => load();

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4 p-1">
    <header class="flex items-center justify-between">
      <div>
        <h1 class="text-lg font-semibold text-n-slate-12">
          {{ t('JABVOX_VOICE_BROADCAST.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 mt-0.5">
          {{ t('JABVOX_VOICE_BROADCAST.SUBTITLE') }}
        </p>
      </div>
      <Button
        :label="t('JABVOX_VOICE_BROADCAST.NEW')"
        icon="i-lucide-plus"
        size="sm"
        @click="openCreate"
      />
    </header>

    <div v-if="loading" class="flex items-center justify-center py-16">
      <Spinner :size="24" />
    </div>

    <div
      v-else-if="!broadcasts.length"
      class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
    >
      {{ t('JABVOX_VOICE_BROADCAST.EMPTY') }}
    </div>

    <div v-else class="overflow-x-auto rounded-lg border border-n-weak">
      <table class="w-full text-sm">
        <thead class="bg-n-alpha-1 text-n-slate-11">
          <tr>
            <th class="text-left px-3 py-2 font-medium">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.NAME') }}
            </th>
            <th class="text-left px-3 py-2 font-medium">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.STATUS') }}
            </th>
            <th class="text-right px-3 py-2 font-medium">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.TOTAL') }}
            </th>
            <th class="text-right px-3 py-2 font-medium">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.DIALED') }}
            </th>
            <th class="text-center px-3 py-2 font-medium">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.AUDIO') }}
            </th>
            <th class="text-right px-3 py-2 font-medium">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.ACTIONS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="b in broadcasts"
            :key="b.id"
            class="border-t border-n-weak text-n-slate-12"
          >
            <td class="px-3 py-2">{{ b.name }}</td>
            <td class="px-3 py-2 font-medium" :class="STATUS_CLASS[b.status]">
              {{ statusLabel(b.status) }}
            </td>
            <td class="px-3 py-2 text-right">{{ b.total }}</td>
            <td class="px-3 py-2 text-right">{{ b.dialed }}</td>
            <td class="px-3 py-2 text-center">
              <span
                :class="b.audio_ready ? 'text-n-teal-11' : 'text-n-slate-9'"
              >
                {{
                  b.audio_ready
                    ? t('JABVOX_VOICE_BROADCAST.AUDIO_READY')
                    : t('JABVOX_VOICE_BROADCAST.AUDIO_MISSING')
                }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end gap-1">
                <Button
                  :label="t('JABVOX_VOICE_BROADCAST.OPEN')"
                  size="xs"
                  variant="outline"
                  color="slate"
                  @click="openDetail(b)"
                />
                <Button
                  v-if="b.status === 'draft'"
                  icon="i-lucide-pencil"
                  size="xs"
                  variant="ghost"
                  color="slate"
                  @click="openEdit(b)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <VoiceBroadcastFormDialog ref="formDialog" @saved="onSaved" />
    <VoiceBroadcastDetailDialog ref="detailDialog" @changed="onChanged" />
  </div>
</template>
