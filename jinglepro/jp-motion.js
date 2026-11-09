/* ═══════════════════════════════════════════════════════════════
   JinglePro — motion & interaction layer
   Router (sidebar) · Lenis smooth scroll · GSAP reveals/counters ·
   wizard selections · voice player · lyric regen · audio players.
   ═══════════════════════════════════════════════════════════════ */
(function () {
  const $  = (s, c = document) => c.querySelector(s);
  const $$ = (s, c = document) => Array.from(c.querySelectorAll(s));
  const hasGSAP = typeof window.gsap !== 'undefined';

  /* ─── Lenis smooth scroll (disabled: conflicts with show/hide SPA router) ─
     Native smooth scroll + GSAP transitions provide the fluid feel instead. */
  let lenis = null;
  function initLenis() { /* intentionally disabled */ }

  /* ─── Reveal on enter (IntersectionObserver) ────────────────── */
  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add('seen'); io.unobserve(e.target); }
    });
  }, { threshold: 0.12, root: $('.scroller') });

  function observeReveals(scope) {
    $$('.reveal', scope).forEach((el, i) => {
      if (!el.classList.contains('seen')) {
        el.style.transitionDelay = ((i % 9) * 55) + 'ms';
        io.observe(el);
      }
    });
  }

  /* ─── Count-up stats ────────────────────────────────────────── */
  function runCounters(scope) {
    $$('[data-count]', scope).forEach((el) => {
      if (el.dataset.done) return;
      el.dataset.done = '1';
      const target = parseFloat(el.dataset.count);
      const dec = (el.dataset.count.indexOf('.') >= 0) ? 1 : 0;
      const suffix = el.dataset.suffix || '';
      const prefix = el.dataset.prefix || '';
      const dur = 1400; const start = performance.now();
      function tick(now) {
        const p = Math.min((now - start) / dur, 1);
        const eased = 1 - Math.pow(1 - p, 3);
        const val = (target * eased).toFixed(dec);
        el.textContent = prefix + (dec ? val : Math.round(val).toLocaleString('it-IT')) + suffix;
        if (p < 1) requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
    });
  }

  /* ─── Router ────────────────────────────────────────────────── */
  const scroller = $('.scroller');
  function go(id, push = true) {
    const target = document.getElementById(id);
    if (!target) return;
    const current = $('.page.on');
    if (current === target) { closeMobileNav(); return; }

    // sidebar active state
    $$('.nav-link').forEach((l) => l.classList.toggle('active', l.dataset.go === id));

    // hero pause/resume
    if (window.__heroSetRunning) window.__heroSetRunning(id === 'home');

    const swap = () => {
      if (current) current.classList.remove('on');
      target.classList.add('on');
      if (scroller) scroller.scrollTop = 0;
      if (lenis) try { lenis.scrollTo(0, { immediate: true }); } catch (e) {}
      // re-arm reveals, then let IntersectionObserver fade them in (CSS transition)
      $$('.reveal', target).forEach((el) => el.classList.remove('seen'));
      observeReveals(target);
      runCounters(target);
      // FAILSAFE: content must never stay invisible if observers/rAF don't fire
      clearTimeout(window.__revealFailsafe);
      window.__revealFailsafe = setTimeout(() => {
        $$('.reveal', target).forEach((el) => el.classList.add('seen'));
      }, 750);
    };

    swap();
    if (push) history.replaceState(null, '', '#' + id);
    closeMobileNav();
  }
  window.jpGo = go;

  /* ─── Mobile nav toggle ─────────────────────────────────────── */
  function openMobileNav() { $('.sidebar')?.classList.add('open'); $('.backdrop')?.classList.add('show'); }
  function closeMobileNav() { $('.sidebar')?.classList.remove('open'); $('.backdrop')?.classList.remove('show'); }

  /* ─── Voice card play toggle + pro hint ─────────────────────── */
  function wireVoices(scope) {
    $$('.voice', scope).forEach((card) => {
      const play = $('.play', card);
      play?.addEventListener('click', (e) => {
        e.stopPropagation();
        const wasPlaying = card.classList.contains('playing');
        $$('.voice.playing', scope).forEach((v) => { v.classList.remove('playing'); setPlayIcon(v, false); });
        if (!wasPlaying) { card.classList.add('playing'); setPlayIcon(card, true); }
      });
      card.addEventListener('click', () => {
        $$('.voice', scope).forEach((v) => v.classList.remove('sel'));
        card.classList.add('sel');
        const hint = $('#voicehint');
        if (hint) hint.classList.toggle('show', card.dataset.pro === '1');
      });
    });
  }
  function setPlayIcon(card, playing) {
    const play = $('.play', card);
    if (!play) return;
    play.innerHTML = playing
      ? '<svg width="12" height="12" viewBox="0 0 10 10"><rect x="1" y="1" width="3" height="8" rx=".5" fill="currentColor"/><rect x="6" y="1" width="3" height="8" rx=".5" fill="currentColor"/></svg>'
      : '<svg width="11" height="13" viewBox="0 0 8 10" style="margin-left:1px"><path d="M0.5 0.7v8.6L7.5 5 0.5 0.7z" fill="currentColor"/></svg>';
  }

  /* ─── Pill group selection ──────────────────────────────────── */
  function wirePills(scope) {
    $$('[data-pillgroup]', scope).forEach((group) => {
      const multi = group.dataset.multi === '1';
      $$('.pill', group).forEach((pill) => {
        pill.addEventListener('click', () => {
          if (multi) { pill.classList.toggle('on'); }
          else { $$('.pill', group).forEach((p) => p.classList.remove('on')); pill.classList.add('on'); }
        });
      });
    });
    $$('.langrow', scope).forEach((group) => {
      $$('.lang', group).forEach((l) => {
        l.addEventListener('click', () => { $$('.lang', group).forEach((x) => x.classList.remove('on')); l.classList.add('on'); });
      });
    });
  }

  /* ─── Tier selection (wizard step 5) ────────────────────────── */
  function wireTiers(scope) {
    const cta = $('#finalize-cta');
    $$('.tier.selectable', scope).forEach((tier) => {
      tier.addEventListener('click', () => {
        $$('.tier.selectable', scope).forEach((t) => t.classList.remove('sel'));
        tier.classList.add('sel');
        if (cta) { cta.classList.remove('disabled'); cta.removeAttribute('disabled'); }
      });
    });
  }

  /* ─── Lyric regenerate + feedback collapse ──────────────────── */
  function wireLyrics(scope) {
    $$('[data-regen]', scope).forEach((btn) => {
      btn.addEventListener('click', () => {
        const orig = btn.innerHTML;
        btn.style.opacity = '.5'; btn.textContent = 'Rigenerando…';
        setTimeout(() => { btn.style.opacity = ''; btn.innerHTML = orig; }, 1400);
      });
    });
    $$('[data-toggle-feedback]', scope).forEach((btn) => {
      btn.addEventListener('click', () => {
        const fb = $('#' + btn.dataset.toggleFeedback);
        fb?.classList.toggle('show');
      });
    });
  }

  /* ─── Mini audio players (decorative waveform) ──────────────── */
  function wirePlayers(scope) {
    $$('.player', scope).forEach((p) => {
      const wf = $('.wf', p);
      if (wf && !wf.dataset.drawn) drawWave(wf);
      const pp = $('.pp', p);
      pp?.addEventListener('click', () => {
        const playing = p.classList.toggle('playing');
        pp.innerHTML = playing
          ? '<svg width="13" height="13" viewBox="0 0 10 10"><rect x="1" y="1" width="3" height="8" rx=".5" fill="currentColor"/><rect x="6" y="1" width="3" height="8" rx=".5" fill="currentColor"/></svg>'
          : '<svg width="12" height="14" viewBox="0 0 8 10" style="margin-left:1px"><path d="M0.5 0.7v8.6L7.5 5 0.5 0.7z" fill="currentColor"/></svg>';
        animateWave(wf, playing);
      });
    });
  }
  function drawWave(svg) {
    svg.dataset.drawn = '1';
    const seed = +svg.dataset.seed || 7;
    const onInk = svg.closest('.on-ink');
    const bars = 56, w = 320, h = 38, gap = 2;   // fixed logical width; stretches to fill
    const bw = (w - gap * (bars - 1)) / bars;
    let s = seed * 9301 + 49297;
    let html = '';
    for (let i = 0; i < bars; i++) {
      s = (s * 9301 + 49297) % 233280;
      const env = Math.sin((i / bars) * Math.PI) * 0.35 + 0.65;
      const a = Math.max(0.12, Math.min(1, (0.25 + (s / 233280) * 0.75) * env));
      const bh = a * h * 0.9, x = i * (bw + gap), y = (h - bh) / 2;
      const col = onInk ? '#f5f1e7' : '#22322a';
      const op = i < bars * 0.28 ? 1 : 0.28;
      html += `<rect class="bar" x="${x}" y="${y}" width="${bw}" height="${bh}" rx="${Math.min(bw,2)/2}" fill="${i<bars*0.28?'#c99846':col}" opacity="${i<bars*0.28?1:op}"/>`;
    }
    svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
    svg.setAttribute('preserveAspectRatio', 'none');
    svg.innerHTML = html;
  }
  function animateWave(svg, on) {
    if (!svg) return;
    $$('.bar', svg).forEach((b, i) => {
      b.style.transition = 'transform .25s ease';
      b.style.transformOrigin = 'center';
      b.style.transform = on ? `scaleY(${0.6 + Math.random()*0.6})` : 'scaleY(1)';
    });
    if (on) {
      svg._iv = setInterval(() => {
        $$('.bar', svg).forEach((b) => { b.style.transform = `scaleY(${0.4 + Math.random()*0.8})`; });
      }, 260);
    } else { clearInterval(svg._iv); }
  }

  /* ─── Magnetic buttons ──────────────────────────────────────── */
  function wireMagnetic() {
    if (!hasGSAP) return;
    $$('.mag').forEach((el) => {
      el.addEventListener('pointermove', (e) => {
        const r = el.getBoundingClientRect();
        gsap.to(el, { x: (e.clientX - r.left - r.width/2) * 0.25, y: (e.clientY - r.top - r.height/2) * 0.35, duration: 0.4, ease: 'power3.out' });
      });
      el.addEventListener('pointerleave', () => gsap.to(el, { x: 0, y: 0, duration: 0.5, ease: 'elastic.out(1,0.4)' }));
    });
  }

  /* ─── Boot ──────────────────────────────────────────────────── */
  function boot() {
    // Arm scroll-reveal only in a visible, motion-OK context — otherwise content shows immediately.
    // ?static=1 (used by the embedded preview) forces everything visible, no reveal gating.
    const staticMode = /[?&]static=1/.test(location.search);
    const okMotion = !window.matchMedia('(prefers-reduced-motion: reduce)').matches && !staticMode;
    if (document.visibilityState === 'visible' && okMotion) {
      document.documentElement.classList.add('reveal-on');
    }
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible' && okMotion) document.documentElement.classList.add('reveal-on');
    });

    initLenis();

    $$('.nav-link').forEach((l) => l.addEventListener('click', () => go(l.dataset.go)));
    $('.hamb')?.addEventListener('click', () => {
      const open = $('.sidebar')?.classList.contains('open');
      open ? closeMobileNav() : openMobileNav();
    });
    $('.backdrop')?.addEventListener('click', closeMobileNav);

    // wire everything once (all pages exist in DOM)
    wireVoices(document);
    wirePills(document);
    wireTiers(document);
    wireLyrics(document);
    wirePlayers(document);
    wireMagnetic();
    // init voice icons
    $$('.voice').forEach((v) => setPlayIcon(v, false));

    // initial page from hash or home
    const initial = (location.hash || '#home').slice(1);
    go(document.getElementById(initial) ? initial : 'home', false);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
