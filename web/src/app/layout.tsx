import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import Sidebar from "@/components/Sidebar";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "PicoBox | Cluster Control Plane",
  description: "Next-generation Lightweight Container Platform Dashboard",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${inter.className} antialiased selection:bg-cyan-500/30`}>
        <Sidebar />
        <main className="pl-64 min-h-screen bg-[#020617] text-slate-200 overflow-hidden relative">
          {/* Background decoration */}
          <div className="absolute top-0 right-0 w-[500px] h-[500px] bg-cyan-500/5 blur-[120px] rounded-full -mr-64 -mt-64" />
          <div className="absolute bottom-0 left-0 w-[400px] h-[400px] bg-blue-600/5 blur-[100px] rounded-full -ml-32 -mb-32" />

          <div className="relative z-10 px-10 py-12">
            {children}
          </div>
        </main>
      </body>
    </html>
  );
}
