#!/bin/sh
set -eu

python3 -m unittest discover -s tests/python -v
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import shell
/usr/lib/qt6/bin/qmllint -I shell shell/shell.qml
