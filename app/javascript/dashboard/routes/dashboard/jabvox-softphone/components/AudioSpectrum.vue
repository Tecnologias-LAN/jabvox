<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';

// Visualizador de espectro de audio (barras animadas) para un MediaStream. Se usa dos
// veces: mi micrófono y el audio remoto. Usa Web Audio API (AnalyserNode) sobre canvas.
const props = defineProps({
  // Función que devuelve el MediaStream a analizar (o null si no hay).
  streamProvider: { type: Function, required: true },
  // Activo solo durante la llamada (para no consumir recursos en reposo).
  active: { type: Boolean, default: false },
  color: { type: String, default: '#4CAF82' },
  bars: { type: Number, default: 16 },
  // true para el audio REMOTO de WebRTC. Chrome entrega ceros al AnalyserNode de un
  // stream remoto salvo que el stream también alimente un <audio> (aunque esté mudo);
  // con este flag creamos ese <audio> "keep-alive" para que el espectro reciba datos.
  remote: { type: Boolean, default: false },
});

const canvas = ref(null);
let audioCtx = null;
let analyser = null;
let source = null;
let rafId = null;
let retryTimer = null;
// <audio> mudo "keep-alive" para destrabar el analizador del stream remoto (bug Chrome).
let keepAlive = null;

const stop = () => {
  if (rafId) cancelAnimationFrame(rafId);
  rafId = null;
  if (retryTimer) clearTimeout(retryTimer);
  retryTimer = null;
  try {
    source?.disconnect();
    audioCtx?.close();
  } catch (e) {
    /* noop */
  }
  if (keepAlive) {
    keepAlive.srcObject = null;
    keepAlive = null;
  }
  source = null;
  analyser = null;
  audioCtx = null;
};

const draw = () => {
  const el = canvas.value;
  if (!el || !analyser) return;
  const ctx = el.getContext('2d');
  const data = new Uint8Array(analyser.frequencyBinCount);
  analyser.getByteFrequencyData(data);

  const { width, height } = el;
  ctx.clearRect(0, 0, width, height);
  const step = Math.floor(data.length / props.bars);
  const barWidth = width / props.bars;
  ctx.fillStyle = props.color;
  for (let i = 0; i < props.bars; i += 1) {
    const value = data[i * step] / 255;
    const barHeight = Math.max(2, value * height);
    ctx.fillRect(
      i * barWidth + 1,
      (height - barHeight) / 2,
      barWidth - 2,
      barHeight
    );
  }
  rafId = requestAnimationFrame(draw);
};

// Nº de reintentos: el MediaStream de WebRTC puede tardar en existir tras contestar.
let attempts = 0;

const start = () => {
  if (!props.active) return;
  const stream = props.streamProvider();
  if (!stream || !stream.getAudioTracks().length) {
    // aún no hay audio: reintentar hasta ~6s (evita la barra muerta de la 1ª llamada)
    if (attempts < 40) {
      attempts += 1;
      retryTimer = setTimeout(start, 150);
    }
    return;
  }
  attempts = 0;
  try {
    // Stream remoto de WebRTC: Chrome no alimenta el AnalyserNode salvo que el stream
    // también esté conectado a un <audio>. Creamos uno mudo (keep-alive) para eso; el
    // sonido real ya lo reproduce el <audio> principal del softphone, así no se duplica.
    if (props.remote) {
      keepAlive = new Audio();
      keepAlive.muted = true;
      keepAlive.srcObject = stream;
      keepAlive.play().catch(() => {});
    }
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    // La política de autoplay puede dejar el contexto suspendido: reanudarlo.
    if (audioCtx.state === 'suspended') audioCtx.resume().catch(() => {});
    source = audioCtx.createMediaStreamSource(stream);
    analyser = audioCtx.createAnalyser();
    analyser.fftSize = 64;
    source.connect(analyser);
    draw();
  } catch (e) {
    stop();
  }
};

watch(
  () => props.active,
  isActive => {
    stop();
    attempts = 0;
    if (isActive) {
      // pequeño retraso inicial; start() reintenta solo si el stream aún no existe
      retryTimer = setTimeout(start, 150);
    }
  },
  { immediate: true }
);

onBeforeUnmount(stop);
</script>

<template>
  <canvas ref="canvas" width="120" height="28" class="w-full h-7 rounded" />
</template>
