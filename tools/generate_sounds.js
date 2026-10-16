// Synthesises the three bundled alarm sounds so the repo ships with original,
// license-free audio. Replace the generated files with real recordings any time.
//   node tools/generate_sounds.js
const fs = require('node:fs');
const path = require('node:path');

const RATE = 22050;
const OUT = path.join(__dirname, '..', 'app', 'assets', 'audio');

// Small deterministic PRNG so regenerated files are byte-identical.
let seed = 1234567;
const rand = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 0xffffffff;
};

const buffer = (seconds) => new Float32Array(Math.round(seconds * RATE));

// Short fade in/out so each loop restarts without an audible click.
function fade(out, inMs = 5, outMs = 400) {
  const fin = Math.round((inMs / 1000) * RATE);
  const fout = Math.round((outMs / 1000) * RATE);
  for (let i = 0; i < fin; i++) out[i] *= i / fin;
  for (let i = 0; i < fout; i++) out[out.length - 1 - i] *= i / fout;
}

function toWav(samples) {
  let peak = 0;
  for (const s of samples) peak = Math.max(peak, Math.abs(s));
  const gain = peak > 0 ? 0.85 / peak : 1;
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((s, i) => {
    const v = Math.max(-1, Math.min(1, s * gain));
    data.writeInt16LE(Math.round(v * 32767), i * 2);
  });
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(RATE, 24);
  header.writeUInt32LE(RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}

// Cathedral Bells: inharmonic partials with long exponential decays.
function bells() {
  const out = buffer(12);
  const partials = [ // [ratio, amplitude, decay seconds]
    [0.5, 0.5, 3.5], [1, 1, 3.0], [1.19, 0.6, 2.2], [1.56, 0.45, 1.8],
    [2, 0.5, 1.4], [2.51, 0.3, 1.0], [3.0, 0.25, 0.8],
  ];
  const notes = [659.25, 523.25, 392.0, 523.25, 659.25, 783.99, 523.25, 392.0];
  notes.forEach((freq, n) => {
    const start = Math.round(n * 1.5 * RATE);
    for (const [ratio, amp, tau] of partials) {
      for (let i = 0; start + i < out.length && i < RATE * tau * 6; i++) {
        const t = i / RATE;
        out[start + i] += amp * Math.exp(-t / tau) * Math.sin(2 * Math.PI * freq * ratio * t);
      }
    }
  });
  fade(out);
  return out;
}

// Lute Morning: Karplus-Strong plucked strings playing a rising arpeggio.
function lute() {
  const out = buffer(10);
  const melody = [261.63, 329.63, 392.0, 523.25, 392.0, 329.63, 293.66, 392.0, 493.88, 587.33, 493.88, 392.0];
  const step = Math.round(0.45 * RATE);
  for (let n = 0; n * step < out.length; n++) {
    const freq = melody[n % melody.length];
    const len = Math.round(RATE / freq);
    const line = Float32Array.from({ length: len }, () => rand() * 2 - 1);
    let idx = 0;
    for (let i = 0; n * step + i < out.length && i < RATE * 1.6; i++) {
      const next = line[(idx + 1) % len];
      out[n * step + i] += 0.8 * line[idx];
      line[idx] = 0.4985 * (line[idx] + next);
      idx = (idx + 1) % len;
    }
  }
  fade(out);
  return out;
}

// Choir Rise: a detuned, vibrato-laden chord that swells from soft to insistent.
function choir() {
  const seconds = 10;
  const out = buffer(seconds);
  const chord = [261.63, 392.0, 523.25, 659.25, 783.99];
  chord.forEach((base, v) => {
    for (const detune of [-0.004, 0, 0.004]) {
      const freq = base * (1 + detune);
      for (let i = 0; i < out.length; i++) {
        const t = i / RATE;
        const vibrato = 1 + 0.004 * Math.sin(2 * Math.PI * (5.2 + v * 0.13) * t);
        let sample = 0;
        for (let h = 1; h <= 4; h++) sample += Math.sin(2 * Math.PI * freq * vibrato * h * t) / h;
        out[i] += sample * Math.min(1, 0.25 + t / 6);
      }
    }
  });
  fade(out, 400, 400);
  return out;
}

fs.mkdirSync(OUT, { recursive: true });
const sounds = { 'cathedral_bells.wav': bells(), 'lute_morning.wav': lute(), 'choir_rise.wav': choir() };
for (const [name, samples] of Object.entries(sounds)) {
  fs.writeFileSync(path.join(OUT, name), toWav(samples));
  console.log(`wrote ${name} (${(samples.length / RATE).toFixed(1)}s)`);
}
