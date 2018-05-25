---
layout: post
title: Recommendations on the Homepage — Odysseus Development Blog
posttitle: Recommendations on the Homepage
header: 25th May 2018 — Adrian Cochrane
date: 2018-05-25 23:39:21 1200
categories: dev
---

In the last post I stated that my next task would be to incorporate those topsites into the newtab page. And just today I managed to do so, which means that a new update is coming very soon.

I went down some dead-ends in developing this, and it required significant reworking of my original ideas of how Prosody's {%% fetch %%} tag should work. So you can consider this post as superceding the last one on {%% fetch %%}.

## The SQLite Dead-end
SQLite has a *great* feature where their databases are single files, and as such can be downloaded from the web in a single request. And I originally thought it would be easiest to use this to combine the online database I've described in my last post with the offline database. But in the end it turned out that approach doesn't work, and besides I wanted to use a different approach where I consolidated all the databases together for all the user's locales.

The issue is that Prosody compiles all it's SQL queries as it parses the templates, which helps to accomplish more reliability, higher performance, and nicer syntax. It also means that all tables queried by a template must exist before it runs. And because the recommendations table would've been loaded in at runtime, this means I can't query it. Oh well, I was halfway to another approach anyways.

## How Does the UI Work?
Upon first launch localized databases (currently only an English one is available) are downloaded for each of the locales specified by the OS, and cached in a new database table (in addition to the existing screenshots table). The reason I do this is to collect all the recommendations that might be relevant to you. Unfortunately this download is currently too large and concurs a heavier performance hit then I'm happy with. Afterall first-impressions matter, so I'll be investigating how to improve this<sup title="But that can be done seperately from releasing the new update">1</sup>.

If this data is already cached in your database, Odysseus will protect your privacy<sup title="Which is an appropriate phrase to use on the day the GDPR comes into force within the EU. Though I've already respected your privacy so much I consider the privacy implications of every time Odysseus hits the Internet.">2</sup> by not downloading it again. If I did I would worry that GitHub's servers (I would even worry if they were my own) were being told every time you opened a new tab, and about the constant performance tax.

Once I've done this it's a very simple matter of querying that database table in weighted-random order, and appending that to the topsites queries. The reason why the order is weighted is because I found that in collecting these recommendations some topics had many more links then others, and I didn't think it was appropriate for me to push one of those topics over the other. The weighted randomness adjusts for this bias.

All of this logic is implemented declaratively in Prosody & SQL.

## How Are These Pages Downloaded?
To allow the above logic to be incorporated into the template for [odysseus:home](odysseus:home), I implemented a new template tag called `{ % fetch % }`. This allows URLs to be computed dynamically, and for the results of fetching each one of those to be rendered via another subtemplate (which may in turn stash the values aside in a database via the `{ % query % }` tag) before continuing to render the template. Ofcourse this is by it's very nature the slowest templating tag available in Prosody.

The parser is now very straightforward. It's two subtemplates seperated by an {% each as %} tag, where that tag also serves to name a variable for the HTTP response. The only real catch is that the tag adjusts the autoescaping context for you to ensure there's no glitches in passing variables via URLs. From there core Prosody already knows how to autoescape all variable values.

The evaluation then involves capturing all the whitespaced separated URLs outputted by the first subtemplate. Then it downloads each URL concurrenty with all the others, and waits for them all to complete before allowing the caller to continue. Or for any failing downloads, it'll output some JavaScript to report the error nicely within WebInspector.

When a response comes in it'll first parse that response into the Prosody datamodel (or at least something with Prosody bindings) before using Data.Stack to pass that response into the second subtemplate. Currently TSV and JSON are supported, with code drafted that would support XML<sup title="I'll blog about the design of this option once I have reason to enable it">3</sup>. The former is parsed manually with help from DataInputStream.read_line and string.split, whereas the latter two utilizes adaptors around LibJSON-GLib and LibXML.

This should all work together very nicely to communicate between Prosody templates and arbitrary websites, even if I'm currently just using it for my own sites.

### Subtle Fixes
There's a few subtleties in getting this to work right. One of wich is to acknowledge that string.split yields strings that were seperated by individual occurrences of the given deliminator, not a sequence of those. Which would translate to a bunch of spurious errors being reported that the empty string can't be parsed as a URL. But yet we must count that URL as having been completed in order for the template not to freeze.

A few others are with getting LibSoup to work correctly. Specifically unsuccessful HTTP Error codes needed to be translated into Vala/GLib errors so templates handle them correctly, and a plugin needed to be enabled in order to access an HTTP response's MIMEtype via LibSoup's highlevel API. 

### Concurrency
Implementing `{ % fetch % }` nicely whilst minimizing the performance penalty of communicating back-and-forth over the Internet<sup title="SIDENOTE: Wayland's done a nice job of avoiding a similar performance pitfall by not having it's conversations be near as back-and-forth">4</sup> required good knowledge of how to work with Vala's async methods.

To make this work I wrote the logic of how to fetch and render HTTP responses as it's own seperate async method and ran it concurrently with the main exec method. This took advantage of Vala to make the code read very clearly whilst avoiding all the majour performance concerns.

Also I implemented a couple of synchronization primitives to make this system work. The first, which resembles a semaphore, simply counts down the number of HTTP responses left to receive and when it reaches 0 execution of the rest of the template resumes. And the second is a simple mutex which keeps a flag for whether it's "locked" and before entering a "critical section" (a.k.a. rendering the subtemplate for HTTP responses, as if that unsynchronized it could potentially yield some ugly output) it checks if the mutex is locked. If it is it resumes execution the next time Odysseus is idling and checks again, at which point it will probably pass. Both of these primitives I wrote avoid the performance overhead of threadsafe atomic variables, and only works for the cooperative multitasking of GLib's mainloop.

And they both required use of a special variant of the yield statement.

### Did I Waste My Time Extending Prosody?
I really don't think so, as most of the code I added to prosody would have needed to be written anyways. I needed to fetch multiple URLs concurrently and parse their TSV files. And those things remained the bulk of the code and the trickiest to get working.

Sure a little more work (and rework) was needed to expose this API as syntax rather than an API, but the result is something that's much nicer to work with. Prosody has been a huge convenience for me in developing an increasing amount of Odysseus's UI, as it nicely complements URLs, SQL, and HTML by providing a syntax for moving data between them that simultaneously embeds nicely into them whilst being recognizably distinct from them. And it does a great job of seperating any performance optimization from the UI code.

It's also worth noting that I've found it's rare for an extension I add to Prosody to only be used only on the page I first develop it for, as that expands the UIs I can easily express with the language. And I foresee fetch being no different.

### What's Wrong With the Old Fetch?
My older implementation might've worked fine outside of any subtemplates, but that restriction harmed my ability to reuse existing code and thereby lead to me needing to complicate the `{ % fetch % }` tag. Specifically I would've need to implement a way to control caching in the tag rather than utilizing the preexisting `{ % query % }` tag, and (for the original UI design) I would've needed to implement a way to select just the first successful request without impacting performance more than necessary. 

Specifically the issue was that the old implementation parsed the remainder of the template and held it within itself (which was necessary to pass in an extra variable, and I thought hold up execution long enough), which would not have worked within any subtemplates as those would no longer see their corresponding tags. Instead `{ % fetch % }` would've balked that those tags were not defined in it's API.

In the end I decided it was a better anyways to use all available databases for recommendations, and rather than go about adding in those complexities I instead removed what complexities I had already placed in there.

And while I no longer have any direct way to use access the responses from a `{ % fetch % }` in the rest of the templates, perhaps that's for the best. Perhaps most of that data fits best in a database, afterall using that side-channel worked out very nicely for `odysseus:home`. And I certainly didn't need this technique in order to hold up execution of the remainder of the template.

---

1. But [reducing download size of the recommendations files] can be done seperately from releasing the new update.
2. Which is an appropriate phrase to use on the day the GDPR comes into force within the EU. Though I've already respected your privacy so much I consider the privacy implications of every time Odysseus hits the Internet.
3. I'll blog about the design of this option once I have reason to enable it
4. SIDENOTE: Wayland's done a nice job of avoiding a similar performance pitfall by not having it's conversations be near as back-and-forth
