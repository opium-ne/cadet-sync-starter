
const notes = [
  {
    title: "HSC Physics — Mechanics",
    subject: "Physics",
    author: "Cadet Contributor",
    price: "৳30",
    tag: "Popular",
  },
  {
    title: "HSC Higher Mathematics",
    subject: "Mathematics",
    author: "Cadet Contributor",
    price: "৳25",
    tag: "New",
  },
  {
    title: "Chemistry — Organic Chemistry",
    subject: "Chemistry",
    author: "Cadet Contributor",
    price: "৳20",
    tag: "Featured",
  },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white">
        <nav className="mx-auto flex max-w-7xl items-center justify-between px-6 py-5">
          <a href="/" className="text-2xl font-extrabold tracking-tight text-blue-700">
            Cadet<span className="text-slate-900">Sync</span>
          </a>

          <div className="hidden items-center gap-8 text-sm font-medium md:flex">
            <a href="#notes" className="hover:text-blue-700">Explore Notes</a>
            <a href="#how-it-works" className="hover:text-blue-700">How It Works</a>
            <a href="#about" className="hover:text-blue-700">About</a>
          </div>

          <div className="flex gap-3">
            <button className="rounded-lg px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-100">
              Log in
            </button>
            <button className="rounded-lg bg-blue-700 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-800">
              Sign up
            </button>
          </div>
        </nav>
      </header>

      <section className="bg-blue-950 px-6 py-24 text-white">
        <div className="mx-auto max-w-7xl">
          <div className="max-w-3xl">
            <p className="mb-5 font-semibold tracking-widest text-blue-300">
              LEARN. SHARE. RISE.
            </p>
            <h1 className="text-4xl font-extrabold leading-tight md:text-6xl">
              Your Knowledge.
              <br />
              Your Cadet Community.
            </h1>
            <p className="mt-6 max-w-xl text-lg leading-8 text-blue-100">
              Discover quality study notes, learn from fellow cadets,
              and share your knowledge with the community.
            </p>

            <div className="mt-9 flex flex-wrap gap-4">
              <a
                href="#notes"
                className="rounded-lg bg-white px-6 py-3 font-bold text-blue-950 hover:bg-blue-100"
              >
                Explore Notes
              </a>
              <a
                href="#about"
                className="rounded-lg border border-blue-300 px-6 py-3 font-bold text-white hover:bg-blue-900"
              >
                Learn More
              </a>
            </div>
          </div>
        </div>
      </section>

      <section id="notes" className="mx-auto max-w-7xl px-6 py-20">
        <div className="mb-10 flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="font-semibold text-blue-700">STUDY MATERIALS</p>
            <h2 className="mt-2 text-3xl font-extrabold">Explore Study Notes</h2>
            <p className="mt-2 text-slate-600">
              Find resources shared by your fellow cadets.
            </p>
          </div>
          <span className="text-sm text-slate-500">Sample content</span>
        </div>

        <div className="grid gap-6 md:grid-cols-3">
          {notes.map((note) => (
            <article
              key={note.title}
              className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm transition hover:-translate-y-1 hover:shadow-md"
            >
              <div className="flex items-center justify-between">
                <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-bold text-blue-700">
                  {note.subject}
                </span>
                <span className="text-xs font-semibold text-slate-500">
                  {note.tag}
                </span>
              </div>
              <h3 className="mt-6 text-xl font-bold">{note.title}</h3>
              <p className="mt-2 text-sm text-slate-500">
                Shared by {note.author}
              </p>
              <div className="mt-6 flex items-center justify-between border-t border-slate-100 pt-5">
                <span className="text-xl font-extrabold text-blue-700">
                  {note.price}
                </span>
                <button className="rounded-lg bg-blue-700 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-800">
                  View Note
                </button>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section id="how-it-works" className="bg-white px-6 py-20">
        <div className="mx-auto max-w-7xl">
          <div className="text-center">
            <p className="font-semibold text-blue-700">SIMPLE PROCESS</p>
            <h2 className="mt-2 text-3xl font-extrabold">How Cadet Sync Works</h2>
          </div>
          <div className="mt-12 grid gap-8 text-center md:grid-cols-3">
            <div className="rounded-2xl bg-slate-50 p-8">
              <div className="text-3xl">📚</div>
              <h3 className="mt-4 text-xl font-bold">Discover</h3>
              <p className="mt-2 text-slate-600">Find useful notes and study materials.</p>
            </div>
            <div className="rounded-2xl bg-slate-50 p-8">
              <div className="text-3xl">🤝</div>
              <h3 className="mt-4 text-xl font-bold">Share</h3>
              <p className="mt-2 text-slate-600">Contribute your own knowledge.</p>
            </div>
            <div className="rounded-2xl bg-slate-50 p-8">
              <div className="text-3xl">🚀</div>
              <h3 className="mt-4 text-xl font-bold">Grow</h3>
              <p className="mt-2 text-slate-600">Learn together with the cadet community.</p>
            </div>
          </div>
        </div>
      </section>

      <footer id="about" className="bg-slate-950 px-6 py-10 text-center text-slate-300">
        <p className="text-xl font-extrabold text-white">CadetSync</p>
        <p className="mt-2 text-sm">Learn. Share. Rise.</p>
        <p className="mt-5 text-xs text-slate-500">
          © 2026 Cadet Sync. All rights reserved.
        </p>
      </footer>
    </main>
  );
}


