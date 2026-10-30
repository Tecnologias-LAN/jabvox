<script setup>
import { computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useSoftphone } from 'dashboard/composables/jabvox/useSoftphone';
import SoftphonePanel from './SoftphonePanel.vue';

const { t } = useI18n();

// Lanzador global del softphone. Se monta una vez (en Dashboard.vue). El teléfono se
// oculta/saca con una pestaña de flecha en el borde derecho. Gateado por el módulo
// jabvox_softphone de la cuenta ACTIVA (multi-cuenta: un usuario puede tener extensiones
// distintas en cada cuenta y siempre usa la de la cuenta en la que está).
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const isEnabled = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.JABVOX_SOFTPHONE
  )
);

const { isOpen, isInCall, open, hide, call, handleAccountSwitch } =
  useSoftphone();

// Punto de entrada de los 3 orígenes (manual/click-to-call/dialer): emiten este evento y
// el softphone llama desde la extensión del usuario en la cuenta actual.
const onDialRequest = ({ number, name } = {}) => {
  if (!isEnabled.value || !number) return;
  call(number, { name });
};

onMounted(() => emitter.on('jabvox.softphone.dial', onDialRequest));
onBeforeUnmount(() => emitter.off('jabvox.softphone.dial', onDialRequest));

// Al cambiar de cuenta activa, re-registrar con la extensión de la nueva cuenta.
watch(accountId, () => handleAccountSwitch());

// La pestaña de flecha alterna mostrar/ocultar el softphone. Ocultar usa hide()
// (solo esconde la vista, SIGUE registrado y recibiendo llamadas), no minimize()
// —que no cambiaba isOpen y dejaba el botón sin poder cerrar—.
const toggle = () => (isOpen.value ? hide() : open());
</script>

<template>
  <div
    v-show="isEnabled"
    data-jabvox-softphone
    class="fixed z-50 flex items-end right-0 bottom-24 sm:bottom-28"
  >
    <!-- Pestaña con flecha para ocultar/sacar el teléfono -->
    <button
      type="button"
      class="flex items-center justify-center w-6 self-center h-16 rounded-l-lg bg-n-slate-12 text-n-solid-1 shadow-lg hover:bg-n-slate-11 transition-colors"
      :title="isOpen ? t('JABVOX_SOFTPHONE.HIDE') : t('JABVOX_SOFTPHONE.SHOW')"
      @click="toggle"
    >
      <span
        class="text-lg transition-transform"
        :class="isOpen ? 'i-lucide-chevron-right' : 'i-lucide-chevron-left'"
      />
      <span
        v-if="isInCall && !isOpen"
        class="absolute top-1 left-1 w-2.5 h-2.5 rounded-full bg-n-teal-9 animate-pulse"
      />
    </button>

    <!-- Panel deslizante del marcador -->
    <transition
      enter-active-class="transition-transform duration-200 ease-out"
      leave-active-class="transition-transform duration-200 ease-in"
      enter-from-class="translate-x-full"
      leave-to-class="translate-x-full"
    >
      <div v-show="isOpen" class="mr-2">
        <SoftphonePanel @click-outside="hide" />
      </div>
    </transition>
  </div>
</template>
