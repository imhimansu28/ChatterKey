#!/usr/bin/env python3
"""Check the static Pages site without network access or third-party dependencies."""
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / 'docs'
BASE = 'https://imhimansu28.github.io/ChatterKey/'
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path = path
        self.tags = []
        self.stack = []
        self.ids = []
        self.title = ''
        self.json_blocks = []
        self.feed(path.read_text())
        self.close()
        assert not self.stack, f'{path}: unclosed elements {self.stack}'

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append((tag, attrs))
        if attrs.get('id'):
            self.ids.append(attrs['id'])
        if tag not in VOID:
            self.stack.append(tag)
        if tag == 'script' and attrs.get('type') == 'application/ld+json':
            self.json_blocks.append('')

    def handle_endtag(self, tag):
        assert self.stack and self.stack[-1] == tag, f'{self.path}: unmatched closing {tag}'
        self.stack.pop()

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.handle_endtag(tag)

    def handle_data(self, data):
        if self.stack and self.stack[-1] == 'title':
            self.title += data
        if self.stack and self.stack[-1] == 'script' and self.json_blocks:
            self.json_blocks[-1] += data

    def matching(self, tag, **attrs):
        return [a for t, a in self.tags if t == tag and all(a.get(k) == v for k, v in attrs.items())]


def local_target(url):
    parsed = urlsplit(url)
    if parsed.netloc != urlsplit(BASE).netloc:
        return None
    assert parsed.path.startswith('/ChatterKey/'), f'Link escapes project site: {url}'
    path = DOCS / unquote(parsed.path.removeprefix('/ChatterKey/'))
    if path.is_dir():
        path /= 'index.html'
    assert path.is_file(), f'Missing local link/asset: {url}'
    return path


def main():
    pages = {p: Page(p) for p in DOCS.rglob('*.html')}
    canonicals, titles, descriptions = [], [], []
    for path, page in pages.items():
        label = str(path.relative_to(ROOT))
        expected = BASE + str(path.relative_to(DOCS)).removesuffix('index.html')
        assert len(page.matching('h1')) == 1, f'{label}: expected one H1'
        assert len(page.ids) == len(set(page.ids)), f'{label}: duplicate IDs'
        assert page.matching('html', lang='en'), f'{label}: missing page language'
        assert page.matching('meta', name='viewport'), f'{label}: missing viewport'
        assert page.title.strip(), f'{label}: empty title'
        assert not page.matching('meta', name='keywords'), f'{label}: unnecessary meta keywords'
        description = page.matching('meta', name='description')
        assert len(description) == 1 and description[0].get('content'), f'{label}: missing description'
        for image in page.matching('img'):
            assert all(k in image for k in ('alt', 'width', 'height')), f'{label}: image lacks alt/dimensions'
        if path.name == '404.html':
            assert page.matching('meta', name='robots', content='noindex')
            assert not page.matching('link', rel='canonical')
        else:
            assert page.matching('link', rel='canonical') == [{'rel': 'canonical', 'href': expected}], f'{label}: canonical mismatch'
            assert not page.matching('meta', name='robots', content='noindex')
            assert page.matching('meta', property='og:url', content=expected)
            assert page.matching('meta', property='og:title', content=page.title)
            assert page.matching('meta', property='og:description', content=description[0]['content'])
            assert page.matching('meta', name='twitter:card', content='summary_large_image')
            assert len(page.json_blocks) == 1
            graph = json.loads(page.json_blocks[0])['@graph']
            assert any(item['@type'] == 'WebPage' and item['url'] == expected for item in graph)
            assert not any('aggregateRating' in item or 'review' in item for item in graph), f'{label}: do not invent reviews'
            for item in graph:
                if item['@type'] == 'SoftwareApplication':
                    assert item['url'] == expected and item['offers']['price'] == 0
                    assert item['downloadUrl'] in (DOCS / 'index.html').read_text()
            social = page.matching('meta', property='og:image')
            assert len(social) == 1 and local_target(social[0]['content'])
            canonicals.append(expected)
            titles.append(page.title)
            descriptions.append(description[0]['content'])
        resources = set()
        for tag, attrs in page.tags:
            reference = attrs.get('href') if tag in ('a', 'link') else attrs.get('src') if tag in ('img', 'script') else None
            if not reference:
                continue
            url = urljoin(expected, reference)
            assert '/releases/latest' not in url, f'{label}: use explicit platform release links'
            target = local_target(url)
            if target:
                fragment = unquote(urlsplit(url).fragment)
                if fragment and target in pages:
                    assert fragment in pages[target].ids, f'{label}: broken fragment {reference}'
                if tag in ('img', 'script') or (tag == 'link' and attrs.get('rel') in ('stylesheet', 'icon', 'apple-touch-icon')):
                    resources.add(target)
                if target.suffix in ('.css', '.js'):
                    digest = hashlib.sha256(target.read_bytes()).hexdigest()[:12]
                    assert urlsplit(url).query == 'v=' + digest, f'{label}: stale asset hash for {target.name}'
            if tag in ('img', 'script') or (tag == 'link' and attrs.get('rel') == 'stylesheet'):
                assert target, f'{label}: unexpected third-party page dependency'
        weight = path.stat().st_size + sum(p.stat().st_size for p in resources)
        assert weight < 200_000, f'{label}: initial local payload over 200 KB; review assets'
        print(f'{label}: metadata, markup, links and assets passed ({weight:,} uncompressed bytes)')
    assert len(set(titles)) == len(titles) and len(set(descriptions)) == len(descriptions)
    sitemap = ET.parse(DOCS / 'sitemap.xml')
    urls = [e.text for e in sitemap.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc')]
    assert Counter(urls) == Counter(canonicals), 'Sitemap must match canonical pages, excluding 404'
    home = pages[DOCS / 'index.html']
    downloads = [a['href'] for a in home.matching('a') if urlsplit(a.get('href', '')).path.endswith(('.apk', '.zip'))]
    assert len(downloads) == 2 and len(set(downloads)) == 2, 'Keep one actual download link per platform on the homepage'
    assert {'top', 'downloads', 'how', 'features', 'use-cases', 'privacy'} <= set(home.ids), 'Preserve existing section anchors'
    assert [section.get('id') for section in home.matching('section')] == ['top', 'use-cases', 'downloads', 'faq'], 'Keep the agreed four-section reading flow'
    assert len(home.matching('figure', **{'class': 'dictation-example'})) == 1, 'Keep one illustrative demo'
    assert len(home.matching('article', **{'class': 'use-case'})) == 3, 'Keep three concrete use cases'
    assert len(home.matching('details')) == 3, 'Keep the homepage FAQ concise; use guides for setup details'
    print('Website checks passed. Local validation does not establish indexing, ranking or real-user performance.')


if __name__ == '__main__':
    main()
