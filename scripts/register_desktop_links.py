"""Register an installed OBE Lens binary as the current user's auth-link handler."""
import argparse
import os
from pathlib import Path
import subprocess
import sys


def desktop_entry(executable):
    # Desktop Exec has its own quoting and field-code rules, not shell syntax.
    value = str(executable).replace('%', '%%')
    for character in ('\\', '"', '`', '$'):
        value = value.replace(character, '\\' + character)
    return ('[Desktop Entry]\nType=Application\nName=OBE Lens\n'
            f'Exec="{value}" %u\nTerminal=false\n'
            'MimeType=x-scheme-handler/com.obelens.app;\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    if not executable.is_file() or any(c in str(executable) for c in '\r\n'):
        parser.error('Provide a valid application executable.')
    if sys.platform == 'win32':
        import winreg
        root = r'Software\Classes\com.obelens.app'
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, root) as key:
            winreg.SetValueEx(key, '', 0, winreg.REG_SZ, 'URL:OBE Lens')
            winreg.SetValueEx(key, 'URL Protocol', 0, winreg.REG_SZ, '')
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, root + r'\shell\open\command') as key:
            winreg.SetValueEx(key, '', 0, winreg.REG_SZ, f'"{executable}" "%1"')
    elif sys.platform.startswith('linux'):
        directory = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'applications'
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'obelens.desktop').write_text(desktop_entry(executable), encoding='utf-8')
        subprocess.run(['xdg-mime', 'default', 'obelens.desktop',
                        'x-scheme-handler/com.obelens.app'], check=True)
    else:
        parser.error('Only Linux and Windows are supported.')
    print('Registered com.obelens.app for', executable)


if __name__ == '__main__':
    main()
