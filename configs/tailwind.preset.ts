// meradOS Tailwind Preset — use via: presets: [meradosPreset]
// For full tokens use @merados/design-system/tailwind instead
// This is a standalone fallback for projects without the design-system package

import type { Config } from 'tailwindcss'

const meradosPreset: Partial<Config> = {
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#f0f9ff',
          100: '#e0f2fe',
          200: '#bae6fd',
          300: '#7dd3fc',
          400: '#38bdf8',
          500: '#0ea5e9',
          600: '#0284c7',
          700: '#0369a1',
          800: '#075985',
          900: '#0c4a6e',
        },
        navy: {
          800: '#1e293b',
          900: '#0f172a',
          950: '#020617',
        },
        surface: {
          elevated: 'var(--surface-elevated, #1e293b)',
          overlay: 'var(--surface-overlay, #0f172a)',
        },
      },
      fontFamily: {
        sans: ['Inter', '-apple-system', 'SF Pro Display', 'system-ui', 'sans-serif'],
        mono: ['SF Mono', 'Fira Code', 'monospace'],
        logo: ['SF Pro Display', 'Inter', 'system-ui', 'sans-serif'],
      },
      borderRadius: {
        sm: '8px',
        md: '12px',
        lg: '16px',
        xl: '22px',
      },
      transitionDuration: {
        instant: '100ms',
        fast: '150ms',
        normal: '250ms',
        slow: '400ms',
        slower: '600ms',
      },
      transitionTimingFunction: {
        standard: 'cubic-bezier(0.4, 0, 0.2, 1)',
        enter: 'cubic-bezier(0, 0, 0.2, 1)',
        exit: 'cubic-bezier(0.4, 0, 1, 1)',
      },
      keyframes: {
        'fade-in': {
          from: { opacity: '0' },
          to: { opacity: '1' },
        },
        'fade-in-up': {
          from: { opacity: '0', transform: 'translateY(8px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
      },
      animation: {
        'fade-in': 'fade-in 250ms cubic-bezier(0, 0, 0.2, 1)',
        'fade-in-up': 'fade-in-up 300ms cubic-bezier(0, 0, 0.2, 1)',
      },
    },
  },
}

export default meradosPreset
