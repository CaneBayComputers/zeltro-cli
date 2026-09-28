# Docs

`guide/` holds the user guide as markdown. It is the source of truth for
<https://zeltro.build/guide/>.

## How it gets published

The guide is **not** a static site build. These files are rendered by the
zeltro.build web app (`App\Support\Guide`), a Laravel app, inside the same
layout as the rest of the site. Production caches each rendered page until the
file changes or the next deploy clears the cache. Publishing is a file copy:

    docs/guide/*.md  ->  <site>/resources/guide/  ->  rendered by the app

`deploy.sh guide` in the site project does the copy, then commits and pushes it
to the site repo, because production deploys from GitHub. Plain `deploy.sh`
does that and deploys the site. It refuses to run if this checkout is behind
its remote. There is no toolchain to install and no build step to run.

## Editing

Write plain GitHub-flavoured markdown. Two conventions carry over from the
guide's Jekyll days and are still honoured:

- **Front matter** sets the page title and its position in the sidebar:

      ---
      title: Installation
      nav_order: 2
      ---

- **Callouts** are a kramdown attribute line placed directly *before* the
  paragraph or blockquote it applies to:

      {: .warning }
      Zeltro starts your agent in a high-trust mode.

  `note`, `warning`, `important` and `highlight` are styled. The marker must
  come before the block, not after it.

Link between pages with a sibling-relative path and a trailing slash --
`[Cheap models](../cheap-models/)` -- so the link works both in the rendered
site and when reading the markdown on GitHub.

Adding a `.md` file here is all that is needed to add a page: the sidebar and
`sitemap.xml` are both generated from this directory.

## What used to be here

Until August 2026 this directory was a Jekyll site (just-the-docs) published by
GitHub Pages at podiumcli.com, and it also held the marketing pages. The site
now lives on its own server and podiumcli.com redirects to zeltro.build, so the
Jekyll config, Gemfile, theme CSS and the old `index.html` / `donate.html` were
removed on 2026-08-22. The guide markdown is the only part still in use. The
logo, favicon, social card and theme screenshot images in this directory are
left over; nothing in this repo references them.

A machine that built the old site may still have a `docs/.jekyll-cache/`
directory. It is Jekyll's build cache, is not tracked in git (it ignores
itself), and can be deleted.
