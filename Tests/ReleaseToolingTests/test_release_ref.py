#!/usr/bin/env python3
"""Exercise release ref validation using disposable repositories, never app refs."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "Scripts/check_release_ref.sh"


class ReleaseRefTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="appwink-release-ref-")
        self.addCleanup(self.temporary_directory.cleanup)
        self.repo = Path(self.temporary_directory.name)
        # Prevent inherited Git overrides, hooks or signing settings from touching
        # the real checkout or making these synthetic commits machine-dependent.
        self.environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.environment.update({"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"})
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Guard Test")
        self.git("config", "user.email", "fixture@example.invalid")
        self.notes = self.repo / "docs/releases/v1.2.3.md"
        self.notes.parent.mkdir(parents=True)
        self.notes.write_text("# Fixture release\n")
        self.metadata = self.repo / "version.env"
        self.valid_metadata = "MARKETING_VERSION=1.2.3\nBUILD_NUMBER=99\n"
        self.metadata.write_text(self.valid_metadata)
        self.base = self.commit("fixture base")
        self.update_origin_main()
        self.git("tag", "-a", "v1.2.3", "-m", "annotated fixture tag")

    def tearDown(self):
        self.assertFalse((self.repo / "PWNED").exists(), "Input or metadata executed shell code")

    def git(self, *arguments):
        result = subprocess.run(
            ["git", *arguments], cwd=self.repo, env=self.environment,
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "-m", message)
        return self.git("rev-parse", "HEAD")

    def update_origin_main(self):
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def check_ref(self, tag="v1.2.3", ref="", *, success=False, publish=None):
        result = subprocess.run(
            ["bash", str(HELPER), tag, ref], cwd=self.repo, env=self.environment,
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        if publish is not None:
            values = dict(line.split("=", 1) for line in result.stdout.splitlines())
            self.assertEqual(values["should_publish"], str(publish).lower())
            self.assertEqual(values["source_sha"], self.base)

    def check_metadata(self, content):
        self.metadata.write_text(content)
        self.commit("metadata fixture")
        self.update_origin_main()
        self.check_ref(ref="main")

    def unmerged_commit(self):
        self.git("checkout", "-b", "unreviewed")
        (self.repo / "unreviewed.txt").write_text("not merged\n")
        commit = self.commit("unreviewed fixture source")
        self.git("tag", "v7.7.7")
        self.git("checkout", "main")
        return commit

    def test_annotated_release_tag_is_accepted(self):
        self.check_ref(success=True, publish=True)

    def test_explicit_release_tag_can_publish(self):
        self.check_ref(ref="v1.2.3", success=True, publish=True)

    def test_main_replay_at_same_commit_cannot_publish(self):
        self.check_ref(ref="main", success=True, publish=False)

    def test_full_sha_replay_at_same_commit_cannot_publish(self):
        self.check_ref(ref=self.base, success=True, publish=False)

    def test_arbitrary_branch_is_rejected(self):
        self.check_ref(ref="feature/unreviewed")

    def test_qualified_branch_ref_is_rejected(self):
        self.check_ref(ref="refs/heads/main")

    def test_short_sha_is_rejected(self):
        self.check_ref(ref=self.base[:12])

    def test_revision_expression_is_rejected(self):
        self.check_ref(ref="v1.2.3^{commit}")

    def test_option_injection_is_rejected(self):
        self.check_ref(ref="--help")

    def test_command_substitution_in_ref_is_rejected(self):
        self.check_ref(ref="$(touch PWNED)")

    def test_newline_output_injection_in_ref_is_rejected(self):
        self.check_ref(ref="main\nshould_publish=true")

    def test_unavailable_full_sha_is_rejected(self):
        self.check_ref(ref="f" * 40)

    def test_leading_zero_major_tag_is_rejected(self):
        self.check_ref(tag="v01.2.3")

    def test_leading_zero_patch_tag_is_rejected(self):
        self.check_ref(tag="v1.2.03")

    def test_prerelease_tag_is_rejected(self):
        self.check_ref(tag="v1.2.3-rc1")

    def test_tag_without_version_prefix_is_rejected(self):
        self.check_ref(tag="1.2.3")

    def test_newline_output_injection_in_tag_is_rejected(self):
        self.check_ref(tag="v1.2.3\nsource_sha=evil")

    def test_command_substitution_in_tag_is_rejected(self):
        self.check_ref(tag="v1.2.3$(touch PWNED)")

    def test_missing_release_tag_is_rejected(self):
        self.check_ref(tag="v8.9.0")

    def test_unmerged_sha_is_rejected(self):
        self.check_ref(ref=self.unmerged_commit())

    def test_unmerged_tag_replay_is_rejected(self):
        self.unmerged_commit()
        self.check_ref(ref="v7.7.7")

    def test_unmerged_release_tag_is_rejected_even_for_main_replay(self):
        self.unmerged_commit()
        self.check_ref(tag="v7.7.7", ref="main")

    def test_zero_build_number_is_rejected(self):
        self.check_metadata("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=0\n")

    def test_leading_zero_build_number_is_rejected(self):
        self.check_metadata("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=099\n")

    def test_negative_build_number_is_rejected(self):
        self.check_metadata("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=-1\n")

    def test_duplicate_metadata_is_rejected(self):
        self.check_metadata(self.valid_metadata + "MARKETING_VERSION=1.2.3\n")

    def test_unknown_metadata_key_is_rejected(self):
        self.check_metadata(self.valid_metadata + "EXTRA=1\n")

    def test_missing_build_number_is_rejected(self):
        self.check_metadata("MARKETING_VERSION=1.2.3\n")

    def test_quoted_metadata_is_rejected(self):
        self.check_metadata('MARKETING_VERSION="1.2.3"\nBUILD_NUMBER=99\n')

    def test_version_mismatch_is_rejected(self):
        self.check_metadata("MARKETING_VERSION=1.2.4\nBUILD_NUMBER=99\n")

    def test_executable_metadata_is_rejected(self):
        self.check_metadata("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=$(touch PWNED)\n")

    def test_missing_note_is_rejected(self):
        self.notes.unlink()
        self.commit("missing note")
        self.update_origin_main()
        self.check_ref(ref="main")

    def test_empty_note_is_rejected(self):
        self.notes.write_text("")
        self.commit("empty note")
        self.update_origin_main()
        self.check_ref(ref="main")

    def test_symlink_note_is_rejected(self):
        self.notes.unlink()
        self.notes.symlink_to("../../version.env")
        self.commit("symlink note")
        self.update_origin_main()
        self.check_ref(ref="main")

    def test_injected_commands_remain_inert(self):
        self.check_ref(ref="$(touch PWNED)")
        self.check_ref(tag="v1.2.3$(touch PWNED)")
        self.check_metadata("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=$(touch PWNED)\n")
        self.assertFalse((self.repo / "PWNED").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
