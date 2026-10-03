// The MouthKeys grin for mouthkeys.com. The geometry is ported number for number from
// scripts/make_app_icon.swift (the app icon) and DESIGN.md §17; change it there first.
// ===================================================================================
// THE GRIN. Geometry ported number for number from scripts/make_app_icon.swift and
// SignalMenuBarMark.swift (DESIGN.md §17). Nothing here is drawn by eye.
//   64-unit grid, y down. Large master: 7 teeth a jaw, 5 wide on a 6.4 pitch, bite 3,
//   smile lifts the corners. Small master: 5 teeth, 6 wide on an 8 pitch, bite 4.
//   The gold tooth is lower index 4 (large) / 3 (small): accent orange.
// Theming: teeth fill var(--ink) and keycap lines stroke var(--surface). In dark that is
// exactly the app icon (white teeth, ink lines on #111214). In light it prints: ink teeth,
// paper-white chamfers, on white. The gold tooth is orange in both.
// Detail follows the pixel count, as the icon does: >= 4.6 px a unit is the 256 px drawing
// (0.3-unit lines at 0.55), >= 2.3 the 128 px drawing (0.6 at 0.8), below that the small master.
// ===================================================================================
const GRIN = {
  large: { teeth: 7, width: 5, pitch: 6.4, gap: 3, gold: 4, upper: [5, 8, 9, 9, 9, 8, 5], lower: [4, 7, 9, 9, 9, 7, 4], smile: [-2.5, -1, -0.3, 0, -0.3, -1, -2.5] },
  small: { teeth: 5, width: 6, pitch: 8, gap: 4, gold: 3, upper: [7, 11, 11, 11, 7], lower: [6, 10, 10, 10, 6], smile: [-2, 0, 0, 0, -2] },
};
const JAW_MAX = 3;   // units the lower jaw can drop (prototype; the menu bar mark drops 2 pt of 16)

function grinTeeth(m) {
  const x0 = 32 - ((m.teeth - 1) * m.pitch + m.width) / 2, mid = 32;
  const out = [];
  for (let i = 0; i < m.teeth; i++) {
    const x = x0 + i * m.pitch;
    out.push({ i, x, w: m.width, upper: true, y: mid - m.gap / 2 - m.upper[i] + m.smile[i], h: m.upper[i] });
    out.push({ i, x, w: m.width, upper: false, y: mid + m.gap / 2 + m.smile[i], h: m.lower[i], gold: i === m.gold });
  }
  return out;
}
function grinBounds(m) {
  const t = grinTeeth(m);
  const x0 = Math.min(...t.map((r) => r.x)), x1 = Math.max(...t.map((r) => r.x + r.w));
  const y0 = Math.min(...t.map((r) => r.y)), y1 = Math.max(...t.map((r) => r.y + r.h));
  return { x0, x1, y0, y1, w: x1 - x0, h: y1 - y0 };
}
// make_app_icon.swift keycap(): face inset by width * inset, offset by near/far, four chamfers.
function keycapPath(r, inset, near, far) {
  const i = r.w * inset;
  const fy = r.upper ? r.y + i * near : r.y + i * far;
  const f = { x: r.x + i, y: fy, w: r.w - 2 * i, h: r.h - i * (near + far) };
  const n = (v) => +v.toFixed(3);
  return `M${n(f.x)} ${n(f.y)}h${n(f.w)}v${n(f.h)}h${n(-f.w)}Z` +
    `M${n(r.x)} ${n(r.y)}L${n(f.x)} ${n(f.y)}M${n(r.x + r.w)} ${n(r.y)}L${n(f.x + f.w)} ${n(f.y)}` +
    `M${n(r.x)} ${n(r.y + r.h)}L${n(f.x)} ${n(f.y + f.h)}M${n(r.x + r.w)} ${n(r.y + r.h)}L${n(f.x + f.w)} ${n(f.y + f.h)}`;
}
// The mark as an <svg>, cropped to the teeth (plus jaw travel). o.px = rendered width in px.
//   o.style: "solid" (the logo) | "line" (quiet outline for empty states)
//   o.live: leaves room under the lower jaw (<g class="jaw">) for it to drop
function grinSVG(o = {}) {
  const px = o.px || 64;
  const big = GRIN.large, bb = grinBounds(big);
  const pad = 1;
  let ppu = px / (bb.w + 2 * pad);
  const m = ppu >= 2.3 || o.style === "line" ? big : GRIN.small;
  const b = grinBounds(m);
  ppu = px / (b.w + 2 * pad);
  const vb = [b.x0 - pad, b.y0 - pad, b.w + 2 * pad, b.h + 2 * pad + (o.live ? JAW_MAX : 0)];
  const h = vb[3] * ppu;
  const detail = o.style === "line" ? { inset: 0.22, near: 0.6, far: 1.4 } : ppu >= 4.6 ? { inset: 0.22, near: 0.6, far: 1.4, lw: 0.3, a: 0.55 } : ppu >= 2.3 ? { inset: 0.24, near: 0.5, far: 1.5, lw: 0.6, a: 0.8 } : null;
  const teeth = grinTeeth(m);
  const draw = (r) => {
    if (o.style === "line") {
      return `<rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" fill="none" stroke="${r.gold ? "var(--accent)" : "currentColor"}" stroke-width="1" vector-effect="non-scaling-stroke"/>` +
        `<path d="${keycapPath(r, detail.inset, detail.near, detail.far)}" fill="none" stroke="${r.gold ? "var(--accent)" : "currentColor"}" stroke-opacity=".5" stroke-width="1" vector-effect="non-scaling-stroke"/>`;
    }
    const fill = r.gold ? "var(--accent)" : "var(--ink)";
    return `<rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" fill="${fill}"/>` +
      (detail ? `<path d="${keycapPath(r, detail.inset, detail.near, detail.far)}" fill="none" stroke="${r.gold ? "#111214" : "var(--surface)"}" stroke-opacity="${detail.a}" stroke-width="${detail.lw}" stroke-linecap="butt"/>` : "");
  };
  const up = teeth.filter((r) => r.upper).map(draw).join("");
  const lo = teeth.filter((r) => !r.upper).map(draw).join("");
  return `<svg class="grin${o.cls ? " " + o.cls : ""}" width="${+px.toFixed(1)}" height="${+h.toFixed(1)}" viewBox="${vb.join(" ")}" shape-rendering="${ppu >= 2.3 ? "geometricPrecision" : "crispEdges"}" aria-label="MouthKeys" role="img"><g>${up}</g><g class="jaw"${o.live ? ' data-live="1"' : ""}>${lo}</g></svg>`;
}

// Fig. 1: the grin as a dimensioned engineering drawing. Built in px so labels stay 10 pt mono at any scale.
function grinDrawing(o = {}) {
  const s = o.s || 6.4;                       // px per grid unit
  const m = GRIN.large, b = grinBounds(m), teeth = grinTeeth(m);
  const W = o.w || 780, H = o.h || 300;
  const ox = Math.round((o.cx || W / 2) - (b.x0 + b.w / 2) * s), oy = Math.round(H / 2 - (b.y0 + b.h / 2) * s - 6);
  const X = (u) => +(ox + u * s).toFixed(2), Y = (u) => +(oy + u * s).toFixed(2);
  const L = "var(--text-2)", T = "var(--text-2)", RL = o.rl || 228;
  const txt = (x, y, t, a = "start", c = T, wgt = 500) => `<text x="${x}" y="${y}" text-anchor="${a}" fill="${c}" font-family="SF Mono, ui-monospace, Menlo, monospace" font-size="10" font-weight="${wgt}" letter-spacing=".6">${t}</text>`;
  const line = (x1, y1, x2, y2, c = L, w = 1, dash = "") => `<path d="M${x1} ${y1}L${x2} ${y2}" stroke="${c}" stroke-width="${w}"${dash ? ` stroke-dasharray="${dash}"` : ""} fill="none" shape-rendering="crispEdges"/>`;
  let g = "";
  // tooth numbers: 01-07 above the upper jaw, 08-14 below the lower
  const topY = Y(b.y0) - 12, botY = Y(b.y1 + JAW_MAX) + 16;
  teeth.forEach((r) => { const n = r.upper ? r.i + 1 : r.i + 8; g += txt(X(r.x + r.w / 2), r.upper ? topY : botY, String(n).padStart(2, "0"), "middle", r.gold ? "var(--accent)" : T, r.gold ? 600 : 500); });
  // width dimension under the numbers
  const dy = botY + 22, xa = X(b.x0), xb = X(b.x1);
  g += line(xa, botY + 10, xa, dy + 5) + line(xb, botY + 10, xb, dy + 5) + line(xa, dy, xb, dy);
  g += line(xa, dy - 4, xa + 6, dy, L) + line(xa, dy + 4, xa + 6, dy, L) + line(xb, dy - 4, xb - 6, dy, L) + line(xb, dy + 4, xb - 6, dy, L);
  g += `<rect x="${(xa + xb) / 2 - 92}" y="${dy - 7}" width="184" height="14" fill="var(--surface)"/>` + txt((xa + xb) / 2, dy + 3.5, `${b.w.toFixed(1)} · 7 KEYS × 6.4 PITCH`, "middle");
  // height dimension at the left
  const hx = xa - 34, ya = Y(b.y0), yb = Y(b.y1);
  g += line(xa - 8, ya, hx - 5, ya) + line(xa - 8, yb, hx - 5, yb) + line(hx, ya, hx, yb);
  g += line(hx - 4, ya + 6, hx, ya) + line(hx + 4, ya + 6, hx, ya) + line(hx - 4, yb - 6, hx, yb) + line(hx + 4, yb - 6, hx, yb);
  g += `<g transform="translate(${hx - 8} ${(ya + yb) / 2}) rotate(-90)">${txt(0, 0, b.h.toFixed(1), "middle")}</g>`;
  // callout: the keycap plan view (upper tooth 06)
  const k = teeth.find((r) => r.upper && r.i === 5);
  const kx = X(k.x + k.w * 0.5), ky = Y(k.y + k.h * 0.35), lx = xb + 46, ly = Y(b.y0) - 4;
  g += `<circle cx="${kx}" cy="${ky}" r="2" fill="${L}"/>` + line(kx, ky, lx - 8, ly) + line(lx - 8, ly, lx + RL, ly);
  g += txt(lx, ly - 6, "KEYCAP · PLAN VIEW") + txt(lx, ly + 14, "FACE INSET 0.22 · 4 CHAMFERS");
  // callout: the bite, measured at the outer tooth where the smile lifts it 2.5
  const ly2 = Y(32) + 6, bt = Y(32 - 1.5 - 2.5), bbm = Y(32 + 1.5 - 2.5);
  g += line(xb + 6, bt, xb + 12, bt) + line(xb + 6, bbm, xb + 12, bbm) + line(xb + 12, bt, xb + 12, bbm) + line(xb + 12, (bt + bbm) / 2, lx - 8, ly2) + line(lx - 8, ly2, lx + RL, ly2);
  g += txt(lx, ly2 - 6, "BITE 3.0 · SMILE 2.5");
  // callout: the gold tooth (tooth 12). The leader runs along y 41, under teeth 13 and 14, so it crosses nothing.
  const gt = teeth.find((r) => r.gold);
  const gx = X(gt.x + gt.w / 2), ly3 = Y(41);
  g += line(gx, ly3, lx + RL, ly3, "var(--text)") + `<rect x="${gx - 3}" y="${ly3 - 3}" width="6" height="6" fill="var(--surface)" stroke="var(--text)" stroke-width="1.5"/>`;
  g += `<rect x="${lx}" y="${ly3 - 14}" width="6" height="6" fill="var(--accent)"/>` + txt(lx + 12, ly3 - 7.5, "TOOTH 12 · <tspan class=\"grin-state\">GOLD</tspan>", "start", "var(--text)", 600);
  g += txt(lx, ly3 + 15, "THE ONE COLOUR · #FF4F1F");
  // the grin itself (detail by scale), lower jaw live
  const det = s >= 4.6 ? { inset: 0.22, near: 0.6, far: 1.4, lw: 0.3, a: 0.55 } : { inset: 0.24, near: 0.5, far: 1.5, lw: 0.6, a: 0.8 };
  const draw = (r) => `<rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" fill="${r.gold ? "var(--accent)" : "var(--ink)"}"/><path d="${keycapPath(r, det.inset, det.near, det.far)}" fill="none" stroke="${r.gold ? "#111214" : "var(--surface)"}" stroke-opacity="${det.a}" stroke-width="${det.lw}"/>`;
  const mark = `<g transform="translate(${ox} ${oy}) scale(${s})"><g>${teeth.filter((r) => r.upper).map(draw).join("")}</g><g class="jaw" data-live="1">${teeth.filter((r) => !r.upper).map(draw).join("")}</g></g>`;
  // centre line through the bite, a drawing convention (dash-dot)
  const cl = line(xa - 16, Y(32), xb + 16, Y(32), "var(--grat)", 1, "10 3 2 3");
  return `<svg class="grin-dwg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="MouthKeys grin, dimensioned">${cl}${mark}${g}</svg>`;
}

if (typeof module !== "undefined") module.exports = { GRIN, grinSVG, grinDrawing, grinTeeth, grinBounds, keycapPath };
