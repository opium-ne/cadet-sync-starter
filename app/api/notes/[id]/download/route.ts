import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';

const noStore = { 'Cache-Control': 'private, no-store' };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Full-PDF access. Authorization is decided in the database (user_can_access_note) using the
// caller's own JWT; only then does the service role sign a short-lived URL. The PDF path is never sent to the browser.
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) return NextResponse.json({ error: 'not_found' }, { status: 404, headers: noStore });
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'auth_required' }, { status: 401, headers: noStore });

  const { data: allowed } = await supabase.rpc('user_can_access_note', { p_note_id: id });
  if (allowed !== true) return NextResponse.json({ error: 'forbidden' }, { status: 403, headers: noStore });

  const admin = createAdminClient();
  const { data: note } = await admin.from('notes').select('pdf_path').eq('id', id).single();
  if (!note?.pdf_path) return NextResponse.json({ error: 'not_found' }, { status: 404, headers: noStore });

  // Clamp: a bad or huge env value must never produce a long-lived link to a paid PDF.
  const ttl = Math.min(Math.max(Number(process.env.SIGNED_URL_TTL_SECONDS) || 60, 10), 300);
  const { data, error } = await admin.storage.from('note-pdfs').createSignedUrl(note.pdf_path, ttl);
  if (error || !data) return NextResponse.json({ error: 'sign_failed' }, { status: 500, headers: noStore });
  return NextResponse.json({ url: data.signedUrl, expiresIn: ttl }, { headers: noStore });
}
