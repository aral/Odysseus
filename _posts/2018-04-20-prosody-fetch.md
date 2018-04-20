---
layout: post
title: Incorporating webdata into templates — Odysseus Development Blog
posttitle: Incorporating WebData Into Templates
header: 20th April 2018 — Adrian Cochrane
date: 2018-04-20 23:15:30 1200
categories: dev
---

One of the best things about the Web is that you can take data from multiple sites and combine them into your own display, [even if](https://ar.al/notes/how-web-2-0-killed-the-internet/) most people celebrating that fact are really trying to get you to improve the value of their silos for free. But nevertheless it was a feature I wanted to incorporate into [Prosody](https://alcinnz.github.io/Odysseus/architecture/2017/07/21/prosody.html). And today I drafted the code to make it work, in what is essentially Prosody [bindings](https://en.wikipedia.org/wiki/Language_binding) for [LibSoup](https://valadoc.org/libsoup-2.4/index.htm).

The syntax for this tag is very simple. It's a block templating-tag where all the [URLs](https://kb.iu.edu/d/adnz) listed upon executing it's body are fetched for their results to be made available in a variable specified by the end tag. The HTTP requests occur [concurrently (but not in-parallel)](http://tutorials.jenkov.com/java-concurrency/concurrency-vs-parallelism.html) so the whole operation only takes as long as the slowest request. And if the data is [XML](https://www.xmlfiles.com/xml/) or [JSON](https://json.org/) it will be parsed by [libXML](https://valadoc.org/libxml-2.0/index.htm) or [JSON-GLib](https://valadoc.org/json-glib-1.0/index.htm) respectively, and otherwise it will be accessible as a filepath. The latter case is mostly just useful for "attaching" [SQLite files](https://sqlite.org/appfileformat.html) onto Odysseus's active database connection.

Implementing this wasn't really that hard, as all it needed was:

1. For it's parser to parse the rest of the template as a trailing "subtemplate", so that a new variable could be added to it's context.
2. To keep a makeshift [mutex](https://en.wikipedia.org/wiki/Mutual_exclusion) (a.k.a. a counter of active HTTP connections) to determine when to execute that tailing subtemplate.

## Why do I want this?
Most pressingly, I wanted to fill in gaps of the topsites with localized links I (or the people localizing Odysseus) would [recommend to you](https://alcinnz.github.io/Odysseus-recommendations/). And this tag will allow me to fetch SQLite databases I provide on that GitHub pages site and load them into the local database. I promise this'll only be a first-launch thing, so as to keep [odysseus:home](odysseus:home) performant and to better protect your [privacy](https://ar.al/notes/the-nature-of-the-self-in-the-digital-age/).

But I could've done that without this tag. What I really want it for is when I'll eventually implement builtin [federated-search](https://www.searx.me/). Because then I'll want to fetch search results from ([compatible](https://github.com/dewitt/opensearch)) sites you've registered with Odysseus.That'll be hard to achieve without this tag.
