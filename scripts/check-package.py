#!/usr/bin/env python3
"""Build a synthetic consumer using only the unpacked Hex archive."""
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

root = Path(__file__).resolve().parent.parent
archives = list(root.glob("otp_form_assistant-*.tar"))
if len(archives) != 1:
    raise SystemExit("Build exactly one package archive before this check.")

with tarfile.open(archives[0]) as archive:
    contents = archive.extractfile("contents.tar.gz").read()

with tempfile.TemporaryDirectory(prefix="otp-form-assistant-") as directory:
    directory = Path(directory)
    package = (directory / "package").resolve()
    package.mkdir()
    with tarfile.open(fileobj=io.BytesIO(contents), mode="r:gz") as archive:
        names = archive.getnames()
        if any("plts" in Path(name).parts or name.startswith(("test/", "config/")) for name in names):
            raise SystemExit("The package includes development-only files.")
        for member in archive.getmembers():
            destination = (package / member.name).resolve()
            if not destination.is_relative_to(package) or not (member.isfile() or member.isdir()):
                raise SystemExit(f"Unexpected archive entry: {member.name}")
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.extractfile(member).read())

    consumer = directory / "consumer"
    shutil.copytree(root / "examples/consumer", consumer)
    environment = dict(os.environ, MIX_ENV="test", FORM_ASSISTANT_SOURCE=str(package))
    for command in (["mix", "deps.get"], ["mix", "compile", "--warnings-as-errors"], ["mix", "test"]):
        subprocess.run(command, cwd=consumer, env=environment, check=True)

print("Unpacked package consumer passed.")
