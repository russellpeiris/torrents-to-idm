import Express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import mime from 'mime-types';
import WebTorrent from 'webtorrent-hybrid';

const app = Express();
app.use(cors());
app.use(Express.json({ limit: '2mb' }));
app.use(Express.urlencoded({ extended: true }));
app.use(morgan('dev'));

// ────────────────────────────────────────────────────────────────────────────────
// WebTorrent client
// ────────────────────────────────────────────────────────────────────────────────
const client = new WebTorrent({
  // You can tweak for better connectivity, but defaults are fine for most cases.
  // dht: true,
  // tracker: true,
});

// Keep in-memory registry of torrents we added (for browsing/cleanup)
const registry = new Map(); // infoHash -> { torrent }

// Helper: ensure a torrent is loaded/added and ready
async function ensureTorrent(resource) {
  return new Promise((resolve, reject) => {
    let existing = null;
    for (const t of client.torrents) {
      if (t.infoHash === resource || t.magnetURI === resource || t._serverAdded === resource) {
        existing = t;
        break;
      }
    }
    const done = (t) => {
      registry.set(t.infoHash, { torrent: t });
      resolve(t);
    };

    if (existing) {
      if (existing.ready) return resolve(existing);
      existing.once('ready', () => done(existing));
      return;
    }

    const t = client.add(resource, { announce: [
      // Public trackers (optional, helps connectivity)
      'udp://tracker.opentrackr.org:1337/announce',
      'udp://open.stealth.si:80/announce',
      'udp://tracker.openbittorrent.com:6969/announce',
      'udp://tracker.internetwarriors.net:1337/announce',
      'udp://exodus.desync.com:6969/announce'
    ]});
    t._serverAdded = resource; // mark for quick lookup
    t.once('error', reject);
    t.once('ready', () => done(t));
  });
}

// ────────────────────────────────────────────────────────────────────────────────
// Routes
// ────────────────────────────────────────────────────────────────────────────────

// Home: simple form
app.get('/', (_req, res) => {
  res.type('html').send(`
  <html><head><meta charset="utf-8"><title>Torrent ➜ HTTP (IDM)</title>
  <style>body{font-family:system-ui,Segoe UI,Roboto,Arial;margin:2rem;max-width:800px}input,button{font-size:1rem;padding:.6rem;border-radius:.6rem;border:1px solid #ddd}button{cursor:pointer}code{background:#f6f6f6;padding:.2rem .4rem;border-radius:.3rem}</style>
  </head><body>
  <h1>🧲 Torrent ➜ HTTP bridge for IDM</h1>
  <p>Paste a <b>magnet link</b> or a <b>.torrent URL</b>. After it connects, you'll get direct file links.</p>
  <form method="post" action="/add" style="display:flex; gap:.6rem">
    <input type="text" name="resource" placeholder="magnet:?xt=... or https://.../file.torrent" style="flex:1" required />
    <button type="submit">Add</button>
  </form>
  <p>Existing torrents: <a href="/torrents">/torrents</a></p>
  </body></html>
  `);
});

// Add a torrent (magnet URI or .torrent URL)
app.post('/add', async (req, res) => {
  try {
    const resource = (req.body.resource || '').trim();
    if (!resource) return res.status(400).json({ error: 'Provide magnet URI or .torrent URL as "resource"' });
    
    // Start adding torrent (don't wait for it to be ready)
    ensureTorrent(resource).catch(err => console.error('Torrent add error:', err));
    
    // Respond immediately
    res.format({
      json: () => res.json({ message: 'Torrent is being added. Check /torrents for status.' }),
      html: () => {
        res.send(`
          <h2>✅ Torrent added!</h2>
          <p>The torrent is connecting to peers...</p>
          <p><a href="/torrents">View all torrents</a> or <a href="/">Add another</a></p>
          <script>setTimeout(() => window.location.href='/torrents', 2000);</script>
        `);
      }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: String(err.message || err) });
  }
});

// List all current torrents
app.get('/torrents', (_req, res) => {
  const list = client.torrents.map(t => ({
    infoHash: t.infoHash,
    name: t.name,
    ready: t.ready,
    downloaded: t.downloaded,
    length: t.length,
    progress: Number(t.progress.toFixed(3)),
    files: t.files.map((f, i) => ({ index: i, name: f.name, length: f.length, path: `/d/${t.infoHash}/${i}/${encodeURIComponent(f.name)}` }))
  }));
  res.json(list);
});

// Serve a specific file with HTTP range support (IDM compatible)
app.get('/d/:infoHash/:fileIndex/:fileName?', async (req, res) => {
  try {
    const { infoHash, fileIndex } = req.params;
    const t = client.torrents.find(tt => tt.infoHash === infoHash);
    if (!t) return res.status(404).send('Torrent not found. Add it at /add first.');

    const file = t.files[Number(fileIndex)];
    if (!file) return res.status(404).send('File not found');

    const total = file.length;
    const range = req.headers.range;

    res.setHeader('Accept-Ranges', 'bytes');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(file.name)}`);

    const contentType = mime.lookup(file.name) || 'application/octet-stream';
    res.setHeader('Content-Type', contentType);

    if (range) {
      const match = range.match(/bytes=(\d+)-(\d*)/);
      if (!match) return res.status(416).send('Malformed Range');
      const start = parseInt(match[1], 10);
      const end = match[2] ? Math.min(parseInt(match[2], 10), total - 1) : total - 1;
      const chunkSize = end - start + 1;
      res.status(206);
      res.setHeader('Content-Range', `bytes ${start}-${end}/${total}`);
      res.setHeader('Content-Length', chunkSize);
      const stream = file.createReadStream({ start, end });
      stream.on('error', (e) => {
        console.error('stream error', e);
        if (!res.headersSent) res.status(500).end('Stream error');
        else res.end();
      });
      stream.pipe(res);
    } else {
      res.status(200);
      res.setHeader('Content-Length', total);
      const stream = file.createReadStream();
      stream.on('error', (e) => {
        console.error('stream error', e);
        if (!res.headersSent) res.status(500).end('Stream error');
        else res.end();
      });
      stream.pipe(res);
    }
  } catch (err) {
    console.error(err);
    res.status(500).send(String(err.message || err));
  }
});

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\nShutting down...');
  client.destroy(() => process.exit(0));
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 Torrent ➜ HTTP (IDM) bridge listening on http://localhost:${PORT}`));