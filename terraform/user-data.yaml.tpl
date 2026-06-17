#cloud-config

bootcmd:
  - mkdir -p /etc/weblatex
  - chmod 750 /etc/weblatex

write_files:
%{ if latex_document != "" ~}
  - path: /tmp/document.tex.b64
    permissions: '0600'
    owner: root:root
    encoding: b64
    content: ${latex_document}
%{ endif ~}

  - path: /etc/weblatex/credentials.env
    permissions: '0640'
    owner: root:www-data
    content: |
      USERNAME=${team_username}
      PASSWORD=${team_password}

  - path: /usr/local/bin/weblatex-provision.sh
    permissions: '0700'
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail
      LOG="[weblatex-provision]"
      TEX_FILE="/var/www/weblatex/document.tex"
      OUT_DIR="/var/www/weblatex"

      mkdir -p "$OUT_DIR"
      chown www-data:www-data "$OUT_DIR"

      # ── 1. .tex Startwert setzen ──────────────────────────────────────────────
      if [ -f /tmp/document.tex.b64 ] && [ -s /tmp/document.tex.b64 ]; then
          echo "$LOG STEP 1: Decoding uploaded .tex document..."
          base64 -d /tmp/document.tex.b64 > "$TEX_FILE"
          rm -f /tmp/document.tex.b64
          echo "$LOG Decoded: $(wc -c < "$TEX_FILE") bytes"
      else
          echo "$LOG STEP 1: No document provided — writing demo document..."
          cat > "$TEX_FILE" << 'DEMO_EOF'
      \documentclass{article}
      \usepackage[utf8]{inputenc}
      \usepackage[T1]{fontenc}

      \title{Web-LaTeX Editor}
      \author{AppStore}
      \date{\today}

      \begin{document}
      \maketitle

      \section{Willkommen}
      Dies ist das Demo-Dokument. Du kannst es direkt im Editor bearbeiten
      und mit \textbf{Ctrl+Enter} (oder dem Kompilieren-Button) neu übersetzen.

      \section{Beispiel}
      Eine einfache Liste:
      \begin{itemize}
        \item Erster Punkt
        \item Zweiter Punkt
        \item Dritter Punkt
      \end{itemize}

      \end{document}
      DEMO_EOF
      fi
      chown www-data:www-data "$TEX_FILE"

      # ── 2. Erstes PDF vorab kompilieren ───────────────────────────────────────
      echo "$LOG STEP 2: Pre-compiling initial PDF..."
      pdflatex -interaction=nonstopmode -output-directory="$OUT_DIR" "$TEX_FILE" > /tmp/pdflatex.log 2>&1 || true
      pdflatex -interaction=nonstopmode -output-directory="$OUT_DIR" "$TEX_FILE" >> /tmp/pdflatex.log 2>&1 || true
      rm -f "$OUT_DIR"/*.aux "$OUT_DIR"/*.log "$OUT_DIR"/*.out "$OUT_DIR"/*.toc 2>/dev/null || true
      chown -R www-data:www-data "$OUT_DIR"

      if [ -f "$OUT_DIR/document.pdf" ]; then
          echo "$LOG Initial PDF compiled successfully"
      else
          echo "$LOG WARNING: Initial PDF compilation failed — editor still works"
      fi

      # ── 3. Services starten ───────────────────────────────────────────────────
      echo "$LOG STEP 3: Starting services..."
      systemctl start weblatex
      systemctl enable weblatex

      # Warten bis Flask bereit
      for i in $(seq 1 30); do
          curl -sf http://127.0.0.1:5000/ > /dev/null 2>&1 && echo "$LOG Flask ready." && break
          sleep 2
      done

      systemctl restart nginx

      # ── 4. Health check ───────────────────────────────────────────────────────
      HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" http://localhost/ || echo "000")
      echo "[weblatex-test] HTTP status: $HTTP_CODE (expected 200)"

      echo "$LOG All steps done. Editor available at http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')/"

runcmd:
  - bash /usr/local/bin/weblatex-provision.sh