/// Bangladesh UGC-style letter-grade points on the 4.0 scale.
double bangladeshUgcGradePoint(double percentage) {
  if (percentage >= 80) return 4.0;
  if (percentage >= 75) return 3.75;
  if (percentage >= 70) return 3.5;
  if (percentage >= 65) return 3.25;
  if (percentage >= 60) return 3.0;
  if (percentage >= 55) return 2.75;
  if (percentage >= 50) return 2.5;
  if (percentage >= 45) return 2.25;
  if (percentage >= 40) return 2.0;
  return 0;
}
