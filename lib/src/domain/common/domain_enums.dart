enum EventType { casual, formal }

enum EventStatus { upcoming, registration, inProgress, completed, archived }

enum TournamentFormat {
  singleElimination,
  doubleElimination,
  singleRoundRobin,
  doubleRoundRobin,
}

enum CheckInStatus { notPresent, checkedIn }

enum PaymentStatus { unpaid, paid }

enum TeamFormationMethod { manual, random, balanced }

enum MatchStatus { scheduled, queued, inProgress, completed }

enum MatchDependencySource { winner, loser }

enum MatchDestinationSlot { sideOne, sideTwo }
