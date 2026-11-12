
"use client";

import Link from "next/link";
import { useMemo, useState } from "react";

const subjects = [
  "All Subjects",
  "Bangla",
  "English",
  "Mathematics",
  "Physics",
  "Chemistry",
  "Biology",
  "ICT",
  "BGS",
];

const notes = [
  {
    id: 1,
    title: "Higher Mathematics — Complete Notes",
    subject: "Mathematics",
    chapter: "Chapter 01–05",
    author: "Cadet Sync Team",
    price: 50,
    type: "Premium",
  },
  {
    id: 2,
    title: "Physics — Motion & Force",
    subject: "Physics",
    chapter: "Chapter 02",
    author: "Cadet Sync Team",
    price: 35,
    type: "Premium",
  },
  {
    id: 3,
    title: "English Grammar — Complete Guide",
    subject: "English",
    chapter: "Grammar",
    author: "Cadet Sync Team",
    price: 40,
    type: "Premium",
  },
  {
    id: 4,
    title: "Chemistry — Chemical Bonding",
    subject: "Chemistry",
    chapter: "Chapter 04",
    author: "Cadet Sync Team",
    price: 30,
    type: "Premium",
  },
  {
    id: 5,
    title: "Biology — Cell Structure",
    subject: "Biology",
    chapter: "Chapter 01",
    author: "Cadet Sync Team",
    price: 25,
    type: "Premium",
  },
  {
    id: 6,
    title: "ICT — Number System",
    subject: "ICT",
    chapter: "Chapter 03",
    author: "Cadet Sync Team",
    price: 0,
    type: "Free",
  },
];

export default function NotesPage() {
  const [activeSubject, setActiveSubject] = useState("All Subjects");
  const [search, setSearch] = useState("");

  const filteredNotes = useMemo(() => {
    return notes.filter((note) => {
      const matchesSubject =
        activeSubject === "All Subjects" ||
        note.subject === activeSubject;

      const matchesSearch =
        note.title.toLowerCase().includes(search.toLowerCase()) ||
        note.subject.toLowerCase().includes(search.toLowerCase());

      return matchesSubject && matchesSearch;
    });
  }, [activeSubject, search]);

  return (
    <main className="min-h-screen bg-[#f8f7f2] text-[#183b32]">
      <header className="sticky top-0 z-40 border-b border-[#e7e5dc] bg-[#f8f7f2]/95 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-5">
          <Link href="/" className="text-2xl font-bold tracking-tight">
            Cadet<span className="text-[#b28b45]">Sync.</span>
          </Link>

          <nav className="hidden items-center gap-8 text-sm font-medium md:flex">
            <Link href="/" className="hover:text-[#b28b45]">
              Home
            </Link>
            <Link href="/notes" className="text-[#b28b45]">
              Notes
            </Link>
            <Link href="/#community" className="hover:text-[#b28b45]">
              Community
            </Link>
          </nav>

          <Link
            href="/login"
            className="rounded-full bg-[#183b32] px-6 py-3 text-sm font-semibold text-white transition hover:bg-[#285648]"
          >
            Sign In
          </Link>
        </div>
      </header>

      <section className="mx-auto max-w-7xl px-6 pb-12 pt-16">
        <p className="mb-4 text-xs font-bold uppercase tracking-[0.3em] text-[#b28b45]">
          The Knowledge Library
        </p>

        <h1 className="max-w-3xl text-4xl font-bold leading-tight tracking-tight md:text-6xl">
          Find the right notes.
          <span className="text-[#b28b45]"> Study smarter.</span>
        </h1>

        <p className="mt-5 max-w-xl leading-7 text-[#6d7972]">
          Explore quality study materials prepared for cadets.
          Learn, revise and achieve more with Cadet Sync.
        </p>

        <div className="mt-10 max-w-2xl">
          <div className="flex items-center gap-3 rounded-2xl border border-[#e5e2d8] bg-white px-5 py-4 shadow-sm">
            <span className="text-xl text-[#b28b45]">⌕</span>
            <input
              type="text"
              placeholder="Search notes, subjects or topics..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full bg-transparent text-sm text-[#183b32] outline-none placeholder:text-[#a0a69f]"
            />
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 pb-20">
        <div className="mb-8 flex flex-col justify-between gap-5 md:flex-row md:items-end">
          <div>
            <p className="mb-2 text-xs font-bold uppercase tracking-[0.2em] text-[#b28b45]">
              Browse Library
            </p>
            <h2 className="text-2xl font-bold md:text-3xl">
              Explore Study Notes
            </h2>
          </div>

          <p className="text-sm text-[#778078]">
            {filteredNotes.length} materials found
          </p>
        </div>

        <div className="mb-10 flex flex-wrap gap-3">
          {subjects.map((subject) => (
            <button
              key={subject}
              onClick={() => setActiveSubject(subject)}
              className={`rounded-full border px-5 py-2.5 text-sm font-semibold transition ${
                activeSubject === subject
                  ? "border-[#183b32] bg-[#183b32] text-white"
                  : "border-[#deded4] bg-white text-[#66736b] hover:border-[#b28b45] hover:text-[#183b32]"
              }`}
            >
              {subject}
            </button>
          ))}
        </div>

        {filteredNotes.length > 0 ? (
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {filteredNotes.map((note) => (
              <article
                key={note.id}
                className="group rounded-3xl border border-[#e9e6dc] bg-white p-7 transition duration-300 hover:-translate-y-1 hover:border-[#c9b17d] hover:shadow-xl"
              >
                <div className="mb-8 flex items-start justify-between">
                  <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-[#f2f0e7] text-2xl text-[#b28b45]">
                    ✦
                  </div>

                  <span
                    className={`rounded-full px-3 py-1.5 text-xs font-bold ${
                      note.type === "Free"
                        ? "bg-[#e8f2e9] text-[#34734b]"
                        : "bg-[#f5efdf] text-[#a17b35]"
                    }`}
                  >
                    {note.type}
                  </span>
                </div>

                <p className="mb-2 text-xs font-bold uppercase tracking-widest text-[#b28b45]">
                  {note.subject}
                </p>

                <h3 className="min-h-[56px] text-xl font-bold leading-7 transition group-hover:text-[#a17b35]">
                  {note.title}
                </h3>

                <p className="mt-3 text-sm text-[#899189]">
                  {note.chapter}
                </p>

                <div className="mt-6 border-t border-[#eeece5] pt-5">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-xs text-[#929990]">Prepared by</p>
                      <p className="mt-1 text-sm font-semibold">
                        {note.author}
                      </p>
                    </div>

                    <p className="text-xl font-bold">
                      {note.price === 0 ? "Free" : `৳${note.price}`}
                    </p>
                  </div>

                  <button
                    onClick={() =>
                      alert("Note details and purchasing will be available soon.")
                    }
                    className="mt-6 w-full rounded-xl border border-[#183b32] py-3 text-sm font-bold text-[#183b32] transition hover:bg-[#183b32] hover:text-white"
                  >
                    View Details →
                  </button>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="rounded-3xl border border-dashed border-[#d8d5ca] bg-white px-6 py-16 text-center">
            <p className="text-xl font-bold">No notes found</p>
            <p className="mt-2 text-sm text-[#899189]">
              Try another subject or search keyword.
            </p>
            <button
              onClick={() => {
                setSearch("");
                setActiveSubject("All Subjects");
              }}
              className="mt-5 text-sm font-bold text-[#a17b35] underline"
            >
              Clear filters
            </button>
          </div>
        )}
      </section>

      <footer className="border-t border-[#e7e5dc] bg-[#183b32] px-6 py-10 text-center text-sm text-white/70">
        <p className="text-xl font-bold text-white">
          Cadet<span className="text-[#d2ad65]">Sync.</span>
        </p>
        <p className="mt-3">
          Knowledge is our tradition. Excellence is our legacy.
        </p>
        <p className="mt-5 text-xs text-white/40">
          © 2026 Cadet Sync. All rights reserved.
        </p>
      </footer>
    </main>
  );
}
