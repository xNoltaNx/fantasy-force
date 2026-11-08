import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// base './' so the built site works from any folder, including a GitHub Pages project path.
export default defineConfig({
  plugins: [react()],
  base: './',
})
