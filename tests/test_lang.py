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
                  ("diff", "truncated"): ["{kib}"], ("bar", "more"): ["{n}"], ("bar", "warn_limit"): ["{tokens}"]}
        for c in codes():
            d = load(c)
            for (group, key), placeholders in needed.items():
                for p in placeholders:
                    with self.subTest(code=c, key=f"{group}.{key}", placeholder=p):
                        self.assertIn(p, d[group][key])

    def test_the_subscription_warning_has_no_money_in_it(self):
        for c in codes():
            with self.subTest(code=c):
                self.assertNotIn("{cost}", load(c)["bar"]["warn_limit"])

    def test_every_legend_row_has_a_stable_unique_id(self):
        en = load("en")
        ids = [r[2] for sec in en["sections"] for r in sec["rows"]]
        self.assertTrue(all(len(r) == 3 for sec in en["sections"] for r in sec["rows"]))
        self.assertEqual(len(ids), len(set(ids)), "duplicated ids")
        for i in ids:
            with self.subTest(id=i):
                self.assertRegex(i, r"^[a-z0-9]+(-[a-z0-9]+)*$")

    def test_ids_are_the_same_in_every_language(self):
        ref = [r[2] for sec in load("en")["sections"] for r in sec["rows"]]
        for c in codes():
            with self.subTest(code=c):
                got = [r[2] for sec in load(c)["sections"] for r in sec["rows"] if len(r) == 3]
                self.assertEqual(got, ref)

    def test_every_link_of_the_bar_points_to_an_existing_row(self):
        import re
        with open(os.path.join(ROOT, "statusline.sh"), encoding="utf-8") as f:
            used = set(re.findall(r"\bhl ([a-z0-9-]+)", f.read()))
        known = {r[2] for sec in load("en")["sections"] for r in sec["rows"]}
        self.assertTrue(used, "the bar should link its segments")
        self.assertEqual(used - known, set())

    def test_setting_names_and_symbols_are_not_translated(self):
        # The environment variable names must stay identical in every language
        for c in codes():
            blob = json.dumps(load(c), ensure_ascii=False)
            for name in ("STATUSLINE_PORT", "STATUSLINE_LANG", "STATUSLINE_RECACHE_USD_PER_MTOK", "STATUSLINE_BURN_WARN", "STATUSLINE_FILES", "STATUSLINE_MAX_FILES", "STATUSLINE_BILLING", "STATUSLINE_LINKS", "STATUSLINE_TOKEN_TTL_HOURS"):
                with self.subTest(code=c, name=name):
                    self.assertIn(name, blob)


if __name__ == "__main__":
    unittest.main()
