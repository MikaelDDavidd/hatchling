// O Hatch que acompanha a rolagem. Cada seção tem um "poleiro": um espaço vazio no layout,
// com humor e fala. Ele fica sentado no poleiro da seção que está na tela e, quando a
// próxima chega, pula até ela: agacha, salta num arco, estica no ar e amassa ao pousar.
// O pulo tem tempo próprio, não depende da velocidade da rolagem. Os olhos seguem o mouse
// e um clique faz ele pular no lugar e falar.
(() => {
  const art = window.HatchArt;
  const perches = [...document.querySelectorAll('.perch')];
  if (!art || !perches.length) return;

  const buddy = document.createElement('div');
  buddy.className = 'buddy';
  buddy.innerHTML = '<div class="buddy-shadow"></div><div class="buddy-body"></div><div class="buddy-say" role="status" aria-live="polite"></div>'
    + '<div class="buddy-think" aria-hidden="true"><span class="t-dot t1"></span><span class="t-dot t2"></span><span class="t-box">click!</span></div>';
  document.body.appendChild(buddy);
  const body = buddy.querySelector('.buddy-body');
  const shadow = buddy.querySelector('.buddy-shadow');
  const bubble = buddy.querySelector('.buddy-say');

  let mood = '', sayTimer = 0;
  function setMood(next, hop) {
    if (next === mood) return;
    mood = next;
    art.setHatch(body, next, 'claude', hop);
  }
  function speak(text) {
    if (!text) return;
    bubble.textContent = text;
    buddy.classList.add('talking');
    clearTimeout(sayTimer);
    sayTimer = setTimeout(() => buddy.classList.remove('talking'), 3000);
  }

  const lerp = (a, b, t) => a + (b - a) * t;
  const easeInOut = (t) => t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

  // Where a perch is right now. Hatch sits on it and scrolls away with it, like anything
  // else on the page; it never hangs on the screen over other content.
  function spot(i) {
    const r = perches[i].getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, size: r.width };
  }
  function activeIndex() {
    // At the very top Hatch stays in the hero, even if the next perch is already in view.
    if (scrollY < 40) return 0;
    let k = 0;
    perches.forEach((p, i) => { if (p.getBoundingClientRect().top + p.offsetHeight / 2 <= innerHeight * 0.86) k = i; });
    return k;
  }

  let station = activeIndex();
  let pos = spot(station);
  let jump = null; // { from, to, start, dur }

  function place(x, y, size, sx = 1, sy = 1, rot = 0, lift = 0) {
    buddy.style.setProperty('--s', size + 'px');
    buddy.style.transform = `translate(${x - size / 2}px, ${y - size / 2}px)`;
    body.style.transform = `rotate(${rot}deg) scale(${sx}, ${sy})`;
    // The shadow stays on the ground and shrinks as Hatch goes up.
    shadow.style.transform = `translateY(${lift}px) scale(${Math.max(.35, 1 - lift / 260)})`;
    shadow.style.opacity = String(Math.max(.15, .55 - lift / 400));
    buddy.classList.toggle('left-say', x > innerWidth * 0.62);
  }

  const setIdle = (on) => buddy.classList.toggle('idle', on);

  function startJump(to) {
    setIdle(false);
    const from = { ...pos };
    const dist = Math.hypot(spot(to).x - from.x, spot(to).y - from.y);
    const end = spot(to);
    // High enough to read as a jump, never so high that Hatch leaves the top of the screen.
    // Coming from a perch that already left the screen, start just above the top edge, so
    // Hatch drops in instead of crossing the whole page.
    if (from.y < -from.size) { from.y = -from.size; from.x = end.x + (from.x > end.x ? 80 : -80); }
    if (from.y > innerHeight + from.size) { from.y = innerHeight + from.size; from.x = end.x + (from.x > end.x ? 80 : -80); }
    const room = Math.min(from.y - from.size / 2, end.y - end.size / 2) - 16;
    const height = Math.max(40, Math.min(240, 90 + dist * 0.3, room));
    jump = { to, from, start: performance.now(), dur: Math.min(680, 420 + dist * 0.22), height };
    buddy.classList.remove('talking');
    setMood('jump', false);
    loop();
  }

  function frame(now) {
    const want = activeIndex();
    if (!jump && want !== station) { station = want; startJump(want); }
    if (jump) {
      // A short crouch, the flight, then a squash on landing.
      const crouch = 70, land = 140;
      const total = crouch + jump.dur + land;
      const t = (now - jump.start);
      const w = activeIndex();
      if (w !== jump.to) jump.to = station = w; // the reader scrolled on while Hatch was in the air
      const target = spot(jump.to);
      if (t < crouch) {
        const c = Math.sin((t / crouch) * Math.PI / 2);
        place(jump.from.x, jump.from.y + c * jump.from.size * 0.06, jump.from.size, 1 + c * .12, 1 - c * .16, 0, -c * jump.from.size * 0.06);
      } else if (t < crouch + jump.dur) {
        const p = easeInOut((t - crouch) / jump.dur);
        const x = lerp(jump.from.x, target.x, p);
        const ground = lerp(jump.from.y, target.y, p);
        const lift = Math.sin(Math.PI * p) * jump.height;
        const size = lerp(jump.from.size, target.size, p);
        const stretch = Math.sin(Math.PI * p);
        const dir = target.x >= jump.from.x ? 1 : -1;
        place(x, ground - lift, size, 1 - stretch * .08, 1 + stretch * .1, dir * (p < .5 ? 14 * p * 2 : 14 * (1 - p) * 2) * (target.x === jump.from.x ? 0 : 1), lift);
        pos = { x, y: ground, size };
      } else if (t < total) {
        const q = (t - crouch - jump.dur) / land;
        const squash = Math.sin(q * Math.PI) * (1 - q);
        place(target.x, target.y + squash * target.size * .05, target.size, 1 + squash * .18, 1 - squash * .2, 0, 0);
        pos = target;
        if (mood === 'jump') setMood(perches[jump.to].dataset.mood || 'idle', false);
      } else {
        pos = target;
        place(target.x, target.y, target.size);
        setMood(perches[jump.to].dataset.mood || 'idle', false);
        speak(perches[jump.to].dataset.say);
        jump = null;
        setIdle(true);
        const again = activeIndex();
        if (again !== station) { station = again; startJump(again); }
      }
      return true;
    }
    pos = spot(station);
    place(pos.x, pos.y, pos.size);
    setIdle(true);
    return false;
  }

  // One frame chain at a time. A chain that stopped getting frames (a hidden tab pauses
  // them) does not block a new one.
  let looping = false, lastTick = 0;
  function loop() {
    if (looping && performance.now() - lastTick < 250) return;
    looping = true;
    lastTick = performance.now();
    const tick = (now) => {
      lastTick = performance.now();
      if (frame(now)) requestAnimationFrame(tick);
      else looping = false;
    };
    requestAnimationFrame(tick);
  }
  addEventListener('scroll', loop, { passive: true });
  addEventListener('resize', loop);
  setMood(perches[station].dataset.mood || 'idle', false);
  place(pos.x, pos.y, pos.size);
  buddy.classList.add('idle');
  setTimeout(() => speak(perches[station].dataset.say), 900);

  // Eyes follow the pointer. When it rests, Hatch looks around by itself.
  let lastPointer = 0;
  const lookAt = (x, y) => body.querySelectorAll('.look').forEach((g) => { g.style.transform = `translate(${x}px, ${y}px)`; });
  addEventListener('pointermove', (e) => {
    lastPointer = performance.now();
    const r = body.getBoundingClientRect();
    const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
    const d = Math.hypot(dx, dy) || 1, m = Math.min(1, d / 260) * 3.2;
    lookAt(dx / d * m, dy / d * m);
  }, { passive: true });

  // Little things while it sits: a glance, a blink-and-smile, a small hop.
  function fidget() {
    setTimeout(fidget, 2200 + Math.random() * 2600);
    if (jump || document.hidden || !buddy.classList.contains('idle')) return;
    const r = body.getBoundingClientRect();
    if (r.bottom < 0 || r.top > innerHeight) return;
    if (performance.now() - lastPointer > 2500) {
      const a = Math.random() * Math.PI * 2, m = 1.5 + Math.random() * 1.8;
      lookAt(Math.cos(a) * m, Math.sin(a) * m * .7);
    }
    const roll = Math.random();
    if (roll < 0.18) {
      const back = perches[station].dataset.mood || 'idle';
      mood = '';
      art.setHatch(body, Math.random() < .6 ? 'wink' : 'surprised', 'claude', false);
      setTimeout(() => { mood = ''; setMood(back, false); }, 900);
    } else if (roll < 0.3) {
      body.classList.remove('hop'); void body.offsetWidth; body.classList.add('hop');
    }
  }
  setTimeout(fidget, 2500);

  // Every click on the page: Hatch blinks and thinks "click!".
  const think = buddy.querySelector('.buddy-think');
  let thinkTimer = 0;
  addEventListener('click', (e) => {
    if (buddy.contains(e.target) || jump) return;
    const r = body.getBoundingClientRect();
    if (r.bottom < 0 || r.top > innerHeight) return;
    body.classList.remove('blinknow'); void body.offsetWidth; body.classList.add('blinknow');
    setTimeout(() => body.classList.remove('blinknow'), 300);
    buddy.classList.remove('talking');
    think.classList.remove('on'); void think.offsetWidth; think.classList.add('on');
    clearTimeout(thinkTimer);
    thinkTimer = setTimeout(() => think.classList.remove('on'), 1300);
  }, { capture: true, passive: true });

  // Poke it: a little hop in place and a line.
  const pokes = ['Hey, that tickles.', "I'm watching your agents.", "Poking me won't make the build faster.", 'Still here.'];
  let n = 0;
  buddy.addEventListener('click', () => {
    if (jump) return;
    const back = mood;
    mood = '';
    art.setHatch(body, n % 2 ? 'wink' : 'excited', 'claude', true);
    speak(pokes[n++ % pokes.length]);
    setTimeout(() => { mood = ''; setMood(perches[station].dataset.mood || back || 'idle', false); }, 1400);
  });
})();
