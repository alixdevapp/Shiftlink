// Les applis de suivi où ShiftLink peut envoyer une sortie (.fit).
enum SendTarget {
  garmin('Garmin Connect'),
  intervals('Intervals.icu');

  final String label;
  const SendTarget(this.label);
}

enum SendStatus { sent, duplicate }
