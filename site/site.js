// Everything on the page that moves, apart from the brain (mesh.js).
(() => {
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const watch = (els, fn, options) => {
    if (!('IntersectionObserver' in window)) return els.forEach((el) => fn(el, true));
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) fn(e.target, e.isIntersecting, io);
    }, options);
    els.forEach((el) => io.observe(el));
  };

  // Things fade up as they come into view, once.
  watch([...document.querySelectorAll('[data-reveal]')], (el, seen, io) => {
    if (!seen) return;
    el.classList.add('in');
    io?.unobserve(el);
  }, { rootMargin: '0px 0px -12% 0px' });

  // The terminal types its commands when it is first seen.
  watch([...document.querySelectorAll('[data-type]')], async (term, seen, io) => {
    if (!seen || term.dataset.typed) return;
    term.dataset.typed = '1';
    io?.unobserve(term);
    if (still) return;
    const lines = [...term.querySelectorAll('.ln')];
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    const texts = lines.map((ln) => (ln.classList.contains('cmd') ? ln.lastChild.textContent : null));
    lines.forEach((ln, i) => {
      ln.classList.add('hide');
      if (texts[i] !== null) ln.lastChild.textContent = '';
    });
    for (const [i, ln] of lines.entries()) {
      ln.classList.remove('hide');
      if (texts[i] === null) {
        await wait(70);
        continue;
      }
      ln.classList.add('typing');
      for (let c = 1; c <= texts[i].length; c++) {
        ln.lastChild.textContent = texts[i].slice(0, c);
        await wait(16 + Math.random() * 22);
      }
      ln.classList.remove('typing');
      await wait(380);
    }
  }, { threshold: 0.4 });

  // The phone beside the apps shows whichever part you are reading.
  const shots = document.querySelectorAll('.apps-phone img');
  const steps = [...document.querySelectorAll('.app-step')];
  const show = (name) => {
    shots.forEach((img) => img.classList.toggle('on', img.dataset.shot === name));
  };
  watch([...document.querySelectorAll('[data-shot]:not(img)')], (el, seen) => {
    if (!seen) return;
    show(el.dataset.shot);
    const step = el.closest('.app-step');
    steps.forEach((s) => s.classList.toggle('on', s === step));
  }, { rootMargin: '-45% 0px -45% 0px' });

  // Scroll: the bar at the top, the header, and the laptop tilting upright.
  const root = document.documentElement;
  const header = document.querySelector('.top');
  const tilted = document.querySelectorAll('[data-tilt]');
  let queued = false;
  const onScroll = () => {
    queued = false;
    const max = root.scrollHeight - innerHeight;
    root.style.setProperty('--scroll', max > 0 ? (scrollY / max).toFixed(4) : '0');
    header?.classList.toggle('scrolled', scrollY > 8);
    if (still) return;
    for (const el of tilted) {
      const top = el.getBoundingClientRect().top;
      const t = Math.min(1, Math.max(0, (top - innerHeight * 0.2) / (innerHeight * 0.7)));
      el.style.setProperty('--tilt', t.toFixed(3));
    }
  };
  addEventListener('scroll', () => {
    if (!queued) {
      queued = true;
      requestAnimationFrame(onScroll);
    }
  }, { passive: true });
  addEventListener('resize', onScroll);
  onScroll();

  // The Copy buttons beside commands.
  for (const button of document.querySelectorAll('[data-copy]')) {
    button.addEventListener('click', async () => {
      const text = document.getElementById(button.dataset.copy).textContent;
      try {
        await navigator.clipboard.writeText(text);
        button.textContent = 'Copied';
      } catch {
        button.textContent = 'Select it';
      }
      setTimeout(() => (button.textContent = 'Copy'), 1600);
    });
  }
})();
