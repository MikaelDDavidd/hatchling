// Simulações do Hatchling na landing: o painel do notch no Mac e o app no iPhone, montados em
// HTML e tocando sozinhos em cenas. Clicar numa cena pula pra ela; o roteiro segue dali.
// Pausa quando sai da tela. Com "reduzir movimento" ligado, as cenas trocam sem deslizar nem pular.
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---------------------------------------------------------------- Hatch
  const EYES = {
    claude: ['#ff8f5c', '#ffc3a6', '#a65c3b'],
    codex: ['#6ba8ff', '#b3d1ff', '#456ea6'],
  };
  let uid = 0;
  function bodyPath() {
    const l = 5, t = 20, r = 95, b = 88, cr = 20, k = cr * 0.38, nl = 35, nr = 65, nd = 8;
    return `M${l + cr} ${t} L${nl - 3} ${t} C${nl + 1.5} ${t} ${nl + 1} ${t + nd} ${nl + 4} ${t + nd} L${nr - 4} ${t + nd} C${nr - 1} ${t + nd} ${nr - 1.5} ${t} ${nr + 3} ${t} L${r - cr} ${t} C${r - k} ${t} ${r} ${t + k} ${r} ${t + cr} L${r} ${b - cr} C${r} ${b - k} ${r - k} ${b} ${r - cr} ${b} L${l + cr} ${b} C${l + k} ${b} ${l} ${b - k} ${l} ${b - cr} L${l} ${t + cr} C${l} ${t + k} ${l + k} ${t} ${l + cr} ${t} Z`;
  }
  const BODY = bodyPath();
  function hatch(mood = 'idle', agent = 'claude') {
    const id = 'h' + (++uid);
    const [eye, light, dim] = EYES[agent] || EYES.claude;
    let hands = { lx: -10, ly: 70, lr: 12.6, rx: 110, ry: 70, rr: -12.6 };
    if (mood === 'cheering' || mood === 'excited' || mood === 'jump') hands = { lx: -14, ly: 28, lr: 28, rx: 114, ry: 28, rr: -28 };
    if (mood === 'waving' || mood === 'wave') Object.assign(hands, { rx: 112, ry: 34, rr: -34 });
    if (mood === 'surprised') Object.assign(hands, { ly: 61, ry: 61 });
    if (mood === 'angry') hands = { lx: -4, ly: 80, lr: 12.6, rx: 104, ry: 80, rr: -12.6 };
    if (mood === 'thinking') Object.assign(hands, { rx: 70, ry: 100 });
    let p = { x: 0, y: 0 };
    if (mood === 'working') p = { x: 1.8, y: 2.4 };
    if (mood === 'thinking') p = { x: -3.2, y: -3 };
    const irisR = (mood === 'surprised' || mood === 'jump') ? 18 : (mood === 'approval' || mood === 'question' || mood === 'excited') ? 16.5 : 14.5;
    const pupilR = (mood === 'surprised' || mood === 'jump') ? 7.8 : irisR / 14.5 * 11.2;
    const px = 2.2 * irisR / 14.5, py = 55 - 2.4 * irisR / 14.5 + p.y;
    const happy = mood === 'happy' || mood === 'cheering' || mood === 'waving';
    const sleep = mood === 'sleeping', wink = mood === 'wink';
    const sign = mood === 'question' ? '?' : '!';
    const hand = (x, y, r, dx) => `<g transform="translate(${x} ${y}) rotate(${r})"><ellipse cx="${dx}" cy="-5.5" rx="3.2" ry="3.4" fill="#1f2127" stroke="#5c616e" stroke-width="2.2"/><ellipse rx="8" ry="7" fill="#1f2127" stroke="#5c616e" stroke-width="2.2"/><ellipse cx="-2.5" cy="-3.5" rx="3.4" ry="2" fill="#fff" opacity=".1"/></g>`;
    const eyeOpen = (cx, show) => show ? `<circle cx="${cx}" cy="55" r="${irisR}" fill="url(#i${id})"/><g class="look"><circle cx="${cx + px + p.x}" cy="${py}" r="${pupilR}" fill="url(#p${id})"/><ellipse cx="${cx + px + p.x + 2.5}" cy="${py - 4.5}" rx="3.5" ry="2.5" fill="#fff" opacity=".92"/></g>` : '';
    return `<svg class="hatch" viewBox="-24 -40 148 148" width="100%" height="100%" aria-hidden="true">
<defs><linearGradient id="b${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#292b33"/><stop offset="1" stop-color="#0f1014"/></linearGradient>
<linearGradient id="s${id}" x1="0" y1=".15" x2="0" y2=".55"><stop offset="0" stop-color="#fff" stop-opacity=".1"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
<radialGradient id="i${id}" cx=".3" cy=".75" r=".95"><stop offset="0" stop-color="${light}"/><stop offset="1" stop-color="${eye}"/></radialGradient>
<radialGradient id="p${id}" cx=".4" cy=".3" r=".85"><stop offset="0" stop-color="#1a2838"/><stop offset="1" stop-color="#020406"/></radialGradient></defs>
${hand(hands.lx, hands.ly, hands.lr, 6.5)}${hand(hands.rx, hands.ry, hands.rr, -6.5)}
<g class="body-g"><path d="${BODY}" fill="url(#b${id})"/><path d="${BODY}" fill="url(#s${id})"/><path d="${BODY}" fill="none" stroke="#5c616e" stroke-width="2.4" stroke-linejoin="round"/>
${mood === 'working' || mood === 'thinking' ? `<g fill="${eye}"><circle cx="44" cy="24" r="1.9"/><circle cx="50" cy="22.4" r="1.9"/><circle cx="56" cy="24" r="1.9"/></g>` : ''}
${mood === 'approval' || mood === 'question' ? `<text x="50" y="16" text-anchor="middle" font-family="-apple-system,system-ui,sans-serif" font-size="17" font-weight="800" fill="#ffb84d">${sign}</text>` : ''}
<g class="eyes">${eyeOpen(33, !happy && !sleep)}${eyeOpen(67, !happy && !sleep && !wink)}</g>
${mood === 'angry' ? `<path d="M18 49 L48 49 L48 63 L18 58 Z" fill="#1c1e24"/><path d="M52 49 L82 49 L82 58 L52 63 Z" fill="#1c1e24"/>` : ''}
${happy ? `<path d="M24 59 Q33 46 42 59" fill="none" stroke="${eye}" stroke-width="4.2" stroke-linecap="round"/>` : ''}
${happy || wink ? `<path d="M58 59 Q67 46 76 59" fill="none" stroke="${eye}" stroke-width="4.2" stroke-linecap="round"/>` : ''}
${sleep ? `<path d="M24 56 Q33 64 42 56" fill="none" stroke="${dim}" stroke-width="3.8" stroke-linecap="round"/><path d="M58 56 Q67 64 76 56" fill="none" stroke="${dim}" stroke-width="3.8" stroke-linecap="round"/>` : ''}
${wink || mood === 'happy' || mood === 'excited' || mood === 'wave' ? `<path d="M43 77 Q50 84 57 77" fill="none" stroke="${eye}" stroke-width="3.2" stroke-linecap="round"/>` : ''}
${mood === 'surprised' || mood === 'jump' ? `<ellipse cx="50" cy="78" rx="3.5" ry="4" fill="#0d0d12" stroke="${eye}" stroke-width="2.2"/>` : ''}
${mood === 'angry' ? `<path d="M45 79 L55 79" stroke="${eye}" stroke-width="3.2" stroke-linecap="round"/>` : ''}
</g></svg>`;
  }
  function setHatch(el, mood, agent, hop) {
    if (!el) return;
    el.innerHTML = hatch(mood, agent);
    if (hop && !reduce) { el.classList.remove('hop'); void el.offsetWidth; el.classList.add('hop'); }
  }
  function say(el, text) {
    if (!el || el.textContent === text) return;
    if (reduce) { el.textContent = text; return; }
    el.classList.add('swap');
    setTimeout(() => { el.textContent = text; el.classList.remove('swap'); }, 160);
  }

  // ---------------------------------------------------------------- shared pieces
  const C = {
    working: '#5cd980', waiting: '#ffa640', idle: 'rgba(255,255,255,.36)',
    claude: '#e0905f', codex: '#6ba8ff', ctxLow: '#5fcf7f', ctxMid: '#d6c35a', ctxHigh: '#e8a33d',
    claudeUse: '#c97b54', codexUse: '#7d93e0',
  };
  const ctxColor = (p) => p < 50 ? C.ctxLow : p < 80 ? C.ctxMid : C.ctxHigh;
  const STATE = { working: ['working', C.working], approval: ['needs your OK', C.waiting], question: ['has a question', C.waiting], idle: ['idle', C.idle] };
  const MARK = {
    claude: (c) => `<svg width="11" height="11" viewBox="-8 -8 16 16" stroke="${c}" stroke-width="1.6" stroke-linecap="round"><path d="M0 -7 V7 M-7 0 H7 M-5 -5 L5 5 M5 -5 L-5 5"/></svg>`,
    codex: (c) => `<svg width="11" height="11" viewBox="-8 -8 16 16" fill="none" stroke="${c}" stroke-width="1.6"><path d="M0 -6.5 L5.6 -3.2 V3.2 L0 6.5 L-5.6 3.2 V-3.2 Z"/></svg>`,
  };
  function dot(s) {
    const color = s.agent === 'codex' ? C.codex : C.claude;
    const busy = s.status === 'working';
    return `<span class="adot${busy ? ' pulse' : ''}" style="background:${color};color:${color};opacity:${s.status === 'idle' ? .4 : 1}"></span>`;
  }
  const QR = 'M0 0h1v1h-1zM1 0h1v1h-1zM2 0h1v1h-1zM3 0h1v1h-1zM4 0h1v1h-1zM5 0h1v1h-1zM6 0h1v1h-1zM9 0h1v1h-1zM10 0h1v1h-1zM11 0h1v1h-1zM14 0h1v1h-1zM16 0h1v1h-1zM18 0h1v1h-1zM20 0h1v1h-1zM24 0h1v1h-1zM26 0h1v1h-1zM27 0h1v1h-1zM28 0h1v1h-1zM29 0h1v1h-1zM30 0h1v1h-1zM31 0h1v1h-1zM32 0h1v1h-1zM0 1h1v1h-1zM6 1h1v1h-1zM8 1h1v1h-1zM9 1h1v1h-1zM11 1h1v1h-1zM12 1h1v1h-1zM13 1h1v1h-1zM14 1h1v1h-1zM16 1h1v1h-1zM18 1h1v1h-1zM21 1h1v1h-1zM26 1h1v1h-1zM32 1h1v1h-1zM0 2h1v1h-1zM2 2h1v1h-1zM3 2h1v1h-1zM4 2h1v1h-1zM6 2h1v1h-1zM8 2h1v1h-1zM9 2h1v1h-1zM11 2h1v1h-1zM12 2h1v1h-1zM13 2h1v1h-1zM16 2h1v1h-1zM18 2h1v1h-1zM21 2h1v1h-1zM23 2h1v1h-1zM24 2h1v1h-1zM26 2h1v1h-1zM28 2h1v1h-1zM29 2h1v1h-1zM30 2h1v1h-1zM32 2h1v1h-1zM0 3h1v1h-1zM2 3h1v1h-1zM3 3h1v1h-1zM4 3h1v1h-1zM6 3h1v1h-1zM8 3h1v1h-1zM9 3h1v1h-1zM10 3h1v1h-1zM19 3h1v1h-1zM21 3h1v1h-1zM22 3h1v1h-1zM26 3h1v1h-1zM28 3h1v1h-1zM29 3h1v1h-1zM30 3h1v1h-1zM32 3h1v1h-1zM0 4h1v1h-1zM2 4h1v1h-1zM3 4h1v1h-1zM4 4h1v1h-1zM6 4h1v1h-1zM9 4h1v1h-1zM10 4h1v1h-1zM13 4h1v1h-1zM15 4h1v1h-1zM17 4h1v1h-1zM18 4h1v1h-1zM20 4h1v1h-1zM23 4h1v1h-1zM24 4h1v1h-1zM26 4h1v1h-1zM28 4h1v1h-1zM29 4h1v1h-1zM30 4h1v1h-1zM32 4h1v1h-1zM0 5h1v1h-1zM6 5h1v1h-1zM9 5h1v1h-1zM11 5h1v1h-1zM12 5h1v1h-1zM13 5h1v1h-1zM14 5h1v1h-1zM16 5h1v1h-1zM17 5h1v1h-1zM20 5h1v1h-1zM21 5h1v1h-1zM24 5h1v1h-1zM26 5h1v1h-1zM32 5h1v1h-1zM0 6h1v1h-1zM1 6h1v1h-1zM2 6h1v1h-1zM3 6h1v1h-1zM4 6h1v1h-1zM5 6h1v1h-1zM6 6h1v1h-1zM8 6h1v1h-1zM10 6h1v1h-1zM12 6h1v1h-1zM14 6h1v1h-1zM16 6h1v1h-1zM18 6h1v1h-1zM20 6h1v1h-1zM22 6h1v1h-1zM24 6h1v1h-1zM26 6h1v1h-1zM27 6h1v1h-1zM28 6h1v1h-1zM29 6h1v1h-1zM30 6h1v1h-1zM31 6h1v1h-1zM32 6h1v1h-1zM8 7h1v1h-1zM9 7h1v1h-1zM11 7h1v1h-1zM18 7h1v1h-1zM23 7h1v1h-1zM24 7h1v1h-1zM0 8h1v1h-1zM6 8h1v1h-1zM8 8h1v1h-1zM11 8h1v1h-1zM12 8h1v1h-1zM13 8h1v1h-1zM14 8h1v1h-1zM15 8h1v1h-1zM16 8h1v1h-1zM17 8h1v1h-1zM19 8h1v1h-1zM25 8h1v1h-1zM26 8h1v1h-1zM29 8h1v1h-1zM30 8h1v1h-1zM31 8h1v1h-1zM2 9h1v1h-1zM3 9h1v1h-1zM5 9h1v1h-1zM9 9h1v1h-1zM11 9h1v1h-1zM12 9h1v1h-1zM14 9h1v1h-1zM15 9h1v1h-1zM18 9h1v1h-1zM19 9h1v1h-1zM22 9h1v1h-1zM23 9h1v1h-1zM28 9h1v1h-1zM30 9h1v1h-1zM4 10h1v1h-1zM6 10h1v1h-1zM7 10h1v1h-1zM10 10h1v1h-1zM11 10h1v1h-1zM12 10h1v1h-1zM15 10h1v1h-1zM16 10h1v1h-1zM18 10h1v1h-1zM20 10h1v1h-1zM0 11h1v1h-1zM3 11h1v1h-1zM4 11h1v1h-1zM7 11h1v1h-1zM8 11h1v1h-1zM10 11h1v1h-1zM12 11h1v1h-1zM14 11h1v1h-1zM15 11h1v1h-1zM16 11h1v1h-1zM19 11h1v1h-1zM23 11h1v1h-1zM24 11h1v1h-1zM26 11h1v1h-1zM28 11h1v1h-1zM29 11h1v1h-1zM30 11h1v1h-1zM31 11h1v1h-1zM6 12h1v1h-1zM8 12h1v1h-1zM9 12h1v1h-1zM10 12h1v1h-1zM12 12h1v1h-1zM13 12h1v1h-1zM14 12h1v1h-1zM16 12h1v1h-1zM18 12h1v1h-1zM19 12h1v1h-1zM21 12h1v1h-1zM23 12h1v1h-1zM24 12h1v1h-1zM26 12h1v1h-1zM27 12h1v1h-1zM0 13h1v1h-1zM3 13h1v1h-1zM4 13h1v1h-1zM7 13h1v1h-1zM8 13h1v1h-1zM11 13h1v1h-1zM13 13h1v1h-1zM14 13h1v1h-1zM16 13h1v1h-1zM17 13h1v1h-1zM18 13h1v1h-1zM19 13h1v1h-1zM21 13h1v1h-1zM23 13h1v1h-1zM24 13h1v1h-1zM25 13h1v1h-1zM26 13h1v1h-1zM29 13h1v1h-1zM32 13h1v1h-1zM4 14h1v1h-1zM6 14h1v1h-1zM8 14h1v1h-1zM9 14h1v1h-1zM10 14h1v1h-1zM11 14h1v1h-1zM14 14h1v1h-1zM17 14h1v1h-1zM20 14h1v1h-1zM22 14h1v1h-1zM24 14h1v1h-1zM27 14h1v1h-1zM29 14h1v1h-1zM0 15h1v1h-1zM9 15h1v1h-1zM13 15h1v1h-1zM14 15h1v1h-1zM15 15h1v1h-1zM23 15h1v1h-1zM24 15h1v1h-1zM27 15h1v1h-1zM29 15h1v1h-1zM30 15h1v1h-1zM31 15h1v1h-1zM1 16h1v1h-1zM2 16h1v1h-1zM6 16h1v1h-1zM8 16h1v1h-1zM9 16h1v1h-1zM10 16h1v1h-1zM13 16h1v1h-1zM17 16h1v1h-1zM19 16h1v1h-1zM28 16h1v1h-1zM29 16h1v1h-1zM32 16h1v1h-1zM0 17h1v1h-1zM5 17h1v1h-1zM7 17h1v1h-1zM8 17h1v1h-1zM9 17h1v1h-1zM12 17h1v1h-1zM15 17h1v1h-1zM16 17h1v1h-1zM18 17h1v1h-1zM19 17h1v1h-1zM20 17h1v1h-1zM21 17h1v1h-1zM23 17h1v1h-1zM25 17h1v1h-1zM26 17h1v1h-1zM27 17h1v1h-1zM30 17h1v1h-1zM32 17h1v1h-1zM0 18h1v1h-1zM2 18h1v1h-1zM3 18h1v1h-1zM6 18h1v1h-1zM7 18h1v1h-1zM9 18h1v1h-1zM14 18h1v1h-1zM15 18h1v1h-1zM16 18h1v1h-1zM18 18h1v1h-1zM19 18h1v1h-1zM20 18h1v1h-1zM22 18h1v1h-1zM23 18h1v1h-1zM25 18h1v1h-1zM26 18h1v1h-1zM28 18h1v1h-1zM29 18h1v1h-1zM32 18h1v1h-1zM0 19h1v1h-1zM1 19h1v1h-1zM4 19h1v1h-1zM5 19h1v1h-1zM7 19h1v1h-1zM10 19h1v1h-1zM11 19h1v1h-1zM14 19h1v1h-1zM15 19h1v1h-1zM16 19h1v1h-1zM18 19h1v1h-1zM20 19h1v1h-1zM22 19h1v1h-1zM23 19h1v1h-1zM29 19h1v1h-1zM30 19h1v1h-1zM31 19h1v1h-1zM32 19h1v1h-1zM0 20h1v1h-1zM1 20h1v1h-1zM2 20h1v1h-1zM3 20h1v1h-1zM6 20h1v1h-1zM8 20h1v1h-1zM9 20h1v1h-1zM11 20h1v1h-1zM12 20h1v1h-1zM16 20h1v1h-1zM17 20h1v1h-1zM25 20h1v1h-1zM27 20h1v1h-1zM28 20h1v1h-1zM31 20h1v1h-1zM32 20h1v1h-1zM0 21h1v1h-1zM2 21h1v1h-1zM7 21h1v1h-1zM8 21h1v1h-1zM10 21h1v1h-1zM11 21h1v1h-1zM13 21h1v1h-1zM14 21h1v1h-1zM16 21h1v1h-1zM21 21h1v1h-1zM23 21h1v1h-1zM28 21h1v1h-1zM29 21h1v1h-1zM30 21h1v1h-1zM31 21h1v1h-1zM0 22h1v1h-1zM3 22h1v1h-1zM6 22h1v1h-1zM8 22h1v1h-1zM9 22h1v1h-1zM15 22h1v1h-1zM16 22h1v1h-1zM22 22h1v1h-1zM26 22h1v1h-1zM27 22h1v1h-1zM28 22h1v1h-1zM29 22h1v1h-1zM31 22h1v1h-1zM0 23h1v1h-1zM2 23h1v1h-1zM4 23h1v1h-1zM11 23h1v1h-1zM12 23h1v1h-1zM18 23h1v1h-1zM19 23h1v1h-1zM22 23h1v1h-1zM24 23h1v1h-1zM26 23h1v1h-1zM29 23h1v1h-1zM30 23h1v1h-1zM0 24h1v1h-1zM1 24h1v1h-1zM2 24h1v1h-1zM3 24h1v1h-1zM4 24h1v1h-1zM6 24h1v1h-1zM12 24h1v1h-1zM14 24h1v1h-1zM15 24h1v1h-1zM16 24h1v1h-1zM19 24h1v1h-1zM24 24h1v1h-1zM25 24h1v1h-1zM26 24h1v1h-1zM27 24h1v1h-1zM28 24h1v1h-1zM31 24h1v1h-1zM8 25h1v1h-1zM9 25h1v1h-1zM14 25h1v1h-1zM15 25h1v1h-1zM16 25h1v1h-1zM17 25h1v1h-1zM18 25h1v1h-1zM19 25h1v1h-1zM20 25h1v1h-1zM23 25h1v1h-1zM24 25h1v1h-1zM28 25h1v1h-1zM29 25h1v1h-1zM30 25h1v1h-1zM32 25h1v1h-1zM0 26h1v1h-1zM1 26h1v1h-1zM2 26h1v1h-1zM3 26h1v1h-1zM4 26h1v1h-1zM5 26h1v1h-1zM6 26h1v1h-1zM9 26h1v1h-1zM10 26h1v1h-1zM13 26h1v1h-1zM15 26h1v1h-1zM16 26h1v1h-1zM20 26h1v1h-1zM22 26h1v1h-1zM23 26h1v1h-1zM24 26h1v1h-1zM26 26h1v1h-1zM28 26h1v1h-1zM29 26h1v1h-1zM30 26h1v1h-1zM31 26h1v1h-1zM0 27h1v1h-1zM6 27h1v1h-1zM9 27h1v1h-1zM14 27h1v1h-1zM20 27h1v1h-1zM23 27h1v1h-1zM24 27h1v1h-1zM28 27h1v1h-1zM29 27h1v1h-1zM30 27h1v1h-1zM31 27h1v1h-1zM0 28h1v1h-1zM2 28h1v1h-1zM3 28h1v1h-1zM4 28h1v1h-1zM6 28h1v1h-1zM9 28h1v1h-1zM11 28h1v1h-1zM12 28h1v1h-1zM13 28h1v1h-1zM14 28h1v1h-1zM18 28h1v1h-1zM20 28h1v1h-1zM21 28h1v1h-1zM22 28h1v1h-1zM24 28h1v1h-1zM25 28h1v1h-1zM26 28h1v1h-1zM27 28h1v1h-1zM28 28h1v1h-1zM0 29h1v1h-1zM2 29h1v1h-1zM3 29h1v1h-1zM4 29h1v1h-1zM6 29h1v1h-1zM9 29h1v1h-1zM12 29h1v1h-1zM13 29h1v1h-1zM16 29h1v1h-1zM18 29h1v1h-1zM19 29h1v1h-1zM21 29h1v1h-1zM22 29h1v1h-1zM28 29h1v1h-1zM30 29h1v1h-1zM31 29h1v1h-1zM32 29h1v1h-1zM0 30h1v1h-1zM2 30h1v1h-1zM3 30h1v1h-1zM4 30h1v1h-1zM6 30h1v1h-1zM10 30h1v1h-1zM11 30h1v1h-1zM14 30h1v1h-1zM16 30h1v1h-1zM17 30h1v1h-1zM19 30h1v1h-1zM21 30h1v1h-1zM22 30h1v1h-1zM23 30h1v1h-1zM24 30h1v1h-1zM25 30h1v1h-1zM28 30h1v1h-1zM31 30h1v1h-1zM32 30h1v1h-1zM0 31h1v1h-1zM6 31h1v1h-1zM9 31h1v1h-1zM11 31h1v1h-1zM15 31h1v1h-1zM16 31h1v1h-1zM18 31h1v1h-1zM30 31h1v1h-1zM0 32h1v1h-1zM1 32h1v1h-1zM2 32h1v1h-1zM3 32h1v1h-1zM4 32h1v1h-1zM5 32h1v1h-1zM6 32h1v1h-1zM8 32h1v1h-1zM9 32h1v1h-1zM11 32h1v1h-1zM13 32h1v1h-1zM17 32h1v1h-1zM18 32h1v1h-1zM22 32h1v1h-1zM23 32h1v1h-1zM24 32h1v1h-1zM25 32h1v1h-1zM28 32h1v1h-1zM31 32h1v1h-1z';

  // Fits a fixed-size design into its stage, keeping it crisp.
  function fit(stage, scaler, w) {
    const apply = () => { scaler.style.transform = `scale(${stage.clientWidth / w})`; };
    new ResizeObserver(apply).observe(stage);
    apply();
  }
  const scaleOf = (stage, w) => stage.clientWidth / w;
  // Position of an element inside the design, in design pixels.
  function where(root, el, stage, w, ox = .5, oy = .5) {
    const s = scaleOf(stage, w), a = root.getBoundingClientRect(), b = el.getBoundingClientRect();
    return { x: (b.left - a.left + b.width * ox) / s, y: (b.top - a.top + b.height * oy) / s };
  }

  // Scenes play in order and loop. Each one sets up its own starting state, so jumping to
  // any of them always looks right.
  // Scenes are slowed down by this much, so there is time to read what Hatch is doing.
  const SPEED = 1.7;

  function director(scenes, chipsEl, stage) {
    let i = 0, timers = [], visible = true, running = false;
    let started = 0, elapsed = 0, hovered = false;
    const chips = scenes.map((sc, n) => {
      const b = document.createElement('button');
      b.className = 'scene'; b.type = 'button';
      b.innerHTML = `${sc.label}<span class="bar"><i></i></span>`;
      b.style.setProperty('--dur', sc.dur * SPEED + 'ms');
      b.addEventListener('click', () => { play(n); });
      chipsEl.appendChild(b);
      return b;
    });
    const clear = () => { timers.forEach(clearTimeout); timers = []; };
    const bar = () => chips[i].querySelector('i');
    // Runs what is left of the current scene from `from` ms in.
    function schedule(from) {
      clear();
      const sc = scenes[i];
      started = performance.now() - from;
      sc.steps.forEach(([at, fn]) => { const t = at * SPEED; if (t >= from) timers.push(setTimeout(fn, t - from)); });
      timers.push(setTimeout(() => {
        if (hovered) return;
        if (visible) play((i + 1) % scenes.length); else running = false;
      }, Math.max(0, sc.dur * SPEED - from)));
      running = true;
    }
    function play(n) {
      i = n;
      chips.forEach((c, k) => { c.classList.toggle('on', k === n); const r = c.querySelector('i'); r.style.animation = 'none'; void r.offsetWidth; r.style.animation = ''; r.style.animationPlayState = ''; });
      // With "reduce motion" the scenes still advance, they just cut instead of moving.
      scenes[n].setup();
      schedule(0);
      if (hovered) pause();
    }
    // Mouse over the simulation holds it where it is, until the mouse leaves.
    function pause() {
      elapsed = performance.now() - started;
      clear();
      bar().style.animationPlayState = 'paused';
    }
    function resume() {
      bar().style.animationPlayState = '';
      schedule(Math.min(elapsed, scenes[i].dur * SPEED));
    }
    stage.addEventListener('mouseenter', () => { hovered = true; pause(); });
    stage.addEventListener('mouseleave', () => { hovered = false; resume(); });
    new IntersectionObserver(([e]) => {
      visible = e.isIntersecting;
      if (visible && !running && !hovered) play(i);
    }, { threshold: .2 }).observe(stage);
    play(0);
  }

  // ================================================================= Mac
  function mac() {
    const stage = document.getElementById('sim-mac');
    if (!stage) return;
    const W = 1280;
    stage.innerHTML = `<div class="sim-scaler"><div class="mac">
  <div class="mac-menubar"><div class="l"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span></div><div class="r"><span>Wed 9:41</span></div></div>
  <div class="notch" id="m-notch">
    <div class="notch-closed"><div style="width:30px;height:30px;position:relative"><div id="m-mini" style="position:absolute;left:-7px;top:-9px;width:44px;height:44px"></div></div><div class="notch-count" id="m-count"></div></div>
    <div class="notch-open" id="m-open">
      <div class="p-head">
        <div style="display:flex;align-items:center;gap:8px"><div style="width:30px;height:30px"></div>
          <div class="p-tabs"><div class="p-tab on">${icon('stack')}Agents</div><div class="p-tab">${icon('tray')}</div><div class="p-tab">${icon('note')}</div></div></div>
        <div class="p-btns"><div class="p-btn" id="m-phone">${icon('phone')}</div><div class="p-btn" id="m-collapse">${icon('chev')}</div><div class="p-btn">${icon('sound')}</div><div class="p-btn">${icon('gear')}</div><div class="p-btn" style="color:rgba(255,110,110,.8)">${icon('power')}</div></div>
      </div>
      <div class="p-body"><div id="m-page"></div></div>
      <div style="height:8px"></div>
    </div>
  </div>
  <div class="cursor" id="m-cursor"><span class="click"></span><svg viewBox="0 0 22 22" width="22" height="22"><path d="M4 2 L4 18 L8.4 14.2 L11.3 20.4 L14 19.2 L11.2 13.2 L17 13 Z" fill="#fff" stroke="#000" stroke-width="1.3" stroke-linejoin="round"/></svg></div>
</div></div>`;
    const scaler = stage.firstElementChild, root = scaler.firstElementChild;
    fit(stage, scaler, W);
    const $ = (id) => root.querySelector('#' + id);
    const notch = $('m-notch'), page = $('m-page'), cursor = $('m-cursor');

    let sessions;
    const fresh = () => ([
      { id: 'a', project: 'recipes-api', tag: '#3b1c', agent: 'claude', status: 'working', model: 'opus-5-5', pct: 41, now: 'Editing src/routes/recipes.ts', task: 'Search recipes by ingredient', ago: 'now' },
      { id: 'b', project: 'landing-page', tag: '#c41d', agent: 'codex', status: 'working', model: 'gpt-5.5', pct: 22, now: 'Running pnpm build', task: 'Ship the new home page', ago: '1m' },
      { id: 'c', project: 'budget-app', tag: '#7f2a', agent: 'claude', status: 'idle', model: 'sonnet-5-5', pct: 64, now: 'Done: the spending chart now groups by category.', task: 'Fix the spending chart', ago: '4m' },
    ]);

    function card(s) {
      const [label, color] = STATE[s.status];
      const need = s.status === 'approval' || s.status === 'question';
      let extra = '';
      if (s.status === 'approval') extra = `<div class="code">$ npm run test -- --coverage<small>Run the test suite before deploying</small></div>
        <div class="btns"><span class="b neg">Deny</span><span class="b">Always allow</span><span class="b pri" data-allow>Allow</span></div>`;
      if (s.status === 'question') extra = `<div class="now" style="color:#fff">Which chart should the dashboard use?</div>
        <div class="opt" data-opt><i>1</i>Bars, grouped by category</div><div class="opt"><i>2</i>Donut, share of the month</div><div class="opt"><i>3</i>Line, spending over time</div>`;
      return `<div class="mcard${need ? ' need' : ''}" data-id="${s.id}">
  <div class="dotcol">${dot(s)}</div>
  <div class="main">
    <div class="row"><span class="name" style="color:${s.status === 'idle' ? 'rgba(255,255,255,.7)' : '#fff'}">${s.project}</span><span class="tag">${s.tag}</span><span class="state" style="color:${color}">${label}</span></div>
    <div class="row ctx"><span>${s.model}</span><span class="bar"><i style="width:${s.pct}%;background:${ctxColor(s.pct)}"></i></span><b style="color:${ctxColor(s.pct)}">${s.pct}%</b></div>
    ${s.status === 'approval' ? '<div class="now">Wants to run a command</div>' : s.status === 'question' ? '' : `<div class="now" style="color:${s.status === 'idle' ? 'rgba(255,255,255,.6)' : 'rgba(255,255,255,.86)'}">${s.now}</div>`}
    ${extra}
    <div class="row task" style="margin-top:6px"><span>${s.task}</span><span class="ago">${s.ago}</span>${MARK[s.agent](s.agent === 'codex' ? C.codex : C.claude)}</div>
  </div></div>`;
    }
    function listPage(mood, line, agent = 'claude') {
      page.innerHTML = `<div class="p-usage"><span><b style="color:${C.claudeUse}">Claude</b> 5h<span class="bar" style="background:rgba(201,123,84,.2)"><i style="width:38%;background:${C.claudeUse}"></i></span>38%</span>
        <span>7d<span class="bar" style="background:rgba(232,163,61,.2)"><i style="width:72%;background:${C.ctxHigh}"></i></span><span style="color:${C.ctxHigh}">72%</span></span>
        <span><b style="color:${C.codexUse}">Codex</b> 5h<span class="bar" style="background:rgba(125,147,224,.2)"><i style="width:12%;background:${C.codexUse}"></i></span>12%</span></div>
      <div class="p-stage"><div style="width:50px;height:50px;position:relative;flex-shrink:0;margin:0 6px"><div id="m-hatch" style="position:absolute;left:-12px;top:-19px;width:74px;height:74px"></div></div><div class="say" id="m-say">${line}</div></div>
      <div class="p-list">${sessions.map(card).join('')}</div>`;
      setHatch($('m-hatch'), mood, agent);
      size();
    }
    function phonePage(paired) {
      page.innerHTML = `<div class="p-stage"><div style="width:50px;height:50px;position:relative;flex-shrink:0;margin:0 6px"><div id="m-hatch" style="position:absolute;left:-12px;top:-19px;width:74px;height:74px"></div></div><div class="say" id="m-say">Point your phone's camera here. I'll take it from there.</div></div>
      <div class="p-page"><div style="display:flex;gap:18px;margin-top:6px">
        <div class="qr-box"><svg viewBox="0 0 33 33" shape-rendering="crispEdges"><path d="${QR}" fill="#0b0b0c"/></svg></div>
        <div style="display:flex;flex-direction:column;gap:6px;padding-top:2px">
          <span style="font-size:11px;color:rgba(255,255,255,.45)">Code</span>
          <span style="font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:24px;font-weight:600;letter-spacing:1px">K7Q2 M9XA</span>
          <span id="m-left" style="font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;color:rgba(255,255,255,.45)">good for 4:59</span>
          <span style="margin-top:6px;font-size:12px;line-height:17px;color:rgba(255,255,255,.55);max-width:300px">On your phone, open Hatchling and point the camera at the QR. If the camera won't cooperate, type the code.</span>
        </div></div>
        <div id="m-paired"></div></div>`;
      setHatch($('m-hatch'), 'waving', 'claude');
      size();
    }
    function size() { notch.style.setProperty('--panel-h', $('m-open').scrollHeight + 'px'); }
    function open(on) { notch.classList.toggle('open', on); if (on) size(); }
    function point(el, ox, oy) {
      if (!el) return;
      const p = where(root, el, stage, W, ox, oy);
      cursor.style.transform = `translate(${p.x - 4}px,${p.y - 2}px)`;
    }
    function click(el) {
      cursor.classList.remove('clicking'); void cursor.offsetWidth; cursor.classList.add('clicking');
      if (el) { el.classList.add('press'); setTimeout(() => el.classList.remove('press'), 140); }
    }
    function cursorAt(x, y) { cursor.style.transition = 'none'; cursor.style.transform = `translate(${x}px,${y}px)`; void cursor.offsetWidth; cursor.style.transition = ''; }
    function closed(active, total, mood = 'working') {
      setHatch($('m-mini'), mood, 'claude');
      $('m-count').innerHTML = active ? `<span class="a">${active}</span><span class="s">/</span>${total}` : `${total}`;
    }
    const byId = (id) => root.querySelector(`[data-id="${id}"]`);
    const set = (id, patch) => { Object.assign(sessions.find((s) => s.id === id), patch); };

    const scenes = [
      { label: 'Live status', dur: 7600, setup() {
          sessions = fresh(); open(false); closed(2, 3); cursorAt(900, 470);
        }, steps: [
          [900, () => point(notch, .5, .6)],
          [1900, () => { listPage('working', '2 sessions working right now.'); open(true); }],
          [4200, () => { set('a', { now: 'Running npm run test', ago: 'now' }); listPage('working', 'recipes-api: running npm run test.'); }],
          [5800, () => point(byId('c'), .6, .5)],
        ] },
      { label: 'Approve in place', dur: 7600, setup() {
          sessions = fresh(); open(true); set('a', { status: 'approval' });
          listPage('approval', 'recipes-api wants to run npm run test. Take a look?'); cursorAt(980, 520);
        }, steps: [
          [1400, () => point(root.querySelector('[data-allow]'))],
          [2600, () => click(root.querySelector('[data-allow]'))],
          [3000, () => { set('a', { status: 'working', now: 'Running npm run test' }); listPage('happy', 'Allowed. The tests are running.'); setHatch($('m-hatch'), 'happy', 'claude', true); }],
          [5400, () => listPage('working', '2 sessions working right now.')],
        ] },
      { label: 'Answer questions', dur: 7600, setup() {
          sessions = fresh(); open(true); set('c', { status: 'question' });
          listPage('question', 'budget-app has a question for you.'); cursorAt(980, 300);
        }, steps: [
          [1500, () => point(root.querySelector('[data-opt]'), .3, .5)],
          [2700, () => { const o = root.querySelector('[data-opt]'); click(o); o.classList.add('pick'); }],
          [3300, () => { set('c', { status: 'working', now: 'Building the bar chart', ago: 'now' }); listPage('working', 'budget-app is on it.'); }],
        ] },
      { label: 'Pair your phone', dur: 8200, setup() {
          sessions = fresh(); open(true); listPage('working', '2 sessions working right now.'); $('m-phone').classList.remove('on'); $('m-phone').innerHTML = icon('phone'); cursorAt(860, 330);
        }, steps: [
          [800, () => point($('m-phone'))],
          [1800, () => { click($('m-phone')); $('m-phone').classList.add('on'); phonePage(); }],
          [3000, () => { const l = $('m-left'); if (l) l.textContent = 'good for 4:57'; }],
          [4100, () => { const l = $('m-left'); if (l) l.textContent = 'good for 4:56'; }],
          [5000, () => {
            say($('m-say'), "Paired. Mikael's iPhone is with me now.");
            setHatch($('m-hatch'), 'cheering', 'claude', true);
            $('m-phone').insertAdjacentHTML('beforeend', '<span class="live"></span>');
            $('m-paired').innerHTML = `<div style="height:1px;background:rgba(255,255,255,.06);margin:16px 0 12px"></div><div style="font-size:11px;color:rgba(255,255,255,.45);margin-bottom:8px">Paired phones</div>
              <div style="display:flex;align-items:center;gap:10px;padding:10px 12px;border-radius:14px;background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.06)"><span style="width:7px;height:7px;border-radius:50%;background:#5fcf6b"></span><b style="font-size:13px">Mikael's iPhone</b><span style="font-size:12px;color:rgba(255,255,255,.45)">connected now</span><span style="margin-left:auto;font-size:12px;font-weight:600;color:#ff8a8a">Disconnect</span></div>`;
            size();
          }],
        ] },
      { label: 'Out of your way', dur: 6800, setup() {
          sessions = fresh(); open(true); listPage('working', '2 sessions working right now.'); cursorAt(700, 400);
        }, steps: [
          [700, () => point($('m-collapse'))],
          [1600, () => { click($('m-collapse')); open(false); closed(2, 3); }],
          [2500, () => { cursor.style.transform = 'translate(860px,420px)'; }],
          [3900, () => { closed(1, 3, 'happy'); setHatch($('m-mini'), 'happy', 'claude', true); }],
          [5600, () => closed(1, 3, 'working')],
        ] },
    ];
    const chips = document.getElementById('sim-mac-scenes');
    director(scenes, chips, stage);
  }

  function icon(name) {
    const P = {
      stack: '<svg width="11" height="11" viewBox="0 0 16 16" fill="currentColor"><rect x="1.5" y="6" width="13" height="8.5" rx="2"/><rect x="3.2" y="3.4" width="9.6" height="1.5" rx=".7"/><rect x="4.8" y="1.2" width="6.4" height="1.3" rx=".6"/></svg>',
      tray: '<svg width="11" height="11" viewBox="0 0 16 16" fill="currentColor"><path d="M1.2 9.2 3.4 3.4Q3.7 2.6 4.6 2.6H11.4Q12.3 2.6 12.6 3.4L14.8 9.2V12.6Q14.8 14.4 13 14.4H3Q1.2 14.4 1.2 12.6ZM3.2 9H5.6Q6 10.8 8 10.8 10 10.8 10.4 9H12.8L11.2 4.4H4.8Z" fill-rule="evenodd"/></svg>',
      note: '<svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="1.8" y="2.6" width="12.4" height="10.8" rx="2"/><path d="M4.6 6.4H11.4M4.6 9.4H9"/></svg>',
      phone: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"><rect x="4.4" y="1.4" width="7.2" height="13.2" rx="2"/><path d="M7 12.2H9"/></svg>',
      chev: '<svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10.5 8 5.5 13 10.5"/></svg>',
      sound: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" stroke-linecap="round"><path d="M2 6H4.6L8 3V13L4.6 10H2Z"/><path d="M10.4 6Q11.6 8 10.4 10"/><path d="M12.4 4.4Q14.6 8 12.4 11.6"/></svg>',
      gear: '<svg width="12" height="12" viewBox="-8 -8 16 16" fill="none" stroke="currentColor"><circle r="5.4" stroke-width="2.4" stroke-dasharray="2.1 1.62"/><circle r="3.9" stroke-width="1.3"/><circle r="1.6" stroke-width="1.2"/></svg>',
      power: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M5 4.2A5.4 5.4 0 1 0 11 4.2"/><path d="M8 1.8V7.6"/></svg>',
    };
    return P[name] || '';
  }

  // ================================================================= iPhone
  // The app as approved on the mobile canvas: Hatch in the middle of every screen, talking
  // through a bubble, with what you can do about it at the bottom.
  function phone() {
    const stage = document.getElementById('sim-phone');
    if (!stage) return;
    const W = 390;
    const AGENT = { claude: C.claude, codex: C.codex };
    const miniRing = (pct, color) => {
      const c = 2 * Math.PI * 7;
      return `<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="7" fill="none" stroke="${color}" stroke-opacity=".2" stroke-width="2.4"/><circle cx="9" cy="9" r="7" fill="none" stroke="${color}" stroke-width="2.4" stroke-linecap="round" stroke-dasharray="${c * pct / 100} ${c}" transform="rotate(-90 9 9)"/></svg>`;
    };
    const stageHtml = (id, hatchSize) => `<div class="ps-stage" id="${id}">
      <div class="ps-bub" id="${id}-bub"></div>
      <span class="ps-dot big"></span><span class="ps-dot small"></span>
      <div class="ps-hatch" id="${id}-h" style="width:${hatchSize}px;height:${hatchSize}px"></div>
      <span class="ps-floor" style="width:${Math.round(hatchSize * .58)}px;margin-top:-${Math.round(hatchSize * .1)}px"></span>
      <div class="ps-below" id="${id}-below"></div>
    </div>`;
    stage.innerHTML = `<div class="sim-scaler"><div class="ph">
  <div class="ph-status"><span>9:41</span><span style="display:flex;gap:6px;align-items:center"><svg width="18" height="12" viewBox="0 0 18 12" fill="#fff"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg><svg width="26" height="12" viewBox="0 0 26 12"><rect x=".5" y=".5" width="22" height="11" rx="3.5" fill="none" stroke="rgba(255,255,255,.5)"/><rect x="2" y="2" width="19" height="8" rx="2" fill="#fff"/><rect x="24" y="4" width="1.5" height="4" rx=".7" fill="rgba(255,255,255,.5)"/></svg></span></div>
  <div class="ph-island"></div>
  <div class="ph-screen" id="p-home">
    <div class="ps-top"><span class="adot" style="background:${C.working};color:${C.working}"></span><b>Mac connected</b><span style="flex:1"></span>${miniRing(38, C.claudeUse)}<span class="mono">38%</span></div>
    ${stageHtml('p-hs', 200)}
    <div class="ps-list"><div class="ps-label"><span>Sessions</span><span class="mono">4</span></div><div class="ps-card" id="p-list"></div></div>
  </div>
  <div class="ph-screen off-down" id="p-att"></div>
  <div class="ph-screen off-right" id="p-sess"></div>
  <div class="ps-done gone" id="p-done"></div>
  <div class="splash gone" id="p-splash"><div class="ps-splash-h" id="p-splash-h"></div><span class="ps-floor" id="p-splash-f" style="width:110px;margin-top:-19px"></span></div>
  <div class="touch" id="p-touch"></div>
</div></div>`;
    const scaler = stage.firstElementChild, root = scaler.firstElementChild;
    fit(stage, scaler, W);
    const $ = (id) => root.querySelector('#' + id);
    let sessions;
    const fresh = () => ([
      { id: 'a', project: 'recipes-api', tag: '#3b1c', agent: 'claude', status: 'working', model: 'opus-5-5', pct: 41, now: 'Running the tests', ask: 'Search recipes by ingredient', mins: 12 },
      { id: 'b', project: 'landing-page', tag: '#c41d', agent: 'codex', status: 'working', model: 'gpt-5.5', pct: 22, now: 'Running pnpm build', ask: 'Ship the new home page', mins: 6 },
      { id: 'c', project: 'budget-app', tag: '#7f2a', agent: 'claude', status: 'done', model: 'sonnet-5-5', pct: 64, now: 'Done: 128 tests passing.', ask: 'run the tests', mins: 31 },
      { id: 'd', project: 'design-system', tag: '#a07e', agent: 'claude', status: 'idle', model: 'sonnet-5-5', pct: 88, now: 'The colour tokens now have a dark variant.', ask: 'make the dark theme', mins: 64 },
    ]);
    const STATUS = {
      working: ['working', C.working], approval: ['needs your OK', C.waiting], question: ['has a question', C.waiting],
      done: ['done', 'rgba(255,255,255,.7)'], idle: ['idle', 'rgba(255,255,255,.4)'],
    };
    function row(s) {
      const [label, color] = STATUS[s.status];
      const busy = s.status === 'working';
      const line = s.status === 'approval' || s.status === 'question' ? 'Waiting for your answer' : s.now;
      return `<div class="ps-row" data-id="${s.id}"><span class="adot${busy ? ' pulse' : ''}" style="background:${AGENT[s.agent]};color:${AGENT[s.agent]};opacity:${s.status === 'idle' ? .4 : 1}"></span>
        <span class="ps-row-t"><b>${s.project}</b><small>${line}</small></span><span class="ps-state" style="color:${color}">${label}</span></div>`;
    }
    const list = () => { $('p-list').innerHTML = sessions.map(row).join(''); };
    const set = (id, patch) => Object.assign(sessions.find((s) => s.id === id), patch);
    const bubble = (id, html) => {
      const el = $(id + '-bub');
      if (reduce) { el.innerHTML = html; return; }
      el.classList.add('swap');
      setTimeout(() => { el.innerHTML = html; el.classList.remove('swap'); }, 160);
    };
    const sayHtml = (main, quiet) => `<p class="ps-say">${main}${quiet ? ` <span>${quiet}</span>` : ''}</p>`;
    function touch(el, ox = .5, oy = .5) {
      if (!el) return;
      const p = where(root, el, stage, W, ox, oy), t = $('p-touch');
      t.style.left = p.x + 'px'; t.style.top = p.y + 'px';
      t.classList.remove('go'); void t.offsetWidth; t.classList.add('go');
    }
    const show = (id, cls, on) => $(id).classList.toggle(cls, !on);
    function home(mood = 'working', main = 'recipes-api: running the tests.', quiet = 'budget-app just finished.') {
      sessions = sessions || fresh();
      list(); setHatch($('p-hs-h'), mood, 'claude'); $('p-hs-bub').innerHTML = sayHtml(main, quiet);
      show('p-att', 'off-down', false); show('p-sess', 'off-right', false); $('p-home').classList.remove('off-left');
      $('p-splash').classList.add('gone'); $('p-done').classList.add('gone');
    }
    const subject = (s, label, color, back) => `<div class="ps-top">${back ? `<div class="back" id="p-back"><svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.5 3 5.5 8l5 5"/></svg></div>` : ''}
      <span class="adot${s.status === 'working' ? ' pulse' : ''}" style="background:${AGENT[s.agent]};color:${AGENT[s.agent]}"></span><b>${s.project}</b><span class="mono dim">${s.tag}</span><span style="flex:1"></span><span class="ps-state" style="color:${color}">${label}</span></div>`;
    function approvalScreen() {
      const s = sessions.find((x) => x.id === 'a');
      $('p-att').innerHTML = subject(s, 'needs your OK', C.waiting) + stageHtml('p-as', 170) +
        `<div class="ps-btns"><span class="ps-btn neg">Deny</span><span class="ps-btn wide">Always this session</span><span class="ps-btn pri" id="p-allow">Allow</span></div>`;
      $('p-as-bub').innerHTML = `${sayHtml('Can I let it run this?')}<div class="ps-code"><i>$ </i>npm run test -- --coverage</div><p class="ps-detail">To run the test suite before deploying.</p>`;
      setHatch($('p-as-h'), 'approval', 'claude');
    }
    function questionScreen() {
      const s = sessions.find((x) => x.id === 'b');
      $('p-att').innerHTML = subject(s, 'has a question', C.waiting) + stageHtml('p-qs', 150) +
        `<div class="ps-bottom"><div class="ps-card">
          <div class="ps-row opt"><span class="n">1</span><span class="ps-row-t"><b>Vercel</b><small>Previews for every branch</small></span></div>
          <div class="ps-row opt" id="p-opt"><span class="n">2</span><span class="ps-row-t"><b>Netlify</b><small>Where the old site lives</small></span></div>
          <div class="ps-row opt"><span class="n">3</span><span class="ps-row-t"><b>Cloudflare Pages</b><small>Same place as the DNS</small></span></div>
        </div><div class="ps-btns static"><span class="ps-btn">Skip</span><span class="ps-btn wide2">Answer something else</span></div></div>`;
      $('p-qs-bub').innerHTML = sayHtml('Where should I deploy the new home?');
      setHatch($('p-qs-h'), 'question', 'codex');
    }
    function sessionScreen() {
      const s = sessions.find((x) => x.id === 'c');
      $('p-sess').innerHTML = subject(s, 'done', 'rgba(255,255,255,.7)', true) + stageHtml('p-ss', 170) +
        `<div class="ps-bottom"><div class="ps-note"><span id="p-note">Send the session a note</span><i id="p-send"><svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 13V3M3.5 7.5 8 3l4.5 4.5"/></svg></i></div></div>`;
      $('p-ss-bub').innerHTML = `${sayHtml('Done: 128 tests passing.')}<p class="ps-detail">You asked: run the tests.</p>`;
      $('p-ss-below').innerHTML = `<div class="ps-meta"><span>sonnet-5-5</span><i></i><span class="ps-bar"><b style="width:64%;background:${C.ctxMid}"></b></span><span style="color:${C.ctxMid}">64%</span><i></i><span>31 min</span></div>`;
      setHatch($('p-ss-h'), 'happy', 'claude');
    }
    function doneScreen() {
      $('p-done').innerHTML = `<div class="ps-top"><span class="dim">Session finished</span><span style="flex:1"></span><span class="back"><svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M1.5 1.5 10.5 10.5M10.5 1.5 1.5 10.5"/></svg></span></div>
        <div class="ps-cele"><span class="ps-ring"></span><span class="ps-ring r2"></span><div class="ps-drop"><div class="ps-hops" id="p-done-h"></div></div></div>
        <div class="ps-reveal"><h3>recipes-api</h3><div class="mono dim c">#3b1c · 12 min · opus-5-5</div>
          <div class="ps-card pad"><small>What got done</small><p>All 212 tests pass and coverage is at 87%. Ready for the deploy.</p></div>
          <span class="ps-btn pri full">Open session</span><div class="ps-timer"><b></b></div><div class="dim c" style="font-size:12px">Tap anywhere to close</div></div>`;
      setHatch($('p-done-h'), 'surprised', 'claude');
      const d = $('p-done'); d.classList.remove('gone', 'play'); void d.offsetWidth; d.classList.add('play');
    }
    const scenes = [
      { label: 'Hatch says hi', dur: 3400, setup() {
          sessions = fresh(); home();
          const s = $('p-splash'), h = $('p-splash-h');
          s.classList.remove('gone', 'land', 'wave', 'hop'); setHatch(h, 'surprised', 'claude');
          void s.offsetWidth; requestAnimationFrame(() => s.classList.add('land'));
        }, steps: [
          [650, () => { setHatch($('p-splash-h'), 'waving', 'claude'); $('p-splash').classList.add('wave'); }],
          [1450, () => { setHatch($('p-splash-h'), 'cheering', 'claude'); $('p-splash').classList.add('hop'); }],
          [2050, () => setHatch($('p-splash-h'), 'happy', 'claude')],
          [2750, () => $('p-splash').classList.add('gone')],
        ] },
      { label: 'Poke Hatch', dur: 7000, setup() { sessions = fresh(); home(); }, steps: [
          [900, () => { touch($('p-hs-h'), .5, .55); setHatch($('p-hs-h'), 'happy', 'claude', true); bubble('p-hs', sayHtml('Hey, that tickles.')); }],
          [3600, () => { touch($('p-hs-h'), .5, .55); setHatch($('p-hs-h'), 'wink', 'claude', true); bubble('p-hs', sayHtml('Watching your 4 sessions.', '2 working.')); }],
        ] },
      { label: 'Approve', dur: 7600, setup() { sessions = fresh(); home(); }, steps: [
          [500, () => { set('a', { status: 'approval' }); list(); setHatch($('p-hs-h'), 'approval', 'claude'); bubble('p-hs', sayHtml('recipes-api needs your OK.')); }],
          [1900, () => { approvalScreen(); show('p-att', 'off-down', true); }],
          [4600, () => touch($('p-allow'))],
          [5000, () => { show('p-att', 'off-down', false); set('a', { status: 'working', now: 'Running npm run test' }); list(); setHatch($('p-hs-h'), 'happy', 'claude', true); bubble('p-hs', sayHtml('Allowed. The tests are running.')); }],
        ] },
      { label: 'Answer', dur: 7400, setup() { sessions = fresh(); home(); }, steps: [
          [500, () => { set('b', { status: 'question' }); list(); setHatch($('p-hs-h'), 'question', 'codex'); bubble('p-hs', sayHtml('landing-page has a question for you.')); }],
          [1800, () => { questionScreen(); show('p-att', 'off-down', true); }],
          [4400, () => { const o = $('p-opt'); touch(o); o.classList.add('press'); }],
          [4800, () => { show('p-att', 'off-down', false); set('b', { status: 'working', now: 'Deploying to Netlify' }); list(); setHatch($('p-hs-h'), 'working', 'codex', true); bubble('p-hs', sayHtml('Answered. landing-page is back at it.')); }],
        ] },
      { label: 'Session done', dur: 7000, setup() { sessions = fresh(); home(); }, steps: [
          [700, () => doneScreen()],
          [1250, () => setHatch($('p-done-h'), 'cheering', 'claude')],
          [2000, () => setHatch($('p-done-h'), 'happy', 'claude')],
          [6600, () => { $('p-done').classList.add('gone'); set('a', { status: 'done', now: 'All 212 tests pass.' }); list(); setHatch($('p-hs-h'), 'happy', 'claude'); $('p-hs-bub').innerHTML = sayHtml('recipes-api is done.', 'landing-page is still building.'); }],
        ] },
      { label: 'Open a session', dur: 7600, setup() { sessions = fresh(); home(); }, steps: [
          [800, () => { const r = $('p-list').querySelector('[data-id="c"]'); touch(r); r.classList.add('press'); }],
          [1200, () => { sessionScreen(); $('p-home').classList.add('off-left'); show('p-sess', 'off-right', true); }],
          [3000, () => { const n = $('p-note'); n.textContent = 'now ship it to TestFlight'; n.classList.add('typed'); $('p-send').classList.add('ready'); }],
          [4300, () => { touch($('p-send')); }],
          [4600, () => { const n = $('p-note'); n.textContent = 'Send the session a note'; n.classList.remove('typed'); $('p-send').classList.remove('ready'); setHatch($('p-ss-h'), 'working', 'claude', true); bubble('p-ss', `${sayHtml('On it: shipping to TestFlight.')}<p class="ps-detail">You asked: now ship it to TestFlight.</p>`); }],
          [6600, () => touch($('p-back'))],
          [6900, () => { show('p-sess', 'off-right', false); $('p-home').classList.remove('off-left'); }],
        ] },
    ];
    director(scenes, document.getElementById('sim-phone-scenes'), stage);
  }

  window.HatchArt = { hatch, setHatch };

  mac();
  phone();
})();
