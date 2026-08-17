#!/usr/bin/env python3
"""Tests for the ESH release metadata tool (scripts/release/release.py).

Executable behavior under test: version parsing, tag parsing, Flutter version
parsing, and the consistency checks that keep root VERSION, Flutter build-name,
and the release tag from drifting.

Run: python scripts/release/test_release.py
"""

import unittest

from release import (
    ReleaseError,
    check_flutter_matches_root,
    check_tag_matches_root,
    parse_flutter_version,
    parse_semver,
    parse_tag,
)


class ParseSemVerTests(unittest.TestCase):
    def test_valid_versions(self):
        for text in ["0.1.0", "1.0.0", "1.12.3"]:
            with self.subTest(text=text):
                self.assertEqual(parse_semver(text), tuple(int(p) for p in text.split(".")))

    def test_invalid_versions(self):
        for text in ["1", "1.0", "v1.0.0", "01.0.0", "1.0.0-alpha", "1.0.0+build", ""]:
            with self.subTest(text=text):
                with self.assertRaises(ReleaseError):
                    parse_semver(text)


class ParseTagTests(unittest.TestCase):
    def test_valid_tag(self):
        self.assertEqual(parse_tag("esh-v1.0.0"), "1.0.0")
        self.assertEqual(parse_tag("esh-v0.1.0"), "0.1.0")

    def test_invalid_tags(self):
        invalid = [
            "v1.0.0",
            "esh-1.0.0",
            "esh-v1",
            "esh-v1.0",
            "esh-v01.0.0",
            "esh-v1.0.0-extra",
            "esh-v1.0.0.0",
        ]
        for tag in invalid:
            with self.subTest(tag=tag):
                with self.assertRaises(ReleaseError):
                    parse_tag(tag)


class ParseFlutterVersionTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(parse_flutter_version("1.2.0+7"), ("1.2.0", 7))

    def test_build_number_may_differ_from_root(self):
        # Build number is not part of the coordinated version identity.
        self.assertEqual(parse_flutter_version("1.2.0+7"), ("1.2.0", 7))
        self.assertEqual(parse_flutter_version("1.2.0+42"), ("1.2.0", 42))

    def test_invalid(self):
        for text in ["1.0", "1.0.0", "v1.0.0+1", "01.0.0+1", "1.0.0+x"]:
            with self.subTest(text=text):
                with self.assertRaises(ReleaseError):
                    parse_flutter_version(text)


class ConsistencyTests(unittest.TestCase):
    def test_tag_matches_root(self):
        check_tag_matches_root("1.2.0", "1.2.0")

    def test_tag_mismatch_fails(self):
        with self.assertRaises(ReleaseError):
            check_tag_matches_root("1.2.0", "1.2.1")

    def test_flutter_matches_root(self):
        check_flutter_matches_root("1.2.0", "1.2.0")

    def test_flutter_mismatch_fails(self):
        with self.assertRaises(ReleaseError):
            check_flutter_matches_root("1.3.0", "1.2.0")


if __name__ == "__main__":
    unittest.main()
