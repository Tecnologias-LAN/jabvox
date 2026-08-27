<script setup>
// Teclado numérico 3x4 (0-9, *, #). Emite el dígito pulsado; la vista decide si lo
// agrega al número o lo envía como DTMF durante una llamada.
const emit = defineEmits(['press']);

const KEYS = [
  { digit: '1', sub: '' },
  { digit: '2', sub: 'ABC' },
  { digit: '3', sub: 'DEF' },
  { digit: '4', sub: 'GHI' },
  { digit: '5', sub: 'JKL' },
  { digit: '6', sub: 'MNO' },
  { digit: '7', sub: 'PQRS' },
  { digit: '8', sub: 'TUV' },
  { digit: '9', sub: 'WXYZ' },
  { digit: '*', sub: '' },
  { digit: '0', sub: '+' },
  { digit: '#', sub: '' },
];
</script>

<template>
  <div class="grid grid-cols-3 gap-2">
    <button
      v-for="key in KEYS"
      :key="key.digit"
      type="button"
      class="flex flex-col items-center justify-center h-12 rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 active:scale-95 transition-transform text-n-slate-12"
      @click="emit('press', key.digit)"
    >
      <span class="text-lg font-medium leading-none">{{ key.digit }}</span>
      <span v-if="key.sub" class="text-[10px] text-n-slate-10 mt-0.5">{{
        key.sub
      }}</span>
    </button>
  </div>
</template>
