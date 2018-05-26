---
layout: post
title: Recommendations on the Homepage — Odysseus Development Blog
posttitle: Recommendations on the Homepage
header: 26th May 2018 — Adrian Cochrane
date: 2018-05-26 12:33:30 1200
categories: dev
---

In my [last post](https://alcinnz.github.io/Odysseus/dev/2018/05/17/new-first-launch-site.html) I stated that I would next be incorporating [those recommendations](https://alcinnz.github.io/Odysseus-recommendations) into [the newtab page](odysseus:home). And just today I managed to do so, which means that a new update is coming very soon.

I went down some dead-ends in developing this, and it required significant reworking of [my original ideas](https://alcinnz.github.io/Odysseus/dev/2018/04/20/prosody-fetch.html). So you can consider this post as superceding that last one on [Prosody](https://alcinnz.github.io/Odysseus/architecture/2017/07/21/prosody.html)'s `{ % fetch % }` tag.

## The SQLite Dead-end
SQLite has a *great* feature where their databases [are single files](https://sqlite.org/appfileformat.html), and as such can be downloaded from the web in a single request. And I originally thought it would be easiest to utilize this fact to combine the online database I've recently generated with your offline database. But in the end it turned out that approach doesn't work, and besides I wanted to do something a bit different.

The issue is that Prosody compiles all it's SQL queries [as it parses](https://alcinnz.github.io/Odysseus/dev/2018/03/18/prosody-abstraction.html) the templates, which helps to accomplish more reliability, higher performance, and nicer syntax. But it also means that all tables queried by a template must exist before it runs. And because the recommendations table would've been loaded in at runtime, this means I can't query it.

Oh well, I was halfway to that other approach anyways.

## How Does the UI Work?
To start recommendations databases are downloaded for each of the locales [specified by the OS](https://valadoc.org/glib-2.0/GLib.Intl.get_language_names.html), and cached in a new database table (in addition to the existing screenshots table). The reason I do this is to aggregate all the recommendations that might be relevant to you. Yet unfortunately this download is currently too large and incurs a [heavy performance hit](http://www.webperformancetoday.com/2012/04/02/latency-101-what-is-latency-and-why-is-it-such-a-big-deal/). Afterall [first-impressions matter](https://elementary.io/docs/human-interface-guidelines#speed-of-launch), so I'll be investigating fixes<sup title="But that can be done seperately from releasing the new update">1</sup>.

If this data is already cached in your database, Odysseus will protect your privacy<sup title="Which is an appropriate phrase to use the day after the GDPR comes into force within the EU. Though I've always respected your privacy so much I hesitate each time I have Odysseus send data over the Internet.">2</sup> by not downloading it again. If I did I would worry that [GitHub's servers](https://github.io/) (I would even worry if they were my own) were being told every time you opened a new tab, and about that constant performance tax.

Once I've done this it's a very simple matter of querying that database table in [weighted](http://www.scholarpedia.org/article/Sampling_bias)-[random](https://sqlite.org/lang_corefunc.html#random) [order](http://www.sqlitetutorial.net/sqlite-order-by/), and appending that to the topsites queries. The reason why the order is weighted is because I found that in collecting these recommendations some topics had many more links then others, and thought it was important to compensate for that bias.

All of this logic is implemented [declaratively](http://latentflip.com/imperative-vs-declarative) in Prosody & SQL.

## How Are These Pages Downloaded?
To allow the above logic to be incorporated into the template generating [odysseus:home](odysseus:home), I implemented a new template tag called `{ % fetch % }`. This allows URLs to be computed dynamically, and for the results of fetching those to be rendered via another subtemplate (which may in turn stash the values aside in your database via the `{ % query % }` tag) before continuing to render the template. Ofcourse this is by it's very nature the slowest templating tag available in Prosody.

The parser is now very straightforward. It's two subtemplates seperated by an `{ % each as % }` tag, where that tag also serves to name a variable in which to store the HTTP response. The only real catch is that the tag adjusts the autoescaping context to ensure there's no glitches in passing variables via URLs. But core Prosody already knew already knew how to do that autoescaping.

The evaluation then involves capturing all the whitespaced separated URLs outputted by the first subtemplate. Then it downloads each URL concurrenty with all the others, and waits for all of them to complete before allowing the caller to continue. Or for any failing downloads, it'll output [some JavaScript](https://developer.mozilla.org/en-US/docs/Web/API/Console/warn) to report the error nicely [within WebInspector](https://webkit.org/blog/2518/state-of-web-inspector/#console).

When a response comes in it'll first parse that response into the Prosody datamodel (or at least into something with Prosody [bindings](https://en.wikipedia.org/wiki/Language_binding)) according to their [MIMEtype](https://www.w3.org/Protocols/rfc1341/4_Content-Type.html) before using Prosody's equivalent to [UnionFS](http://unionfs.filesystems.org/) to pass that response into the second subtemplate. Currently TSV and JSON are supported, with code drafted that would support XML<sup title="I'll blog about the design of this option later once I have reason to enable it">3</sup>. The former is parsed manually with help from [DataInputStream.read_line](https://valadoc.org/gio-2.0/GLib.DataInputStream.read_line_async.html) and [string.split](https://valadoc.org/glib-2.0/string.split.html), whereas the latter two utilizes [adaptors](https://sourcemaking.com/design_patterns/adapter) around [JSON-GLib](https://valadoc.org/json-glib-1.0/index.htm) and [LibXML](https://valadoc.org/libxml-2.0/index.htm)<sup title="Also while these aren't supported yet, I had already implemented their adaptors so it took no effort to integrate them.">4</title>. 

This should all work together very nicely to communicate between Prosody templates and arbitrary websites, even if I'm currently just using it for [my own sites](https://alcinnz.github.io/Odysseus-recommendations/).

### Subtle Fixes
There's a few subtleties in getting this to work right. One of wich is to acknowledge that string.split yields strings that were seperated by individual occurrences of the given deliminator, not a sequence of those. Which would manifest as a bunch of spurious errors being reported that the empty string can't be parsed as a URL. But yet we must count that URL as having been completed in order for the template not to freeze.

A few others are with getting [LibSoup](https://valadoc.org/libsoup-2.4/index.htm) to work correctly. Specifically unsuccessful HTTP Error codes [needed to be translated](https://valadoc.org/libsoup-2.4/Soup.Message.status_code.html) into Vala/GLib errors so templates handle them correctly, and [a plugin](https://valadoc.org/libsoup-2.4/Soup.ContentSniffer.html) needed to be enabled in order to access an HTTP response's MIMEtype via LibSoup's [highlevel API](https://valadoc.org/libsoup-2.4/Soup.RequestHTTP.html). 

### Concurrency
Implementing `{ % fetch % }` nicely whilst minimizing the performance penalty of communicating back-and-forth over the Internet<sup title="SIDENOTE: Wayland's done a nice job of avoiding a similar performance pitfall by avoiding having it's conversations be back-and-forth">5</sup> required good knowledge of how to work with [Vala's async methods](https://wiki.gnome.org/Projects/Vala/AsyncSamples).

To make this work I wrote the logic of how to fetch and render HTTP responses as it's own seperate async method and ran it concurrently with the main exec method. This took advantage of Vala to make the code read very clearly whilst avoiding all the majour performance concerns.

Also I implemented a couple of synchronization primitives. The first, which resembles a [counting semaphore](https://en.wikipedia.org/wiki/Semaphore_%28programming%29), simply counts down the number of HTTP responses left to receive, and when it reaches 0 resumes execution of the rest of the template. And the second is a simple [mutex/lock/binary semaphore](https://en.wikipedia.org/wiki/Lock_(computer_science)) which keeps a flag for whether it's "locked" and before entering a "critical section" (a.k.a. rendering the subtemplate for HTTP responses, as if left unsynchronized it could potentially yield some ugly output) it checks if the mutex is locked. If it is it resumes execution the next time Odysseus is [idling](https://valadoc.org/glib-2.0/GLib.Idle.add.html) and [checks again](https://en.wikipedia.org/wiki/Spinlock), at which point it'll probably be unlocked. Both of these primitives I wrote avoid the performance overhead of threadsafe [atomic variables](https://wiki.osdev.org/Atomic_operation), and only works for the [cooperative multitasking](https://en.wikipedia.org/wiki/Cooperative_multitasking) of GLib's [mainloop](https://valadoc.org/glib-2.0/GLib.MainLoop.html).

And they both required use of a special variant of the yield statement.

### Did I Waste My Time Extending Prosody?
I really don't think so, as most of the code I added to prosody would have needed to be written anyways. I needed to fetch multiple URLs concurrently and parse their TSV files. And those things remained the bulk of the code and the trickiest to get working.

Sure a little more work (and rework) was needed to expose this API as syntax rather than an API, but the result is something that's much nicer to work with. Prosody has been a huge convenience for me in developing an increasing amount of Odysseus's UI, as it nicely complements URLs, SQL, and HTML by providing a nice syntax for moving data between them. And it does a great job of separating any performance optimization from the UI code.

It's also worth noting that I've found it's rare for Prosody extensions to be useful for a single page. And I foresee fetch being no different.

### What's Wrong With the Old Fetch?
My older implementation might've worked fine outside of any subtemplates, but that restriction harmed my ability to reuse existing code and thereby lead me needing to complicate the `{ % fetch % }` tag. Specifically I would've needed to implement a means for controlling caching within the tag rather than utilizing the preexisting `{ % query % }` tag, and (for the original UI design) I would've needed to implement a way to select just the first successful request without impacting performance more than necessary.

Specifically the issue was that the old implementation parsed the remainder of the template and held it within itself (which was necessary to pass in an extra variable, and, I thought, hold up execution long enough), which would not have worked within any subtemplates as those would no longer see their corresponding closing tags. Instead `{ % fetch % }` would've balked that those closing tags were not defined in Prosody's API.

In the end I decided it was a better anyways to use all available databases for recommendations, and rather than go about adding in those complexities I instead removed what complexities I had already placed in there.

And while I no longer have any direct way to use access the responses from a `{ % fetch % }` in the rest of the templates, perhaps that's for the best. Perhaps most of that data fits best in a database, and afterall using that side-channel worked out very nicely for `odysseus:home`. And I certainly didn't need this technique in order to hold up execution of the remainder of the template.

---

1. But [reducing download size of the recommendations files] can be done seperately from releasing the new update.
2. Which is an appropriate phrase to use the day after the GDPR comes into force within the EU. Though I've always respected your privacy so much I hesitate each time I have Odysseus send data over the Internet.
3. I'll blog about the design of this option later once I have reason to enable it.
4. Also while these aren't supported yet, I had already implemented their adaptors so it took no effort to integrate them.
5. SIDENOTE: Wayland's done a nice job of avoiding a similar performance pitfall by avoiding having it's conversations be back-and-forth.
