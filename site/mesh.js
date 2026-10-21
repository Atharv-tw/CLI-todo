// The brain in the hero: notes, days, people and projects, linked the way a
// vault links them, turning in 3D, with the agents that read it around it.
// Plain canvas, no libraries. It stops drawing while it is off screen.
(() => {
  const canvas = document.getElementById('brain');
  const feed = document.getElementById('feed');
  if (!canvas || !canvas.getContext) return;
  const ctx = canvas.getContext('2d');
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Seeded, so it is the same brain on every visit.
  let seed = 20261021;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const pick = (list, r = Math.random) => list[Math.floor(r() * list.length)];

  // Two colours only: white for what you know, orange for what is moving.
  const WHITE = '244,241,234';
  const ORANGE = '242,84,27';
  const TAU = Math.PI * 2;
  const KINDS = {
    note: { rgb: WHITE, size: 4.2 },
    day: { rgb: ORANGE, size: 4.6 },
    person: { rgb: WHITE, size: 5.6 },
    learning: { rgb: WHITE, size: 4.8 },
    project: { rgb: ORANGE, size: 8 },
  };
  const kindAt = () => {
    const r = rnd();
    return r < 0.56 ? 'note' : r < 0.76 ? 'day' : r < 0.86 ? 'person' : r < 0.95 ? 'learning' : 'project';
  };

  // Each point starts scattered far out and flies into place.
  const nodes = [];
  const edges = [];
  const add = (x, y, z, kind = kindAt()) => {
    const u = rnd() * 2 - 1;
    const a = rnd() * Math.PI * 2;
    const r = 2.6 + rnd() * 2.2;
    const s = Math.sqrt(1 - u * u);
    nodes.push({
      x, y, z, kind,
      ox: Math.cos(a) * s * r, oy: u * r, oz: Math.sin(a) * s * r,
      delay: rnd() * 0.7,
      flash: 0, label: null,
      px: 0, py: 0, pz: 0, ps: 1, p: 0,
    });
    return nodes.length - 1;
  };

  const norm = (v) => {
    const l = Math.hypot(v[0], v[1], v[2]) || 1;
    return [v[0] / l, v[1] / l, v[2] / l];
  };
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

  // A point on one hemisphere (side -1 or 1) from a direction: an ellipsoid,
  // flat where the two meet, flatter underneath, narrower at the front
  // (z > 0), with a ripple of folds over it. depth < 1 goes inside.
  const surface = (side, d, depth = 1) => {
    const fold = 1 + 0.05 * Math.sin(13 * d[2] + 7 * d[1]) * Math.cos(11 * d[1] - 5 * d[0]);
    const k = fold * depth;
    let x = side * 0.43 + d[0] * 0.47 * k;
    let y = d[1] * 0.72 * k;
    const z = d[2] * 1.0 * k;
    if (x * side < 0.06) x = side * 0.06;
    if (y < -0.16) y = -0.16 + (y + 0.16) * 0.55;
    // The temporal lobe: the lower side swells a little, towards the front.
    x += side * 0.07 * Math.max(0, -d[1]) * Math.exp(-((d[2] - 0.15) ** 2) / 0.12);
    x *= 1 - 0.12 * z;
    return [x, y, z];
  };

  // The folds: short walks that wander over each hemisphere, each step a
  // note linked to the one before, like the ridges on a brain.
  for (const side of [-1, 1]) {
    for (let g = 0; g < 26; g++) {
      let d = norm([side * (0.15 + rnd()), rnd() * 2 - 1.1, rnd() * 2 - 1]);
      let h = norm(cross(d, norm([rnd() - 0.5, rnd() - 0.5, rnd() - 0.5])));
      const steps = 9 + Math.floor(rnd() * 9);
      const turn = (rnd() - 0.5) * 0.8;
      let prev = -1;
      for (let i = 0; i < steps; i++) {
        const [x, y, z] = surface(side, d);
        const n = add(x, y, z);
        if (prev >= 0) edges.push([prev, n]);
        prev = n;
        const angle = turn + Math.sin(i * 1.4 + g) * 0.7;
        const b = cross(d, h);
        h = norm([
          h[0] * Math.cos(angle) + b[0] * Math.sin(angle),
          h[1] * Math.cos(angle) + b[1] * Math.sin(angle),
          h[2] * Math.cos(angle) + b[2] * Math.sin(angle),
        ]);
        d = norm([d[0] + h[0] * 0.13, d[1] + h[1] * 0.13, d[2] + h[2] * 0.13]);
        if (d[0] * side < -0.05) h[0] = Math.abs(h[0]) * side;
        const along = dot(h, d);
        h = norm([h[0] - along * d[0], h[1] - along * d[1], h[2] - along * d[2]]);
      }
    }
    // Deeper memories, inside.
    for (let i = 0; i < 34; i++) {
      const d = norm([side * (0.2 + rnd()), rnd() * 2 - 1, rnd() * 2 - 1]);
      add(...surface(side, d, 0.3 + rnd() * 0.45));
    }
  }

  // The cerebellum, at the back underneath: rings, like its fine folds.
  for (let b = 0; b < 6; b++) {
    const v = -0.8 + b * 0.32;
    const w = Math.sqrt(1 - v * v);
    let first = -1;
    let prev = -1;
    for (let i = 0; i < 18; i++) {
      const a = (i / 18) * Math.PI * 2;
      const n = add(
        Math.cos(a) * 0.5 * w,
        -0.4 + v * 0.17 + Math.sin(a * 3 + b) * 0.012,
        -0.74 + Math.sin(a) * 0.25 * w,
        rnd() < 0.8 ? 'note' : 'day',
      );
      if (prev >= 0) edges.push([prev, n]);
      else first = n;
      prev = n;
    }
    edges.push([prev, first]);
  }

  // The brainstem.
  let stem = -1;
  for (let i = 0; i < 7; i++) {
    const n = add(Math.sin(i) * 0.015, -0.3 - i * 0.1, -0.32 - i * 0.03, 'note');
    if (stem >= 0) edges.push([stem, n]);
    stem = n;
  }

  // Tie the folds together: each point to its nearest neighbours.
  const linked = new Set(edges.map(([a, b]) => (a < b ? `${a}-${b}` : `${b}-${a}`)));
  const link = (a, b) => {
    const key = a < b ? `${a}-${b}` : `${b}-${a}`;
    if (a === b || linked.has(key)) return false;
    linked.add(key);
    edges.push([a, b]);
    return true;
  };
  for (let i = 0; i < nodes.length; i++) {
    const A = nodes[i];
    const near = [];
    for (let j = 0; j < nodes.length; j++) {
      if (j === i) continue;
      const B = nodes[j];
      const dd = (A.x - B.x) ** 2 + (A.y - B.y) ** 2 + (A.z - B.z) ** 2;
      if (dd < 0.045) near.push([dd, j]);
    }
    near.sort((p, q) => p[0] - q[0]);
    let made = 0;
    for (const [, j] of near) {
      if (made >= 2) break;
      if (link(i, j)) made++;
    }
  }

  // Links across the brain, as notes link to projects and people.
  const far = [];
  const hubs = nodes.map((n, i) => i).filter((i) => nodes[i].kind === 'project' || nodes[i].kind === 'person');
  for (let k = 0; k < 70; k++) {
    const a = pick(hubs, rnd);
    const b = Math.floor(rnd() * nodes.length);
    const A = nodes[a];
    const B = nodes[b];
    const dd = Math.hypot(A.x - B.x, A.y - B.y, A.z - B.z);
    if (dd > 0.45 && dd < 1.5) far.push([a, b]);
  }

  // Some points are named, the way a vault names its notes.
  const names = [
    ['Me.md', 'note'], ['Rules.md', 'note'], ['INDEX.md', 'note'],
    ['projects/Thesis', 'project'], ['projects/Half marathon', 'project'],
    ['people/Priya', 'person'], ['people/Arjun', 'person'],
    ['days/2026-10-13', 'day'], ['morning/2026-10-14', 'day'], ['weekly/2026-W42', 'day'],
    ['Decisions.md', 'note'], ['Ideas.md', 'note'],
    ['learning/Bayesian stats', 'learning'], ['notes/Reading list', 'note'],
  ];
  const named = [];
  const surfaceCount = nodes.length;
  for (const [label, kind] of names) {
    for (let tries = 0; tries < 200; tries++) {
      const i = Math.floor(rnd() * surfaceCount);
      const n = nodes[i];
      if (n.label || Math.abs(n.x) < 0.25) continue;
      if (named.some((j) => Math.hypot(nodes[j].x - n.x, nodes[j].y - n.y, nodes[j].z - n.z) < 0.42)) continue;
      n.label = label;
      n.kind = kind;
      named.push(i);
      break;
    }
  }

  const adjacent = nodes.map(() => []);
  for (const [a, b] of edges) {
    adjacent[a].push(b);
    adjacent[b].push(a);
  }

  // The agents, circling it.
  const agents = [
    { name: 'Claude Code', rgb: ORANGE, verbs: ['read', 'logged work to', 'searched'] },
    { name: 'Nightly routine', rgb: ORANGE, verbs: ['filed into', 'planned from', 'updated'] },
    { name: 'Codex', rgb: WHITE, verbs: ['read', 'searched'] },
    { name: 'Your phone', rgb: WHITE, verbs: ['synced'] },
    { name: 'Any MCP agent', rgb: WHITE, verbs: ['read', 'searched'] },
  ].map((a, i) => ({ ...a, phase: (i / 5) * Math.PI * 2, lift: [0.18, -0.12, 0.3, -0.26, 0.04][i], px: 0, py: 0, pz: 0, ps: 1 }));
  const ORBIT = 1.38;

  const disc = (x, y, r) => {
    if (!(r > 0)) return;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, TAU);
    ctx.fill();
  };

  let W = 0;
  let H = 0;
  let R = 1;
  let dpr = 1;
  const resize = () => {
    const box = canvas.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = box.width;
    H = box.height;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    R = Math.min(W * 0.3, H * 0.42);
  };

  // Where the pointer is, and how the brain has been spun by dragging.
  let mx = 0;
  let my = 0;
  let tx = 0;
  let ty = 0;
  let spin = 0;
  let velocity = 0;
  let dragX = null;
  addEventListener('pointermove', (e) => {
    tx = (e.clientX / innerWidth - 0.5) * 2;
    ty = (e.clientY / innerHeight - 0.5) * 2;
  }, { passive: true });
  canvas.addEventListener('pointerdown', (e) => {
    if (e.pointerType !== 'mouse') return;
    dragX = e.clientX;
    canvas.setPointerCapture(e.pointerId);
    canvas.classList.add('grabbing');
  });
  canvas.addEventListener('pointermove', (e) => {
    if (dragX === null) return;
    velocity = (e.clientX - dragX) * 0.006;
    spin += velocity;
    dragX = e.clientX;
  });
  const release = () => {
    dragX = null;
    canvas.classList.remove('grabbing');
  };
  canvas.addEventListener('pointerup', release);
  canvas.addEventListener('pointercancel', release);

  // Signals: an agent reaches into the brain, and it spreads along links.
  const pulses = [];
  let lastSaid = 0;
  const say = (agent, node, now) => {
    if (!feed || now - lastSaid < 1.5) return;
    lastSaid = now;
    const li = document.createElement('li');
    const who = document.createElement('b');
    who.textContent = agent.name;
    who.style.color = `rgb(${agent.rgb})`;
    const what = document.createElement('code');
    what.textContent = node.label;
    li.append(who, ` ${pick(agent.verbs)} `, what);
    feed.prepend(li);
    while (feed.children.length > 3) feed.lastElementChild.remove();
  };
  const fire = (now) => {
    const agent = pick(agents);
    const target = Math.random() < 0.55 ? pick(named) : Math.floor(Math.random() * nodes.length);
    const path = [target];
    let at = target;
    const hops = 3 + Math.floor(Math.random() * 5);
    for (let i = 0; i < hops; i++) {
      const next = adjacent[at];
      if (!next.length) break;
      at = pick(next);
      path.push(at);
    }
    pulses.push({ agent, path, leg: -1, t: 0 });
    if (nodes[target].label) say(agent, nodes[target], now);
  };

  const ease = (t) => 1 - (1 - t) ** 3;
  const CAM = 3.4;
  let clock = still ? 99 : 0;
  let nextFire = 2.2;

  const draw = (dt) => {
    mx += (tx - mx) * 0.04;
    my += (ty - my) * 0.04;
    if (dragX === null) {
      spin += velocity;
      velocity *= 0.95;
    }
    const yaw = 0.9 + (still ? 0 : clock * 0.13) + spin + mx * 0.35;
    const pitch = -0.28 + my * 0.16;
    const cy = Math.cos(yaw);
    const sy = Math.sin(yaw);
    const cp = Math.cos(pitch);
    const sp = Math.sin(pitch);
    const cx = W / 2;
    const cyy = H / 2 + R * 0.06;
    const project = (o, x, y, z) => {
      const x1 = x * cy + z * sy;
      const z1 = -x * sy + z * cy;
      const y2 = y * cp - z1 * sp;
      const z2 = y * sp + z1 * cp;
      const s = CAM / (CAM + z2);
      o.px = cx + x1 * s * R;
      o.py = cyy - y2 * s * R;
      o.pz = z2;
      o.ps = s;
    };

    for (const n of nodes) {
      const p = ease(Math.min(1, Math.max(0, (clock - n.delay) / 1.9)));
      n.p = p;
      project(n, n.ox + (n.x - n.ox) * p, n.oy + (n.y - n.oy) * p, n.oz + (n.z - n.oz) * p);
      if (n.flash > 0) n.flash = Math.max(0, n.flash - dt * 1.4);
    }
    const built = ease(Math.min(1, Math.max(0, (clock - 1.1) / 1.6)));
    // The agents keep to a tilted ring that faces you while the brain turns
    // inside it, so they never swing off the edge.
    const ring = (o, angle, out, lift) => {
      const z = Math.sin(angle) * out;
      const s = 6 / (6 + z);
      o.px = cx + Math.cos(angle) * out * s * R;
      o.py = cyy - (lift + Math.sin(angle) * 0.3) * s * R;
      o.pz = z;
      o.ps = s;
    };
    for (const a of agents) {
      ring(a, a.phase + clock * 0.16, ORBIT * (0.4 + 0.6 * built), a.lift * 0.4);
    }

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);

    // The orbit.
    if (built > 0) {
      ctx.beginPath();
      const o = { px: 0, py: 0, pz: 0, ps: 1 };
      for (let i = 0; i <= 72; i++) {
        const a = (i / 72) * Math.PI * 2;
        ring(o, a, ORBIT, 0);
        if (i === 0) ctx.moveTo(o.px, o.py);
        else ctx.lineTo(o.px, o.py);
      }
      ctx.strokeStyle = `rgba(255,255,255,${0.07 * built})`;
      ctx.lineWidth = 1;
      ctx.setLineDash([2, 6]);
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Links, fainter the further back they are.
    const near = [new Path2D(), new Path2D(), new Path2D(), new Path2D()];
    for (const [a, b] of edges) {
      const A = nodes[a];
      const B = nodes[b];
      const z = (A.pz + B.pz) / 2;
      const k = z < -0.45 ? 3 : z < 0 ? 2 : z < 0.45 ? 1 : 0;
      near[k].moveTo(A.px, A.py);
      near[k].lineTo(B.px, B.py);
    }
    const linkAlpha = [0.04, 0.07, 0.11, 0.18];
    ctx.lineWidth = 0.8;
    for (let k = 0; k < 4; k++) {
      ctx.strokeStyle = `rgba(${WHITE},${linkAlpha[k] * built})`;
      ctx.stroke(near[k]);
    }
    const across = new Path2D();
    for (const [a, b] of far) {
      across.moveTo(nodes[a].px, nodes[a].py);
      across.lineTo(nodes[b].px, nodes[b].py);
    }
    ctx.strokeStyle = `rgba(${ORANGE},${0.1 * built})`;
    ctx.stroke(across);

    // The points.
    const unit = R / 150;
    for (const n of nodes) {
      const kind = KINDS[n.kind];
      const depth = Math.min(1, Math.max(0.16, 0.62 - n.pz * 0.5));
      // While flying in, points can pass the camera: skip them, and cap the
      // ones close to it.
      if (n.ps <= 0) continue;
      const r = Math.min(kind.size * unit * n.ps * 0.3, kind.size * unit * 0.8);
      ctx.globalAlpha = depth * (0.35 + 0.65 * n.p);
      ctx.fillStyle = `rgb(${n.flash > 0.3 ? ORANGE : kind.rgb})`;
      disc(n.px, n.py, r);
      if (n.flash > 0) {
        // Reached: a ring that widens and fades.
        ctx.globalAlpha = n.flash * 0.8;
        ctx.strokeStyle = `rgb(${ORANGE})`;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(n.px, n.py, r + 1 + (1 - n.flash) * 10 * unit, 0, TAU);
        ctx.stroke();
      }
    }

    // Signals.
    for (let i = pulses.length - 1; i >= 0; i--) {
      const s = pulses[i];
      s.t += dt / (s.leg < 0 ? 0.75 : 0.2);
      while (s.t >= 1) {
        s.t -= 1;
        s.leg++;
        nodes[s.path[s.leg]].flash = 1;
        if (s.leg >= s.path.length - 1) break;
      }
      if (s.leg >= s.path.length - 1) {
        pulses.splice(i, 1);
        continue;
      }
      const from = s.leg < 0 ? s.agent : nodes[s.path[s.leg]];
      const to = nodes[s.path[s.leg + 1]];
      const hx = from.px + (to.px - from.px) * s.t;
      const hy = from.py + (to.py - from.py) * s.t;
      ctx.globalAlpha = s.leg < 0 ? 0.45 : 0.7;
      ctx.strokeStyle = `rgb(${ORANGE})`;
      ctx.lineWidth = s.leg < 0 ? 1 : 1.2;
      ctx.beginPath();
      ctx.moveTo(from.px, from.py);
      ctx.lineTo(hx, hy);
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = `rgb(${ORANGE})`;
      disc(hx, hy, 2.4 * unit);
    }

    // The agents themselves.
    for (const a of agents) {
      const depth = Math.min(1, Math.max(0.3, 0.75 - a.pz * 0.4));
      ctx.globalAlpha = depth * built;
      ctx.fillStyle = '#0b0b0d';
      disc(a.px, a.py, 7 * unit * a.ps);
      ctx.strokeStyle = `rgb(${a.rgb})`;
      ctx.lineWidth = 1.3;
      ctx.stroke();
      ctx.fillStyle = `rgb(${a.rgb})`;
      disc(a.px, a.py, 2.6 * unit * a.ps);
    }

    // Names: the notes facing you, and every agent.
    ctx.textBaseline = 'middle';
    const small = Math.max(10, Math.min(12, R / 17));
    ctx.font = `500 ${small}px ui-monospace, "SF Mono", "Cascadia Code", "Roboto Mono", Menlo, monospace`;
    for (const i of named) {
      const n = nodes[i];
      const a = Math.min(0.85, Math.max(0, (-n.pz - 0.05) * 1.8)) * n.p + n.flash * 0.5;
      if (a <= 0.02) continue;
      ctx.globalAlpha = Math.min(1, a);
      ctx.fillStyle = n.flash > 0.3 ? `rgb(${ORANGE})` : '#d9d4ca';
      // Names on the right read leftwards, so none runs off the edge.
      const right = n.px > W * 0.6;
      ctx.textAlign = right ? 'right' : 'left';
      ctx.fillText(n.label, n.px + (right ? -8 : 8), n.py);
    }
    ctx.font = `650 ${small + 1}px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`;
    for (const a of agents) {
      ctx.globalAlpha = Math.min(1, Math.max(0.35, 0.8 - a.pz * 0.35)) * built;
      ctx.fillStyle = `rgb(${a.rgb})`;
      const right = a.px > W / 2;
      ctx.textAlign = right ? 'right' : 'left';
      ctx.fillText(a.name, a.px + (right ? -1 : 1) * (12 * unit + 4), a.py);
    }
    ctx.globalAlpha = 1;
    ctx.textAlign = 'left';
  };

  // Runs only while it can be seen.
  let running = false;
  let onScreen = false;
  let last = 0;
  const frame = (now) => {
    if (!running) return;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    clock += dt;
    if (clock > nextFire) {
      fire(clock);
      nextFire = clock + 0.35 + Math.random() * 0.6;
    }
    draw(dt);
    requestAnimationFrame(frame);
  };
  const start = () => {
    if (running || still) return;
    running = true;
    last = performance.now();
    requestAnimationFrame(frame);
  };
  const stop = () => {
    running = false;
  };

  resize();
  draw(0);
  new ResizeObserver(() => {
    resize();
    if (!running) draw(0);
  }).observe(canvas);
  new IntersectionObserver(([entry]) => {
    onScreen = entry.isIntersecting;
    if (onScreen && !document.hidden) start();
    else stop();
  }).observe(canvas);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) stop();
    else if (onScreen) start();
  });
})();
