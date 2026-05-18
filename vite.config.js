import { defineConfig } from 'vite';

// Phase 0: Vite is used as a dev server / build tool, but the existing
// <script>-tag loading model in index.html stays intact. ESM conversion
// happens in Phase 5. Keep this config minimal until then.
export default defineConfig({
  root: '.',
  publicDir: false,
  server: {
    port: 5173,
    open: false,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  test: {
    environment: 'jsdom',
    globals: false,
    include: ['tests/**/*.test.js'],
    setupFiles: ['tests/setup.js'],
  },
});
