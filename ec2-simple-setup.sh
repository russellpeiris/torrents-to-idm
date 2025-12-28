#!/bin/bash
# Simplified EC2 User Data Script for Torrents to IDM
# This script creates the app directly without cloning from GitHub

set -e

echo "🚀 Setting up Torrents to IDM on EC2..."

# Update system
yum update -y

# Install Docker
amazon-linux-extras install docker -y
service docker start
usermod -a -G docker ec2-user
systemctl enable docker

# Install Node.js 18
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Create application directory
mkdir -p /home/ec2-user/torrents-to-idm
cd /home/ec2-user/torrents-to-idm

# Create package.json
cat > package.json <<'PKGEOF'
{
  "name": "torrents-to-idm",
  "version": "1.0.0",
  "description": "Download torrents and serve via HTTP for IDM",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "webtorrent": "^2.0.0"
  }
}
PKGEOF

# Create server.js
cat > server.js <<'SERVEREOF'
const express = require('express');
const WebTorrent = require('webtorrent');
const path = require('path');

const app = express();
const client = new WebTorrent();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static('public'));

// Store torrents info
const torrents = new Map();

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Torrents to IDM</title>
      <style>
        body { font-family: Arial; max-width: 1200px; margin: 50px auto; padding: 20px; }
        input { width: 70%; padding: 10px; }
        button { padding: 10px 20px; background: #007bff; color: white; border: none; cursor: pointer; }
        .torrent { border: 1px solid #ddd; padding: 15px; margin: 10px 0; }
        .file { padding: 5px; margin: 5px 0; background: #f5f5f5; }
      </style>
    </head>
    <body>
      <h1>🚀 Torrents to IDM</h1>
      <p>Add torrent magnet links or .torrent URLs, then download files with IDM using HTTP links</p>
      <input type="text" id="magnetInput" placeholder="Paste magnet link or .torrent URL here">
      <button onclick="addTorrent()">Add Torrent</button>
      <div id="torrents"></div>
      <script>
        function addTorrent() {
          const magnet = document.getElementById('magnetInput').value;
          if (!magnet) return alert('Please enter a magnet link');
          fetch('/api/add', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({magnet})
          }).then(() => {
            document.getElementById('magnetInput').value = '';
            loadTorrents();
          });
        }
        function loadTorrents() {
          fetch('/api/torrents').then(r => r.json()).then(data => {
            const html = data.map(t => \`
              <div class="torrent">
                <h3>\${t.name || 'Loading...'}</h3>
                <p>Progress: \${t.progress}% | Peers: \${t.numPeers} | Speed: \${t.downloadSpeed}</p>
                \${t.files.map(f => \`
                  <div class="file">
                    📄 \${f.name} (\${f.size})
                    \${f.url ? \`<br><a href="\${f.url}" target="_blank">\${f.url}</a>\` : ''}
                  </div>
                \`).join('')}
              </div>
            \`).join('');
            document.getElementById('torrents').innerHTML = html;
          });
        }
        setInterval(loadTorrents, 2000);
        loadTorrents();
      </script>
    </body>
    </html>
  `);
});

app.post('/api/add', (req, res) => {
  const { magnet } = req.body;
  client.add(magnet, (torrent) => {
    torrents.set(torrent.infoHash, torrent);
    console.log('Added torrent:', torrent.name);
  });
  res.json({ success: true });
});

app.get('/api/torrents', (req, res) => {
  const list = Array.from(torrents.values()).map(t => ({
    name: t.name,
    progress: (t.progress * 100).toFixed(1),
    downloadSpeed: (t.downloadSpeed / 1024 / 1024).toFixed(2) + ' MB/s',
    numPeers: t.numPeers,
    files: t.files.map(f => ({
      name: f.name,
      size: (f.length / 1024 / 1024).toFixed(2) + ' MB',
      url: \`http://\${req.get('host')}/download/\${t.infoHash}/\${encodeURIComponent(f.name)}\`
    }))
  }));
  res.json(list);
});

app.get('/download/:infoHash/:filename', (req, res) => {
  const torrent = torrents.get(req.params.infoHash);
  if (!torrent) return res.status(404).send('Torrent not found');
  const file = torrent.files.find(f => f.name === decodeURIComponent(req.params.filename));
  if (!file) return res.status(404).send('File not found');
  res.setHeader('Content-Type', 'application/octet-stream');
  res.setHeader('Content-Disposition', \`attachment; filename="\${file.name}"\`);
  file.createReadStream().pipe(res);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(\`✅ Server running on port \${PORT}\`);
});
SERVEREOF

# Install dependencies and start
npm install

# Create systemd service for auto-start
cat > /etc/systemd/system/torrents-to-idm.service <<'SERVICEEOF'
[Unit]
Description=Torrents to IDM Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/torrents-to-idm
ExecStart=/usr/bin/node server.js
Restart=always
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Set permissions
chown -R ec2-user:ec2-user /home/ec2-user/torrents-to-idm

# Enable and start service
systemctl daemon-reload
systemctl enable torrents-to-idm
systemctl start torrents-to-idm

echo "✅ Setup complete!"
echo "🌍 Access your service at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
