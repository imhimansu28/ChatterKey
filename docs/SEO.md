# Website maintenance and search visibility

The website is static HTML/CSS/JavaScript served from `docs` at the GitHub Pages project path `/ChatterKey/`. There is no frontend build, external font, analytics script, cookie banner dependency or runtime content fetch. Existing top-level section links remain supported. Historical Markdown release notes and README assets are retained.

## Content and search intent

These are editorial targets based on shipped functionality, **not measured search-volume or ranking claims**:

| Page | Primary intent | Distinct useful content |
| --- | --- | --- |
| `/ChatterKey/` | Open-source voice typing for Mac and Android | Product overview, examples, provider costs/privacy, two platform downloads, common questions |
| `/ChatterKey/macos/` | Mac voice typing / Fn dictation / selected-text voice editing | Mac-specific permissions, installation, hands-free controls, Accessibility and Copy recovery |
| `/ChatterKey/android/` | Android voice keyboard / keyboard APK setup | English (India) layout, enabling the IME, microphone, private counters and all-profile debug migration |

Use these phrases naturally in titles, headings, descriptions and explanatory links. Do not add a meta-keywords tag, repeated keyword lists, hidden SEO text, fake download totals/reviews, unsupported speed/accuracy claims or unshipped platform features. Examples are explicitly illustrative, not live demos or screenshots. Provider fees, cloud processing and platform limitations remain visible.

Keep the homepage's **two actual file-download buttons** together in `#downloads`. Header, hero, footer and platform guides navigate there instead of repeating binary-download buttons. Checksum links are supplementary text links, not additional installation CTAs.

## Homepage structure

Keep one reading flow: **hero → three everyday use cases → platform downloads → three essential questions**. Use direct headings and one illustrative dictation example. Do not add another demo, tabbed studio, decorative sculpture, feature grid or large footer slogan. The light ivory/sage palette is retained; content priority, not additional visual decoration, is the design constraint.

The example uses prewritten HTML text, not a live recording, benchmark or app screenshot. There is no replay control, animation loop or graphics engine. The shared script only operates the mobile navigation. Main content and native FAQ disclosures work without JavaScript; reduced-motion preferences also disable smooth scrolling and button transitions.

Keep provider fees, the API-key requirement and internet dependency near the download decision. Mac signing and Android distribution/testing limitations remain visible in the platform cards, not hidden in an accordion. Detailed permissions, protected-value checks, recovery, storage and setup belong in the existing platform guides; a concise FAQ links to privacy and editing guidance.

Historical `#how`, `#features` and `#privacy` fragments remain meaningful targets on the consolidated page. The website checker enforces the four-section order, one demo, three use cases and three FAQ disclosures. Validate reading order and screenshots as well as technical checks; passing tests does not establish design quality or production approval.

## Before publishing

```bash
python3 Scripts/check-website.py
node --check docs/script.js
bash Scripts/check-public.sh
```

Use a local server that serves **only `docs`**, mounted at `/ChatterKey/`, to exercise the same project-relative paths as production. Do not serve the repository root: that can expose ignored local files. Test desktop, 320/390 px widths, enlarged text, no-JavaScript navigation, reduced motion, keyboard menu/FAQ, deep links, and the final footer link in a short viewport. The custom `404.html` uses absolute project paths so nested missing URLs can recover; GitHub Pages must return an actual 404 status.

Each indexable page has a distinct title/description, one H1, self-canonical URL, Open Graph/Twitter metadata and matching visible content. The sitemap lists only the three canonical HTML pages. The 404 page is noindex and excluded. Social art is a local 1200 × 630 PNG; the small header icon avoids loading the large original asset. Keep the original assets needed by README/history.

The platform pages describe their real `SoftwareApplication` entities, OS, version and free app offer; AI usage is separately billed. **No rating or review is fabricated.** Google currently requires an eligible rating/review for its software-app rich result, so this markup is descriptive, not a claim of rich-result eligibility. We do not promise FAQ rich results or rankings.

On a platform release, update its version, requirement/caveat text, named download/checksum URLs, platform-page JSON-LD, and release-note links together. Keep the explicit Mac/Android tag convention. Update the CSS/JS query hashes in all HTML pages whenever those assets change. Refresh social metadata/art when the product positioning changes.

## After deployment: work that cannot be proven locally

1. Verify the live canonical URLs and assets return successfully, the unknown-page route returns 404, and the host's root robots policy allows crawling.
2. In the owner's Google Search Console, verify a **URL-prefix property** for `https://imhimansu28.github.io/ChatterKey/` using an approved ownership method. No verification token is included or account access assumed by this change.
3. Submit `https://imhimansu28.github.io/ChatterKey/sitemap.xml`. Inspect the homepage and two platform URLs and request indexing if appropriate. Submission is a hint, not a guarantee of crawling or indexing.
4. Check the live pages with Rich Results Test and PageSpeed Insights. Distinguish a local lab result from real-user Core Web Vitals; do not advertise an unmeasured score.
5. Use Search Console's page/query reports to track organic impressions, clicks, CTR and actual search terms over time. Review useful landing pages and whether search snippets accurately describe them. No download-event tracking or analytics backend has been added; those require a separate privacy/consent decision.
6. Improve content from real support questions. A concise, tested setup/recovery guide is preferable to many nearly identical keyword pages. Share accurate release/setup material in relevant communities under their rules; no bought links, spam posts or traffic guarantees.

### GitHub Pages robots limitation

Google reads robots.txt at the **host root**, `https://imhimansu28.github.io/robots.txt`, not `/ChatterKey/robots.txt`. Adding a file inside this project's `docs` directory would not control the host's crawler policy. This change deliberately does not add a misleading project-subdirectory robots.txt or modify a separate website/repository. Submit the sitemap through Search Console; manage host-root robots rules only with explicit authorization. No `robots.txt` is required merely to permit crawling when the root policy is absent.

## Primary references

- [Google SEO Starter Guide](https://developers.google.com/search/docs/fundamentals/seo-starter-guide)
- [Helpful, people-first content](https://developers.google.com/search/docs/fundamentals/creating-helpful-content)
- [Canonical URLs](https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls)
- [Building and submitting a sitemap](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)
- [robots.txt location and rules](https://developers.google.com/crawling/docs/robots-txt/create-robots-txt)
- [Software-app structured data requirements](https://developers.google.com/search/docs/appearance/structured-data/software-app)
