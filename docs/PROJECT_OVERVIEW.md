# Project Overview

## Purpose and community context

The Community Pickleball Management System addresses the practical work of a
small local pickleball community that initially operates one court. Organizers
need one consistent place to prepare events, know who is present and paid,
create temporary teams, run matches in an orderly court queue, and retain
results after play ends. Community members and guests need a reliable view of
current play, upcoming events, completed events, players, and results.

The product supports both quick, casual one-day or winner-takes-all events and
more formal tournaments. Formal events can optionally use divisions such as
Men, Women, Kids, Seniors, Mixed, and Open. An event does not need to have every
division.

## Users, access, and connectivity

- A **guest** may read public tournament and player information but may not
  modify it.
- A **player** is a permanent community record and does not need an account to
  participate.
- A player may optionally have an authenticated account linked later through a
  secure claim process. Linking must preserve the existing player's history.
- An **organizer** is an authenticated user with an explicit role or
  permission. Organizers can manage tournaments.
- Android is the primary, offline-first organizer platform. Important organizer
  work must remain available without connectivity and synchronize later.
- The iPhone experience is an online-first Flutter Web/PWA used through Safari.
  Authenticated iPhone organizers can manage tournaments while online; they are
  not restricted to view-only access.

## Players, participation, and teams

Players are created once in the permanent community directory and reused
across events. Event participation associates a player with an event and, when
applicable, a division. Check-in determines who is present and eligible for
team or match generation.

Teams are temporary event/division records rather than permanent identities.
Version 1 supports manual team formation, random generation, and simple
balanced generation based on approved player skill information. Balanced
generation uses simple application logic, not an AI feature. The precise
skill scale and team-size rule remain open decisions.

Payments happen outside the application. The system records only `Paid` or
`Unpaid` status and related totals; it does not process money.

## Events and tournament operation

The Version 1 event lifecycle is:

`UPCOMING` → `REGISTRATION` → `IN PROGRESS` → `COMPLETED` → `ARCHIVED`

Only these tournament formats are approved for Version 1:

1. Single Elimination.
2. Double Elimination.
3. Single Round Robin.
4. Double Round Robin.

The single-court workflow must prominently show **Now Playing** and **Up Next**
and progress the queue across the approved formats. Scores and finalized
results drive bracket progression, round-robin standings, placements, history,
and statistics, subject to rules that are still recorded as open decisions.

## History and statistics

Completed events become historical records and are preserved rather than
deleted. Match records are the statistical source of truth where practical.
Statistics distinguish:

- Match wins and losses.
- Tournament appearances.
- Championships.
- Runner-up finishes.
- Overall individual player performance.
- Performance with each temporary partner.

Individual statistics and partner statistics are separate. Opponent
head-to-head statistics are not part of Version 1.

## Version 1 exclusions

Version 1 does not include:

- Payment processing, GCash integration, or credit/debit card processing.
- Native App Store iPhone distribution or native iPhone offline support.
- Paid infrastructure.
- AI application features.
- Chat, messaging, or social networking.
- Complex ranking systems, achievements, or badges.
- Opponent head-to-head statistics.
- Push notifications.
- Tournament formats beyond the four approved formats.

## Cost constraint

The project must remain cost-free in Version 1. It uses free-tier
infrastructure, a directly distributed Android APK, and a Flutter Web/PWA on a
free static host. The hosting provider remains an open decision.
