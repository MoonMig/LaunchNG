#!/usr/bin/env python3
"""Prepend a release entry to appcast.xml (repo root), creating the feed if
it doesn't exist yet. Used by scripts/release.sh and
scripts/release-notarized.sh after signing the release zip with
scripts/sparkle-tools/bin/sign_update.

Usage:
    update_appcast.py <repo-root> <version> <zip-name> <sign_update-output>

<sign_update-output> is the raw stdout of `sign_update <zip>`, e.g.:
    sparkle:edSignature="BASE64..." length="12345"
"""
import datetime
import pathlib
import sys

def main() -> None:
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)

    root_dir = pathlib.Path(sys.argv[1])
    version = sys.argv[2]
    zip_name = sys.argv[3]
    sig_attrs = sys.argv[4].strip()
    appcast_path = root_dir / "appcast.xml"

    pub_date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    download_url = f"https://github.com/MoonMig/LaunchNG/releases/download/v{version}/{zip_name}"
    notes_url = f"https://github.com/MoonMig/LaunchNG/releases/tag/v{version}"

    item = f"""    <item>
      <title>Version {version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>{notes_url}</sparkle:releaseNotesLink>
      <enclosure url="{download_url}" {sig_attrs} type="application/octet-stream" />
    </item>
"""

    if appcast_path.exists():
        text = appcast_path.read_text(encoding="utf-8")
        insert_at = text.index("<item>") if "<item>" in text else text.index("</channel>")
        text = text[:insert_at] + item + text[insert_at:]
    else:
        text = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>LaunchNG</title>
    <link>https://raw.githubusercontent.com/MoonMig/LaunchNG/main/appcast.xml</link>
    <description>LaunchNG update feed.</description>
    <language>en</language>
{item}  </channel>
</rss>
"""

    appcast_path.write_text(text, encoding="utf-8")
    print(f"Updated {appcast_path} with version {version}")


if __name__ == "__main__":
    main()
