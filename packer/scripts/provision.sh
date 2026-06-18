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
  python3-pip \
  unzip \
  zip

echo "[3/6] Creating Flask app..."
sudo mkdir -p /opt/weblatex/templates
sudo mkdir -p /var/www/weblatex

# Demo-Projekt als ZIP im Image ablegen
DEMO_TMP=$(mktemp -d)
mkdir -p "$DEMO_TMP/chapters"

sudo tee "$DEMO_TMP/master.tex" > /dev/null << 'DEMO_MASTER'
\documentclass{article}
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{hyperref}

\title{Web-LaTeX Editor}
\author{AppStore}
\date{\today}

\begin{document}
\maketitle
\tableofcontents
\newpage

\input{chapters/intro}
\input{chapters/example}

\end{document}
DEMO_MASTER

sudo tee "$DEMO_TMP/chapters/intro.tex" > /dev/null << 'DEMO_INTRO'
\section{Willkommen}
Dies ist das Demo-Projekt. Jeder Abschnitt liegt in einer eigenen Datei
im Verzeichnis \texttt{chapters/}.

Bearbeite \texttt{master.tex} im Editor und kompiliere mit \textbf{Ctrl+Enter}.
DEMO_INTRO

sudo tee "$DEMO_TMP/chapters/example.tex" > /dev/null << 'DEMO_EXAMPLE'
\section{Beispiel}
Eine einfache Liste:
\begin{itemize}
  \item \texttt{master.tex} -- Einstiegspunkt, bindet alle Kapitel ein
  \item \texttt{chapters/intro.tex} -- Einleitung
  \item \texttt{chapters/example.tex} -- Dieser Abschnitt
\end{itemize}

Eine Formel: $E = mc^2$
DEMO_EXAMPLE

(cd "$DEMO_TMP" && sudo zip -r /opt/weblatex/demo_project.zip .)
rm -rf "$DEMO_TMP"
sudo chown www-data:www-data /opt/weblatex/demo_project.zip

sudo tee /opt/weblatex/app.py > /dev/null << 'PYEOF'
import os
import subprocess
from functools import wraps
from flask import Flask, request, jsonify, send_file, render_template, session, redirect, url_for

app = Flask(__name__)

# Persistent secret key — kein Session-Verlust bei Service-Restart
_secret_path = '/etc/weblatex/flask_secret'
if os.path.exists(_secret_path):
    with open(_secret_path, 'rb') as _f:
        app.secret_key = _f.read()
else:
    app.secret_key = os.urandom(32)

BASE_DIR = '/var/www/weblatex'
USERS_DIR = '/etc/weblatex/users'

def email_to_dirname(email):
    return email.replace('@', '_').replace('.', '-')

def get_user_dir(email):
    return os.path.join(BASE_DIR, email_to_dirname(email))

def load_credentials():
    creds = {}
    if not os.path.isdir(USERS_DIR):
        return creds
    for fname in os.listdir(USERS_DIR):
        if not fname.endswith('.env'):
            continue
        try:
            user_data = {}
            with open(os.path.join(USERS_DIR, fname)) as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        k, v = line.split('=', 1)
                        user_data[k.strip()] = v.strip()
            if 'EMAIL' in user_data and 'PASSWORD' in user_data:
                creds[user_data['EMAIL']] = user_data['PASSWORD']
        except (OSError, PermissionError):
            continue
    return creds

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login_page'))
        return f(*args, **kwargs)
    return decorated

@app.route('/login', methods=['GET'])
def login_page():
    if session.get('logged_in'):
        return redirect(url_for('index'))
    error = request.args.get('error')
    return render_template('login.html', error=error)

@app.route('/login', methods=['POST'])
def do_login():
    creds = load_credentials()
    username = request.form.get('username', '').strip()
    password = request.form.get('password', '').strip()
    if username in creds and creds[username] == password:
        session['logged_in'] = True
        session['username'] = username
        return redirect(url_for('index'))
    return redirect(url_for('login_page', error='1'))

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login_page'))

@app.route('/')
@login_required
def index():
    user_dir = get_user_dir(session['username'])
    os.makedirs(user_dir, exist_ok=True)
    master = os.path.join(user_dir, 'master.tex')
    content = ''
    if os.path.exists(master):
        with open(master, 'r') as f:
            content = f.read()
    return render_template('index.html', content=content, username=session['username'])

@app.route('/compile', methods=['POST'])
@login_required
def compile_tex():
    data = request.get_json()
    tex_content = data.get('content', '')
    user_dir = get_user_dir(session['username'])
    os.makedirs(user_dir, exist_ok=True)
    master = os.path.join(user_dir, 'master.tex')
    with open(master, 'w') as f:
        f.write(tex_content)
    # Alte Hilfsdateien und PDF löschen damit success:true nur bei echtem PDF gilt
    for ext in ['aux', 'log', 'out', 'toc', 'pdf']:
        try:
            os.remove(os.path.join(user_dir, 'master.' + ext))
        except FileNotFoundError:
            pass
    # cwd=user_dir damit \input{} relativ aufgelöst wird
    result = subprocess.run(
        ['pdflatex', '-interaction=nonstopmode', '-output-directory', user_dir, 'master.tex'],
        cwd=user_dir,
        capture_output=True, text=True, timeout=60
    )
    if result.returncode == 0:
        subprocess.run(
            ['pdflatex', '-interaction=nonstopmode', '-output-directory', user_dir, 'master.tex'],
            cwd=user_dir,
            capture_output=True, text=True, timeout=60
        )
    pdf_path = os.path.join(user_dir, 'master.pdf')
    if os.path.exists(pdf_path):
        return jsonify({'success': True})
    log = result.stdout + result.stderr
    errors = [l for l in log.splitlines() if l.startswith('!') or 'Error' in l]
    return jsonify({'success': False, 'errors': errors[:20]})

@app.route('/files')
@login_required
def list_files():
    user_dir = get_user_dir(session['username'])
    files = []
    for root, dirs, fnames in os.walk(user_dir):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for fname in sorted(fnames):
            if fname.endswith('.tex'):
                rel = os.path.relpath(os.path.join(root, fname), user_dir)
                files.append(rel)
    return jsonify(files)

@app.route('/file/<path:relpath>', methods=['GET'])
@login_required
def get_file(relpath):
    user_dir = get_user_dir(session['username'])
    full = os.path.realpath(os.path.join(user_dir, relpath))
    if not full.startswith(os.path.realpath(user_dir)):
        return 'Forbidden', 403
    if not os.path.exists(full):
        return 'Not found', 404
    with open(full, 'r') as f:
        return jsonify({'content': f.read()})

@app.route('/file/<path:relpath>', methods=['POST'])
@login_required
def save_file(relpath):
    user_dir = get_user_dir(session['username'])
    full = os.path.realpath(os.path.join(user_dir, relpath))
    if not full.startswith(os.path.realpath(user_dir)):
        return 'Forbidden', 403
    os.makedirs(os.path.dirname(full), exist_ok=True)
    data = request.get_json()
    with open(full, 'w') as f:
        f.write(data.get('content', ''))
    return jsonify({'success': True})

@app.route('/pdf')
@login_required
def get_pdf():
    user_dir = get_user_dir(session['username'])
    pdf_path = os.path.join(user_dir, 'master.pdf')
    if os.path.exists(pdf_path):
        return send_file(pdf_path, mimetype='application/pdf')
    return 'No PDF available', 404

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
PYEOF

echo "[4/6] Creating HTML templates..."
sudo tee /opt/weblatex/templates/login.html > /dev/null << 'LOGINEOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Web-LaTeX — Login</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: sans-serif; background: #1e1e2e; color: #cdd6f4;
           display: flex; align-items: center; justify-content: center; height: 100vh; }
    .card { background: #181825; border: 1px solid #313244; border-radius: 10px;
            padding: 40px; width: 360px; }
    h1 { color: #cba6f7; font-size: 1.4rem; margin-bottom: 8px; }
    p  { color: #6c7086; font-size: 0.85rem; margin-bottom: 28px; }
    label { display: block; font-size: 0.85rem; color: #a6adc8; margin-bottom: 6px; }
    input { width: 100%; padding: 10px 12px; background: #313244; border: 1px solid #45475a;
            border-radius: 6px; color: #cdd6f4; font-size: 0.95rem; margin-bottom: 16px; }
    input:focus { outline: none; border-color: #cba6f7; }
    button { width: 100%; padding: 11px; background: #cba6f7; color: #1e1e2e;
             font-weight: 700; font-size: 1rem; border: none; border-radius: 6px; cursor: pointer; }
    button:hover { background: #b4befe; }
    .error { background: #3b1b1b; color: #f38ba8; border-radius: 6px;
             padding: 10px 14px; font-size: 0.85rem; margin-bottom: 16px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Web-LaTeX Editor</h1>
    <p>Bitte melde dich mit deinen Zugangsdaten an.</p>
    {% if error %}
    <div class="error">Benutzername oder Passwort falsch.</div>
    {% endif %}
    <form method="POST" action="/login">
      <label for="username">E-Mail</label>
      <input type="email" id="username" name="username" autocomplete="username" required>
      <label for="password">Passwort</label>
      <input type="password" id="password" name="password" autocomplete="current-password" required>
      <button type="submit">Anmelden</button>
    </form>
  </div>
</body>
</html>
LOGINEOF

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
    header { padding: 10px 20px; background: #181825; display: flex; align-items: center; gap: 12px; border-bottom: 1px solid #313244; flex-shrink: 0; }
    header h1 { font-size: 1.1rem; color: #cba6f7; }
    .btn { padding: 8px 18px; border: none; border-radius: 5px; cursor: pointer; font-size: 0.9rem; font-weight: 600; }
    .btn-compile { background: #a6e3a1; color: #1e1e2e; }
    .btn-compile:hover { background: #94e2d5; }
    .btn-compile:disabled { background: #45475a; color: #6c7086; cursor: not-allowed; }
    .btn-logout { background: transparent; color: #6c7086; border: 1px solid #45475a; margin-left: auto; }
    .btn-logout:hover { color: #f38ba8; border-color: #f38ba8; }
    .user-info { font-size: 0.8rem; color: #6c7086; }
    .status { font-size: 0.85rem; }
    .status.ok { color: #a6e3a1; }
    .status.err { color: #f38ba8; }
    .status.compiling { color: #fab387; }
    main { display: flex; flex: 1; overflow: hidden; }
    /* Sidebar */
    .sidebar { width: 180px; background: #181825; border-right: 1px solid #313244; display: flex; flex-direction: column; flex-shrink: 0; }
    .sidebar-header { padding: 8px 12px; font-size: 0.75rem; color: #6c7086; text-transform: uppercase; letter-spacing: 0.05em; border-bottom: 1px solid #313244; }
    .file-list { flex: 1; overflow-y: auto; padding: 4px 0; }
    .file-item { padding: 6px 12px; font-size: 0.82rem; cursor: pointer; color: #a6adc8; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .file-item:hover { background: #313244; color: #cdd6f4; }
    .file-item.active { background: #313244; color: #cba6f7; font-weight: 600; }
    /* Editor */
    .editor-pane { flex: 1; display: flex; flex-direction: column; border-right: 1px solid #313244; min-width: 0; }
    .editor-pane .CodeMirror { flex: 1; height: 100%; font-size: 13px; line-height: 1.6; }
    .editor-pane .CodeMirror-scroll { height: 100%; }
    /* Preview */
    .preview-pane { flex: 1; background: #181825; display: flex; flex-direction: column; min-width: 0; }
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
    <span class="user-info">{{ username }}</span>
    <a href="/logout" class="btn btn-logout">Abmelden</a>
  </header>
  <main>
    <div class="sidebar">
      <div class="sidebar-header">Dateien</div>
      <div class="file-list" id="fileList"></div>
    </div>
    <div class="editor-pane">
      <textarea id="editor">{{ content }}</textarea>
    </div>
    <div class="preview-pane">
      <iframe id="preview" src="/pdf"></iframe>
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
    editor.setSize('100%', '100%');

    // Datei-Cache: ungespeicherte Änderungen pro Datei merken
    const fileCache = {};
    let currentFile = 'master.tex';

    async function loadFileList() {
      const res = await fetch('/files');
      const files = await res.json();
      const list = document.getElementById('fileList');
      list.innerHTML = '';
      files.forEach(f => {
        const item = document.createElement('div');
        item.className = 'file-item' + (f === currentFile ? ' active' : '');
        item.textContent = f;
        item.title = f;
        item.onclick = () => switchFile(f);
        list.appendChild(item);
      });
    }

    async function switchFile(filename) {
      // Aktuellen Stand im Cache speichern
      fileCache[currentFile] = editor.getValue();
      // Aktiven Eintrag wechseln
      document.querySelectorAll('.file-item').forEach(el => {
        el.classList.toggle('active', el.textContent === filename);
      });
      currentFile = filename;
      // Aus Cache laden oder vom Server holen
      if (fileCache[filename] !== undefined) {
        editor.setValue(fileCache[filename]);
      } else {
        const res = await fetch('/file/' + filename);
        const data = await res.json();
        editor.setValue(data.content);
        fileCache[filename] = data.content;
      }
      editor.focus();
    }

    async function saveCurrentFile() {
      await fetch('/file/' + currentFile, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content: editor.getValue() })
      });
      fileCache[currentFile] = editor.getValue();
    }

    async function compile() {
      // Aktuelle Datei speichern bevor kompiliert wird
      await saveCurrentFile();
      const btn = document.getElementById('compileBtn');
      const status = document.getElementById('status');
      const errorBox = document.getElementById('errorBox');
      const errorText = document.getElementById('errorText');
      btn.disabled = true;
      status.className = 'status compiling';
      status.textContent = 'Kompiliert...';
      errorBox.style.display = 'none';
      try {
        // master.tex Inhalt aus Cache oder Server holen
        const masterContent = fileCache['master.tex'] !== undefined
          ? fileCache['master.tex']
          : await fetch('/file/master.tex').then(r => r.json()).then(d => d.content);
        const res = await fetch('/compile', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ content: masterContent })
        });
        const data = await res.json();
        if (data.success) {
          status.className = 'status ok';
          status.textContent = '✓ Erfolgreich';
          document.getElementById('preview').src = '/pdf?t=' + Date.now();
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

    // Beim Start Dateiliste laden
    loadFileList();
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
sudo mkdir -p /etc/weblatex/users
sudo chown root:www-data /etc/weblatex /etc/weblatex/users
sudo chmod 750 /etc/weblatex /etc/weblatex/users
sudo python3 -c "import os; open('/etc/weblatex/flask_secret','wb').write(os.urandom(32))"
sudo chown root:www-data /etc/weblatex/flask_secret
sudo chmod 640 /etc/weblatex/flask_secret
sudo systemctl daemon-reload
sudo systemctl enable weblatex

echo "[6/6] Configuring nginx as reverse proxy..."
sudo tee /etc/nginx/sites-available/weblatex > /dev/null << 'NGINXEOF'
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        client_max_body_size 5M;
    }
}
NGINXEOF

sudo ln -sf /etc/nginx/sites-available/weblatex /etc/nginx/sites-enabled/weblatex
sudo rm -f /etc/nginx/sites-enabled/default

echo "Cleanup..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

echo "Provisioning finished. Image is ready for deployment."
