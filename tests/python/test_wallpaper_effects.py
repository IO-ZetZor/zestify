"""Exercise serialized map work, cache invalidation and worker failure recovery."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]


class WallpaperEffectsSchedulerTest(unittest.TestCase):
    def test_map_work_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='zestify-map-queue-') as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(REPO / 'shell', target_is_directory=True)
            script = root / 'helper'
            script.write_text("#!/usr/bin/env python3\n"
                "import fcntl, json, os, sys, time\nfrom pathlib import Path\n"
                "source=sys.argv[sys.argv.index('--source')+1]\n"
                "lookup='--no-inference' in sys.argv\n"
                "state=Path(os.environ['MAP_FIXTURE_STATE'])\n"
                "with state.with_suffix('.lock').open('a') as lock:\n"
                "    fcntl.flock(lock,fcntl.LOCK_EX)\n"
                "    counts=json.loads(state.read_text()) if state.exists() else {}\n"
                "    key=('cache:' if lookup else 'warm:')+source\n"
                "    count=counts.get(key,0)+1;counts[key]=count;state.write_text(json.dumps(counts))\n"
                "if source=='deadline' and lookup: time.sleep(2.3)\n"
                "elif source.startswith('slow') or (source=='generation' and count==1):time.sleep(0.4)\n"
                "elif source=='outline-soon' and not lookup:time.sleep(0.6)\n"
                "elif source=='outline-slow' and not lookup:time.sleep(2.5)\n"
                "if source=='bad-json':print('{invalid');sys.exit(0)\n"
                "maps={'ok':True,'kind':'perfil','field':f'/maps/{source}-{count}.png','line':'/maps/line.png'}\n"
                "if lookup and source in ('outline-soon','outline-slow','deadline'):maps.update(kind='contagio',cached=False,pending=True)\n"
                "if source=='transient':maps.update(kind='contagio',error='temporary failure')\n"
                "print(json.dumps(maps))\n")
            script.chmod(0o755)
            harness = root / 'queue.qml'
            harness.write_text((REPO / 'tests/quickshell/wallpaper-effects.qml').read_text().replace('../../shell/', 'shell/'))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', ZESTI_BIN=str(script), MAP_FIXTURE_STATE=str(root / 'counts.json'))
            env.pop('WAYLAND_DISPLAY', None)
            result = subprocess.run(['qs', '--no-color', '-p', str(harness)], env=env, text=True, capture_output=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('WALLPAPER EFFECTS PASS:', output)
            for error in ('TypeError', 'ReferenceError', 'Binding loop', 'Cannot assign', 'Unable to assign'):
                self.assertNotIn(error, output)
