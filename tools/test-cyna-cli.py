"""Verify Cyna CLI inspection aliases, output files, and failure envelopes."""

from pathlib import Path
import os
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("CYNA_WEIV_BINARY", ROOT / "cyna-out/bin/weiv"))
FIXTURE = "test/examples/basic/basic-counter.weiv"


def invoke(*args: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        (str(BINARY), *args),
        cwd=ROOT,
        check=False,
        capture_output=True,
    )


def assert_equal(left: bytes, right: bytes, label: str) -> None:
    if left != right:
        raise AssertionError(f"{label} differs")


def main() -> None:
    assert BINARY.exists(), f"missing Cyna Weiv binary: {BINARY}"
    diagnostics = (
        ("emit", "ast"),
        ("emit", "sir"),
        ("emit", "lir"),
        ("emit", "render-tree"),
        ("emit", "browser-plan"),
        ("emit", "invalidation-graph"),
    )
    aliases = {
        ("inspect", "lir"): ("emit", "lir"),
        ("inspect", "ir"): ("emit", "lir"),
        ("inspect", "render-tree"): ("emit", "render-tree"),
        ("inspect", "browser-plan"): ("emit", "browser-plan"),
        ("inspect", "invalidation-graph"): ("emit", "invalidation-graph"),
    }

    with tempfile.TemporaryDirectory(prefix="weiv-cyna-cli-") as directory:
        output = Path(directory)
        for index, form in enumerate(diagnostics):
            direct = invoke(*form, FIXTURE)
            assert direct.returncode == 0, " ".join(form)
            compile_form = invoke("compile", *form, FIXTURE)
            assert_equal(compile_form.stdout, direct.stdout, f"compile {' '.join(form)}")
            assert_equal(compile_form.stderr, direct.stderr, f"compile {' '.join(form)} stderr")

            emitted = output / f"diagnostic-{index}.txt"
            result = invoke(*form, FIXTURE, str(emitted))
            assert result.returncode == 0, " ".join(form)
            assert result.stdout == b""
            assert emitted.read_bytes() == direct.stdout

            compile_emitted = output / f"compile-diagnostic-{index}.txt"
            result = invoke("compile", *form, FIXTURE, str(compile_emitted))
            assert result.returncode == 0, f"compile {' '.join(form)}"
            assert result.stdout == b""
            assert compile_emitted.read_bytes() == direct.stdout

        for alias, form in aliases.items():
            expected = invoke(*form, FIXTURE)
            actual = invoke(*alias, FIXTURE)
            assert actual.returncode == expected.returncode
            assert_equal(actual.stdout, expected.stdout, " ".join(alias))
            assert_equal(actual.stderr, expected.stderr, " ".join(alias))

        for command in ("inspect-project", "build-browser"):
            result = invoke(command, FIXTURE, str(output / "unused"))
            expected = invoke()
            assert result.returncode == 0
            assert_equal(result.stderr, expected.stderr, f"{command} usage")

        missing = output / "missing.weiv"
        for form in (("emit", "lir"), ("analyze", "component"), ("validate", "app")):
            text = invoke(*form, str(missing))
            structured = invoke("--json-diagnostics", *form, str(missing))
            assert text.returncode == 1
            assert structured.returncode == 1
            assert b"cli.read_failed" in text.stderr or b"app.validate_failed" in text.stderr
            assert b'"ok": false' in structured.stderr

    print("Cyna CLI inspection, alias, output, and failure checks passed")


if __name__ == "__main__":
    main()
