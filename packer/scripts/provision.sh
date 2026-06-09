#!/usr/bin/env bash
set -euo pipefail

echo "[1/6] Waiting for cloud-init..."
cloud-init status --wait || true

echo "[2/6] Installing packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  texlive-latex-base \
  texlive-latex-recommended \
  texlive-latex-extra \
  texlive-fonts-recommended \
  texlive-lang-german \
  nginx \
  python3 \
  python3-flask \
  python3-pip

echo "[3/6] Creating Flask app..."
sudo mkdir -p /opt/weblatex/templates
sudo mkdir -p /var/www/weblatex

sudo tee /opt/weblatex/app.py > /dev/null << 'PYEOF'
import os
import subprocess
import tempfile
from flask import Flask, request, jsonify, send_file, render_template

app = Flask(__name__)
WORK_DIR = '/var/www/weblatex'
TEX_FILE = os.path.join(WORK_DIR, 'document.tex')

@app.route('/')
def index():
    content = ''
    if os.path.exists(TEX_FILE):
        with open(TEX_FILE, 'r') as f:
            content = f.read()
    return render_template('index.html', content=content)

@app.route('/compile', methods=['POST'])
def compile_tex():
    data = request.get_json()
    tex_content = data.get('content', '')

    os.makedirs(WORK_DIR, exist_ok=True)
    with open(TEX_FILE, 'w') as f:
        f.write(tex_content)

    for aux in ['document.aux', 'document.log', 'document.out', 'document.toc']:
        try:
            os.remove(os.path.join(WORK_DIR, aux))
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ['pdflatex', '-interaction=nonstopmode', '-output-directory', WORK_DIR, TEX_FILE],
        capture_output=True, text=True, timeout=60
    )
    # Zweiter Lauf für Referenzen
    if result.returncode == 0:
        subprocess.run(
            ['pdflatex', '-interaction=nonstopmode', '-output-directory', WORK_DIR, TEX_FILE],
            capture_output=True, text=True, timeout=60
        )

    pdf_path = os.path.join(WORK_DIR, 'document.pdf')
    if os.path.exists(pdf_path):
        return jsonify({'success': True})
    else:
        log = result.stdout + result.stderr
        # Relevante Fehlerzeilen herausfiltern
        errors = [l for l in log.splitlines() if l.startswith('!') or 'Error' in l]
        return jsonify({'success': False, 'errors': errors[:20]})

@app.route('/document.pdf')
def get_pdf():
    pdf_path = os.path.join(WORK_DIR, 'document.pdf')
    if os.path.exists(pdf_path):
        return send_file(pdf_path, mimetype='application/pdf')
    return 'No PDF available', 404

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
PYEOF

echo "[4/6] Creating HTML template..."
sudo tee /opt/weblatex/templates/index.html > /dev/null << 'HTMLEOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Web-LaTeX Editor</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/theme/dracula.min.css">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: sans-serif; background: #1e1e2e; color: #cdd6f4; height: 100vh; display: flex; flex-direction: column; }
    header { padding: 10px 20px; background: #181825; display: flex; align-items: center; gap: 12px; border-bottom: 1px solid #313244; }
    header h1 { font-size: 1.1rem; color: #cba6f7; }
    .btn { padding: 8px 18px; border: none; border-radius: 5px; cursor: pointer; font-size: 0.9rem; font-weight: 600; }
    .btn-compile { background: #a6e3a1; color: #1e1e2e; }
    .btn-compile:hover { background: #94e2d5; }
    .btn-compile:disabled { background: #45475a; color: #6c7086; cursor: not-allowed; }
    .status { font-size: 0.85rem; margin-left: auto; }
    .status.ok { color: #a6e3a1; }
    .status.err { color: #f38ba8; }
    .status.compiling { color: #fab387; }
    main { display: flex; flex: 1; overflow: hidden; }
    .editor-pane { flex: 1; display: flex; flex-direction: column; border-right: 1px solid #313244; }
    .editor-pane .CodeMirror { flex: 1; height: 100%; font-size: 13px; line-height: 1.6; }
    .editor-pane .CodeMirror-scroll { height: 100%; }
    .preview-pane { flex: 1; background: #181825; display: flex; flex-direction: column; }
    .preview-pane iframe { flex: 1; border: none; background: white; }
    .error-box { padding: 16px; background: #302030; color: #f38ba8; font-family: monospace; font-size: 0.8rem; overflow-y: auto; max-height: 200px; }
    .error-box pre { white-space: pre-wrap; }
  </style>
</head>
<body>
  <header>
    <h1>Web-LaTeX Editor</h1>
    <button class="btn btn-compile" id="compileBtn" onclick="compile()">▶ Kompilieren</button>
    <span class="status" id="status"></span>
  </header>
  <main>
    <div class="editor-pane">
      <textarea id="editor">{{ content }}</textarea>
    </div>
    <div class="preview-pane">
      <iframe id="preview" src="/document.pdf"></iframe>
      <div class="error-box" id="errorBox" style="display:none"><pre id="errorText"></pre></div>
    </div>
  </main>

  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/stex/stex.min.js"></script>
  <script>
    const editor = CodeMirror.fromTextArea(document.getElementById('editor'), {
      mode: 'stex',
      theme: 'dracula',
      lineNumbers: true,
      lineWrapping: true,
      autofocus: true,
      extraKeys: { 'Ctrl-Enter': compile, 'Cmd-Enter': compile }
    });
    // Editor füllt die gesamte Höhe
    editor.setSize('100%', '100%');

    async function compile() {
      const btn = document.getElementById('compileBtn');
      const status = document.getElementById('status');
      const errorBox = document.getElementById('errorBox');
      const errorText = document.getElementById('errorText');

      btn.disabled = true;
      status.className = 'status compiling';
      status.textContent = 'Kompiliert...';
      errorBox.style.display = 'none';

      try {
        const res = await fetch('/compile', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ content: editor.getValue() })
        });
        const data = await res.json();

        if (data.success) {
          status.className = 'status ok';
          status.textContent = '✓ Erfolgreich';
          document.getElementById('preview').src = '/document.pdf?t=' + Date.now();
          errorBox.style.display = 'none';
        } else {
          status.className = 'status err';
          status.textContent = '✗ Fehler';
          errorText.textContent = data.errors.join('\n');
          errorBox.style.display = 'block';
        }
      } catch (e) {
        status.className = 'status err';
        status.textContent = '✗ Verbindungsfehler';
      } finally {
        btn.disabled = false;
      }
    }
  </script>
</body>
</html>
HTMLEOF

echo "[5/6] Creating systemd service..."
sudo tee /etc/systemd/system/weblatex.service > /dev/null << 'SVCEOF'
[Unit]
Description=Web-LaTeX Flask App
After=network.target

[Service]
User=www-data
WorkingDirectory=/opt/weblatex
ExecStart=/usr/bin/python3 /opt/weblatex/app.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVCEOF

sudo chown -R www-data:www-data /opt/weblatex /var/www/weblatex
sudo systemctl daemon-reload
sudo systemctl enable weblatex

echo "[6/6] Configuring nginx as reverse proxy..."
sudo tee /etc/nginx/sites-available/weblatex > /dev/null << 'NGINXEOF'
server {
    listen 80 default_server;
    server_name _;

    # PDF direkt ausliefern (statisch)
    location /document.pdf {
        root /var/www/weblatex;
        add_header Content-Disposition inline;
        add_header Content-Type application/pdf;
    }

    # Alles andere geht an Flask
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # Großes Request-Body für lange .tex-Dokumente
        client_max_body_size 2M;
    }
}
NGINXEOF

sudo ln -sf /etc/nginx/sites-available/weblatex /etc/nginx/sites-enabled/weblatex
sudo rm -f /etc/nginx/sites-enabled/default

echo "Cleanup..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Reset machine-id
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

echo "Provisioning finished. Image is ready for deployment."