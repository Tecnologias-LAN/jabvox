<script setup>
import { ref, watch, nextTick, onMounted, onBeforeUnmount } from 'vue';
import ImageResizer from './ImageResizer.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);

const editorRef = ref(null);
const editorWrap = ref(null);
const selectedImg = ref(null);
const activeFormats = ref({});
const currentFontSize = ref('14');
let isFocused = false;

const FONT_SIZES = [
  8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 36, 48, 60, 72,
];

// ── detect font size at cursor ────────────────────────────────────────────────
const detectFontSize = () => {
  const sel = window.getSelection();
  if (!sel?.anchorNode || !editorRef.value) return;
  const el =
    sel.anchorNode.nodeType === 3
      ? sel.anchorNode.parentElement
      : sel.anchorNode;
  let node = el;
  let found = '';
  while (node && node !== editorRef.value) {
    if (node.style?.fontSize) {
      found = node.style.fontSize.replace('px', '');
      break;
    }
    node = node.parentElement;
  }
  if (!found)
    found = Math.round(
      parseFloat(window.getComputedStyle(el).fontSize)
    ).toString();
  const snap = FONT_SIZES.reduce((p, c) =>
    Math.abs(c - Number(found)) < Math.abs(p - Number(found)) ? c : p
  );
  currentFontSize.value = String(snap);
};

const updateActiveFormats = () => {
  activeFormats.value = {
    bold: document.queryCommandState('bold'),
    italic: document.queryCommandState('italic'),
    underline: document.queryCommandState('underline'),
    strikethrough: document.queryCommandState('strikeThrough'),
    orderedList: document.queryCommandState('insertOrderedList'),
    bulletList: document.queryCommandState('insertUnorderedList'),
  };
  detectFontSize();
};

// ── sync model ────────────────────────────────────────────────────────────────
watch(
  () => props.modelValue,
  val => {
    if (!isFocused && editorRef.value && editorRef.value.innerHTML !== val)
      editorRef.value.innerHTML = val || '';
  },
  { immediate: true }
);

const onDocClick = e => {
  if (
    !editorWrap.value?.contains(e.target) &&
    !e.target.closest('.image-resizer-overlay') &&
    !e.target.closest('.img-float-bar')
  )
    selectedImg.value = null;
};

onMounted(() => {
  if (editorRef.value) editorRef.value.innerHTML = props.modelValue || '';
  document.addEventListener('selectionchange', updateActiveFormats);
  document.addEventListener('click', onDocClick);
});
onBeforeUnmount(() => {
  document.removeEventListener('selectionchange', updateActiveFormats);
  document.removeEventListener('click', onDocClick);
});

const onInput = () => emit('update:modelValue', editorRef.value.innerHTML);
const onFocus = () => {
  isFocused = true;
};
const onBlur = () => {
  isFocused = false;
};

// ── image selection ───────────────────────────────────────────────────────────
const imgBar = ref({ display: 'none' });
const imgBarWidth = ref('');

const refreshImgBar = img => {
  if (!img) {
    imgBar.value = { display: 'none' };
    imgBarWidth.value = '';
    return;
  }
  nextTick(() => {
    const r = img.getBoundingClientRect();
    imgBar.value = {
      position: 'fixed',
      top: `${Math.max(4, r.top - 46)}px`,
      left: `${Math.max(4, r.left)}px`,
      zIndex: '99999',
    };
    imgBarWidth.value = `${img.offsetWidth}px`;
  });
};

watch(selectedImg, refreshImgBar);

const onEditorClick = e => {
  if (e.target.tagName === 'IMG') {
    selectedImg.value = e.target;
  } else if (
    e.target.closest?.('.image-resizer-overlay') ||
    e.target.closest?.('.img-float-bar')
  ) {
    // keep selection
  } else if (!e.target.closest?.('[data-img-text]')) {
    const wrap = e.target.closest?.('[data-img-mode="behind"]');
    if (wrap) {
      const img = wrap.querySelector('img');
      if (img) {
        selectedImg.value = img;
        return;
      }
    }
    selectedImg.value = null;
  } else {
    selectedImg.value = null;
  }
};

const onResizeEnd = () => {
  onInput();
  if (selectedImg.value) refreshImgBar(selectedImg.value);
};

// ── text commands ─────────────────────────────────────────────────────────────
const exec = (cmd, val = null) => {
  editorRef.value.focus();
  document.execCommand(cmd, false, val);
  onInput();
  updateActiveFormats();
};

const applyFontSize = size => {
  editorRef.value.focus();
  document.execCommand('fontSize', false, 7);
  editorRef.value.querySelectorAll('font[size="7"]').forEach(f => {
    const s = document.createElement('span');
    s.style.fontSize = `${size}px`;
    s.innerHTML = f.innerHTML;
    f.replaceWith(s);
  });
  currentFontSize.value = String(size);
  onInput();
  updateActiveFormats();
};

const changeFontSize = delta => {
  const current = parseInt(currentFontSize.value, 10);
  const idx = FONT_SIZES.findIndex(s => s >= current);
  const next =
    delta > 0
      ? FONT_SIZES[Math.min(idx + 1, FONT_SIZES.length - 1)]
      : FONT_SIZES[Math.max(idx - 1, 0)];
  applyFontSize(next);
};

const currentTextColor = ref('#000000');
const currentBgColor = ref('#ffffff');
let savedRange = null;

const saveSelection = () => {
  const sel = window.getSelection();
  savedRange = sel?.rangeCount ? sel.getRangeAt(0).cloneRange() : null;
};

const restoreAndExec = (cmd, val) => {
  editorRef.value.focus();
  if (savedRange) {
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(savedRange);
  }
  document.execCommand(cmd, false, val);
  onInput();
  updateActiveFormats();
};

const setColor = e => {
  currentTextColor.value = e.target.value;
  restoreAndExec('foreColor', e.target.value);
};
const setBgColor = e => {
  currentBgColor.value = e.target.value;
  restoreAndExec('hiliteColor', e.target.value);
};
const setAlign = a =>
  exec(
    { left: 'justifyLeft', center: 'justifyCenter', right: 'justifyRight' }[a]
  );
const insertLink = () => {
  const u = prompt('URL del enlace:');
  if (u) exec('createLink', u);
};
const insertHRule = () => exec('insertHorizontalRule');

// ── images ────────────────────────────────────────────────────────────────────
const imageInput = ref(null);
const triggerImageUpload = () => imageInput.value?.click();

const insertBase64Image = src => {
  editorRef.value.focus();
  const img = document.createElement('img');
  img.src = src;
  img.style.maxWidth = '100%';
  const sel = window.getSelection();
  if (sel?.rangeCount) {
    const range = sel.getRangeAt(0);
    range.deleteContents();
    range.insertNode(img);
    range.setStartAfter(img);
    range.collapse(true);
    sel.removeAllRanges();
    sel.addRange(range);
  } else {
    editorRef.value.appendChild(img);
  }
  selectedImg.value = img;
  onInput();
};

const insertTextAtCaret = text => {
  editorRef.value.focus();
  const sel = window.getSelection();
  if (sel?.rangeCount) {
    const r = sel.getRangeAt(0);
    r.deleteContents();
    r.insertNode(document.createTextNode(text));
    r.collapse(false);
    sel.removeAllRanges();
    sel.addRange(r);
  } else {
    editorRef.value.appendChild(document.createTextNode(text));
  }
  onInput();
};

const insertImageFromFile = e => {
  const file = e.target.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = ev => insertBase64Image(ev.target.result);
  reader.readAsDataURL(file);
  e.target.value = '';
};

const onPaste = e => {
  const items = e.clipboardData?.items;
  if (!items) return;
  Array.from(items).some(item => {
    if (item.type.startsWith('image/')) {
      e.preventDefault();
      const reader = new FileReader();
      reader.onload = ev => insertBase64Image(ev.target.result);
      reader.readAsDataURL(item.getAsFile());
      return true;
    }
    return false;
  });
};

const onDrop = e => {
  const text =
    e.dataTransfer?.getData('text/jabvox-variable') ||
    e.dataTransfer?.getData('text/plain');
  if (!text) return;
  e.preventDefault();
  insertTextAtCaret(text);
};

// ── image layout ──────────────────────────────────────────────────────────────
const exitBehindMode = img => {
  const wrap = img.parentElement?.closest('[data-img-mode="behind"]');
  if (!wrap) return;
  img.removeAttribute('style');
  img.style.maxWidth = '100%';
  img.style.display = 'block';
  img.style.margin = '8px auto';
  wrap.parentNode.insertBefore(img, wrap);
  wrap.remove();
};

const setImgLayout = layout => {
  const img = selectedImg.value;
  if (!img) return;
  exitBehindMode(img);
  img.style.position = '';
  img.style.zIndex = '';
  img.style.inset = '';
  img.style.pointerEvents = '';
  img.style.height = 'auto';
  img.style.objectFit = '';

  if (layout === 'left') {
    img.style.float = 'left';
    img.style.display = '';
    img.style.margin = '0 16px 8px 0';
    if (!img.style.width) img.style.width = '45%';
  } else if (layout === 'right') {
    img.style.float = 'right';
    img.style.display = '';
    img.style.margin = '0 0 8px 16px';
    if (!img.style.width) img.style.width = '45%';
  } else if (layout === 'center') {
    img.style.float = '';
    img.style.display = 'block';
    img.style.margin = '8px auto';
    if (!img.style.width) img.style.width = '80%';
  } else {
    img.style.float = '';
    img.style.display = 'block';
    img.style.width = '100%';
    img.style.margin = '0';
  }
  onInput();
  nextTick(() => refreshImgBar(img));
};

// "Fondo": wrap image + text zone so text appears on top of image
const setImgBehind = () => {
  const img = selectedImg.value;
  if (!img) return;
  exitBehindMode(img);

  const wrap = document.createElement('div');
  wrap.setAttribute('data-img-mode', 'behind');
  wrap.style.cssText =
    'position:relative;overflow:hidden;min-height:220px;margin:4px 0;border-radius:8px;';

  img.style.cssText =
    'position:absolute;inset:0;width:100%;height:100%;object-fit:cover;z-index:0;pointer-events:none;margin:0;float:none;display:block;';

  const textZone = document.createElement('div');
  textZone.setAttribute('data-img-text', 'true');
  textZone.style.cssText =
    'position:relative;z-index:1;padding:32px 24px;min-height:220px;color:#fff;text-shadow:0 1px 4px rgba(0,0,0,.6);';
  textZone.innerHTML =
    '<p style="font-size:18px;font-weight:bold;">Escribe aquí tu texto</p>';

  img.parentNode.insertBefore(wrap, img);
  wrap.appendChild(img);
  wrap.appendChild(textZone);
  selectedImg.value = null;
  onInput();
};

const changeImgWidth = delta => {
  const img = selectedImg.value;
  if (!img) return;
  const w = Math.max(60, Math.min((img.offsetWidth || 300) + delta, 1200));
  img.style.width = `${w}px`;
  img.style.height = 'auto';
  imgBarWidth.value = `${w}px`;
  onInput();
};
</script>

<template>
  <div
    ref="editorWrap"
    class="email-editor rounded-xl border border-slate-200 dark:border-slate-600 overflow-visible flex flex-col"
  >
    <!-- ── Toolbar ── -->
    <div
      class="flex flex-wrap items-center gap-0.5 px-2 py-1.5 bg-slate-50 dark:bg-slate-800 border-b border-slate-200 dark:border-slate-600 rounded-t-xl"
    >
      <!-- Font size: A- / number / A+ -->
      <button
        class="toolbar-btn"
        :title="$t('JABVOX_EMAIL.EDITOR.FONT_DECREASE')"
        @mousedown.prevent="changeFontSize(-1)"
      >
        <span class="font-bold leading-none text-[11px]">{{
          $t('JABVOX_EMAIL.EDITOR.FONT_SIZE_LETTER')
        }}</span>
        <span class="font-bold leading-none text-[8px] mt-0.5">−</span>
      </button>
      <span
        class="text-xs text-slate-600 dark:text-slate-300 font-mono w-7 text-center select-none tabular-nums"
        >{{ currentFontSize }}</span
      >
      <button
        class="toolbar-btn"
        :title="$t('JABVOX_EMAIL.EDITOR.FONT_INCREASE')"
        @mousedown.prevent="changeFontSize(1)"
      >
        <span class="font-bold leading-none text-[14px]">{{
          $t('JABVOX_EMAIL.EDITOR.FONT_SIZE_LETTER')
        }}</span>
        <span class="font-bold leading-none text-[9px] mt-0.5">+</span>
      </button>

      <div class="w-px h-5 bg-slate-300 dark:bg-slate-600 mx-1" />

      <button
        class="toolbar-btn"
        :class="[activeFormats.bold && 'active']"
        :title="$t('JABVOX_EMAIL.EDITOR.BOLD')"
        @mousedown.prevent="exec('bold')"
      >
        <span class="i-lucide-bold w-3.5 h-3.5" />
      </button>
      <button
        class="toolbar-btn"
        :class="[activeFormats.italic && 'active']"
        :title="$t('JABVOX_EMAIL.EDITOR.ITALIC')"
        @mousedown.prevent="exec('italic')"
      >
        <span class="i-lucide-italic w-3.5 h-3.5" />
      </button>
      <button
        class="toolbar-btn"
        :class="[activeFormats.underline && 'active']"
        :title="$t('JABVOX_EMAIL.EDITOR.UNDERLINE')"
        @mousedown.prevent="exec('underline')"
      >
        <span class="i-lucide-underline w-3.5 h-3.5" />
      </button>
      <button
        class="toolbar-btn"
        :class="[activeFormats.strikethrough && 'active']"
        :title="$t('JABVOX_EMAIL.EDITOR.STRIKETHROUGH')"
        @mousedown.prevent="exec('strikeThrough')"
      >
        <span class="i-lucide-strikethrough w-3.5 h-3.5" />
      </button>

      <div class="w-px h-5 bg-slate-300 dark:bg-slate-600 mx-1" />

      <button
        class="toolbar-btn"
        :title="$t('JABVOX_EMAIL.EDITOR.ALIGN_LEFT')"
        @mousedown.prevent="setAlign('left')"
      >
        <span class="i-lucide-align-left w-3.5 h-3.5" />
      </button>
      <button
        class="toolbar-btn"
        :title="$t('JABVOX_EMAIL.EDITOR.ALIGN_CENTER')"
        @mousedown.prevent="setAlign('center')"
      >
        <span class="i-lucide-align-center w-3.5 h-3.5" />
      </button>
      <button
        class="toolbar-btn"
        :title="$t('JABVOX_EMAIL.EDITOR.ALIGN_RIGHT')"
        @mousedown.prevent="setAlign('right')"
      >
        <span class="i-lucide-align-right w-3.5 h-3.5" />
      </button>

      <div class="w-px h-5 bg-slate-300 dark:bg-slate-600 mx-1" />

      <button
        class="toolbar-btn"
        :class="[activeFormats.bulletList && 'active']"
        :title="$t('JABVOX_EMAIL.EDITOR.BULLET_LIST')"
        @mousedown.prevent="exec('insertUnorderedList')"
      >
        <span class="i-lucide-list w-3.5 h-3.5" />
      </button>
      <button
        class="toolbar-btn"
        :class="[activeFormats.orderedList && 'active']"
        :title="$t('JABVOX_EMAIL.EDITOR.ORDERED_LIST')"
        @mousedown.prevent="exec('insertOrderedList')"
      >
        <span class="i-lucide-list-ordered w-3.5 h-3.5" />
      </button>

      <div class="w-px h-5 bg-slate-300 dark:bg-slate-600 mx-1" />

      <label
        class="toolbar-btn relative overflow-hidden cursor-pointer flex-col gap-0 !min-w-[28px] !h-8"
        :title="$t('JABVOX_EMAIL.EDITOR.TEXT_COLOR')"
      >
        <span class="i-lucide-baseline w-3.5 h-3.5 mt-0.5" />
        <span
          class="block w-3.5 h-1 rounded-sm mt-0.5 shrink-0"
          :style="{ background: currentTextColor }"
        />
        <input
          type="color"
          :value="currentTextColor"
          class="absolute inset-0 opacity-0 w-full h-full cursor-pointer"
          @mousedown="saveSelection"
          @input="setColor"
        />
      </label>
      <label
        class="toolbar-btn relative overflow-hidden cursor-pointer flex-col gap-0 !min-w-[28px] !h-8"
        :title="$t('JABVOX_EMAIL.EDITOR.BG_COLOR')"
      >
        <span class="i-lucide-paint-bucket w-3.5 h-3.5 mt-0.5" />
        <span
          class="block w-3.5 h-1 rounded-sm mt-0.5 shrink-0"
          :style="{ background: currentBgColor }"
        />
        <input
          type="color"
          :value="currentBgColor"
          class="absolute inset-0 opacity-0 w-full h-full cursor-pointer"
          @mousedown="saveSelection"
          @input="setBgColor"
        />
      </label>

      <div class="w-px h-5 bg-slate-300 dark:bg-slate-600 mx-1" />

      <button
        class="toolbar-btn"
        :title="$t('JABVOX_EMAIL.EDITOR.LINK')"
        @mousedown.prevent="insertLink"
      >
        <span class="i-lucide-link w-3.5 h-3.5" />
      </button>
      <button
        class="toolbar-btn"
        :title="$t('JABVOX_EMAIL.EDITOR.HORIZONTAL_RULE')"
        @mousedown.prevent="insertHRule"
      >
        <span class="i-lucide-minus w-3.5 h-3.5" />
      </button>
      <button
        class="toolbar-btn"
        :title="$t('JABVOX_EMAIL.EDITOR.INSERT_IMAGE')"
        @mousedown.prevent="triggerImageUpload"
      >
        <span class="i-lucide-image w-3.5 h-3.5" />
      </button>
      <input
        ref="imageInput"
        type="file"
        accept="image/*"
        class="hidden"
        @change="insertImageFromFile"
      />
    </div>

    <!-- ── Canvas ── -->
    <div
      class="flex-1 overflow-y-auto bg-slate-100 dark:bg-slate-700 p-6 min-h-96 rounded-b-xl relative"
    >
      <div
        class="mx-auto bg-white shadow-md rounded-lg overflow-hidden max-w-[600px] font-[Arial,Helvetica,sans-serif]"
      >
        <div
          ref="editorRef"
          contenteditable="true"
          spellcheck="true"
          class="outline-none p-6 min-h-64 text-sm text-slate-800 leading-relaxed email-content break-words"
          @input="onInput"
          @focus="onFocus"
          @blur="onBlur"
          @paste="onPaste"
          @dragover.prevent
          @drop="onDrop"
          @click="onEditorClick"
          @keyup="updateActiveFormats"
          @mouseup="updateActiveFormats"
        />
      </div>
    </div>

    <!-- ── Image floating toolbar + resize overlay ── -->
    <teleport to="body">
      <!-- Image options bar (dark pill above selected image) -->
      <div v-if="selectedImg" class="img-float-bar" :style="imgBar">
        <!-- Layout -->
        <button
          class="ifb-btn"
          :title="$t('JABVOX_EMAIL.EDITOR.IMG_FLOAT_LEFT')"
          @mousedown.prevent="setImgLayout('left')"
        >
          <span class="i-lucide-align-left w-3.5 h-3.5" />
        </button>
        <button
          class="ifb-btn"
          :title="$t('JABVOX_EMAIL.EDITOR.IMG_CENTER')"
          @mousedown.prevent="setImgLayout('center')"
        >
          <span class="i-lucide-align-center w-3.5 h-3.5" />
        </button>
        <button
          class="ifb-btn"
          :title="$t('JABVOX_EMAIL.EDITOR.IMG_FLOAT_RIGHT')"
          @mousedown.prevent="setImgLayout('right')"
        >
          <span class="i-lucide-align-right w-3.5 h-3.5" />
        </button>
        <button
          class="ifb-btn"
          :title="$t('JABVOX_EMAIL.EDITOR.IMG_FULL_WIDTH')"
          @mousedown.prevent="setImgLayout('full')"
        >
          <span class="i-lucide-maximize-2 w-3.5 h-3.5" />
        </button>

        <div class="ifb-sep" />

        <!-- Behind text -->
        <button
          class="ifb-btn ifb-label"
          :title="$t('JABVOX_EMAIL.EDITOR.IMG_BEHIND_TITLE')"
          @mousedown.prevent="setImgBehind"
        >
          <span class="i-lucide-layers w-3.5 h-3.5" />
          <span>{{ $t('JABVOX_EMAIL.EDITOR.IMG_BEHIND_LABEL') }}</span>
        </button>

        <div class="ifb-sep" />

        <!-- Width -->
        <button
          class="ifb-btn"
          :title="$t('JABVOX_EMAIL.EDITOR.IMG_REDUCE')"
          @mousedown.prevent="changeImgWidth(-60)"
        >
          <span class="i-lucide-minus w-3.5 h-3.5" />
        </button>
        <span class="ifb-size">{{ imgBarWidth }}</span>
        <button
          class="ifb-btn"
          :title="$t('JABVOX_EMAIL.EDITOR.IMG_EXPAND')"
          @mousedown.prevent="changeImgWidth(60)"
        >
          <span class="i-lucide-plus w-3.5 h-3.5" />
        </button>
      </div>

      <ImageResizer :img="selectedImg" @resize-end="onResizeEnd" />
    </teleport>
  </div>
</template>

<style>
/* ── main toolbar buttons ── */
.toolbar-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 1px;
  min-width: 28px;
  height: 28px;
  padding: 0 4px;
  border-radius: 4px;
  color: #475569;
  cursor: pointer;
  transition: background-color 0.1s;
  background: transparent;
  border: none;
}
.toolbar-btn:hover {
  background-color: #e2e8f0;
}
.dark .toolbar-btn:hover {
  background-color: #334155;
}
.toolbar-btn.active {
  background-color: #dbeafe;
  color: #1d4ed8;
}
.dark .toolbar-btn.active {
  background-color: #1e3a5f;
  color: #93c5fd;
}

/* ── image floating bar ── */
.img-float-bar {
  display: flex;
  align-items: center;
  gap: 2px;
  background: #1e293b;
  border-radius: 10px;
  padding: 4px 8px;
  box-shadow: 0 6px 24px rgba(0, 0, 0, 0.4);
  user-select: none;
}
.ifb-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 4px;
  min-width: 30px;
  height: 30px;
  padding: 0 6px;
  border-radius: 6px;
  color: #94a3b8;
  background: transparent;
  border: none;
  cursor: pointer;
  font-size: 11px;
  transition:
    background 0.1s,
    color 0.1s;
  white-space: nowrap;
}
.ifb-btn:hover {
  background: #334155;
  color: #f1f5f9;
}
.ifb-label {
  gap: 5px;
}
.ifb-sep {
  width: 1px;
  height: 18px;
  background: #334155;
  margin: 0 2px;
  flex-shrink: 0;
}
.ifb-size {
  font-size: 11px;
  color: #64748b;
  min-width: 46px;
  text-align: center;
  font-family: monospace;
}

/* ── editor content ── */
.email-content img {
  max-width: 100%;
  height: auto;
  cursor: pointer;
}
.email-content h1,
.email-content h2,
.email-content h3 {
  font-weight: bold;
  margin: 0.4em 0;
}
.email-content p {
  margin: 0 0 0.5em;
}
.email-content ul {
  list-style: disc;
  padding-left: 1.5em;
  margin: 0.5em 0;
}
.email-content ol {
  list-style: decimal;
  padding-left: 1.5em;
  margin: 0.5em 0;
}
.email-content a {
  color: #4f46e5;
  text-decoration: underline;
}
.email-content hr {
  border: none;
  border-top: 1px solid #e2e8f0;
  margin: 1em 0;
}
</style>
