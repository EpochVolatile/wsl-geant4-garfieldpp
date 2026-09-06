"""Check real release selection logic embedded in the delivered Bash file."""
import pathlib
import re
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'install-particle-stack.sh'


class ReleaseSelection(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), 'Installer and release selection have not been implemented')
        source = SCRIPT.read_text(encoding='utf-8')
        body = re.search(r"<<'PY_RELEASE'\n(.*?)\nPY_RELEASE", source, re.S).group(1)
        self.module = {'__name__': 'selection_test'}
        exec(compile(body, str(SCRIPT), 'exec'), self.module)

    def pick(self, names, minor=6, gcc=(11, 5, 0)):
        html = '\n'.join('<a href="' + n + '">' + n + '</a>' for n in names)
        return self.module['select_root'](html, minor, gcc)

    def test_excludes_newer_os_prerelease_development_and_newer_compiler(self):
        expected = 'root_v6.36.06.Linux-almalinux9.6-x86_64-gcc11.5.tar.gz'
        result = self.pick([
            expected,
            'root_v6.40.04.Linux-almalinux9.8-x86_64-gcc11.5.tar.gz',
            'root_v6.38.00-rc1.Linux-almalinux9.6-x86_64-gcc11.5.tar.gz',
            'root_v6.37.02.Linux-almalinux9.6-x86_64-gcc11.5.tar.gz',
            'root_v6.36.07.Linux-almalinux9.6-x86_64-gcc11.5.tar.gz',
            'root_v6.38.00.Linux-almalinux9.6-x86_64-gcc12.2.tar.gz',
            'root_v6.38.00.Linux-almalinux9.6-x86_64-gcc11.6.tar.gz',
        ])
        self.assertEqual(result, ('6.36.06', expected))

    def test_numeric_sorting_and_older_os_are_allowed(self):
        newer = 'root_v6.36.10.Linux-almalinux9.5-x86_64-gcc11.4.tar.gz'
        self.assertEqual(self.pick([
            'root_v6.36.08.Linux-almalinux9.6-x86_64-gcc11.5.tar.gz', newer
        ]), ('6.36.10', newer))

    def test_no_compatible_binary_stops(self):
        with self.assertRaises(RuntimeError):
            self.pick(['root_v6.40.04.Linux-almalinux9.8-x86_64-gcc11.5.tar.gz'])


if __name__ == '__main__':
    unittest.main()
