<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import ImageResizer from './ImageResizer.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);

const editorRef = ref(null);
const editorWrap = ref(null);
const selectedImg = ref(null);
const activeFormats = ref({});
let isFocused = false;

// ─── font sizes ───────────────────────────────────────────────────────────────
const FONT_SIZES = ['12', '14', '16', '18', '20', '24', '32'];

// ─── format state ────────────────────────────────────────────────────────────
const updateActiveFormats = () => {
  activeFormats.value = {
    bold: document.queryCommandState('bold'),
    italic: document.queryCommandState('italic'),
    underline: document.queryCommandState('underline'),
    strikethrough: document.queryCommandState('strikeThrough'),
    orderedList: document.queryCommandState('insertOrderedList'),
    bulletList: document.queryCommandState('insertUnorderedList'),
  };
};

// ─── sync incoming value ─────────────────────────────────────────────────────
watch(
  () => props.modelValue,
  val => {
    if (!isFocused && editorRef.value && editorRef.value.innerHTML !== val) {
      editorRef.value.innerHTML = val || '';
    }
  },
  { immediate: true }
);

onMounted(() => {
  if (editorRef.value) editorRef.value.innerHTML = props.modelValue || '';
  document.addEventListener('selectionchange', updateActiveFormats);
});

onBeforeUnmount(() => {
  document.removeEventListener('selectionchange', updateActiveFormats);
});

// ─── emit ────────────────────────────────────────────────────────────────────
const onInput = () => emit('update:modelValue', editorRef.value.innerHTML);
const onFocus = () => {
  isFocused = true;
};
const onBlur = () => {
  isFocused = false;
};

// ─── image selection ─────────────────────────────────────────────────────────
const onEditorClick = e => {
  if (e.target.tagName === 'IMG') {
    selectedImg.value = e.target;
  } else if (!e.target.closest?.('.image-resizer-overlay')) {
    selectedImg.value = null;
  }
};

// deselect when clicking anywhere outside the editor or overlay
const onDocClick = e => {
  if (
    !editorWrap.value?.contains(e.target) &&
    !e.target.closest('.image-resizer-overlay')
  ) {
    selectedImg.value = null;
  }
};

onMounted(() => document.addEventListener('click', onDocClick));
onBeforeUnmount(() => document.removeEventListener('click', onDocClick));

const onResizeEnd = () => {
  onInput();
};

// ─── toolbar commands ─────────────────────────────────────────────────────────
const exec = (cmd, val = null) => {
  editorRef.value.focus();
  document.execCommand(cmd, false, val);
  onInput();
  updateActiveFormats();
};

const setHeading = e => {
  const val = e.target.value;
  exec('formatBlock', val === 'p' ? '<P>' : `<${val.toUpperCase()}>`);
  e.target.value = 'p';
};

const setFontSize = e => {
  exec('fontSize', 7);
  editorRef.value.querySelectorAll('font[size="7"]').forEach(f => {
    const span = document.createElement('span');
    span.style.fontSize = e.target.value;
    span.innerHTML = f.innerHTML;
    f.replaceWith(span);
  });
  onInput();
};

const setColor = e => exec('foreColor', e.target.value);
const setBgColor = e => exec('hiliteColor', e.target.value);
const setAlign = a =>
  exec(
    { left: 'justifyLeft', center: 'justifyCenter', right: 'justifyRight' }[a]
  );

const insertLink = () => {
  const url = prompt('URL del enlace:');
  if (url) exec('createLink', url);
};
const insertHRule = () => exec('insertHorizontalRule');

// ─── images ──────────────────────────────────────────────────────────────────
const imageInput = ref(null);
const triggerImageUpload = () => imageInput.value?.click();

const insertBase64Image = src => {
  editorRef.value.focus();
  const img = document.createElement('img');
  img.src = src;
  img.style.maxWidth = '100%';
  const sel = window.getSelection();
  if (sel && sel.rangeCount) {
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
  const selection = window.getSelection();
  if (selection && selection.rangeCount) {
    const range = selection.getRangeAt(0);
    range.deleteContents();
    range.insertNode(document.createTextNode(text));
    range.collapse(false);
    selection.removeAllRanges();
    selection.addRange(range);
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
</script>

<template>
  <div
    ref="editorWrap"
    class="email-editor rounded-xl border border-slate-200 dark:border-slate-600 overflow-visible flex flex-col"
  >
    <!-- Toolbar -->
    <div
      class="flex flex-wrap items-center gap-0.5 px-2 py-1.5 bg-slate-50 dark:bg-slate-800 border-b border-slate-200 dark:border-slate-600 rounded-t-xl"
    >
      <select
        class="text-xs rounded border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200 px-1 py-0.5 h-7"
        @change="setHeading"
      >
        <option value="p">{{ $t('JABVOX_EMAIL.EDITOR.PARAGRAPH') }}</option>
        <option value="h1">{{ $t('JABVOX_EMAIL.EDITOR.HEADING1') }}</option>
        <option value="h2">{{ $t('JABVOX_EMAIL.EDITOR.HEADING2') }}</option>
        <option value="h3">{{ $t('JABVOX_EMAIL.EDITOR.HEADING3') }}</option>
      </select>

      <select
        class="text-xs rounded border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200 px-1 py-0.5 h-7 ml-1"
        @change="setFontSize"
      >
        <option v-for="size in FONT_SIZES" :key="size" :value="`${size}px`">
          {{ size }}
        </option>
      </select>

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
        class="toolbar-btn relative overflow-hidden cursor-pointer"
        :title="$t('JABVOX_EMAIL.EDITOR.TEXT_COLOR')"
      >
        <span class="i-lucide-baseline w-3.5 h-3.5" />
        <input
          type="color"
          class="absolute inset-0 opacity-0 w-full h-full cursor-pointer"
          @input="setColor"
        />
      </label>
      <label
        class="toolbar-btn relative overflow-hidden cursor-pointer"
        :title="$t('JABVOX_EMAIL.EDITOR.BG_COLOR')"
      >
        <span class="i-lucide-paint-bucket w-3.5 h-3.5" />
        <input
          type="color"
          class="absolute inset-0 opacity-0 w-full h-full cursor-pointer"
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

    <!-- Email canvas -->
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

      <!-- Image resize overlay (fixed position in viewport) -->
      <teleport to="body">
        <ImageResizer :img="selectedImg" @resize-end="onResizeEnd" />
      </teleport>
    </div>
  </div>
</template>

<style>
.toolbar-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 28px;
  height: 28px;
  padding: 0 4px;
  border-radius: 4px;
  font-size: 12px;
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

.email-content img {
  max-width: 100%;
  height: auto;
  display: block;
  margin: 8px auto;
  cursor: pointer;
}
.email-content h1 {
  font-size: 2em;
  font-weight: bold;
  margin: 0.5em 0;
}
.email-content h2 {
  font-size: 1.5em;
  font-weight: bold;
  margin: 0.5em 0;
}
.email-content h3 {
  font-size: 1.17em;
  font-weight: bold;
  margin: 0.5em 0;
}
.email-content p {
  margin: 0 0 0.75em 0;
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
