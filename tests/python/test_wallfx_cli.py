"""CLI map preparation keeps inference private and preserves JSON contracts."""
import io
import json
from pathlib import Path
import subprocess
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from zesti.cli import main
from zesti.paths import Paths


class WallpaperEffectsCliTest(unittest.TestCase):
    def test_setup_reaches_the_private_runtime(self):
        with patch('zesti.wallfx.setup_runtime', return_value={'ok': True, 'model': 'birefnet-general-lite'}) as setup, redirect_stdout(io.StringIO()) as output:
            self.assertEqual(main(['wallpaper', 'effects', 'setup']), 0)
            self.assertIsInstance(setup.call_args.args[0], Paths)
            self.assertEqual(json.loads(output.getvalue())['model'], 'birefnet-general-lite')

    def test_setup_failure_is_json_and_nonzero(self):
        with patch('zesti.wallfx.setup_runtime', return_value={'ok': False, 'error': 'download failed'}), redirect_stdout(io.StringIO()) as output:
            self.assertEqual(main(['wallpaper', 'effects', 'setup']), 1)
            self.assertIn('download failed', json.loads(output.getvalue())['error'])

    def test_private_interpreter_receives_exact_source_and_optout(self):
        with patch('zesti.wallfx.runtime_python', return_value=Path('/private/wallfx/venv/bin/python')), patch('zesti.cli.os.execv') as run:
            self.assertEqual(main(['wallpaper', 'effects', 'prepare', '--source', '/wall paper #?.jpg', '--no-inference']), 0)
            command = run.call_args.args[1]
            self.assertEqual(command[0], '/private/wallfx/venv/bin/python')
            self.assertTrue(command[1].endswith('/scripts/wallpaper-effects.py'))
            self.assertEqual(command[2:], ['--source', '/wall paper #?.jpg', '--no-inference'])
            self.assertEqual(run.call_args.args[0], command[0])

    def test_host_without_runtime_can_generate_colonies(self):
        maps = {'kind': 'contagio', 'field': '/cache/field.png', 'line': '/cache/line.png'}
        with patch('zesti.wallfx.runtime_python', return_value=None), patch('zesti.wallfx.prepare_effect', return_value=maps) as prepare, redirect_stdout(io.StringIO()) as output:
            self.assertEqual(main(['wallpaper', 'effects', 'prepare', '--source', '/wall.jpg', '--no-inference']), 0)
            self.assertEqual(prepare.call_args.args[0], Path('/wall.jpg'))
            self.assertFalse(prepare.call_args.kwargs['allow_inference'])
            self.assertEqual(json.loads(output.getvalue()), {'ok': True, **maps})

    def test_video_uses_cached_palette_frame_for_its_subject(self):
        with patch('zesti.wallfx.runtime_python', return_value=None), patch('zesti.wallpaper.extract_palette_source', return_value=Path('/cache/frame.jpg')) as frame, patch('zesti.wallfx.prepare_effect', return_value={'kind': 'perfil', 'field': '/field.png', 'line': '/line.png'}) as prepare, redirect_stdout(io.StringIO()):
            self.assertEqual(main(['wallpaper', 'effects', 'prepare', '--source', '/movie.mp4']), 0)
            self.assertEqual(frame.call_args.args[0], Path('/movie.mp4'))
            self.assertEqual(prepare.call_args.args[0], Path('/cache/frame.jpg'))

    def test_bad_source_is_reported_without_traceback(self):
        with patch('zesti.wallfx.runtime_python', return_value=None), patch('zesti.wallfx.prepare_effect', side_effect=FileNotFoundError('missing.jpg')), redirect_stdout(io.StringIO()) as output:
            self.assertEqual(main(['wallpaper', 'effects', 'prepare', '--source', 'missing.jpg']), 1)
            data = json.loads(output.getvalue())
            self.assertFalse(data['ok'])
            self.assertIn('missing.jpg', data['error'])

    def test_cache_only_video_probe_never_launches_ffmpeg(self):
        maps = {'kind': 'contagio', 'field': '/field.png', 'line': '/line.png'}
        with patch('zesti.wallfx.runtime_python', return_value=None), patch('zesti.wallpaper.cached_palette_source', return_value=None), patch('zesti.wallpaper.extract_palette_source') as extract, patch('zesti.wallfx.prepare_effect', return_value=maps) as prepare, redirect_stdout(io.StringIO()):
            self.assertEqual(main(['wallpaper', 'effects', 'prepare', '--source', '/movie.mp4', '--no-inference']), 0)
            extract.assert_not_called()
            self.assertEqual(prepare.call_args.args[0], Path('/movie.mp4'))
            self.assertFalse(prepare.call_args.kwargs['allow_inference'])

    def test_cache_only_video_probe_uses_existing_frame(self):
        with patch('zesti.wallfx.runtime_python', return_value=None), patch('zesti.wallpaper.cached_palette_source', return_value=Path('/frame.jpg')), patch('zesti.wallfx.prepare_effect', return_value={'kind': 'perfil', 'field': '/field.png', 'line': '/line.png'}) as prepare, redirect_stdout(io.StringIO()):
            self.assertEqual(main(['wallpaper', 'effects', 'prepare', '--source', '/movie.mp4', '--no-inference']), 0)
            self.assertEqual(prepare.call_args.args[0], Path('/frame.jpg'))
