'''
Telluride Cloud Video Downloader.
Copyright 2020-2026 FrostWire LLC.
Author: @gubatron

A portable and easy to use yt_dlp wrapper by FrostWire.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
'''
# python path imports
from datetime import datetime
from urllib.parse import urlparse, urlunparse
import argparse
import json
import os
import sys
import yt_dlp
from yt_dlp.utils import YoutubeDLError

BUILD = 46

YOUTUBE_CONTENT_PATHS = (
    '/videos', '/streams', '/shorts', '/playlist', '/watch', '/live')
YOUTUBE_TAB_IDS = frozenset({
    'videos', 'streams', 'shorts', 'live', 'playlists', 'community',
    'featured', 'releases', 'podcasts', 'about'
})


def welcome():
    '''
    Prints the name of the program, build and copyright
    '''
    print()
    print("Telluride Cloud Video Downloader. Build " + str(BUILD))
    print(
        f"Copyright 2020-{datetime.today().year} FrostWire LLC. Licensed under Apache 2.0."
    )
    print(f"Python {sys.version}")
    print(sys.version_info)
    print(f"CWD={os.getcwd()}")
    print()


def prepare_options_parser(parser):
    '''
    Initialize all the possible program options
    '''
    parser.add_argument(
        "--audio-only",
        "-a",
        action='store_true',
        help='Downloads the video and keeps only a separate audio file' +
        ' usually a .mp3. (requires ffmpeg installed in the system)')
    parser.add_argument(
        "--meta-only",
        "-m",
        action='store_true',
        help='Prints a JSON dictionary with all the metadata available on' +
        ' the video file found in the page_url. ' +
        'Does not download the video file')
    parser.add_argument(
        "--playlist",
        "-p",
        action='store_true',
        help='Extracts playlist/channel entries (up to 50) as JSON without downloading')
    parser.add_argument(
        "page_url",
        nargs='?',
        help="The URL of the page that hosts the video you need to backup locally")


def base_ydl_opts(quiet=False):
    '''
    Shared yt-dlp options. Keep keys stable for FrostWire parsers.
    '''
    return {
        'nocheckcertificate': True,
        'quiet': quiet,
        'restrictfilenames': True,
        'trim_file_name': 200,
        'no_color': True,
    }


def normalize_youtube_channel_url(page_url):
    '''
    Point bare YouTube channel URLs at the Videos tab.
    Keeps query/fragment intact so ?si=... does not break the path.
    '''
    if 'youtube.com' not in page_url.lower():
        return page_url
    parsed = urlparse(page_url)
    path = parsed.path or ''
    if any(suffix in path.lower() for suffix in YOUTUBE_CONTENT_PATHS):
        return page_url
    new_path = path.rstrip('/') + '/videos'
    return urlunparse((parsed.scheme, parsed.netloc, new_path,
                       parsed.params, parsed.query, parsed.fragment))


def emit_json(payload):
    '''
    Print JSON the way FrostWire's TellurideParser expects: a '{' somewhere
    on stdout after the welcome banner.
    '''
    print(json.dumps(payload, indent=2, default=str))


def fail(message):
    '''
    Print an ERROR: line so TellurideParser.onError fires, then exit.
    '''
    text = str(message).strip()
    if not text.startswith('ERROR:'):
        text = f'ERROR: {text}'
    print(text)
    sys.exit(1)


def playlist_entry(entry):
    '''
    Map one yt-dlp flat entry to the TellurideJSONPlaylistEntry shape.
    '''
    if not entry:
        return None
    entry_id = entry.get('id') or ''
    if entry_id in YOUTUBE_TAB_IDS:
        return None
    url = entry.get('url') or entry.get('webpage_url') or ''
    if not url and not entry_id:
        return None
    data = {
        'id': entry_id,
        'title': entry.get('title', ''),
        'url': url,
        'webpage_url': entry.get('webpage_url') or url,
    }
    for field in ('thumbnail', 'duration', 'upload_date', 'view_count'):
        if entry.get(field) is not None:
            data[field] = entry.get(field)
    description = entry.get('description')
    if description:
        data['description'] = description[:200]
    return data


def extract_playlist(page_url):
    '''
    Flat-extract up to 50 playlist/channel entries as JSON.
    '''
    page_url = normalize_youtube_channel_url(page_url)
    opts = base_ydl_opts(quiet=True)
    opts['extract_flat'] = True
    opts['playlist_items'] = '1-50'
    opts['ignoreerrors'] = True
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(page_url, download=False)
    if not info:
        fail('Could not extract playlist metadata')
    raw_entries = info.get('entries')
    if raw_entries is None:
        raw_entries = [info]
    entries = []
    for entry in raw_entries:
        mapped = playlist_entry(entry)
        if mapped:
            entries.append(mapped)
    emit_json({
        'type': 'playlist',
        'title': info.get('title', ''),
        'extractor': info.get('extractor_key') or info.get('extractor', ''),
        'entries': entries,
    })


def extract_meta(page_url):
    '''
    Dump sanitized yt-dlp metadata JSON for a single video.
    '''
    opts = base_ydl_opts(quiet=True)
    opts['format'] = 'bestaudio/best'
    opts['noplaylist'] = True
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(page_url, download=False)
        if not info:
            fail('Could not extract video metadata')
        emit_json(ydl.sanitize_info(info))


def download_media(page_url, audio_only):
    '''
    Download the media at page_url, optionally extracting audio as mp3.
    '''
    opts = base_ydl_opts(quiet=False)
    if audio_only:
        print("Audio-only download.")
        opts['format'] = 'bestaudio/best'
        opts['postprocessors'] = [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'mp3',
            'preferredquality': '192',
        }]
    with yt_dlp.YoutubeDL(opts) as ydl:
        ydl.download([page_url])


def main():
    '''
    Main function
    '''
    welcome()
    arg_parser = argparse.ArgumentParser()
    prepare_options_parser(arg_parser)
    args, _ = arg_parser.parse_known_args()

    audio_only = args.audio_only
    meta_only = args.meta_only
    playlist = args.playlist
    page_url = args.page_url

    if page_url is None:
        print('Please pass a video page URL or "--help" for instructions\n')
        sys.exit(1)

    try:
        if playlist:
            extract_playlist(page_url)
            sys.exit(0)
        if meta_only:
            extract_meta(page_url)
            sys.exit(0)
        download_media(page_url, audio_only)
    except YoutubeDLError as err:
        fail(err)


if __name__ == '__main__':
    main()
