---
layout: post
title: Prosody Refactor — Odysseus Development Blog
posttitle: Refactoring and Optimizing Prosody
header: 31st May 2018 — Adrian Cochrane
date: 2018-05-31 23:31:31 1200
categories: dev
---

I've spent the last few days making Prosody's code read better, with there being two dominant changes. Both of which would also decrease Odysseus's CPU and memory usage (Note: I haven't measured this, but the latter of these makes a difference on human-visible timescales). And both of which serves as great illustrations of some Computer Science concepts.

## new `Data.Let`
When dealing with small amounts of data it is [often more efficient](https://trac.webkit.org/browser/webkit/trunk/Source/WTF/wtf/BubbleSort.h#L31) to use datastructures that Computer Science considers inefficient. This is because those more efficient algorithms generally have setup costs that often aren't worth it at those scales. Until now this was exactly the case for Prosody.

Previously Prosody used a [hashmap](https://webkit.org/blog/6/hashtables-part-1/) to [store it's variables in](https://github.com/alcinnz/Odysseus/blob/931027dd14211ba7d9d3d1d62d1ec1a53cd53a70/src/Services/Prosody/data.vala#L227), and then in order to define new variables for within a "subtemplate" it'd overlay one hashmap [ontop of another](https://github.com/alcinnz/Odysseus/blob/931027dd14211ba7d9d3d1d62d1ec1a53cd53a70/src/Services/Prosody/data.vala#L285). That is it'd add a wrapper which whenever it fails to lookup a value in one hashmap it'll look it up in a fallback.

And while that code is still very useful, I replaced most of it's uses with a ligherweight "[parallel linked-list](https://github.com/alcinnz/Odysseus/blob/931027dd14211ba7d9d3d1d62d1ec1a53cd53a70/src/Services/Prosody/data.vala#L364)". That is it checks each variable in turn for a match. And, to make it easy to add new variable contexts, it represents this list by having variable reference the next one.

And not only is this computationally more efficient, but it slightly reduces the number of method calls Odysseus makes that CPUs [struggle to optimize](https://webkit.org/blog/189/announcing-squirrelfish/)<sup title="Though if I really wanted to make dent that way, I'd have reimplemented the interpretor.">1</sup>, and vitally it can be easier for other code to construct.

## Goodbye [`GLib.Bytes`](https://valadoc.org/glib-2.0/GLib.Bytes.html), Hello `Slice`
This is the bigger change, and the one which made all the difference in terms of performance. To be honest I can't really tell that `Data.Slice` actually made a difference in terms of performance, I just know it theoretically would have. It is also the trickiest to explain.

But in a nutshell I replaced every use of [`GLib.Bytes`](https://gitlab.gnome.org/GNOME/glib/blob/master/glib/gbytes.c) inside Prosody and the broader Odysseus codebase with a newly written wrapper I called `Slice`, which worked better with Vala's [syntactic sugar](https://www.syntacticsugar.org/) and [LibGee](https://valadoc.org/gee-0.8/Gee.html) collections library.

### The Problem
The issue was actually in Vala's [bindings to GLib](https://gitlab.gnome.org/GNOME/vala/blob/90b7a26ed6d74cc2d2371ffd4108ebad3b8bc98d/vapi/glib-2.0.vapi#L5028). That is it added a `slice` (which the Vala language provides syntactic sugar for) method was I expected to be implemented thus:

    new GLib.Bytes.from_bytes(this, start, end - start);

Whereas it was actually implemented as:

    unowned uint8[] data = this.get_data ();
    return new GLib.Bytes (data[start:end]);

What's the big deal? It's that, with Prosody's frequency of use, `data[start:end]` became a [performance bottleneck](https://www.apicasystems.com/blog/5-common-performance-bottlenecks/). How so?

Well, Vala compiles that little bit of code to something [akin](https://gitlab.gnome.org/GNOME/vala/blob/90b7a26ed6d74cc2d2371ffd4108ebad3b8bc98d/codegen/valaccodearraymodule.vala#L193) [to](https://gitlab.gnome.org/GNOME/vala/blob/90b7a26ed6d74cc2d2371ffd4108ebad3b8bc98d/codegen/valaccodearraymodule.vala#L419):

    int _ret_0_length = end - start;
    byte* _ret_0 = data + start;
    byte* _ret_1 = malloc(_ret_0_length);
    memcpy(_ret_1, _ret_0, sizeof(byte) * _ret_0_length);

The issue is all of those [malloc()](https://sourceware.org/git/?p=glibc.git;a=blob;f=malloc/malloc.c;h=96149549758dd424f5c08bed3b7ed1259d5d5664;hb=HEAD#l44) and [memcpy()](https://sourceware.org/git/?p=glibc.git;a=blob;f=sysdeps/i386/memcpy.S;h=0f8719087c33e018ec4bba45254900494b1db25c;hb=HEAD#l56) calls. Because malloc needs to look through it's collection of free memory for something large enough or failing that take the performance hit of communicating to the kernel so it can do the same. And memcpy has to process every single character in the slice one-more-time. All on hardware which operates on a single fixed-size (vectorized) number at a time, and gets frustrated waiting on RAM which is just so (relatively) sloooooooooow.

### The Fix
This whole problem is caused by the Vala compiler not trusting that the memory being sliced will remain valid. Heck, the two function calls I'm wanting to avoid are generated not when a slice is performed but when the result is handed to other code.

But for Prosody this issue is barely even a concern, simply because the templates it parses are *always* in memory for as long as Odysseus is running. But ignoring memory management issues can be **disastrous**, and besides I don't think Vala can be convinced to do so. Then again if I was using a language like Rust, [it would've realized](https://doc.rust-lang.org/book/second-edition/ch10-03-lifetime-syntax.html) this copying isn't neccessary and thus not compile any code for it.

As it turns out I was already aware of this potential issue and that was the whole reason I was using `GLib.Bytes`. It's a [GObject class](https://developer.gnome.org/gobject/stable/chapter-gobject.html) that wraps a bytearray with some very minor memory management that keeps the array it's slicing alive.

So I wrapped the `GLib.Bytes` in a new class with the `slice` implementation I expected, and while I was at it I added other syntactic sugars, methods, etc to make all it's callers more readable. Making this switch was a large undertaking because of how widely used `GLib.Bytes` is in Prosody and to a lesser extent Odysseus at large. And sure, I could've instead switched from calling `slice()` to `new GLib.Bytes.from_bytes()` but then it would've been easier to overlook code that needed to be changed and there'd always be a temptation to use the former due to it's concise syntax. Besides Prosody's source code is much more readable now!

#### But what about allocating `GLib.Bytes`?
Good question! As it turns out all `GLib.Bytes` objects are the same size, which allows GLib to confidently allocate several of them at a time. That way when Prosody requires a new Bytes object one will almost always have been allocated for it already, requiring just a single fetch from memory.

This technique is in very heavy use across all GObject-based libraries, and any Vala program. In fact this technique is, in theory, the main reason that (as *elementary* has found) apps written in Vala start much faster than those written in Python.

And if you're concerned about the templates' source code being in memory at all times, they're theoretically more concise in source form than executable form. So I save memory by not compiling them. Also this way the templates are compacted tighter together and are loaded into physical memory on-demand in a single disk-fetch. 

### Summary
Previously Odysseus was wasting lots of time allocating memory it didn't really need, beyond Vala's distrust in how long the template's source code will remain in memory. Which was unneccessary because those templates are compiled into Odysseus's executable. I thought I was using an API that would avoid this issue, but it turned out it was implemented using the exact code I was trying to avoid.

I was using the right class though, so I switched all uses of that class with a new wrapper that worked nicer with Vala and fixed the issue. Doing it that way made sure I fixed all related performance problems and made Odysseus's code easier to read.

Now whenever Prosody references some text from a template, it does so in only a very small handful of operations that take near-constant time. Not only that but those operations occur almost entirely in the CPU leaving memory access very linear, which is generally easier on the CPU's cache.

I can't entirely guarantee that there aren't regressions arising from this, so I'll hold off a little until I can do a proper feature release. At such point I should've caught all bugs.

---

1. Though if I really wanted to make dent that way, I'd have reimplemented the interpretor.
2. C doesn't worry about this at all, which just makes it harder on those who use that language and is a common source of security vulnerabilities.
