---
title: w-help
section: reference
order: 0
summary: Open the W documentation in the Help window.
---

`w-help` — Open the W documentation in the Help window.

## Usage

```
Usage: w-help [page[#anchor]] [--search query]

Info: Open the W documentation in the Help window.

Arguments:
  page            A documentation page, as its Markdown path or without the
                  extension: guide/updates, guide/updates.md, faq, recovery.
                  Default: the index. An already open window with no page given
                  is only focused
  #anchor         A heading on the page (its slug, as in the Hub's help links)

Options:
  --search QUERY  Open the page with QUERY already searched
  -h, --help      Show this help

Exit codes:
  0  Success   1  Runtime error (no such page)   2  Usage error

Examples:
  w-help
  w-help guide/updates#where-you-see-updates
  w-help --search snapshot
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-help help`.
