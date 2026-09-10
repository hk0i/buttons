// Device-local last-viewed Page per Profile. Deliberately NOT in Config and
// never on the wire — a paired phone and desktop keep their own view. One
// localStorage key holds the whole map, so it's one parse, one write, and
// trivially inspectable in devtools.
//
// Every access is guarded: a thrown or absent localStorage (private mode,
// a fresh production origin, cleared site data) degrades to "no stored page".
// Losing this state is acceptable — it's a best-effort UI convenience.

const KEY = "buttons:lastPageByProfile";

function readMap(): Record<string, string> {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw) as unknown;
    if (parsed && typeof parsed === "object") return parsed as Record<string, string>;
    return {};
  } catch {
    return {};
  }
}

/** Stored page id for this profile, or null if none / storage unavailable. */
export function getLastPageId(profileId: string): string | null {
  const value = readMap()[profileId];
  return typeof value === "string" ? value : null;
}

/** Record the current page for this profile. No-op on storage failure. */
export function setLastPageId(profileId: string, pageId: string): void {
  try {
    const map = readMap();
    map[profileId] = pageId;
    localStorage.setItem(KEY, JSON.stringify(map));
  } catch {
    // swallowed — see file header
  }
}
