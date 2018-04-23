---
layout: post
title: Replacing The DOM — Odysseus Development Blog
posttitle: Let's Replacing JavaScript With Something Better — For Page Manipulation
header: 21st April 2018 — Adrian Cochrane
date: 2018-04-21 21:34:53 1200
categories: misc post-js
---

This post is a reply to [Let's Replace JavaScript With Something Better](https://john.ankarstrom.se/english/texts/replacing-javascript/), so I'll expect you to have read it first. Did you read it? Good. Let's procede!

In that artical John Ankarström suggested it may be time to consider how we might replace JavaScript with something less vulnerable to [surveillance](https://www.eff.org/issues/online-behavioral-tracking), [CPU bugs](https://webkit.org/blog/8048/what-spectre-and-meltdown-mean-for-webkit/), and other [undesirables](https://better.fyi/sites/forbes.com/). To do so he proposed we extend HTML with a special kind of link which inserts it's response into the current webpage, and for CSS to be extended to allow style rules to be made conditional on the presence of another selector. With these proposals we should be able to readily replace most, but not all, non user-hostile JavaScripts present on the Web. But to get us the rest of the way, Ankarström left an open question of how to replace JavaScript for the purposes of manipulating the page in response to user input. 

I intend to answer that open question in this blog post.

## Aside: The user confirmation quandary
There are several UI design constraints on how to confirm any dynamic HTTP requests a page makes without resulting in confirmation blindness. Specifically:

1. The confirmation click must be the [same click](http://alistapart.com/article/neveruseawarning) (or other interaction) that would trigger the confirmation box. Because our human ability to form habits will make that the same gesture anyways.
2. It must be [impossible](https://textslashplain.com/2017/01/14/the-line-of-death/) for the page to (fully) recreate the look of the confirmation messages.
3. It should be nonobtrusive enough to not get in the reader's way.
4. It must communicate clearly what that click will do.

As such I will propose that the best visual effect to achieve all of this would be to gray out the entire window (including any browser controls) the page is viewed on except the highlighted elements.

## Security Model
When replacing JavaScript it's important not only to consider what we want to keep, but what we do not want to keep. As such I would want to place down the following rules for building interactive webpages.

1. It should impossible to obscure one element with another except in response to a click event.
2. The reader must be aware of the results of any computation, anything else would just be draining their battery.
3. The interaction must be triggered by the reader.
4. This must be fully sandboxed to a given subsection of the page.
5. I will assume that most potential security vulnerabilities rely on Turing completeness and predictable control flow.

## Preventing user-hostile modal boxes
User hostile modal displays are really more the fault of CSS than they are of JavaScript, though JS does make them more annoying. So I popose that we deprecate the [`position`](https://developer.mozilla.org/en-US/docs/Web/CSS/position) property in favour of flex and grid layouts, as well as a minor extension to Ankarström's suggested Ajax interface.

That extension would be two new HTML attributes (`modal=`selector & `transient=`selector) as well as one CSS property (`transient-side:` atop, above, below, left, right, or aside). If you're familiar with his proposal, mine should be quite natural to understand.

## Interactive page snippets
The [myriad](http://todomvc.com/) of JavaScript frameworks suggests a partial solution to this: you manipulate your webpages the same way you generate them. By using a template. And just combining it with a simple URI routing syntax (that I'll describe later) would make it very useful, as it could intercept HTTP requests in order to take computational load off the server whereever possible.

But it does not get us all the way there. It would not allow for implementing useful controls like [slippy maps](http://leafletjs.com/), [text editting](https://codemirror.net/), and [tokenized inputs](http://loopj.com/jquery-tokeninput/). For that we need to design a syntax for processing input gestures into data that can be embedded into the template, ideally without making them two entirely different languages. The best inspiration I have to guide that is [Rx.js](https://github.com/Reactive-Extensions/RxJS) and the [Reactive Functional Programming](https://gist.github.com/staltz/868e7e9bc2a7b8c1f754) paradigm it implements.

Essentially RFP involves treating events as a datastructure rather than as control flow, so you can describe the transfomations on them as a [pipeline](https://en.wikipedia.org/wiki/Software_pipelining) of operations rather than as mutations of some global variables. And at it's most basic these operations involve:

* scan - combines the most recent value with the running "sum" of all previous values according to some given function.
* merge - combine two streams so the most recent event in the output stream is the most recent event amongst all it's input streams.
* map - applies a function to each event in it's input so as to compute it's output events.
* mergeLatest - combines two streams so that each output event always contains the latest events from both of it's inputs.
* filter - excludes events from a stream based on a given condition.
* just - generates a stream with a single given event.

If we have automatic conversions between streams and non-varying values we'd almost automatically have brought *mergeLatest*, *map*, and *just* into the language's syntax in a very declarative manor, resulting in a language which just looks like a templating language with access to the latest input events. Add in a special name (say, `_`) for the last computed value from an expression to naturally incorporate the *scan* operation, and if we say `undefined` (which'll arise anyways simply by a desire to not to bother visitors with developer errors) values are excluded from streams we'd have incorporated `filter` as well. Which would just leave us with having to define an operator for *merge*.

### Data Model
As for how data is represented in those streams, we'd need to consider what data will most frequently be operated upon in this language. And the answer there is that the input would come in as various numbers for different aspects of the event (as per JavaScript), and the output would be a hierarchy combining strings and XML-like nodes. Then for when we're using templates to intercept requests, we'd want to trivially access it's path components and it's query parameters.

This suggests to me that the data model should consist of "structures" which consists of a type, named fields, and a list of children; where most of the leaves of this hierarchy would be numbers. There would be a literal syntax for strings but really that'd be syntactic sugar for a structure containing a list of numbers. And ofcourse variables and fields could be marked as containing time-varying values which'll cause the coercions I described previously.

### Syntax
The language's syntax would be half-way between a functional language and a templating language, sort-of like [Elm](http://elm-lang.org/). That is it'd have at it's core syntax to define variables (which don't vary unless they're time-varying based on input) for use in the following expression and syntax to call functions. Furthermore it'd have operators to process time-varying values, numbers, and structures (as defined in the data model), as well as syntax for constructing values of those types. But for the most part the power of time-varying values would come not from operators upon them but their implicit conversion from and to constant values. Because then you can write your code without worrying about handling changes in those values, and everything would just work.

To obtain input this language's API would provide functions representing the different events which take a CSS selector and return a stream of data representing a particular type of interaction upon elements matching that selector. And thereby it'll combine all the strengths of this language with some of those of CSS.

To extend this syntax for convenient abstractions and conditionals, I'd allow those variable declarations to take arguments (thereby marking them functions) and allowing them to [pattern match](https://en.wikipedia.org/wiki/Pattern_matching) upon them (which'll have concise condition syntax for numeric ranges, and destructuring structures). That could make for a great URL routing syntax! Perhaps I'd even allow functions to be incorporated into the data model and introduce a lambda syntax so that I can define a *scan*/*map*/*filter* operator for time-varying values.

### Toying with Turing completeness
Once we have that syntax, it's worth noting it takes hardly anything to make this language Turing complete. As long as I allow recursion then developers would be able to compute anything. But that might not be a good thing, as then they can code viruses. So if we were to allow recursion, I'd suggest for the sake of security and performance that:

1. Browsers should only compute what is necessary to render the page.
2. Browsers should randomize the remaining order of execution to head off a potentially large class of security vulnerabilities.
3. If recursion is used to compute a visible element, it should first render as a disclosure button the reader has to click to see the results of the computation.
4. That disclosure indicator should be capable of starting and stopping the program per the whims of the reader.

It'd be interesting how far we could go without needing Turing completeness, though it's hard to imagine any standard library for this language could get by without it.

### Custom elements
Most uses of JavaScript that aren't covered by Ankarström involve creating custom controls to embed on webpages, and to aid the use of those controls I propose that not only should it be possible to use this language to implement interactive sections of webpages or intercept HTTP requests, but to define behaviours for new elements. These controls could most easily be imported and used by utilizing [XML's namespacing syntax](http://xmlmaster.org/en/article/d01/c10/).

And as for defining these controls, it'd be very easy to write it as an expression which pattern matches the elements it's replacing.

### Example syntax

Finding a reasonably simple example to demonstrate this proposed language's syntax is difficult, because it's intended to replace the relatively complex JavaScripts. However for some sort of Hello World, I'll demonstrate a click counter:

    <script type="text/dhtml">{button}["Clicked ", click "button" @\ -> _ + 1, " times"]</script>

Yay! It's a one-liner!

### Benefits
This new language would give webdevs a syntax that removes the burden of various performance considerations. Right out-of-the gate they wouldn't need `requestAnimationFrame`, `setTimeout(cb, 0)`, `new Worker(script)`, or necessarily care which order the events came in; as a simple JIT can easily handle all those optimizations for them. And nor would syntax-highlighting online code editors like CodeMirror need to worry about the performance impact of reformatting the entire source code for every edit - the browser would just handle it itself. And perhaps it'll even read nicer.

For browsers it gives them more flexibility in optimizing away the computation for these gestures and templating, as well as for handling any security vulnerability. All whether or not we allow this language to be turing complete. And if we do allow Turing completeness, the language would allow browsers to block any background computation and give the user the option to stop anything that's taking too long. This is all because due to it's [Functional Programming paradigm](https://maryrosecook.com/blog/post/a-practical-introduction-to-functional-programming) the order of execution would be fully in the control of the browser and not the script.

## Conclusion
In extending John Ankarström's proposals to create a future beyond JavaScript, I propose that:

* Graying out the *entire* browser window except some highlighted elements may be the most effective visual effect for confirming requests without causing any permission blindness.
* His Intercooler-inspired interface for dynamic HTTP requests should be extended to be the *only* way to create visual overlays, such that they can't get overly annoyting.
* And a new language should be added for declaring interactive sections of the page.

This new language would be in part a templating language with it's own HTML syntax (such that < & > are available for use in expressions and the element's body can be a sequence of expressions), and in part a reactive functional language that understands CSS selectors. That way it'd be strong at both the inputs and outputs it'd commonly have to deal with.

It'd be trivial to make such a language Turing complete or not, and even if we did it'd be easy to ensure all processing is relevent to whatever gets displayed. And perhaps it'd even be possible to head off most software/hardware vulnerabilities with the browser's control over the order of execution, though maybe that's wishful thinking.

But in the end, I don't really care whether these suggestions are taken up or not. What I care about is contributing to this important conversation.
