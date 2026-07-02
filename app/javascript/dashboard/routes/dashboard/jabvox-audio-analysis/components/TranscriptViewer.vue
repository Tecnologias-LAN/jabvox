<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Reusable transcript viewer with in-transcript search.
// - `words` (optional): [{ word, start, end }] with per-word/segment timing.
//   When present, the viewer renders timestamped tokens and search can match by
//   word OR by time (mm:ss / m:ss / seconds).
// - `text`: plain transcript fallback used when there are no timed words.
const props = defineProps({
  words: { type: Array, default: () => [] },
  text: { type: String, default: '' },
});

const { t } = useI18n();

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const hasWords = computed(
  () => Array.isArray(props.words) && props.words.length > 0
);

const query = ref('');
const currentMatch = ref(0); // index into matchIndices for word-search navigation

const fmtTime = seconds => {
  const s = Math.max(0, Math.floor(Number(seconds) || 0));
  const mm = String(Math.floor(s / 60)).padStart(2, '0');
  const ss = String(s % 60).padStart(2, '0');
  return `${mm}:${ss}`;
};

// Parses a time query like "1:05", "65" or "0:30" into seconds, or null if it
// is not a time expression (so we fall back to word search).
const parseTimeQuery = raw => {
  const q = raw.trim();
  if (/^\d{1,3}$/.test(q)) return Number(q);
  const m = q.match(/^(\d{1,3}):([0-5]?\d)$/);
  if (m) return Number(m[1]) * 60 + Number(m[2]);
  return null;
};

const timeSeconds = computed(() => parseTimeQuery(query.value));
const isTimeSearch = computed(
  () =>
    hasWords.value && query.value.trim() !== '' && timeSeconds.value !== null
);

// Word indices that match the text query (case-insensitive substring).
const matchIndices = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q || isTimeSearch.value || !hasWords.value) return [];
  return props.words.reduce((acc, w, i) => {
    if ((w.word || '').toLowerCase().includes(q)) acc.push(i);
    return acc;
  }, []);
});

// The word index closest to (and at/after) the searched time, for "jump to time".
const timeMatchIndex = computed(() => {
  if (!isTimeSearch.value) return -1;
  const target = timeSeconds.value;
  let best = -1;
  props.words.forEach((w, i) => {
    if (Number(w.start) <= target) best = i;
  });
  // If target is before the first word, highlight the first one.
  return best === -1 ? 0 : best;
});

// Indices to highlight in the rendered token list.
const highlighted = computed(() => {
  if (isTimeSearch.value) {
    return timeMatchIndex.value >= 0
      ? new Set([timeMatchIndex.value])
      : new Set();
  }
  return new Set(matchIndices.value);
});

const activeIndex = computed(() => {
  if (isTimeSearch.value) return timeMatchIndex.value;
  if (!matchIndices.value.length) return -1;
  return matchIndices.value[currentMatch.value % matchIndices.value.length];
});

// Plain-text search: matched count for the fallback (no timestamps) view.
const plainHighlights = computed(() => {
  const q = query.value.trim();
  if (!q || hasWords.value) return null;
  const parts = props.text.split(new RegExp(`(${escapeRegExp(q)})`, 'ig'));
  return parts;
});

const resultLabel = computed(() => {
  if (query.value.trim() === '') return '';
  if (isTimeSearch.value) {
    return timeMatchIndex.value >= 0
      ? t('JABVOX_AUDIO.TRANSCRIPT.AT_TIME', {
          time: fmtTime(props.words[timeMatchIndex.value]?.start),
        })
      : t('JABVOX_AUDIO.TRANSCRIPT.NO_RESULTS');
  }
  if (hasWords.value) {
    const n = matchIndices.value.length;
    return n
      ? t('JABVOX_AUDIO.TRANSCRIPT.MATCH_COUNT', {
          current: n ? (currentMatch.value % n) + 1 : 0,
          total: n,
        })
      : t('JABVOX_AUDIO.TRANSCRIPT.NO_RESULTS');
  }
  // Plain text
  const count = plainHighlights.value
    ? plainHighlights.value.filter(
        p => p.toLowerCase() === query.value.trim().toLowerCase()
      ).length
    : 0;
  return count
    ? t('JABVOX_AUDIO.TRANSCRIPT.MATCH_TOTAL', { total: count })
    : t('JABVOX_AUDIO.TRANSCRIPT.NO_RESULTS');
});

const tokenRefs = ref({});
const setTokenRef = (i, el) => {
  if (el) tokenRefs.value[i] = el;
};
const scrollToActive = () => {
  const el = tokenRefs.value[activeIndex.value];
  if (el?.scrollIntoView) {
    el.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }
};

const nextMatch = () => {
  if (!matchIndices.value.length) return;
  currentMatch.value = (currentMatch.value + 1) % matchIndices.value.length;
  scrollToActive();
};
const prevMatch = () => {
  if (!matchIndices.value.length) return;
  currentMatch.value =
    (currentMatch.value - 1 + matchIndices.value.length) %
    matchIndices.value.length;
  scrollToActive();
};

const onSearch = () => {
  currentMatch.value = 0;
  scrollToActive();
};
const clear = () => {
  query.value = '';
  currentMatch.value = 0;
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <!-- Search bar -->
    <div class="flex items-center gap-2">
      <div
        class="flex items-center gap-2 flex-1 px-2.5 py-1.5 rounded-lg bg-n-alpha-1 border border-n-weak"
      >
        <span class="i-lucide-search size-3.5 text-n-slate-10" />
        <input
          v-model="query"
          type="text"
          class="flex-1 min-w-0 bg-transparent text-xs text-n-slate-12 focus:outline-none"
          :placeholder="
            hasWords
              ? t('JABVOX_AUDIO.TRANSCRIPT.SEARCH_PLACEHOLDER_TIMED')
              : t('JABVOX_AUDIO.TRANSCRIPT.SEARCH_PLACEHOLDER')
          "
          @keyup.enter="onSearch"
        />
        <button
          v-if="query"
          type="button"
          class="p-0.5 rounded text-n-slate-10 hover:text-n-slate-12"
          @click="clear"
        >
          <span class="i-lucide-x size-3.5" aria-hidden="true" />
        </button>
      </div>
      <!-- Prev/next only for word search with multiple hits -->
      <div
        v-if="!isTimeSearch && matchIndices.length > 1"
        class="flex items-center gap-0.5"
      >
        <button
          type="button"
          class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-2"
          @click="prevMatch"
        >
          <span class="i-lucide-chevron-up size-3.5" />
        </button>
        <button
          type="button"
          class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-2"
          @click="nextMatch"
        >
          <span class="i-lucide-chevron-down size-3.5" />
        </button>
      </div>
    </div>
    <p v-if="resultLabel" class="text-[11px] text-n-slate-10">
      {{ resultLabel }}
    </p>

    <!-- Timed transcript: each token shows its time; matches are highlighted -->
    <div
      v-if="hasWords"
      class="p-2.5 rounded-lg bg-n-solid-2 border border-n-weak text-xs text-n-slate-12 leading-6 max-h-64 overflow-y-auto"
    >
      <span
        v-for="(w, i) in words"
        :key="i"
        :ref="el => setTokenRef(i, el)"
        class="inline-flex items-baseline gap-0.5 mr-1 rounded px-0.5"
        :class="
          highlighted.has(i)
            ? i === activeIndex
              ? 'bg-n-amber-9 text-white'
              : 'bg-n-amber-3 text-n-amber-11'
            : ''
        "
      >
        <span class="text-[10px] text-n-slate-10 tabular-nums"
          >[{{ fmtTime(w.start) }}]</span
        >
        <span>{{ w.word }}</span>
      </span>
    </div>

    <!-- Plain transcript fallback: highlight matched substrings -->
    <p
      v-else
      class="p-2.5 rounded-lg bg-n-solid-2 border border-n-weak text-xs text-n-slate-12 whitespace-pre-wrap break-words max-h-64 overflow-y-auto"
    >
      <template v-if="plainHighlights">
        <template v-for="(part, i) in plainHighlights" :key="i">
          <mark
            v-if="part.toLowerCase() === query.trim().toLowerCase() && part"
            class="bg-n-amber-3 text-n-amber-11 rounded px-0.5"
            >{{ part }}</mark
          >
          <template v-else>{{ part }}</template>
        </template>
      </template>
      <template v-else>{{ text }}</template>
    </p>
  </div>
</template>
