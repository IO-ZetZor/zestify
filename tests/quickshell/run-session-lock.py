#!/usr/bin/env python3
"""Exercise production lock/PAM logic in an isolated nested Hyprland session.

A temporary pam_exec policy accepts a fixed test token; no account passwords or
production PAM configuration are touched. Requires Hyprland, qs and pam_exec.so.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
ARTIFACTS = Path('/tmp/zestify-session-lock')
ARTIFACTS.mkdir(exist_ok=True)


def wait_for(check, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.05)
    raise RuntimeError('Timed out waiting for native lock test condition')


def read_image(path):
    try:
        with Image.open(path) as image:
            return image.convert('RGB')
    except OSError:
        # Qt creates the file before saveToFile finishes writing its pixels.
        return None


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


with tempfile.TemporaryDirectory(prefix='zl-') as directory:
    work = Path(directory)
    runtime = work / 'r'
    runtime.mkdir(mode=0o700)
    config = work / 'config'
    shell = config / 'quickshell/zestify'
    shutil.copytree(REPO / 'shell', shell)
    (shell / 'shell.qml').write_text((REPO / 'tests/quickshell/session-lock.qml').read_text().replace('../../shell/', ''))
    (config / 'zestify').mkdir()
    (config / 'zestify/config.json').write_text(json.dumps({
        'session': {'lockAfter': 0, 'dpmsOffAfter': 0, 'suspendAfter': 0, 'lockBeforeSleep': False, 'criticalBattery': -1},
        'theme': {'apply': False, 'transparency': 0.35},
    }))
    wallpaper_state = work / 'state/zestify/wallpaper'
    wallpaper_state.mkdir(parents=True)
    (wallpaper_state / 'path.txt').write_text(str(REPO / 'shell/assets/rem-smile.gif'))
    pamdir = work / 'pam'
    pamdir.mkdir()
    verifier = work / 'verify.py'
    verifier.write_text('#!/usr/bin/env python3\nimport sys\n'
                        "sys.exit(0 if sys.stdin.buffer.read().rstrip(b'\\0') == b'zestify-test-token' else 1)\n")
    verifier.chmod(0o755)
    (pamdir / 'zestify-test').write_text(f'auth required pam_exec.so debug log=/tmp/zestify-session-lock/pam.log expose_authtok {verifier}\n')
    controller = shell / 'components/SessionLock.qml'
    source = controller.read_text().replace('config: "login"',
        f'config: "zestify-test"\n        configDirectory: "{pamdir}"')
    source = source.replace('property bool active: false',
        'property alias testAuth: authFlow\n    property bool testUnlockAnimated: false\n'
        '    property bool testHoldUnlock: false\n    property var testReadySecure: []\n    property bool active: false')
    source = source.replace('function beginUnlock() {', 'function beginUnlock() {\n        testReadySecure = [];')
    source = source.replace('function unlockOverlayReady(screenName, serial) {',
        'function unlockOverlayReady(screenName, serial) {\n        testReadySecure = testReadySecure.concat([nativeLock.secure]);')
    source = source.replace('function finishUnlock(animated) {',
        'function finishUnlock(animated) {\n        testUnlockAnimated = animated;')
    source = source.replace('function capturedUnlock(screenName, frame, serial) {',
        'function capturedUnlock(screenName, frame, serial) {\n        if (testHoldUnlock) return;')
    controller.write_text(source)
    surface = shell / 'components/LockSurface.qml'
    source = surface.read_text().replace('import Quickshell\n', 'import Quickshell\nimport Quickshell.Io\n')
    source = source.replace('    readonly property string screenName:', '''    IpcHandler {
        target: "surface-" + root.screenName
        function state(): string {
            const input = findInput(face);
            return JSON.stringify({active: face.authActive, focused: input.activeFocus,
                text: input.text, readOnly: input.readOnly, handoff: root.showingHandoff,
                firstFrameHandoff: root.firstFrameHandoff, wallpaperReady: wallpaper.ready,
                blurCached: blur.cached});
        }
        function submit(value: string): void {
            const input = findInput(face);
            input.text = value;
            face.submit();
        }
        function preview(path: string): void {
            face.parent.grabToImage(result => result.saveToFile(path));
        }
        function backgroundPreview(path: string): void {
            handoffImage.grabToImage(result => result.saveToFile(path));
        }
    }
    property bool firstFrameHandoff: false
    property bool frameSeen: false
    Connections {
        target: root.contentItem.Window.window
        function onFrameSwapped() {
            if (!root.frameSeen) {
                root.firstFrameHandoff = root.showingHandoff;
                root.frameSeen = true;
            }
        }
    }
    function findInput(item) {
        if (item.objectName === "lockResponse") return item;
        for (const child of item.children || []) {
            const found = findInput(child);
            if (found) return found;
        }
        return null;
    }
    readonly property string screenName:''')
    surface.write_text(source)
    scripts = work / 'scripts'
    scripts.mkdir()
    delay_frame = work / 'delay-frame'
    (scripts / 'lock.py').write_text(
        'import runpy, sys, time\nfrom pathlib import Path\n'
        f'if "--frame" in sys.argv and Path({str(delay_frame)!r}).exists(): time.sleep(2)\n'
        f'runpy.run_path({str(REPO / "scripts/lock.py")!r}, run_name="__main__")\n')
    (scripts / 'logind-watch.py').write_text('import time\ntime.sleep(120)\n')
    hyprconfig = work / 'hyprland.lua'
    hyprconfig.write_text('hl.monitor({output="", mode="1280x720@60", position="auto", scale=1})\nhl.config({misc={allow_session_lock_restore=true}, input={accel_profile="flat", sensitivity=0}})\nhl.layer_rule({match={namespace="zestify-lock-pull"}, no_anim=true})\n')
    env = {**os.environ, 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(config),
           'XDG_STATE_HOME': str(work / 'state'), 'XDG_CACHE_HOME': str(work / 'cache'),
           'AQ_BACKEND': 'wayland,headless', 'HYPRLAND_NO_SD_VARS': '1', 'HYPRLAND_NO_SD_NOTIFY': '1',
           'ZESTI_BIN': '/usr/bin/true', 'PYTHON': 'python3', 'ZESTIFY_SCRIPTS': str(scripts),
           'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/nonexistent'}
    env['WAYLAND_DISPLAY'] = str(Path(os.environ['XDG_RUNTIME_DIR']) / os.environ['WAYLAND_DISPLAY'])
    env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
    compositor = quickshell = competitor = None
    with (ARTIFACTS / 'hyprland.log').open('w') as hyprlog, (ARTIFACTS / 'quickshell.log').open('w') as qslog:
        try:
            compositor = subprocess.Popen(['Hyprland', '--config', str(hyprconfig)], env=env, stdout=hyprlog, stderr=subprocess.STDOUT)
            def compositor_ready():
                if compositor.poll() is not None:
                    raise RuntimeError('Nested Hyprland exited; see /tmp/zestify-session-lock/hyprland.log')
                sockets = [path for path in runtime.glob('wayland-*') if not path.name.endswith('.lock')]
                instances = list((runtime / 'hypr').glob('*/.socket.sock'))
                return (sockets[0], instances[0]) if sockets and instances else None
            display, instance = wait_for(compositor_ready)
            env['WAYLAND_DISPLAY'] = display.name
            env['HYPRLAND_INSTANCE_SIGNATURE'] = instance.parent.name
            def run(command, timeout=5):
                result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=timeout)
                if result.returncode:
                    raise RuntimeError(result.stderr or result.stdout)
                return result.stdout.strip()
            # Bootstrap rendering with nested Wayland, then exercise headless
            # outputs so host pointer motion cannot interfere with synthetic drags.
            run(['hyprctl', 'output', 'create', 'headless', 'LOCK-MAIN'])
            run(['hyprctl', 'eval', 'hl.monitor({output="WAYLAND-1", disabled=true})'])
            def ipc(method, *args, target='zestify'):
                return run(['qs', 'ipc', '-c', 'zestify', 'call', target, method, *args])
            def get_state():
                return json.loads(ipc('lockStatus'))
            def wait_for_unlock(screens=1, capture=False):
                wait_for(lambda: not get_state()['active'])
                state = json.loads(ipc('testState'))
                assert state['animated'] and state['exitActive'], state
                assert len(state['readySecure']) >= screens and all(state['readySecure']), state
                assert 0 <= state['exitProgress'] < 1, state
                if capture:
                    run(['grim', '-o', 'LOCK-MAIN', str(ARTIFACTS / 'unlock-mid.png')])
                wait_for(lambda: not json.loads(ipc('testState'))['exitActive'])
                if capture:
                    final = ARTIFACTS / 'unlock-desktop.png'
                    run(['grim', '-o', 'LOCK-MAIN', str(final)])
                    with Image.open(final) as image:
                        assert image.convert('RGB').getpixel((640, 360)) == (38, 56, 75), 'Exit frame covered the desktop after the fade'
            quickshell = subprocess.Popen(['qs', '-c', 'zestify', '--no-color'], env=env, stdout=qslog, stderr=subprocess.STDOUT)
            def shell_ready():
                if quickshell.poll() is not None:
                    raise RuntimeError('Quickshell exited; see /tmp/zestify-session-lock/quickshell.log')
                try:
                    return get_state()
                except (RuntimeError, ValueError):
                    return None
            wait_for(shell_ready)
            # CLI requests the production controller and waits for real secure.
            run(['python3', str(REPO / 'scripts/lock.py')])
            assert get_state()['secure']
            screen = json.loads(ipc('testState'))['screens'][0]
            surface_target = 'surface-' + screen
            first = json.loads(ipc('state', target=surface_target))
            assert first['active'] and first['focused'] and not first['readOnly'], first
            time.sleep(0.25)
            ipc('preview', str(ARTIFACTS / 'lockscreen.png'), target=surface_target)
            wait_for(lambda: (ARTIFACTS / 'lockscreen.png').exists())
            ipc('submit', 'wrong-test-token', target=surface_target)
            wait_for(lambda: json.loads(ipc('testState'))['feedback'])
            assert get_state()['secure']
            assert not json.loads(ipc('state', target=surface_target))['text']
            # Hot reload must retain compositor ownership and status generation.
            generation = get_state()['generation']
            entry = shell / 'shell.qml'
            entry.write_text(entry.read_text() + '\n// reload while locked\n')
            time.sleep(0.75)
            wait_for(shell_ready)
            assert get_state()['secure'] and get_state()['generation'] == generation
            assert json.loads(ipc('testState'))['locked']
            run(['grim', '-o', 'LOCK-MAIN', str(ARTIFACTS / 'unlock-start.png')])
            ipc('submit', 'zestify-test-token', target=surface_target)
            wait_for_unlock(capture=True)
            assert not json.loads(ipc('testState'))['locked']
            # Force a cold, slow native wallpaper load after the curtain is
            # already ready. The first native buffer must retain its background.
            ipc('prepareCurtain')
            wait_for(lambda: ipc('curtainReady') == 'true')
            curtain_image = ARTIFACTS / 'curtain-background.png'
            handoff_image = ARTIFACTS / 'handoff-background.png'
            curtain_image.unlink(missing_ok=True)
            handoff_image.unlink(missing_ok=True)
            ipc('curtainPreview', str(curtain_image))
            wait_for(curtain_image.exists)
            delay_frame.touch()
            ipc('finishCurtain')
            wait_for(lambda: get_state()['secure'])
            handoff = json.loads(ipc('state', target=surface_target))
            assert handoff['handoff'] and handoff['firstFrameHandoff'], handoff
            assert not handoff['wallpaperReady'] and not handoff['blurCached'], handoff
            ipc('backgroundPreview', str(handoff_image), target=surface_target)
            wait_for(handoff_image.exists)
            with wait_for(lambda: read_image(curtain_image)) as before, wait_for(lambda: read_image(handoff_image)) as after:
                assert before.size == after.size
                assert before.tobytes() == after.tobytes(), 'Handoff changed the curtain background'
            wait_for(lambda: json.loads(ipc('state', target=surface_target))['blurCached'])
            assert not json.loads(ipc('state', target=surface_target))['handoff']
            delay_frame.unlink()
            ipc('submit', 'zestify-test-token', target=surface_target)
            wait_for_unlock()
            # A fresh lock request must revoke an in-flight authenticated exit.
            ipc('lock')
            wait_for(lambda: get_state()['secure'])
            ipc('holdUnlock', 'true')
            ipc('submit', 'zestify-test-token', target=surface_target)
            wait_for(lambda: json.loads(ipc('testState'))['unlocking'])
            assert get_state()['secure']
            ipc('lock')
            time.sleep(1.3)
            assert get_state()['secure'] and not json.loads(ipc('testState'))['unlocking']
            ipc('holdUnlock', 'false')
            ipc('submit', 'zestify-test-token', target=surface_target)
            wait_for_unlock()
            # All outputs are automatically covered, and the form can migrate.
            ipc('lock')
            wait_for(lambda: get_state()['secure'])
            generation = get_state()['generation']
            assert int(ipc('lock')) == generation
            run(['hyprctl', 'output', 'create', 'headless', 'LOCK-SECOND'])
            wait_for(lambda: len(json.loads(ipc('testState'))['screens']) == 2)
            wait_for(lambda: json.loads(ipc('state', target='surface-LOCK-SECOND')))
            assert get_state()['secure']
            ipc('selectScreen', 'LOCK-SECOND')
            wait_for(lambda: json.loads(ipc('state', target='surface-LOCK-SECOND'))['active'])
            ipc('submit', 'zestify-test-token', target='surface-LOCK-SECOND')
            wait_for_unlock(screens=2)
            ipc('lock')
            wait_for(lambda: get_state()['secure'])
            run(['hyprctl', 'output', 'remove', 'LOCK-SECOND'])
            wait_for(lambda: json.loads(ipc('state', target=surface_target))['active'])
            assert get_state()['secure']
            # Crash leaves compositor secured; a new locker can take over.
            quickshell.kill()
            quickshell.wait()
            recovery_env = env
            quickshell = subprocess.Popen(['qs', '-c', 'zestify', '--no-color'], env=recovery_env, stdout=qslog, stderr=subprocess.STDOUT)
            wait_for(shell_ready)
            ipc('lock')
            wait_for(lambda: get_state()['secure'])
            ipc('submit', 'zestify-test-token', target=surface_target)
            wait_for_unlock()
            run(['sh', str(REPO / 'tests/quickshell/run-lockpull.sh')], timeout=25)
            print('NATIVE LOCK PASS: longer unlock fade, overlays ready while secure, first-frame curtain background with delayed wallpaper, secure CLI readiness, real PAM failure/success, keyboard focus, reload, hotplug, crash recovery, curtain pointer gestures')
            print('Preview: /tmp/zestify-session-lock/lockscreen.png')
        finally:
            stop(competitor)
            stop(quickshell)
            stop(compositor)
            for logfile in runtime.glob("hypr/*/hyprland.log"):
                shutil.copy2(logfile, ARTIFACTS / "hyprland-detail.log")
