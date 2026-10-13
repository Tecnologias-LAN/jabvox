import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
  // Separa las librerías pesadas de terceros en chunks propios ("vendor-*"). No
  // cambia qué se carga, pero: (1) mejora la caché del navegador (un vendor estable
  // no invalida su chunk al cambiar el código de la app), y (2) evita que libs
  // grandes se mezclen con el código de arranque. Combinado con los dynamic imports
  // (Twilio, color, audio, drive) mantiene liviano el bundle inicial del login y la app.
  build: {
    chunkSizeWarningLimit: 1200,
    rollupOptions: {
      output: {
        // Agrupa por ruta de node_modules (robusto: no falla aunque un paquete sea
        // transitivo). Separa las libs pesadas en chunks "vendor-*" estables para
        // mejorar la caché del navegador y aislarlas del código de arranque.
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined;
          if (id.includes('@twilio/voice-sdk')) return 'vendor-twilio';
          if (id.includes('chart.js') || id.includes('vue-chartjs') || id.includes('@kurkle/color')) return 'vendor-charts';
          if (id.includes('@vueuse/')) return 'vendor-vueuse';
          if (id.includes('prosemirror') || id.includes('@chatwoot/prosemirror-schema')) return 'vendor-editor';
          if (id.includes('@sentry')) return 'vendor-sentry';
          if (id.includes('@amplitude')) return 'vendor-amplitude';
          if (id.includes('markdown-it') || id.includes('dompurify') || id.includes('linkify-it')) return 'vendor-markdown';
          if (id.includes('highlight.js') || id.includes('@highlightjs/')) return 'vendor-highlight';
          if (id.includes('@lk77/vue3-color')) return 'vendor-color';
          if (id.includes('libphonenumber-js') || id.includes('vuedraggable') || id.includes('sortablejs') || id.includes('qrcode') || id.includes('vue-datepicker-next') || id.includes('@tanstack/table-core')) return 'vendor-misc';
          return undefined;
        },
      },
    },
  },
  // Pre-empaqueta los visores pesados del Drive (Word/Excel) al arrancar, en vez
  // de compilarlos en caliente la primera vez que se abre uno (lo que hacía que
  // "Cargando vista previa…" se demorara varios segundos en dev).
  optimizeDeps: {
    include: ['mammoth/mammoth.browser', 'xlsx', 'jszip'],
  },
});
