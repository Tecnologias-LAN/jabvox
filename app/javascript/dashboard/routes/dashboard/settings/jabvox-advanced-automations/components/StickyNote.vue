<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { NOTE_COLORS, noteColorStyle } from '../composables/useFlowNotes';

// NOTA ADHESIVA: solo texto y solo visual. Va DETRÁS de los pasos y NO se
// ejecuta; el motor ni la mira. Se mueve, se redimensiona y se edita en el sitio.
const props = defineProps({
  note: { type: Object, required: true },
  selected: { type: Boolean, default: false },
  // Zoom del lienzo: el arrastre en píxeles de pantalla se divide por él para
  // que la nota siga al cursor sin desfase al estar alejado o acercado.
  zoom: { type: Number, default: 1 },
});

const emit = defineEmits(['update', 'select', 'delete', 'duplicate']);

const { t } = useI18n();

const editing = ref(false);
const textarea = ref(null);
const draft = ref('');

const style = computed(() => noteColorStyle(props.note.color));

// El texto se muestra tal cual, con los saltos de línea del usuario.
const hasText = computed(() => (props.note.text || '').trim().length > 0);

const boxStyle = computed(() => ({
  transform: `translate(${props.note.position.x}px, ${props.note.position.y}px)`,
  width: `${props.note.width}px`,
  height: `${props.note.height}px`,
}));

// La barra NO escala con el lienzo: a zoom bajo sus botones de 16 px quedarían
// de 4 px, imposibles de acertar. Se contra-escala y se ancla por su base.
const barStyle = computed(() => {
  const z = props.zoom > 0 ? props.zoom : 1;
  return {
    transform: `scale(${1 / z})`,
    transformOrigin: 'bottom left',
    bottom: '100%',
    marginBottom: `${6 / z}px`,
  };
});

function startEditing() {
  if (editing.value) return;
  draft.value = props.note.text || '';
  editing.value = true;
  // El textarea ya está montado (v-show), pero el foco se pide tras el repintado:
  // con `visibility` recién cambiada el navegador ignora un focus() inmediato.
  nextTick(() => {
    const el = textarea.value;
    if (!el) return;
    el.focus();
    // Nota vacía: no hay nada que seleccionar, solo colocar el cursor.
    if (draft.value) el.select();
  });
}

function commit() {
  if (!editing.value) return;
  editing.value = false;
  if (draft.value !== props.note.text) {
    emit('update', { ...props.note, text: draft.value });
  }
}

// Escape descarta la edición; Ctrl/Cmd+Enter la confirma. Enter solo salta de
// línea: es un bloque de texto, no un campo de una línea.
function onKeydown(event) {
  if (event.key === 'Escape') {
    editing.value = false;
    event.stopPropagation();
    return;
  }
  if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
    commit();
    event.stopPropagation();
  }
}

// ---- Arrastre y redimensionado ------------------------------------------

// Un solo gestor para las dos cosas: se captura en `window` porque el puntero
// se sale de la nota en cuanto el movimiento es rápido.
// Umbral en px de pantalla: por debajo no es un arrastre, es un clic. Sin esto
// el `preventDefault` del pointerdown mataba el foco y la selección de texto.
const DRAG_THRESHOLD = 3;

// Un arrastre real traga el `click` que el navegador emite después; sin esta
// marca el doble clic siguiente se perdía y no se podía volver a editar.
const dragged = ref(false);

function beginDrag(event, mode) {
  if (editing.value) return;
  // Solo el botón principal: con el derecho o el medio no se arrastra, y dejar
  // gestores colgados en `window` bloqueaba el doble clic posterior.
  if (event.button !== 0) return;
  event.stopPropagation();
  emit('select', props.note.id);

  const start = { x: event.clientX, y: event.clientY };
  const origin = {
    x: props.note.position.x,
    y: props.note.position.y,
    width: props.note.width,
    height: props.note.height,
  };
  const zoom = props.zoom || 1;
  let active = false;

  const onMove = move => {
    const rawX = move.clientX - start.x;
    const rawY = move.clientY - start.y;
    if (!active) {
      if (Math.abs(rawX) < DRAG_THRESHOLD && Math.abs(rawY) < DRAG_THRESHOLD) {
        return;
      }
      active = true;
      dragged.value = true;
    }
    // Solo al arrastrar de verdad: cancelar la selección de texto del navegador.
    move.preventDefault();
    const dx = rawX / zoom;
    const dy = rawY / zoom;
    if (mode === 'move') {
      emit('update', {
        ...props.note,
        position: { x: origin.x + dx, y: origin.y + dy },
      });
    } else {
      emit('update', {
        ...props.note,
        width: Math.max(160, Math.round(origin.width + dx)),
        height: Math.max(90, Math.round(origin.height + dy)),
      });
    }
  };
  const onUp = () => {
    window.removeEventListener('pointermove', onMove);
    window.removeEventListener('pointerup', onUp);
    window.removeEventListener('pointercancel', onUp);
    // Se libera en el tic siguiente, ya consumido el `click` del arrastre.
    if (dragged.value)
      nextTick(() => {
        dragged.value = false;
      });
  };
  window.addEventListener('pointermove', onMove);
  window.addEventListener('pointerup', onUp);
  // Sin esto un arrastre interrumpido (el navegador roba el puntero) dejaba el
  // gestor de `pointermove` vivo y la nota seguía al ratón sin botón pulsado.
  window.addEventListener('pointercancel', onUp);
}

// Al cambiar de nota seleccionada se sale de la edición: el texto a medias se
// guardaría igualmente al perder el foco, pero el cursor no debe quedar suelto.
watch(
  () => props.selected,
  isSelected => {
    if (!isSelected) commit();
  }
);
</script>

<template>
  <!-- `pointer-events-auto` es necesario: la capa contenedora los desactiva
  para que los clics del lienzo (panear, seleccionar) lleguen al fondo. -->
  <div
    class="jf-note pointer-events-auto absolute left-0 top-0 origin-top-left rounded-xl border shadow-sm transition-shadow"
    :class="[style.box, selected ? 'ring-2 ring-n-brand' : 'hover:shadow-md']"
    :style="boxStyle"
    @pointerdown="beginDrag($event, 'move')"
    @dblclick.stop="startEditing"
  >
    <!-- Barra flotante ENCIMA de la nota: colores y acciones. Solo con la nota
    activa. `bottom: 100%` la ancla al borde superior sea cual sea su alto. -->
    <div
      v-if="selected && !editing"
      class="absolute left-0 z-10 flex items-center gap-1 rounded-lg border border-n-weak bg-n-solid-1 px-1 py-1 shadow-md"
      :style="barStyle"
      @pointerdown.stop
      @dblclick.stop
    >
      <button
        v-for="color in NOTE_COLORS"
        :key="color"
        type="button"
        class="size-4 rounded-full border border-n-weak transition-transform hover:scale-110"
        :class="[
          noteColorStyle(color).swatch,
          color === note.color ? 'ring-1 ring-n-brand ring-offset-1' : '',
        ]"
        :title="t(`JABVOX_ADVANCED_AUTOMATIONS.NOTES.COLORS.${color}`)"
        @click.stop="emit('update', { ...note, color })"
      />
      <span class="mx-0.5 h-4 w-px bg-n-weak" />
      <button
        type="button"
        class="flex size-6 items-center justify-center rounded-md text-n-slate-11 transition-colors hover:bg-n-alpha-2"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.NOTES.EDIT')"
        @click.stop="startEditing"
      >
        <span class="i-lucide-pencil size-3.5" />
      </button>
      <button
        type="button"
        class="flex size-6 items-center justify-center rounded-md text-n-slate-11 transition-colors hover:bg-n-alpha-2"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.NOTES.DUPLICATE')"
        @click.stop="emit('duplicate', note.id)"
      >
        <span class="i-lucide-copy size-3.5" />
      </button>
      <button
        type="button"
        class="flex size-6 items-center justify-center rounded-md text-n-ruby-11 transition-colors hover:bg-n-ruby-3"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.NOTES.DELETE')"
        @click.stop="emit('delete', note.id)"
      >
        <span class="i-lucide-trash-2 size-3.5" />
      </button>
    </div>

    <!-- `v-show`, NO `v-if`: el textarea existe siempre, así el focus() nunca
    depende de que Vue acabe de montarlo. -->
    <textarea
      v-show="editing"
      ref="textarea"
      v-model="draft"
      class="nodrag nopan nowheel size-full cursor-text resize-none select-text rounded-xl border-0 bg-transparent p-3 text-sm leading-relaxed outline-none"
      :class="style.text"
      :placeholder="t('JABVOX_ADVANCED_AUTOMATIONS.NOTES.PLACEHOLDER')"
      @pointerdown.stop
      @keydown="onKeydown"
      @blur="commit"
    />
    <!-- Nota vacía: el div ocupa toda la caja igualmente (`size-full`), así que
    el doble clic tiene dónde caer aunque no haya una sola letra. -->
    <div
      v-show="!editing"
      class="size-full select-text overflow-hidden whitespace-pre-wrap break-words p-3 text-sm leading-relaxed"
      :class="hasText ? style.text : style.placeholder"
    >
      {{
        hasText ? note.text : t('JABVOX_ADVANCED_AUTOMATIONS.NOTES.PLACEHOLDER')
      }}
    </div>

    <!-- Asa de redimensionado en la esquina inferior derecha. `.stop` es
    OBLIGATORIO: sin él el pointerdown burbujeaba a la caja y abría un segundo
    arrastre 'move' a la vez, moviendo y redimensionando de golpe. -->
    <button
      v-if="!editing"
      type="button"
      class="absolute -bottom-0.5 -right-0.5 flex size-4 cursor-nwse-resize items-center justify-center rounded-br-xl opacity-0 transition-opacity group-hover:opacity-100"
      :class="[style.handle, selected ? '!opacity-100' : '']"
      :title="t('JABVOX_ADVANCED_AUTOMATIONS.NOTES.RESIZE')"
      @pointerdown.stop="beginDrag($event, 'resize')"
      @dblclick.stop
    />
  </div>
</template>

<style scoped>
/* La nota está DETRÁS de los pasos, así que su asa no debe robar el cursor de
   arrastre del lienzo cuando la nota no está activa. */
.jf-note:hover .cursor-nwse-resize {
  opacity: 1;
}
</style>
