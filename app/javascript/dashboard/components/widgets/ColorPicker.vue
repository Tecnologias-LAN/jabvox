<script>
import { defineAsyncComponent } from 'vue';

// @lk77/vue3-color pesa ~269 KB. Se carga de forma diferida (solo al abrir el
// selector de color), no en el bundle de arranque. El <Chrome> ya estaba tras un
// v-if, así que el componente async solo se resuelve cuando el usuario lo abre.
const Chrome = defineAsyncComponent(() =>
  import('@lk77/vue3-color').then(m => m.Chrome)
);

export default {
  components: {
    Chrome,
  },
  props: {
    modelValue: {
      type: String,
      default: '',
    },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      isPickerOpen: false,
    };
  },
  methods: {
    closeTogglePicker() {
      if (this.isPickerOpen) {
        this.toggleColorPicker();
      }
    },
    toggleColorPicker() {
      this.isPickerOpen = !this.isPickerOpen;
    },
    updateColor(e) {
      this.$emit('update:modelValue', e.hex);
    },
  },
};
</script>

<template>
  <div class="colorpicker">
    <div
      class="colorpicker--selected"
      :style="`background-color: ${modelValue}`"
      @click.prevent="toggleColorPicker"
    />
    <Chrome
      v-if="isPickerOpen"
      v-on-clickaway="closeTogglePicker"
      disable-alpha
      :model-value="modelValue"
      class="colorpicker--chrome"
      @update:model-value="updateColor"
    />
  </div>
</template>

<style scoped lang="scss">
.colorpicker {
  position: relative;
}

.colorpicker--selected {
  @apply border border-solid border-n-weak rounded cursor-pointer h-8 w-8 mb-4;
}

.colorpicker--chrome.vc-chrome {
  @apply shadow-lg -mt-2.5 absolute z-[9999] border border-solid border-n-weak rounded;

  :deep(input) {
    @apply bg-white dark:bg-white;
  }
}
</style>
