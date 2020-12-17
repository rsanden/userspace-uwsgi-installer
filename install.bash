#!/bin/bash

set -e

MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$MYDIR"

source "$MYDIR/config"

#--- Constants ---
if ! [[ "$SERVER_TYPE" = "apache" || "$SERVER_TYPE" = "nginx" ]]; then
  echo "Unrecognized SERVER_TYPE: $SERVER_TYPE. Choose from: apache, nginx"
  exit 1
fi

if [[ "$PORT" = "77777" ]]; then
  echo "Invalid port: $PORT. Please use the port assigned to the Proxy Port application."
  exit 1
fi

#--- Do Substitutions ---
mkdir -p "$PREFIX/src"
cp -r "$MYDIR/templates" "$PREFIX/src"
cd "$PREFIX/src/templates"
source substitutions.bash

#--- Initial Config ---
mkdir -p "$PREFIX"/{bin,conf,etc,lib,var/run,tmp}
cp "$PREFIX/src/templates/httpd.conf.template" "$PREFIX/conf/httpd.conf"
cp "$PREFIX/src/templates/nginx.conf.template" "$PREFIX/conf/nginx.conf"
cp "$PREFIX/src/templates/httpd-uwsgi.ini.template" "$PREFIX/etc/httpd-uwsgi.ini"
cp "$PREFIX/src/templates/nginx-uwsgi.ini.template" "$PREFIX/etc/nginx-uwsgi.ini"

cd "$PREFIX/etc"
if [[ "$SERVER_TYPE" = "apache" ]]; then
  ln -s httpd-uwsgi.ini uwsgi.ini
else
  ln -s nginx-uwsgi.ini uwsgi.ini
fi

mkdir -p "$LOGDIR"
ln -s "$LOGDIR" "$PREFIX/log"

if ! [[ -f "$APPDIR1/wsgi.py" ]]; then
  cp "$MYDIR/templates/wsgi.py" "$APPDIR1/"
fi

#--- Create venv (and install uwsgi into it) ---
cd "$PREFIX"
python3.6 -m venv env
source env/bin/activate
pip install --upgrade pip
pip install wheel
pip install uwsgi
deactivate

#--- Create start/stop/restart scripts ---
cd "$PREFIX/bin"

ln -s "/usr/sbin/httpd" "$PREFIX/bin/httpd"
ln -s "/usr/sbin/nginx" "$PREFIX/bin/nginx"

cat << "EOF" > start-httpd
#!/bin/bash
MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$(dirname $MYDIR)/env/bin/uwsgi" --ini "$(dirname $MYDIR)/etc/uwsgi.ini" 2>/dev/null
$MYDIR/httpd -d "$(dirname $MYDIR)"
EOF

cat << "EOF" > stop-httpd
#!/bin/bash
MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
kill $(cat "$MYDIR/../var/run/httpd.pid") &> /dev/null
"$(dirname $MYDIR)/env/bin/uwsgi" --stop "$(dirname $MYDIR)/var/run/uwsgi.pid" &> /dev/null
EOF

cat << "EOF" > start-nginx
#!/bin/bash
MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$(dirname $MYDIR)/env/bin/uwsgi" --ini "$(dirname $MYDIR)/etc/uwsgi.ini" 2>/dev/null
$MYDIR/nginx -c "$(dirname $MYDIR)/conf/nginx.conf" -p "$(dirname $MYDIR)" 2>/dev/null
EOF

cat << "EOF" > stop-nginx
#!/bin/bash
MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
kill $(cat "$MYDIR/../var/run/nginx.pid") &> /dev/null
"$(dirname $MYDIR)/env/bin/uwsgi" --stop "$(dirname $MYDIR)/var/run/uwsgi.pid" &> /dev/null
EOF

cat << "EOF" > restart
#!/bin/bash
MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$MYDIR/stop"
sleep 3
"$MYDIR/start"
EOF

chmod 755 start-httpd stop-httpd
chmod 755 start-nginx stop-nginx
chmod 755 restart

if [[ "$SERVER_TYPE" = "apache" ]]; then
  ln -s start-httpd start
  ln -s stop-httpd stop
else
  ln -s start-nginx start
  ln -s stop-nginx stop
fi

#--- Remove temporary files ---
rm -r "$PREFIX/src"

#--- Create cron entry ---
line="\n# $STACKNAME stack\n*/10 * * * * $PREFIX/bin/start &>/dev/null"
(crontab -l 2>/dev/null || true; echo -e "$line" ) | crontab -

#--- Start the application ---
$PREFIX/bin/start
