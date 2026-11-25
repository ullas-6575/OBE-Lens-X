import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import register_desktop_links as links


class RegistrationTests(unittest.TestCase):
    def test_windows_registers_current_user_and_quotes_executable(self):
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / 'obelens.exe'
            executable.touch()
            registry = MagicMock()
            with patch('sys.argv', ['register', str(executable)]), \
                 patch('sys.platform', 'win32'), \
                 patch.dict('sys.modules', {'winreg': registry}):
                links.main()
            registry.CreateKey.assert_any_call(
                registry.HKEY_CURRENT_USER, r'Software\Classes\com.obelens.app')
            registry.CreateKey.assert_any_call(
                registry.HKEY_CURRENT_USER,
                r'Software\Classes\com.obelens.app\shell\open\command')
            registry.SetValueEx.assert_any_call(
                registry.CreateKey.return_value.__enter__.return_value,
                '', 0, registry.REG_SZ, f'"{executable.resolve()}" "%1"')

    def test_linux_registration_uses_exact_executable_and_scheme(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / 'app with spaces' / 'obelens'
            executable.parent.mkdir()
            executable.touch()
            with patch('sys.argv', ['register', str(executable)]), \
                 patch('sys.platform', 'linux'), \
                 patch.dict('os.environ', {'XDG_DATA_HOME': str(root / 'data')}), \
                 patch.object(links.subprocess, 'run') as run:
                links.main()
            entry = (root / 'data/applications/obelens.desktop').read_text()
            self.assertIn(f'Exec="{executable}" %u', entry)
            self.assertIn('MimeType=x-scheme-handler/com.obelens.app;', entry)
            run.assert_called_once_with(['xdg-mime', 'default', 'obelens.desktop',
                                         'x-scheme-handler/com.obelens.app'], check=True)


if __name__ == '__main__':
    unittest.main()
