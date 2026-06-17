#cloud-config

bootcmd:
  - mkdir -p /etc/weblatex/users
  - chown root:www-data /etc/weblatex /etc/weblatex/users
  - chmod 750 /etc/weblatex /etc/weblatex/users

write_files:
%{ for uid, file in assignment_files ~}
  - path: /tmp/assignment/${file.name}
    permissions: '0644'
    owner: root:root
    encoding: b64
    content: ${file.content_b64}
%{ endfor ~}

%{ for user in team_users ~}
  - path: /etc/weblatex/users/${replace(replace(user.email, "@", "_at_"), ".", "-")}.env
    permissions: '0640'
    owner: root:www-data
    content: |
      EMAIL=${user.email}
      PASSWORD=${user.password}
%{ endfor ~}

  - path: /usr/local/bin/weblatex-provision.sh
    permissions: '0700'
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail
      LOG="[weblatex-provision]"
      BASE_DIR="/var/www/weblatex"

      mkdir -p "$BASE_DIR"
      chown www-data:www-data "$BASE_DIR"
      chmod 755 "$BASE_DIR"

      # ── 1. Flask secret_key persistent erzeugen ──────────────────────────────
      if [ ! -f /etc/weblatex/flask_secret ]; then
          python3 -c "import os; open('/etc/weblatex/flask_secret','wb').write(os.urandom(32))"
          chown root:www-data /etc/weblatex/flask_secret
          chmod 640 /etc/weblatex/flask_secret
      fi

      # ── 2. Pro User Verzeichnis + Startdokumente anlegen ─────────────────────
      for envfile in /etc/weblatex/users/*.env; do
          [ -f "$envfile" ] || continue

          EMAIL=""
          while IFS='=' read -r key val; do
              case "$key" in
                  EMAIL) EMAIL="$val" ;;
              esac
          done < "$envfile"
          [ -z "$EMAIL" ] && continue

          UNAME=$(echo "$EMAIL" | sed 's/@/_/;s/\./-/g')
          UDIR="$BASE_DIR/$UNAME"
          mkdir -p "$UDIR"

          # assignment_files verarbeiten
          if [ -d /tmp/assignment ] && [ "$(ls -A /tmp/assignment 2>/dev/null)" ]; then
              for srcfile in /tmp/assignment/*; do
                  fname=$(basename "$srcfile")
                  if echo "$fname" | grep -qi '\.zip$'; then
                      # ZIP entpacken
                      unzip -o "$srcfile" -d "$UDIR" > /tmp/unzip_"$UNAME".log 2>&1 || \
                          echo "$LOG WARNING: unzip failed for $fname"
                  else
                      cp "$srcfile" "$UDIR/$fname"
                  fi
              done
          fi

          # Fallback: Demo-Dokument wenn kein master.tex vorhanden
          if [ ! -f "$UDIR/master.tex" ]; then
              cat > "$UDIR/master.tex" << 'DEMO_EOF'
      \documentclass{article}
      \usepackage[utf8]{inputenc}
      \usepackage[T1]{fontenc}
      \title{Web-LaTeX Editor}
      \author{AppStore}
      \date{\today}
      \begin{document}
      \maketitle
      \section{Willkommen}
      Dies ist das Demo-Dokument. Bearbeite es im Editor und kompiliere mit Ctrl+Enter.
      \end{document}
      DEMO_EOF
          fi

          chown -R www-data:www-data "$UDIR"

          # Vorab-Kompilierung
          su -s /bin/bash www-data -c \
              "pdflatex -interaction=nonstopmode -output-directory='$UDIR' '$UDIR/master.tex'" \
              > /tmp/pdflatex_"$UNAME".log 2>&1 || true
      done

      # Aufräumen
      rm -rf /tmp/assignment

      # ── 3. Services starten ───────────────────────────────────────────────────
      echo "$LOG STEP 3: Starting services..."
      systemctl start weblatex
      systemctl enable weblatex

      for i in $(seq 1 30); do
          curl -sf http://127.0.0.1:5000/ > /dev/null 2>&1 && echo "$LOG Flask ready." && break
          sleep 2
      done

      systemctl restart nginx

      HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" http://localhost/ || echo "000")
      echo "[weblatex-test] HTTP status: $HTTP_CODE (expected 200)"
      echo "$LOG All steps done."

runcmd:
  - bash /usr/local/bin/weblatex-provision.sh
