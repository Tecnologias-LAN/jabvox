<script setup>
/**
 * Campos que exigen los tipos de plantilla que Meta soporta además del
 * estándar: autenticación (código OTP), header de ubicación, carrusel, oferta
 * por tiempo limitado y botón de cupón.
 *
 * En envío masivo estos valores son FIJOS para toda la audiencia (igual que el
 * media del header): el mapeo por columna del CSV solo aplica a las variables
 * del cuerpo. Eso se avisa en la propia UI para no dar a entender que se puede
 * personalizar por destinatario.
 *
 * Ver docs/whatsapp-flows/templates-sending-architecture.md.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  isAuthenticationTemplate,
  hasLocationHeader,
  hasCarousel,
  hasLimitedTimeOffer,
  getCarouselCards,
} from 'dashboard/helper/templateHelper';

const props = defineProps({
  // Plantilla elegida, tal como la devuelve Meta (con `components`).
  template: { type: Object, default: null },
  // { authCode, location, ltoExpirationMs, copyCode, cards }
  modelValue: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const tpl = computed(() => props.template || {});

const isAuth = computed(() => isAuthenticationTemplate(tpl.value));
const isLocation = computed(() => hasLocationHeader(tpl.value));
const isCarousel = computed(() => hasCarousel(tpl.value));
const isLto = computed(() => hasLimitedTimeOffer(tpl.value));

const copyCodeButtonIndex = computed(() => {
  const buttons =
    (tpl.value.components || []).find(c => c.type === 'BUTTONS')?.buttons || [];
  return buttons.findIndex(b => b.type === 'COPY_CODE');
});
const hasCopyCode = computed(() => copyCodeButtonIndex.value >= 0);

const cardDefinitions = computed(() =>
  getCarouselCards(tpl.value).map((card, index) => ({
    index,
    buttons: (
      (card.components || []).find(c => c.type === 'BUTTONS')?.buttons || []
    ).map((button, buttonIndex) => ({ ...button, index: buttonIndex })),
  }))
);

// ¿Esta plantilla necesita algún campo extra? Si no, el bloque no se muestra.
const isVisible = computed(
  () =>
    isAuth.value ||
    isLocation.value ||
    isCarousel.value ||
    isLto.value ||
    hasCopyCode.value
);

const update = patch =>
  emit('update:modelValue', { ...props.modelValue, ...patch });

const updateLocation = (field, value) =>
  update({
    location: { ...(props.modelValue.location || {}), [field]: value },
  });

const updateCard = (cardIndex, patch) => {
  const cards = [...(props.modelValue.cards || [])];
  cards[cardIndex] = { ...(cards[cardIndex] || {}), ...patch };
  update({ cards });
};

const updateCardMedia = (cardIndex, mediaUrl) =>
  updateCard(cardIndex, { header: { media_url: mediaUrl } });

const updateCardButton = (cardIndex, buttonIndex, parameter) => {
  const buttons = [...(props.modelValue.cards?.[cardIndex]?.buttons || [])];
  buttons[buttonIndex] = { index: buttonIndex, parameter };
  updateCard(cardIndex, { buttons });
};

// El input entrega 'YYYY-MM-DDTHH:mm'; Meta espera epoch en milisegundos.
const updateLto = value => {
  const parsed = value ? new Date(value).getTime() : '';
  update({ ltoExpirationMs: Number.isNaN(parsed) ? '' : parsed });
};

const inputClass =
  'reset-base w-full text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2';
</script>

<template>
  <div v-show="isVisible" class="flex flex-col gap-4">
    <p class="text-xs text-n-slate-11">
      {{ t('JABVOX_BULK_WA.EXTRAS.FIXED_FOR_ALL') }}
    </p>

    <!-- Autenticación: Meta genera el cuerpo; solo se envía el código. -->
    <div v-if="isAuth" class="flex flex-col gap-1.5">
      <label class="text-sm font-medium">
        {{ t('JABVOX_BULK_WA.EXTRAS.AUTH_CODE') }}
      </label>
      <input
        :value="modelValue.authCode || ''"
        type="text"
        :class="inputClass"
        :placeholder="t('JABVOX_BULK_WA.EXTRAS.AUTH_CODE_PLACEHOLDER')"
        @input="update({ authCode: $event.target.value })"
      />
    </div>

    <!-- Botón de cupón (COPY_CODE). -->
    <div v-if="hasCopyCode" class="flex flex-col gap-1.5">
      <label class="text-sm font-medium">
        {{ t('JABVOX_BULK_WA.EXTRAS.COPY_CODE') }}
      </label>
      <input
        :value="modelValue.copyCode || ''"
        type="text"
        maxlength="15"
        :class="inputClass"
        :placeholder="t('JABVOX_BULK_WA.EXTRAS.COPY_CODE_PLACEHOLDER')"
        @input="update({ copyCode: $event.target.value })"
      />
    </div>

    <!-- Header de ubicación: se completa al enviar. -->
    <div v-if="isLocation" class="flex flex-col gap-2">
      <label class="text-sm font-medium">
        {{ t('JABVOX_BULK_WA.EXTRAS.LOCATION') }}
      </label>
      <div class="grid grid-cols-2 gap-2">
        <input
          :value="modelValue.location?.latitude || ''"
          type="text"
          :class="inputClass"
          :placeholder="t('JABVOX_BULK_WA.EXTRAS.LATITUDE')"
          @input="updateLocation('latitude', $event.target.value)"
        />
        <input
          :value="modelValue.location?.longitude || ''"
          type="text"
          :class="inputClass"
          :placeholder="t('JABVOX_BULK_WA.EXTRAS.LONGITUDE')"
          @input="updateLocation('longitude', $event.target.value)"
        />
      </div>
      <input
        :value="modelValue.location?.name || ''"
        type="text"
        :class="inputClass"
        :placeholder="t('JABVOX_BULK_WA.EXTRAS.PLACE_NAME')"
        @input="updateLocation('name', $event.target.value)"
      />
      <input
        :value="modelValue.location?.address || ''"
        type="text"
        :class="inputClass"
        :placeholder="t('JABVOX_BULK_WA.EXTRAS.ADDRESS')"
        @input="updateLocation('address', $event.target.value)"
      />
    </div>

    <!-- Oferta por tiempo limitado. -->
    <div v-if="isLto" class="flex flex-col gap-1.5">
      <label class="text-sm font-medium">
        {{ t('JABVOX_BULK_WA.EXTRAS.LTO') }}
      </label>
      <input
        type="datetime-local"
        :class="inputClass"
        @input="updateLto($event.target.value)"
      />
      <p class="text-xs text-n-slate-11">
        {{ t('JABVOX_BULK_WA.EXTRAS.LTO_HELP') }}
      </p>
    </div>

    <!-- Carrusel: una tarjeta por cada una aprobada en la plantilla. -->
    <div v-if="isCarousel" class="flex flex-col gap-2">
      <label class="text-sm font-medium">
        {{ t('JABVOX_BULK_WA.EXTRAS.CAROUSEL') }}
      </label>
      <div
        v-for="card in cardDefinitions"
        :key="`card-${card.index}`"
        class="flex flex-col gap-2 p-2.5 rounded-lg border border-n-weak"
      >
        <p class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_BULK_WA.EXTRAS.CARD', { number: card.index + 1 }) }}
        </p>
        <input
          :value="modelValue.cards?.[card.index]?.header?.media_url || ''"
          type="url"
          :class="inputClass"
          :placeholder="t('JABVOX_BULK_WA.EXTRAS.CARD_MEDIA')"
          @input="updateCardMedia(card.index, $event.target.value)"
        />
        <input
          v-for="button in card.buttons"
          :key="`card-${card.index}-btn-${button.index}`"
          :value="
            modelValue.cards?.[card.index]?.buttons?.[button.index]
              ?.parameter || ''
          "
          type="text"
          :class="inputClass"
          :placeholder="
            t('JABVOX_BULK_WA.EXTRAS.CARD_BUTTON', {
              label: button.text || button.index + 1,
            })
          "
          @input="
            updateCardButton(card.index, button.index, $event.target.value)
          "
        />
      </div>
    </div>
  </div>
</template>
