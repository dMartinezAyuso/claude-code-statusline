"""Every language file must have exactly the same shape as the English one."""
import glob
import json
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANG_DIR = os.path.join(ROOT, "lang")
EXPECTED = {"en", "es", "fr", "pt", "de"}


def load(code):
    with open(os.path.join(LANG_DIR, f"{code}.json"), encoding="utf-8") as f:
        return json.load(f)


def codes():
    return sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(LANG_DIR, "*.json")))


class Languages(unittest.TestCase):
    def test_expected_languages_exist(self):
        self.assertTrue(EXPECTED.issubset(set(codes())), codes())

    def test_file_names_are_two_letter_codes(self):
        for c in codes():
            with self.subTest(code=c):
                self.assertRegex(c, r"^[a-z]{2}$")

    def test_same_keys_as_english(self):
        en = load("en")
        for c in codes():
            d = load(c)
            for group in ("bar", "page", "diff"):
                with self.subTest(code=c, group=group):
                    self.assertEqual(sorted(d[group]), sorted(en[group]))

    def test_same_help_shape_as_english(self):
        en = load("en")["sections"]
        for c in codes():
            d = load(c)["sections"]
            with self.subTest(code=c):
                self.assertEqual([len(s["rows"]) for s in d], [len(s["rows"]) for s in en])

    def test_no_empty_strings(self):
        for c in codes():
            d = load(c)
            texts = [v for g in ("bar", "page", "diff") for v in d[g].values()]
            texts += [x for s in d["sections"] for x in [s["title"]] + [t for r in s["rows"] for t in r]]
            with self.subTest(code=c):
                self.assertTrue(all(isinstance(t, str) and t.strip() for t in texts))

    def test_placeholders_are_kept(self):
        needed = {("bar", "warn"): ["{tokens}", "{cost}"], ("diff", "title"): ["{repo}", "{count}"],
                  ("diff", "truncated"): ["{kib}"], ("bar", "more"): ["{n}"]}
        for c in codes():
            d = load(c)
            for (group, key), placeholders in needed.items():
                for p in placeholders:
                    with self.subTest(code=c, key=f"{group}.{key}", placeholder=p):
                        self.assertIn(p, d[group][key])

    def test_setting_names_and_symbols_are_not_translated(self):
        # The environment variable names must stay identical in every language
        for c in codes():
            blob = json.dumps(load(c), ensure_ascii=False)
            for name in ("STATUSLINE_PORT", "STATUSLINE_LANG", "STATUSLINE_RECACHE_USD_PER_MTOK", "STATUSLINE_BURN_WARN", "STATUSLINE_FILES", "STATUSLINE_MAX_FILES"):
                with self.subTest(code=c, name=name):
                    self.assertIn(name, blob)


if __name__ == "__main__":
    unittest.main()
