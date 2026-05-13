<script setup>
/**
 * ImageResizer — overlay with 8 resize handles for a selected <img> element.
 * Mount it once inside EmailBodyEditor; it auto-shows/hides based on `img` prop.
 */
import { ref, watch, nextTick, onMounted, onBeforeUnmount } from 'vue';

const props = defineProps({
  img: { type: Object, default: null }, // the selected HTMLImageElement
});
const emit = defineEmits(['resizeEnd']);

// ─── overlay box ─────────────────────────────────────────────────────────────
const visible = ref(false);
const overlayRef = ref(null);

const HANDLES = ['nw', 'n', 'ne', 'w', 'e', 'sw', 's', 'se'];

const HANDLE_CLASSES = {
  nw: 'absolute top-[-5px] left-[-5px] cursor-nw-resize',
  n: 'absolute top-[-5px] left-[calc(50%_-_5px)] cursor-n-resize',
  ne: 'absolute top-[-5px] right-[-5px] cursor-ne-resize',
  w: 'absolute top-[calc(50%_-_5px)] left-[-5px] cursor-w-resize',
  e: 'absolute top-[calc(50%_-_5px)] right-[-5px] cursor-e-resize',
  sw: 'absolute bottom-[-5px] left-[-5px] cursor-sw-resize',
  s: 'absolute bottom-[-5px] left-[calc(50%_-_5px)] cursor-s-resize',
  se: 'absolute bottom-[-5px] right-[-5px] cursor-se-resize',
};

// position the overlay over the image
const reposition = () => {
  if (!props.img) {
    visible.value = false;
    return;
  }
  const r = props.img.getBoundingClientRect();
  visible.value = true;
  nextTick(() => {
    if (!overlayRef.value) return;
    overlayRef.value.style.top = `${r.top + window.scrollY}px`;
    overlayRef.value.style.left = `${r.left + window.scrollX}px`;
    overlayRef.value.style.width = `${r.width}px`;
    overlayRef.value.style.height = `${r.height}px`;
  });
};

watch(
  () => props.img,
  img => {
    if (img) reposition();
    else visible.value = false;
  }
);

// reposition on scroll / resize
const onScroll = () => {
  if (props.img) reposition();
};
onMounted(() => {
  window.addEventListener('scroll', onScroll, true);
  window.addEventListener('resize', onScroll);
});
onBeforeUnmount(() => {
  window.removeEventListener('scroll', onScroll, true);
  window.removeEventListener('resize', onScroll);
});

// ─── drag logic ──────────────────────────────────────────────────────────────
let dragging = null; // { handle, startX, startY, origW, origH, origLeft, origTop, imgEl }

const onMouseMove = e => {
  if (!dragging) return;
  const { handle, startX, startY, origW, origH, aspect, imgEl } = dragging;
  const dx = e.clientX - startX;
  const dy = e.clientY - startY;

  let newW = origW;
  let newH = origH;

  if (handle.includes('e')) newW = Math.max(40, origW + dx);
  if (handle.includes('w')) newW = Math.max(40, origW - dx);
  if (handle.includes('s')) newH = Math.max(40, origH + dy);
  if (handle.includes('n')) newH = Math.max(40, origH - dy);

  // corners: keep aspect ratio always
  if (handle.length === 2) {
    if (handle.includes('e') || handle.includes('w')) {
      newH = newW / aspect;
    } else {
      newW = newH * aspect;
    }
  }

  imgEl.style.width = `${Math.round(newW)}px`;
  imgEl.style.height = `${Math.round(newH)}px`;
  imgEl.removeAttribute('width');
  imgEl.removeAttribute('height');
  reposition();
};

const onMouseUp = () => {
  document.removeEventListener('mousemove', onMouseMove);
  document.removeEventListener('mouseup', onMouseUp);
  dragging = null;
  emit('resizeEnd');
};

const onHandleMouseDown = (e, handle) => {
  e.preventDefault();
  e.stopPropagation();
  const img = props.img;
  if (!img) return;

  dragging = {
    handle,
    startX: e.clientX,
    startY: e.clientY,
    origW: img.offsetWidth,
    origH: img.offsetHeight,
    aspect: img.offsetWidth / img.offsetHeight,
    imgEl: img,
  };

  document.addEventListener('mousemove', onMouseMove);
  document.addEventListener('mouseup', onMouseUp);
};
</script>

<template>
  <div
    v-if="visible"
    ref="overlayRef"
    class="image-resizer-overlay absolute pointer-events-none z-[9999]"
  >
    <!-- selection border -->
    <div
      class="absolute inset-0 border-2 border-woot-500 pointer-events-none"
    />

    <!-- 8 handles -->
    <div
      v-for="handle in HANDLES"
      :key="handle"
      class="w-2.5 h-2.5 bg-white border-2 border-indigo-500 rounded-sm pointer-events-auto"
      :class="[HANDLE_CLASSES[handle]]"
      @mousedown="onHandleMouseDown($event, handle)"
    />
  </div>
</template>
