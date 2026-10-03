// Generates web/rive/grid-banner/scene.rml: a 4 x 3 grid that assembles into a Herald banner.
// Build: rive rive/grid-banner --once  (outputs rive/grid-banner/build/grid-banner.riv -> copy to public/rive/)
import { writeFileSync } from "node:fs";

let n = 100;
const id = () => `0:${++n}`;
const EXPO = '<CubicEaseInterpolator x1="0.16" y1="1" x2="0.3" y2="1"/>';
const QUINT = '<CubicEaseInterpolator x1="0.22" y1="1" x2="0.36" y2="1"/>';

// colours (ARGB)
// the page's one banner skin: night-2 card, night hairline, bone ink, Herald blue, no green
const PAPER_LINE = "FF263559", CARD = "FF13203F", INK = "FFF4F6FA", MUTED = "FF9AA8C4", ACCENT = "FF3B9BE8", GRID = "B33B9BE8", WHITE = "FFFFFFFF", BTN = "FF1F2F55", SIGNAL = "FFD9371E";

const W = 380, H = 136, PAD = 12, GAP = 8;
const COLS = [40, 172, 68, 52];
const ROWS = [36, 28, 32];
const colX = COLS.reduce((a, w, i) => [...a, i === 0 ? PAD : a[i - 1] + COLS[i - 1] + GAP], []);
const rowY = ROWS.reduce((a, h, i) => [...a, i === 0 ? PAD : a[i - 1] + ROWS[i - 1] + GAP], []);

const font = id();
const sm = id();
const anim = id();
const keyed = []; // { objectId, propertyKey, frames: [[frame, value, interp?]] }
const key = (objectId, propertyKey, frames) => keyed.push({ objectId, propertyKey, frames });

const shapes = [];
// banner background (declared LAST: Rive draws front-to-back, first element on top)
const bannerId = id();
shapes.push(`<Shape x="0" y="0" name="Banner" id="${bannerId}"><Rectangle width="${W}" height="${H}" originX="0" originY="0" cornerRadiusTL="12" name="Path"/><Fill name="Fill"><SolidColor colorValue="${CARD}" name="C"/></Fill><Stroke thickness="1" name="Stroke"><SolidColor colorValue="${PAPER_LINE}" name="C"/></Stroke></Shape>`);
key(bannerId, 18, [[0, 0, EXPO], [18, 1]]);

// 12 dashed cells
const swallowed = new Set(["0-2", "1-2", "1-3", "2-3"]);
const merges = { "0-1": 172 + GAP + 68, "1-1": 172 + GAP + 68 + GAP + 52, "2-2": 68 + GAP + 52 };
let k = 0;
for (let r = 0; r < 3; r++) for (let c = 0; c < 4; c++) {
  const cid = id(), pid = id();
  const w = COLS[c], h = ROWS[r];
  shapes.push(`<Shape x="${colX[c]}" y="${rowY[r]}" name="cell-${r}-${c}" id="${cid}"><Rectangle width="${w}" height="${h}" originX="0" originY="0" cornerRadiusTL="5" name="Path" id="${pid}"/><Stroke thickness="1" cap="round" name="Stroke"><SolidColor colorValue="${GRID}" name="C"/><DashPath name="Dashes"><Dash length="4" name="On"/><Dash length="3" name="Off"/></DashPath></Stroke></Shape>`);
  const s = 6 + k * 3, e = s + 14;
  const tag = `${r}-${c}`;
  if (swallowed.has(tag)) key(cid, 18, [[0, 0], [s, 0, EXPO], [e, 1], [48, 1, QUINT], [60, 0]]);
  else key(cid, 18, [[0, 0], [s, 0, EXPO], [e, 1], [112, 1, QUINT], [134, 0]]);
  if (merges[tag]) key(pid, 20, [[0, w], [50, w, QUINT], [66, merges[tag]]]);
  k++;
}

// components: a Node per component, keyed on opacity (18) and y (14)
const comps = [];
const comp = (name, x, y, inner, start) => {
  const nid = id();
  comps.push(`<Node x="${x}" y="${y}" name="${name}" id="${nid}">${inner}</Node>`);
  key(nid, 18, [[0, 0], [start, 0, EXPO], [start + 14, 1]]);
  key(nid, 14, [[0, y - 8], [start, y - 8, EXPO], [start + 18, y]]);
};
const style = (sid, size, weight, color, styleName) =>
  `<TextStylePaint fontSize="${size}" fontAssetId="${font}" familyName="DM Sans" styleName="${styleName}" name="S" id="${sid}"><Fill name="Fill"><SolidColor colorValue="${color}" name="C"/></Fill><TextStyleAxis tag="2003265652" axisValue="${weight}" name="Weight"/></TextStylePaint>`;
const text = (str, x, y, size, weight, color, styleName, centered = false) => {
  const sid = id();
  return `<Text x="${x}" y="${y}" sizingValue="autoWidth" ${centered ? 'originX="0.5" originY="0.5"' : ""} name="T"><${""}LayoutParticipantPlaceholder/>${style(sid, size, weight, color, styleName)}<TextValueRun styleId="${sid}" text="${str}" name="Run"/></Text>`.replace("<LayoutParticipantPlaceholder/>", "");
};

// icon: 32x32 Herald-blue tile with a white dot and the mark's red dot
comp("Icon", colX[0] + 4, rowY[0] + 2, `<Shape x="9" y="9" name="Bell"><Rectangle width="14" height="14" originX="0" originY="0" cornerRadiusTL="7" name="Path"/><Fill name="Fill"><SolidColor colorValue="${WHITE}" name="C"/></Fill></Shape><Shape x="21" y="3" name="Dot"><Rectangle width="8" height="8" originX="0" originY="0" cornerRadiusTL="4" name="Path"/><Fill name="Fill"><SolidColor colorValue="${SIGNAL}" name="C"/></Fill></Shape><Shape name="Tile"><Rectangle width="32" height="32" originX="0" originY="0" cornerRadiusTL="8" name="Path"/><Fill name="Fill"><SolidColor colorValue="${ACCENT}" name="C"/></Fill></Shape>`, 70);
// title
comp("Title", colX[1], rowY[0] + 9, text("Build passed", 0, 0, 14, 600, INK, "SemiBold"), 76);
// status badge, trailing-centred in its cell
comp("Badge", colX[3] + (COLS[3] - 36), rowY[0] + 9, `${text("OK", 18, 9, 10, 700, WHITE, "Bold", true)}<Shape name="Pill"><Rectangle width="36" height="18" originX="0" originY="0" cornerRadiusTL="9" name="Path"/><Fill name="Fill"><SolidColor colorValue="${ACCENT}" name="C"/></Fill></Shape>`, 82);
// body
comp("Body", colX[1], rowY[1] + 6, text("142 tests, 0 failures · main", 0, 0, 12, 400, MUTED, "Regular"), 88);
// buttons
comp("OpenLog", colX[1], rowY[2], `${text("Open log", 42, 16, 12, 600, WHITE, "SemiBold", true)}<Shape name="Btn"><Rectangle width="84" height="32" originX="0" originY="0" cornerRadiusTL="7" name="Path"/><Fill name="Fill"><SolidColor colorValue="${ACCENT}" name="C"/></Fill></Shape>`, 94);
comp("Deploy", colX[2], rowY[2], `${text("Deploy", 36, 16, 12, 600, INK, "SemiBold", true)}<Shape name="Btn"><Rectangle width="72" height="32" originX="0" originY="0" cornerRadiusTL="7" name="Path"/><Fill name="Fill"><SolidColor colorValue="${BTN}" name="C"/></Fill></Shape>`, 100);

const trig = id(), stA = id();
const kf = (f) => f.map(([frame, value, interp]) => `<KeyFrameDouble value="${value}" frame="${frame}" interpolationType="${interp ? "cubic" : "hold"}">${interp ?? ""}</KeyFrameDouble>`).join("");
const keyedXml = keyed.map((k) => `<KeyedObject objectId="${k.objectId}"><KeyedProperty propertyKey="${k.propertyKey}">${kf(k.frames)}</KeyedProperty></KeyedObject>`).join("\n");

const rml = `<Rive version="1" kind="fragment">
<Artboard defaultStateMachineId="${sm}" styleId="0:5" width="${W}" height="${H}" name="grid-banner" id="0:2">
<LayoutComponentStyle name="Artboard Style" id="0:5"/>
${comps.join("\n")}
${shapes.slice(1).join("\n")}
${shapes[0]}
<StateMachine name="Main" id="${sm}"><StateMachineTrigger name="replay" id="${trig}"/>
<StateMachineLayer name="Assemble" id="${id()}"><AnyState x="200" y="-120"/><ExitState x="400" y="-120"/><EntryState><StateTransition stateToId="${stA}"/></EntryState>
<AnimationState x="200" y="0" reset="true" animationId="${anim}" id="${stA}"><StateTransition stateToId="${stA}" duration="0"><TransitionTriggerCondition inputId="${trig}"/></StateTransition></AnimationState>
</StateMachineLayer></StateMachine>
<LinearAnimation loopValue="oneShot" fps="60" duration="150" name="assemble" id="${anim}">
${keyedXml}
</LinearAnimation>
</Artboard>
<FontAsset file="DMSans.ttf" name="DM Sans" id="${font}"/>
</Rive>
`;
writeFileSync(new URL("../rive/grid-banner/scene.rml", import.meta.url), rml);
console.log("wrote scene.rml", rml.length, "bytes");
