---
layout: post
title: New First-launch Site — Odysseus Development Blog
posttitle: New First-launch Site
header: 17th 2018 — Adrian Cochrane
date: 2018-05-17 17:03:41 1200
categories: dev
---

On first launch if an elementary app doesn't have any other data to show [it should highlight some options](https://elementary.io/docs/human-interface-guidelines#first-launch-experience) for loading data into the app. The way you load [data](odysseus:history) into Odysseus is by simply surfing the web, so to follow that principle I've designed a [website](https://alcinnz.github.io/Odysseus-recommendations/) with a bunch of links to start your websurfing on.

And while I was slowed down by a sickness, over the last while I've been redesigning that site to make it more helpful for it's purpose, nicer and more minimal looking, and easier for me to maintain. Very simply what I changed was to add more scripting, and now not only do you have a nice simple page full of a random sampling of links illustrated by a screenshot of their destinations, but all I have to maintain are those web addresses.

This scripting comes both in the form of in-page JavaScript (due to limitations of GitHub pages), as well as a script to take those screenshots using the exact same technologies as Odysseus itself. The latter did involve some involve some tricky error handling. In particular I had to deal with "connection timeouts" on a random sampling of webpages, which I handled by trying reloading the page up to three times.

I hope that having a random sampling will do a better job encouraging you to explore, and that the screenshots will do a better job representing those links whilst making them look more intriguing.

Finally these links are intended as an aid to start your web surfing in Odysseus, and in hopes of garnering your trust for that I'm specifically excluding any paid sponsershops if/when they will occur. And tommorrow I will make this dataset further fulfill it's purpose for longer by incorporating it into [the new tab page](odysseus:home).
