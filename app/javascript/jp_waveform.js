/* ═══════════════════════════════════════════════════════════════
   JinglePro — hero "ora in riproduzione" player
   A real-feeling audio player: a classic symmetric sound-wave that
   sweeps a playhead, cycling through example shop jingles so the
   small-business owner sees exactly what they'll get.
   Canvas-based; draws a full static frame immediately (never blank).
   ═══════════════════════════════════════════════════════════════ */
(function () {
  function init() {
    const canvas = document.getElementById('heroWave');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const nameEl = document.querySelector('[data-shop-name]');
    const tagEl  = document.querySelector('[data-shop-tag]');
    const curEl  = document.querySelector('[data-cur]');
    const durEl  = document.querySelector('[data-dur]');
    const playBtn = document.getElementById('heroPlay');
    const dotsWrap = document.getElementById('heroDots');

    const BRASS = '#c99846', BRASS_HI = '#e6c074', DIM = 'rgba(201,152,70,0.40)';

    // International style demos — genre + BPM read the same in every country (no per-market swap)
    const shops = [
      { name: 'Pop',       tag: '124 BPM', seed: 7,  dur: 30 },
      { name: 'Lo-fi',     tag: '82 BPM',  seed: 23, dur: 28 },
      { name: 'Cinematic', tag: '90 BPM',  seed: 41, dur: 34 },
      { name: 'Funk',      tag: '108 BPM', seed: 58, dur: 26 },
      { name: 'Acoustic',  tag: '96 BPM',  seed: 72, dur: 30 },
    ];

    let W = 0, H = 0, dpr = 1;
    let cur = 0, progress = 0, playing = true, t = 0, last = performance.now();

    // build dots
    if (dotsWrap) {
      dotsWrap.innerHTML = shops.map((_, i) => `<span class="hp-dot${i === 0 ? ' on' : ''}"></span>`).join('');
    }

    // deterministic per-shop bar profile, musical envelope
    function profile(seed, n) {
      const out = []; let s = seed * 9301 + 49297;
      for (let i = 0; i < n; i++) {
        s = (s * 9301 + 49297) % 233280;
        const r = s / 233280;
        // a couple of overlaid "beats" so it reads rhythmic, not noisy
        const beat = 0.45 + 0.4 * Math.abs(Math.sin(i * 0.5 + seed)) + 0.25 * Math.abs(Math.sin(i * 0.17));
        const env = Math.sin((i / n) * Math.PI) * 0.35 + 0.65;
        out.push(Math.max(0.08, Math.min(1, (0.35 + r * 0.5) * beat * env)));
      }
      return out;
    }
    let bars = profile(shops[0].seed, 72);
    let barCount = 72;

    function resize() {
      const r = canvas.getBoundingClientRect();
      if (!r.width || !r.height) return;
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = r.width * dpr; canvas.height = r.height * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      W = r.width; H = r.height;
      barCount = Math.max(36, Math.min(90, Math.floor(W / 7)));
      bars = profile(shops[cur].seed, barCount);
      draw();
    }
    const ro = new ResizeObserver(resize); ro.observe(canvas);

    function draw() {
      if (!W) return;
      ctx.clearRect(0, 0, W, H);
      const gap = 3;
      const bw = (W - gap * (barCount - 1)) / barCount;
      const mid = H / 2;
      const playedX = progress * W;
      for (let i = 0; i < barCount; i++) {
        const x = i * (bw + gap);
        // gentle live shimmer
        const shimmer = playing ? (0.9 + 0.1 * Math.sin(t * 4 + i * 0.6)) : 1;
        const amp = bars[i] * (H * 0.46) * shimmer;
        const isPlayed = x < playedX;
        ctx.fillStyle = isPlayed ? BRASS_HI : DIM;
        roundRect(ctx, x, mid - amp, Math.max(1, bw), amp * 2, Math.min(bw, 3) / 2);
        ctx.fill();
      }
      // playhead
      if (playing || progress > 0) {
        ctx.fillStyle = BRASS;
        ctx.fillRect(playedX - 1, H * 0.06, 2, H * 0.88);
        ctx.beginPath(); ctx.arc(playedX, H * 0.06, 3, 0, Math.PI * 2); ctx.fill();
      }
    }

    function roundRect(c, x, y, w, h, r) {
      c.beginPath();
      c.moveTo(x + r, y);
      c.arcTo(x + w, y, x + w, y + h, r);
      c.arcTo(x + w, y + h, x, y + h, r);
      c.arcTo(x, y + h, x, y, r);
      c.arcTo(x, y, x + w, y, r);
      c.closePath();
    }

    function fmt(sec) { const m = Math.floor(sec / 60); const s = Math.floor(sec % 60); return m + ':' + String(s).padStart(2, '0'); }

    function setShop(i, animateText) {
      cur = (i + shops.length) % shops.length;
      const sh = shops[cur];
      bars = profile(sh.seed, barCount);
      progress = 0;
      if (durEl) durEl.textContent = fmt(sh.dur);
      const apply = () => { if (nameEl) nameEl.textContent = sh.name; if (tagEl) tagEl.textContent = sh.tag; };
      if (animateText && nameEl) {
        nameEl.style.opacity = tagEl.style.opacity = '0';
        setTimeout(() => { apply(); nameEl.style.opacity = tagEl.style.opacity = '1'; }, 220);
      } else { apply(); }
      if (dotsWrap) [...dotsWrap.children].forEach((d, k) => d.classList.toggle('on', k === cur));
    }

    // init text/dur; start partway so the sound-wave reads immediately
    setShop(0, false);
    progress = 0.32;

    let running = true;
    function frame(now) {
      requestAnimationFrame(frame);
      if (!running) return;
      // self-heal: when the hero becomes visible / resizes, sync the canvas backing size
      if (W === 0 || Math.abs((canvas.clientWidth || 0) - W) > 1) resize();
      const dt = Math.min((now - last) / 1000, 0.05); last = now;
      t += dt;
      if (playing) {
        progress += dt / shops[cur].dur;
        if (curEl) curEl.textContent = fmt(progress * shops[cur].dur);
        if (progress >= 1) { setShop(cur + 1, true); progress = 0; }
      }
      draw();
    }
    requestAnimationFrame(frame);

    function setPlayIcon() {
      if (!playBtn) return;
      playBtn.innerHTML = playing
        ? '<svg width="14" height="14" viewBox="0 0 10 10"><rect x="1" y="1" width="3" height="8" rx=".5" fill="currentColor"/><rect x="6" y="1" width="3" height="8" rx=".5" fill="currentColor"/></svg>'
        : '<svg width="13" height="15" viewBox="0 0 8 10" style="margin-left:2px"><path d="M0.5 0.7v8.6L7.5 5 0.5 0.7z" fill="currentColor"/></svg>';
    }
    setPlayIcon();
    playBtn?.addEventListener('click', () => { playing = !playing; setPlayIcon(); last = performance.now(); });
    dotsWrap?.addEventListener('click', (e) => {
      const dot = e.target.closest('.hp-dot'); if (!dot) return;
      setShop([...dotsWrap.children].indexOf(dot), true); playing = true; setPlayIcon();
    });

    // router pause/resume hook (keep same name used by jp-motion)
    window.__heroSetRunning = function (on) {
      if (on && !running) { running = true; last = performance.now(); requestAnimationFrame(frame); }
      else if (!on) { running = false; }
    };

    resize();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
