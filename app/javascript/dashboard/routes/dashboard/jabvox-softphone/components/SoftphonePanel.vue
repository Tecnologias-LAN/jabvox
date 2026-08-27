<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useSoftphone } from 'dashboard/composables/jabvox/useSoftphone';
import SoftphoneDialpad from './SoftphoneDialpad.vue';
import SoftphoneHistory from './SoftphoneHistory.vue';
import AudioSpectrum from './AudioSpectrum.vue';

const emit = defineEmits(['clickOutside']);
// Tarjeta del softphone. Coherente con el estilo del dashboard (tokens n-slate).
// Incluye: extensión + estado en la cabecera, pestañas marcador/historial, teclado físico,
// copiar/pegar, visualizadores de espectro (mic + remoto) y cierre al tocar fuera.
const { t } = useI18n();
const {
  state,
  dialedNumber,
  isMuted,
  isInCall,
  extension,
  currentTarget,
  call,
  hangup,
  pressDigit,
  clearNumber,
  toggleMute,
  setDialedNumber,
  close,
  getLocalStream,
  getRemoteStream,
} = useSoftphone();

const tab = ref('dial'); // 'dial' | 'history'

// --- Estado de conexión (cabecera) ---
const statusLabel = computed(() => {
  const labels = {
    disconnected: t('JABVOX_SOFTPHONE.STATUS.DISCONNECTED'),
    registering: t('JABVOX_SOFTPHONE.STATUS.REGISTERING'),
    registered: t('JABVOX_SOFTPHONE.STATUS.REGISTERED'),
    calling: t('JABVOX_SOFTPHONE.STATUS.CALLING'),
    in_call: t('JABVOX_SOFTPHONE.STATUS.IN_CALL'),
    failed: t('JABVOX_SOFTPHONE.STATUS.FAILED'),
  };
  return labels[state.value] || labels.disconnected;
});
const statusColor = computed(() => {
  if (['in_call', 'registered'].includes(state.value)) return 'bg-n-teal-9';
  if (['calling', 'registering'].includes(state.value)) return 'bg-n-amber-9';
  if (state.value === 'failed') return 'bg-n-ruby-9';
  return 'bg-n-slate-8';
});

const displayValue = computed(() =>
  isInCall.value && currentTarget.value.phone
    ? currentTarget.value.phone
    : dialedNumber.value
);

const handleCall = () => call();

// Input editable: acepta solo dígitos, +, *, #. Soporta seleccionar-todo,
// borrar, pegar de forma nativa. Sanea en cada cambio para evitar que se cuele
// texto (estados/atajos) en el número.
const onInput = e => {
  setDialedNumber(e.target.value);
  // reflejar el valor saneado en el input (por si se pegó algo con letras)
  if (e.target.value !== dialedNumber.value)
    e.target.value = dialedNumber.value;
};

// --- Copiar / pegar (botones y atajos de teclado) ---
const paste = async () => {
  try {
    const text = await navigator.clipboard.readText();
    setDialedNumber(text);
  } catch (e) {
    /* permiso denegado: se ignora */
  }
};
const copy = async () => {
  try {
    await navigator.clipboard.writeText(dialedNumber.value);
  } catch (e) {
    /* noop */
  }
};

// --- Teclado físico (DTMF en llamada) ---
// El input editable ya maneja dígitos/borrado/copiar/pegar/seleccionar-todo de forma
// NATIVA cuando tiene el foco, así que el listener global NO debe duplicar esa lógica:
// se limita a enviar DTMF durante una llamada activa (cuando no hay input con foco).
// El guard en window evita registrar el listener dos veces tras un re-montaje (HMR).
const onKeydown = e => {
  const tag = document.activeElement?.tagName;
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;

  // Solo en llamada: teclas 0-9 * # envían DTMF.
  if (isInCall.value && /^[0-9*#]$/.test(e.key)) {
    pressDigit(e.key);
    e.preventDefault();
  }
};

// --- Ocultar al tocar fuera del teléfono ---
// El launcher (panel + pestaña de flecha) tiene el atributo data-jabvox-softphone; un clic
// fuera de ese contenedor oculta el teléfono. No se oculta durante una llamada activa.
const onDocClick = e => {
  if (isInCall.value) return;
  const launcher = e.target.closest?.('[data-jabvox-softphone]');
  if (!launcher) emit('clickOutside');
};

onMounted(() => {
  // Guard para no acumular listeners (evita el bug del dígito multiplicado).
  if (!window.jabvoxSoftphoneKeydownBound) {
    window.jabvoxSoftphoneKeydownBound = onKeydown;
    document.addEventListener('keydown', onKeydown);
  }
  // click en captura, con un tick de retraso para no auto-cerrarse al abrir.
  setTimeout(() => document.addEventListener('click', onDocClick), 0);
});
onBeforeUnmount(() => {
  if (window.jabvoxSoftphoneKeydownBound === onKeydown) {
    document.removeEventListener('keydown', onKeydown);
    window.jabvoxSoftphoneKeydownBound = null;
  }
  document.removeEventListener('click', onDocClick);
});
</script>

<template>
  <div
    class="flex flex-col w-[calc(100vw-3.5rem)] max-w-xs sm:w-72 rounded-xl border border-n-weak bg-n-solid-2 shadow-lg overflow-hidden"
  >
    <!-- Cabecera: marca + extensión + estado -->
    <header
      class="flex items-center justify-between px-3 py-2 border-b border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span class="w-2 h-2 rounded-full shrink-0" :class="statusColor" />
        <div class="min-w-0">
          <div class="flex items-center gap-1">
            <!-- eslint-disable-next-line vue/no-bare-strings-in-template @intlify/vue-i18n/no-raw-text -->
            <span class="text-sm font-semibold text-n-slate-12">Jabvox</span>
            <span v-if="extension" class="text-xs text-n-slate-11">
              {{ `· ${t('JABVOX_SOFTPHONE.EXT')} ${extension}` }}
            </span>
          </div>
          <span class="block text-[11px] text-n-slate-10 truncate">{{
            statusLabel
          }}</span>
        </div>
      </div>
      <button
        type="button"
        class="p-1 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="t('JABVOX_SOFTPHONE.CLOSE')"
        @click="close"
      >
        <span class="i-lucide-x text-base" />
      </button>
    </header>

    <!-- Pestañas -->
    <div class="flex border-b border-n-weak text-xs">
      <button
        type="button"
        class="flex-1 py-2 font-medium"
        :class="
          tab === 'dial'
            ? 'text-n-slate-12 border-b-2 border-n-teal-9'
            : 'text-n-slate-10'
        "
        @click="tab = 'dial'"
      >
        {{ t('JABVOX_SOFTPHONE.TAB_DIAL') }}
      </button>
      <button
        type="button"
        class="flex-1 py-2 font-medium"
        :class="
          tab === 'history'
            ? 'text-n-slate-12 border-b-2 border-n-teal-9'
            : 'text-n-slate-10'
        "
        @click="tab = 'history'"
      >
        {{ t('JABVOX_SOFTPHONE.TAB_HISTORY') }}
      </button>
    </div>

    <!-- Marcador -->
    <div v-if="tab === 'dial'">
      <!-- Display + copiar/pegar -->
      <div class="px-3 pt-3">
        <div
          class="flex items-center gap-1 rounded-lg bg-n-alpha-1 px-3 py-2 min-h-[44px]"
        >
          <!-- Durante la llamada: solo lectura del destino. En reposo: input editable
               (seleccionar-todo, borrar, pegar nativos) que solo acepta dígitos/+/*/#. -->
          <span
            v-if="isInCall"
            class="flex-1 text-lg font-medium text-n-slate-12 truncate min-h-[1.5rem]"
            :title="displayValue"
          >
            {{ displayValue }}
          </span>
          <input
            v-else
            :value="dialedNumber"
            type="text"
            inputmode="tel"
            autocomplete="off"
            spellcheck="false"
            :placeholder="t('JABVOX_SOFTPHONE.CALL')"
            class="flex-1 min-w-0 bg-transparent text-lg font-medium text-n-slate-12 outline-none placeholder:text-n-slate-9 placeholder:text-sm"
            @input="onInput"
            @keydown.enter="dialedNumber && handleCall()"
          />
          <button
            v-if="dialedNumber && !isInCall"
            type="button"
            class="p-1 text-n-slate-10 hover:text-n-slate-12"
            :title="t('JABVOX_SOFTPHONE.COPY')"
            @click="copy"
          >
            <span class="i-lucide-copy text-sm" />
          </button>
          <button
            v-if="!isInCall"
            type="button"
            class="p-1 text-n-slate-10 hover:text-n-slate-12"
            :title="t('JABVOX_SOFTPHONE.PASTE')"
            @click="paste"
          >
            <span class="i-lucide-clipboard text-sm" />
          </button>
          <button
            v-if="dialedNumber && !isInCall"
            type="button"
            class="p-1 text-n-slate-10 hover:text-n-slate-12"
            :title="t('JABVOX_SOFTPHONE.CLEAR')"
            @click="clearNumber"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </div>
        <p
          v-if="isInCall && currentTarget.name"
          class="mt-1 text-xs text-n-slate-11 text-center truncate"
        >
          {{ currentTarget.name }}
        </p>
      </div>

      <!-- Visualizadores de espectro durante la llamada -->
      <div v-if="isInCall" class="px-3 pt-3 space-y-2">
        <div class="flex items-center gap-2">
          <span class="i-lucide-mic text-sm text-n-slate-10 shrink-0" />
          <AudioSpectrum
            :stream-provider="getLocalStream"
            :active="isInCall"
            color="#4CAF82"
          />
        </div>
        <div class="flex items-center gap-2">
          <span class="i-lucide-volume-2 text-sm text-n-slate-10 shrink-0" />
          <AudioSpectrum
            :stream-provider="getRemoteStream"
            :active="isInCall"
            remote
            color="#1A8FBF"
          />
        </div>
      </div>

      <!-- Teclado -->
      <div class="px-3 pt-3">
        <SoftphoneDialpad @press="pressDigit" />
      </div>

      <!-- Acciones -->
      <div class="flex items-center justify-center gap-3 px-3 py-4">
        <button
          v-if="isInCall"
          type="button"
          class="flex items-center justify-center w-10 h-10 rounded-full bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
          :class="{ 'text-n-ruby-9': isMuted }"
          :title="t('JABVOX_SOFTPHONE.MUTE')"
          @click="toggleMute"
        >
          <span
            :class="isMuted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
            class="text-lg"
          />
        </button>

        <button
          v-if="!isInCall"
          type="button"
          class="flex items-center justify-center flex-1 h-12 rounded-full bg-n-slate-12 text-n-solid-1 font-semibold disabled:opacity-50"
          :disabled="!dialedNumber"
          @click="handleCall"
        >
          <span class="i-lucide-phone text-lg mr-2" />
          {{ t('JABVOX_SOFTPHONE.CALL') }}
        </button>

        <button
          v-if="isInCall"
          type="button"
          class="flex items-center justify-center w-14 h-14 rounded-full bg-n-ruby-9 hover:bg-n-ruby-10 text-white shadow"
          :title="t('JABVOX_SOFTPHONE.HANGUP')"
          @click="hangup"
        >
          <span class="i-lucide-phone-off text-xl" />
        </button>
      </div>
    </div>

    <!-- Historial -->
    <SoftphoneHistory v-else @dial="tab = 'dial'" />
  </div>
</template>
