<script setup>
import { ref, computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  options: {
    type: Array,
    required: true,
  },
  modelValue: {
    type: String,
    required: true,
  },
  label: {
    type: String,
    required: true,
  },
  subMenuPosition: {
    type: String,
    default: 'right',
    validator: value => {
      return ['right', 'left', 'bottom'].includes(value);
    },
  },
  // Cuando las etiquetas son largas (p. ej. "Respuesta pendiente: la más antigua
  // primero"), 'wide' ensancha el panel y desactiva el truncado para que cada
  // opción se lea completa. Por defecto se mantiene el comportamiento compacto.
  wide: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue']);

const isOpen = ref(false);

const labelValue = computed(() => props.label);

const toggleMenu = () => {
  isOpen.value = !isOpen.value;
};

const handleSelect = value => {
  emit('update:modelValue', value);
  isOpen.value = false;
};
</script>

<template>
  <div
    v-on-clickaway="() => (isOpen = false)"
    class="relative flex flex-col gap-1 min-w-0"
    :class="wide ? 'w-full' : 'w-fit'"
  >
    <Button
      icon="i-lucide-chevron-down"
      size="sm"
      trailing-icon
      color="slate"
      variant="faded"
      :class="[
        wide ? '!w-full max-w-full min-w-0' : '!w-fit max-w-40',
        { 'dark:!bg-n-alpha-2 !bg-n-slate-9/20': isOpen },
      ]"
      :label="labelValue"
      @click="toggleMenu"
    />
    <div
      v-if="isOpen"
      class="absolute select-none flex flex-col gap-1 bg-n-alpha-3 backdrop-blur-[100px] p-1 top-0 shadow-lg z-40 rounded-lg border border-n-weak dark:border-n-strong/50"
      :class="[
        wide ? 'min-w-64 w-max max-w-xs' : 'max-w-64',
        {
          'ltr:left-full rtl:right-full ltr:ml-1 rtl:mr-1':
            subMenuPosition === 'right',
          'ltr:right-full rtl:left-full ltr:mr-1 rtl:ml-1':
            subMenuPosition === 'left',
          'top-full mt-1 ltr:right-0 rtl:left-0': subMenuPosition === 'bottom',
        },
      ]"
    >
      <Button
        v-for="option in options"
        :key="option.value"
        :label="option.label"
        :icon="option.value === modelValue ? 'i-lucide-check' : ''"
        size="sm"
        variant="ghost"
        color="slate"
        :trailing-icon="!wide"
        class="!px-2.5"
        :class="[
          wide
            ? '!justify-start !h-auto !py-1.5 [&_span]:!whitespace-normal [&_span]:!overflow-visible [&_span]:!text-left'
            : '!justify-end !h-7',
          { '!bg-n-alpha-2': option.value === modelValue },
        ]"
        @click="handleSelect(option.value)"
      />
    </div>
  </div>
</template>
