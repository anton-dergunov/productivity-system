#!/usr/bin/env python3

import argparse
import json
import os
from pathlib import Path
from datetime import datetime


def format_timestamp(ts_usec):
    if not ts_usec:
        return ""

    try:
        ts = int(ts_usec) / 1_000_000
        return datetime.utcfromtimestamp(ts).isoformat() + "Z"
    except Exception:
        return ""


def load_note(json_file):
    with open(json_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    title = data.get("title", "").strip()

    text = (
        data.get("textContent")
        or data.get("text")
        or ""
    ).strip()

    created = (
        format_timestamp(data.get("createdTimestampUsec"))
        or format_timestamp(data.get("userEditedTimestampUsec"))
    )

    attachments = []

    for att in data.get("attachments", []):
        mime_type = att.get("mimetype", "")
        file_path = att.get("filePath", "")

        if file_path:
            attachments.append(file_path)

    return {
        "title": title,
        "text": text,
        "created": created,
        "source_file": json_file.name,
        "attachments": attachments,
    }


def write_org(notes, output_path):
    with open(output_path, "w", encoding="utf-8") as out:

        out.write("#+TITLE: Google Keep Export\n\n")

        for note in notes:

            title = note["title"] or "Untitled"

            out.write(f"* {title}\n")

            out.write(":PROPERTIES:\n")

            if note["created"]:
                out.write(
                    f":CREATED: {note['created']}\n"
                )

            out.write(
                f":SOURCE_FILE: {note['source_file']}\n"
            )

            out.write(":END:\n\n")

            if note["text"]:
                out.write(note["text"])
                out.write("\n\n")

            if note["attachments"]:
                out.write("** Attachments\n\n")

                for attachment in note["attachments"]:
                    out.write(
                        f"- [[file:{attachment}]]\n"
                    )

                out.write("\n")


def write_markdown(notes, output_path):
    with open(output_path, "w", encoding="utf-8") as out:

        out.write("# Google Keep Export\n\n")

        for note in notes:

            title = note["title"] or "Untitled"

            out.write(f"# {title}\n\n")

            if note["created"]:
                out.write(
                    f"Created: {note['created']}\n\n"
                )

            if note["text"]:
                out.write(note["text"])
                out.write("\n\n")

            if note["attachments"]:
                out.write("## Attachments\n\n")

                for attachment in note["attachments"]:
                    out.write(
                        f"- {attachment}\n"
                    )

                out.write("\n")

            out.write("---\n\n")


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "takeout_dir",
        help="Google Keep Takeout directory",
    )

    parser.add_argument(
        "--format",
        choices=["org", "md"],
        default="org",
    )

    parser.add_argument(
        "--output",
        default=None,
    )

    args = parser.parse_args()

    root = Path(args.takeout_dir)

    json_files = list(root.rglob("*.json"))

    notes = []

    for json_file in json_files:
        try:
            notes.append(load_note(json_file))
        except Exception as e:
            print(
                f"Skipping {json_file}: {e}"
            )

    notes.sort(
        key=lambda n: n["created"] or ""
    )

    if args.output:
        output_path = args.output
    else:
        output_path = (
            "keep_export.org"
            if args.format == "org"
            else "keep_export.md"
        )

    if args.format == "org":
        write_org(notes, output_path)
    else:
        write_markdown(notes, output_path)

    print(
        f"Exported {len(notes)} notes to {output_path}"
    )


if __name__ == "__main__":
    main()
