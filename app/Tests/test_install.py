import importlib.util
from pathlib import Path
import tomllib
import unittest

spec = importlib.util.spec_from_file_location("installer", Path(__file__).resolve().parents[1] / "install_codex_notify.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class PreserveConfiguration(unittest.TestCase):
    def test_multiline_preserves_remaining_bytes(self):
        suffix = '\nmodel = "example"\n[desktop]\nfoo = true # comment\n'
        text = '# original\nnotify = [\n  "/existing/Notifier",\n  "turn-ended",\n]\n' + suffix
        command = ["/Users/魔女/Elaina.app/notify", "--config", "/with space/config.json"]
        updated = installer.replace_notify(text, command)
        self.assertTrue(updated.startswith('# original\nnotify = '))
        self.assertTrue(updated.endswith(suffix))
        self.assertEqual(tomllib.loads(updated)["notify"], command)

    def test_insert_stays_at_user_root(self):
        text = '[projects."/example"]\ntrust_level = "trusted"\n'
        updated = installer.replace_notify(text, ["/pet"])
        self.assertTrue(updated.endswith(text))
        self.assertEqual(tomllib.loads(updated)["notify"], ["/pet"])

    def test_restore_does_not_erase_new_settings(self):
        text = 'notify = ["/pet"]\nnew_setting = 123\n'
        updated = installer.replace_notify(text, ["/original", "turn-ended"])
        self.assertIn('new_setting = 123\n', updated)
        self.assertEqual(tomllib.loads(updated)["notify"], ["/original", "turn-ended"])
        removed = installer.replace_notify(text, None)
        self.assertEqual(removed, 'new_setting = 123\n')

    def test_invalid_config_is_rejected(self):
        with self.assertRaises(tomllib.TOMLDecodeError):
            installer.replace_notify('notify = ["unterminated"', ["/pet"])


if __name__ == "__main__":
    unittest.main()
