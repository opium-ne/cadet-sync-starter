
import Image from "next/image";

const subjects = [
  ["Bangla", "subject-bangla.svg"],
  ["English", "subject-english.svg"],
  ["Mathematics", "subject-mathematics.svg"],
  ["Physics", "subject-physics.svg"],
  ["Chemistry", "subject-chemistry.svg"],
  ["Biology", "subject-biology.svg"],
  ["ICT", "subject-ict.svg"],
  ["BGS", "subject-bgs.svg"],
];

const notes = [
  { title: "Higher Mathematics", subject: "SCIENCE", author: "Teaching Cadet", price: "৳45", rating: "4.9", color: "bg-[#e9eee6]", icon: "∑" },
  { title: "English Grammar & Writing", subject: "ENGLISH", author: "Student Contributor", price: "৳30", rating: "4.8", color: "bg-[#f3eadc]", icon: "Aa" },
  { title: "Physics Short Notes", subject: "SCIENCE", author: "Teaching Cadet", price: "৳50", rating: "5.0", color: "bg-[#e9e9df]", icon: "⚛" },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-[#faf9f5] text-[#203d31]">
      <header className="sticky top-0 z-50 border-b border-[#e9e5d9] bg-[#faf9f5]/95 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
          <a href="#" className="flex items-center gap-3">
            <Image src="/assets/cadet-sync-logo.jpg" alt="Cadet Sync" width={52} height={52} className="rounded-full object-cover" />
            <div>
              <div className="font-serif text-xl font-bold tracking-wide">CADET SYNC</div>
              <div className="text-[9px] font-semibold tracking-[3px] text-[#a17c42]">LEARN. SHARE. RISE.</div>
            </div>
          </a>

          <nav className="hidden items-center gap-8 text-sm font-medium md:flex">
            <a href="#subjects" className="hover:text-[#b18a4c]">Subjects</a>
            <a href="#notes" className="hover:text-[#b18a4c]">Explore Notes</a>
            <a href="#community" className="hover:text-[#b18a4c]">Community</a>
            <a href="#about" className="hover:text-[#b18a4c]">About</a>
          </nav>

          <div className="flex items-center gap-3">
            <a href="/login" className="hidden text-sm font-semibold sm:block">Log in</a>
            <a href="/signup" className="rounded-md bg-[#234536] px-5 py-3 text-sm font-semibold text-white transition hover:bg-[#315d47]">
              Join Us <span className="ml-1">↗</span>
            </a>
          </div>
        </div>
      </header>

      <section className="mx-auto grid max-w-7xl items-center gap-12 px-6 py-16 md:grid-cols-2 md:py-24">
        <div>
          <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-[#dfd4bd] px-4 py-2 text-xs font-semibold tracking-wider text-[#987541]">
            <span>✦</span> BANGLADESH CADET COMMUNITY
          </div>
          <h1 className="max-w-xl font-serif text-5xl font-bold leading-[1.13] tracking-tight md:text-7xl">
            Knowledge is our <span className="italic text-[#a27b43]">tradition.</span>
            <br /> Excellence is our legacy.
          </h1>
          <p className="mt-7 max-w-lg text-base leading-8 text-[#68746b]">
            A dedicated learning community where cadets share knowledge,
            discover quality academic resources, and grow together.
          </p>
          <div className="mt-9 flex flex-wrap gap-4">
            <a href="#notes" className="rounded-md bg-[#234536] px-7 py-4 text-sm font-semibold text-white shadow-lg shadow-[#234536]/10 hover:bg-[#315d47]">
              Explore Study Notes ↗
            </a>
            <a href="#community" className="rounded-md border border-[#cfc7b7] px-7 py-4 text-sm font-semibold hover:bg-[#f0eee7]">
              Discover Community
            </a>
          </div>
          <div className="mt-12 flex items-center gap-4 border-t border-[#e7e2d7] pt-7">
            <div className="flex -space-x-3">
              <div className="grid h-10 w-10 place-items-center rounded-full border-2 border-[#faf9f5] bg-[#d7c3a0] text-sm">C</div>
              <div className="grid h-10 w-10 place-items-center rounded-full border-2 border-[#faf9f5] bg-[#9eae9c] text-sm">S</div>
              <div className="grid h-10 w-10 place-items-center rounded-full border-2 border-[#faf9f5] bg-[#d9d8c7] text-sm">T</div>
            </div>
            <p className="text-xs leading-5 text-[#69756d]">
              <strong className="text-[#234536]">A community built on knowledge</strong><br />
              Learn together. Rise together.
            </p>
          </div>
        </div>

        <div className="relative">
          <div className="absolute -right-4 -top-4 h-32 w-32 rounded-full border border-[#b9955c]/40" />
          <div className="relative overflow-hidden rounded-t-[180px] rounded-b-lg border-[7px] border-white shadow-2xl shadow-[#243d30]/15">
            <Image
              src="/assets/hero-cadet-campus.jpg"
              alt="Cadet campus"
              width={900}
              height={1000}
              priority
              className="h-[430px] w-full object-cover md:h-[570px]"
            />
          </div>
          <div className="absolute -bottom-6 -left-5 rounded-lg border border-[#e9e1d2] bg-white p-5 shadow-xl">
            <div className="font-serif text-2xl font-bold text-[#a17c42]">Learn. Share. Rise.</div>
            <p className="mt-1 text-xs text-[#758077]">Together towards excellence.</p>
          </div>
        </div>
      </section>

      <section id="subjects" className="border-y border-[#e9e4d9] bg-[#f3f1e9] py-16">
        <div className="mx-auto max-w-7xl px-6">
          <div className="mb-10 flex flex-wrap items-end justify-between gap-4">
            <div>
              <p className="text-xs font-bold tracking-[3px] text-[#a17c42]">KNOWLEDGE LIBRARY</p>
              <h2 className="mt-3 font-serif text-4xl font-bold">Explore by Subject</h2>
            </div>
            <p className="max-w-sm text-sm leading-6 text-[#758077]">Find resources, notes and academic materials for your learning journey.</p>
          </div>
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4 lg:grid-cols-8">
            {subjects.map(([name, image]) => (
              <a key={name} href="#notes" className="group flex flex-col items-center rounded-lg border border-[#e7e1d5] bg-[#faf9f5] p-5 transition hover:-translate-y-1 hover:border-[#b9955c] hover:shadow-lg">
                <Image src={`/assets/${image}`} alt={name} width={64} height={64} className="h-14 w-14 object-contain transition group-hover:scale-110" />
                <span className="mt-4 text-sm font-semibold">{name}</span>
              </a>
            ))}
          </div>
        </div>
      </section>

      <section id="notes" className="mx-auto max-w-7xl px-6 py-20">
        <div className="flex flex-wrap items-end justify-between gap-5">
          <div>
            <p className="text-xs font-bold tracking-[3px] text-[#a17c42]">THE LEARNING COLLECTION</p>
            <h2 className="mt-3 font-serif text-4xl font-bold">Discover Study Notes</h2>
            <p className="mt-3 text-sm text-[#758077]">Explore academic resources shared by the community.</p>
          </div>
          <a href="/notes" className="text-sm font-bold text-[#987541] hover:underline">View all notes ↗</a>
        </div>

        <div className="mt-10 grid gap-6 md:grid-cols-3">
          {notes.map((note) => (
            <article key={note.title} className="overflow-hidden rounded-lg border border-[#e9e4d9] bg-white transition hover:-translate-y-1 hover:shadow-xl">
              <div className={`flex h-48 items-center justify-center ${note.color}`}>
                <span className="font-serif text-7xl text-[#315744]/70">{note.icon}</span>
              </div>
              <div className="p-6">
                <div className="flex items-center justify-between">
                  <span className="text-[10px] font-bold tracking-[2px] text-[#a17c42]">{note.subject}</span>
                  <span className="text-xs text-[#987541]">★ {note.rating}</span>
                </div>
                <h3 className="mt-3 font-serif text-xl font-bold">{note.title}</h3>
                <p className="mt-2 text-xs text-[#758077]">Shared by {note.author}</p>
                <div className="mt-6 flex items-center justify-between border-t border-[#eeeae2] pt-4">
                  <span className="text-lg font-bold">{note.price}</span>
                  <a href="/notes" className="text-sm font-semibold text-[#987541] hover:underline">Explore note ↗</a>
                </div>
              </div>
            </article>
          ))}
        </div>
        <p className="mt-5 text-xs text-[#8b8b80]">Sample content for design preview. Live notes will appear when the backend is connected.</p>
      </section>

      <section id="community" className="bg-[#203f31] text-white">
        <div className="mx-auto grid max-w-7xl items-center gap-10 px-6 py-16 md:grid-cols-2 md:py-20">
          <div>
            <p className="text-xs font-bold tracking-[3px] text-[#d6b77d]">BE PART OF SOMETHING GREATER</p>
            <h2 className="mt-4 font-serif text-4xl font-bold leading-tight md:text-5xl">Great minds grow better together.</h2>
            <p className="mt-5 max-w-lg text-sm leading-7 text-white/70">
              Share what you know, learn from fellow cadets, and help build a stronger academic community.
            </p>
            <a href="/signup" className="mt-8 inline-block rounded-md bg-[#c5a36b] px-7 py-4 text-sm font-bold text-[#203f31] hover:bg-[#d8bd8e]">
              Join the Community ↗
            </a>
          </div>
          <div className="relative h-72 overflow-hidden rounded-lg md:h-96">
            <Image src="/assets/community-cadet.jpg" alt="Cadet community" fill className="object-cover" />
          </div>
        </div>
      </section>

      <section id="about" className="bg-[#f3f1e9] px-6 py-12 text-center">
        <p className="font-serif text-3xl font-bold italic text-[#234536]">“Learn. Share. Rise.”</p>
        <p className="mt-3 text-sm text-[#758077]">A shared journey of knowledge, discipline and excellence.</p>
      </section>

      <footer className="bg-[#172e24] px-6 py-10 text-white/70">
        <div className="mx-auto flex max-w-7xl flex-col justify-between gap-6 sm:flex-row">
          <div>
            <p className="font-serif text-xl font-bold text-white">CADET SYNC</p>
            <p className="mt-2 text-xs tracking-widest text-[#c5a36b]">LEARN. SHARE. RISE.</p>
          </div>
          <div className="flex flex-wrap gap-6 text-xs">
            <a href="#subjects" className="hover:text-white">Subjects</a>
            <a href="#notes" className="hover:text-white">Notes</a>
            <a href="#community" className="hover:text-white">Community</a>
            <a href="#about" className="hover:text-white">About</a>
          </div>
        </div>
        <div className="mx-auto mt-8 max-w-7xl border-t border-white/10 pt-6 text-xs">
          © 2026 Cadet Sync. Learn. Share. Rise.
        </div>
      </footer>
    </main>
  );
}
