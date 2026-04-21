import type { Metadata } from "next";
import "./globals.css";
import { NavBar } from "@/components/NavBar";

export const metadata: Metadata = {
  title: "Crusade Ledger — Campaign of the Burning Star",
  description:
    "Record your victories. Claim the stars. A Warhammer 40,000 campaign tracker.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=Cinzel:wght@400;600;800&family=Cormorant+Garamond:ital,wght@0,400;0,600;0,700;1,400&family=UnifrakturCook:wght@700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <NavBar />
        <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          {children}
        </main>
        <footer className="text-center py-8 text-parchment-dark text-sm font-body italic">
          <div className="divider-ornate">
            <span>Ave Imperator</span>
          </div>
          <p className="mt-4">In the grim darkness of the far future, there is only war.</p>
        </footer>
      </body>
    </html>
  );
}
