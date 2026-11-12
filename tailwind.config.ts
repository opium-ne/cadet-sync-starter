import type { Config } from 'tailwindcss';

// Palette taken from the brief. Do not add new colours without a reason.
const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ivory: '#F8F6EE', cream: '#F1F0E5', forest: '#123D2B', deep: '#0B3022',
        sage: '#DCE8D6', gold: '#C69A4A', charcoal: '#202923',
      },
      fontFamily: {
        serif: ['var(--font-serif)', 'Playfair Display', 'Georgia', 'serif'],
        sans: ['var(--font-sans)', 'Inter', 'system-ui', 'sans-serif'],
        bengali: ['var(--font-bengali)', 'Hind Siliguri', 'sans-serif'],
      },
      borderRadius: { card: '1.25rem', control: '0.75rem' },
      boxShadow: { soft: '0 1px 2px rgb(32 41 35 / 0.04), 0 8px 24px -12px rgb(32 41 35 / 0.14)' },
      borderColor: { DEFAULT: 'rgb(18 61 43 / 0.12)' },
    },
  },
  plugins: [],
};
export default config;
