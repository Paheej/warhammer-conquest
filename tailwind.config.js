/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        ink: {
          DEFAULT: "#0a0806",
          2: "#14100a",
          3: "#1f180f",
        },
        parchment: {
          DEFAULT: "#e8dcc0",
          dim: "#b8a888",
          dark: "#8a7a5c",
        },
        brass: {
          DEFAULT: "#b8892d",
          bright: "#d9a94a",
          dark: "#7a5a1c",
        },
        blood: "#6b1616",
        crusade: "#c9392a",
      },
      fontFamily: {
        display: ['"Cinzel"', "serif"],
        body: ['"Cormorant Garamond"', "serif"],
        gothic: ['"UnifrakturCook"', "serif"],
      },
      backgroundImage: {
        "parchment-grain":
          "radial-gradient(circle at 50% 50%, rgba(184,137,45,0.08) 0%, transparent 60%)",
      },
    },
  },
  plugins: [],
};
