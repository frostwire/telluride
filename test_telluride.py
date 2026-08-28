'''Tests for Telluride URL normalization.'''
import unittest

import telluride


class NormalizeYoutubeChannelUrlTest(unittest.TestCase):

    def test_channel_named_watchthis_appends_videos(self):
        url = 'https://www.youtube.com/c/watchthis'
        self.assertEqual(
            'https://www.youtube.com/c/watchthis/videos',
            telluride.normalize_youtube_channel_url(url))

    def test_watch_url_is_unchanged(self):
        url = 'https://www.youtube.com/watch?v=abc'
        self.assertEqual(url, telluride.normalize_youtube_channel_url(url))

    def test_videos_tab_is_unchanged(self):
        url = 'https://www.youtube.com/channel/UCabc/videos?si=1'
        self.assertEqual(url, telluride.normalize_youtube_channel_url(url))

    def test_bare_channel_keeps_query(self):
        url = 'https://www.youtube.com/@frostwire?si=abc'
        self.assertEqual(
            'https://www.youtube.com/@frostwire/videos?si=abc',
            telluride.normalize_youtube_channel_url(url))


if __name__ == '__main__':
    unittest.main()
