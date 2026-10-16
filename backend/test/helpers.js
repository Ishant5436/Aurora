const { spawn } = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');

// Must run before anything requires src/config/env.js. GEMINI_API_KEY is set to
// an empty string (not deleted) so dotenv can never load a real key into tests.
function configureEnv(extra = {}) {
  Object.assign(process.env, {
    NODE_ENV: 'test',
    MONGODB_URI: 'mongodb://placeholder',
    JWT_SECRET: 'test-secret-test-secret-test-secret-123',
    GEMINI_API_KEY: '',
    GEMINI_BACKOFF_MS: '0,0', // tests must not sit through real retry delays
    ...extra,
  });
}

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.once('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

// Boots a throwaway local mongod so tests exercise real MongoDB behaviour
// (unique indexes, $sample, upserts) with nothing to download or pay for.
async function startMongod() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aurora-mongo-'));
  const port = await freePort();
  const proc = spawn(
    'mongod',
    ['--dbpath', dir, '--port', String(port), '--bind_ip', '127.0.0.1', '--nounixsocket'],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  );

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('mongod did not start within 30s')), 30_000);
    proc.stdout.on('data', (chunk) => {
      if (chunk.toString().includes('Waiting for connections')) {
        clearTimeout(timer);
        resolve();
      }
    });
    proc.once('error', reject);
    proc.once('exit', (code) => reject(new Error(`mongod exited early (code ${code})`)));
  });

  return {
    uri: `mongodb://127.0.0.1:${port}/aurora_test`,
    async stop() {
      const exited = new Promise((resolve) => proc.once('exit', resolve));
      proc.kill('SIGTERM');
      await exited;
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

module.exports = { configureEnv, startMongod };
