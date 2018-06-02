---
layout: post
title: App Suggestions — Odysseus Development Blog
posttitle: Encouraging a More Open Web via a Stronger App Ecosystem
header: 2nd Jun 2018 — Adrian Cochrane
date: 2018-06-02 21:54:15 1200
categories: design
---

Native vs Web, it's a heated argument. But perhaps it's not an argument we should be having.

If we want the open web to succeed over centralized platforms, we need the web itself to [take on](https://blogg.forteller.net/2013/first-steps/) some of their features. And native apps can help with that!

Besides if the reason you want the Open Web to succeed is because it's built on open standards, elementary OS is as well. It, and most operating systems other than Windows, Mac OS X, Android, and iOS follow the POSIX and [FreeDesktop.Org standards](https://www.freedesktop.org/wiki/Specifications/). Which means that while Odysseus caters specifically to elementary OS, it should still work great on any of those other systems.

## Extending the Web with native apps
Odysseus has long used native apps to open (most) anything other than a webpage or HTTP(S) link. That is [`mailto:`](https://tools.ietf.org/html/rfc2368) links opens Mail's compose dialog, [`xmpp:`](https://tools.ietf.org/html/rfc5122) links could open an instant messenger, [`magnet:`](https://sourceforge.net/projects/magnet-uri/) links could start the download in [Torrential](appstream://com.github.davidmhewitt.torrential.desktop), etc. This already works today.

But there's an adoption hurdle. If you don't have, say, Torrential installed your `magnet:` won't do anything.

## Fixing the adoption hurdle
It's been [argued before](https://blogg.forteller.net/2013/first-steps/) that the way to fix this adoption problem is to build the features<sup title="Things like feedreaders and instant messaging">1</sup> into the browser. But doing so would significantly increase the complexity of Odysseus, making it harder for you to learn and significantly harder for me to develop. And as such it would detract from me making Odysseus the best web browser I can accomplish, besides it's [against](https://elementary.io/docs/human-interface-guidelines#think-in-modules) the elementary HIG.

So instead I improved the error messages (and error reporting) so that they smooth out this adoption curve a little. Now the relevant error pages show a grid of compatible apps you can install, and clicking on one shows more information about it in your package manager (i.e. the elementary AppCenter).

So now the adoption hurdle is just a single straigtforward decision, and two clicks to get past it. Not that bad!

## Technical details
These app recommendations will work on any operating system<sup title="Specifically relating to the package repository and package manager components">2</sup> which supports the FreeDesktop.Org [AppStream](https://www.freedesktop.org/wiki/Distributions/AppStream/) standard. Which ofcourse includes elementary OS's [AppCenter](appstream://org.pantheon.appcenter.desktop).

Behind the scenes the error messages are implemented as Prosody templates which embeds a new template tag which in turn fetches information from an XML database (as per the AppStream standard) to render via a second Prosody template. Furthermore I used the [MIME Info](https://www.freedesktop.org/wiki/Specifications/shared-mime-info-spec/) standard (another XML database) to show human readable descriptions of these filetypes and URI schemas where possible, and the [Icon Theme](https://www.freedesktop.org/wiki/Specifications/icon-theme-spec/), [Desktop Entry](https://www.freedesktop.org/wiki/Specifications/desktop-entry-spec/), and [MIME Application](https://www.freedesktop.org/wiki/Specifications/mime-apps-spec/) specs to refer to the correct package manager no matter which it is. So while it may look like I'm referring specifically to the AppCenter in Odysseus, I actually am not.

The latter two of those standards are the same ones I've been using all along to open otherwise unknown filetypes and URI schemas.

This all really serves to illustrate that free desktops like elementary OS are fully built on open standards, just as much as the Web. And at no point in developing this feature could I get away from from thinking about at least one open standard.

---

1. Things like feedreaders and instant messaging.
2. Specifically relating to the package repository and package manager components
