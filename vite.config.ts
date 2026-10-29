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
  // Pre-empaqueta los visores pesados del Drive (Word/Excel) al arrancar, en vez
  // de compilarlos en caliente la primera vez que se abre uno (lo que hacía que
  // "Cargando vista previa…" se demorara varios segundos en dev).
  optimizeDeps: {
    include: ['mammoth/mammoth.browser', 'xlsx', 'jszip'],
  },
});
