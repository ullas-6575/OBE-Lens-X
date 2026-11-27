import 'dart:async';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/services/result_service.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/repository.dart';

class FakeAuthService implements AuthService {
  final bool signupSession;
  @override
  bool hasSession;
  @override
  final bool isAdmin;
  final events = StreamController<SessionEvent>.broadcast();
  FakeAuthService(
      {this.signupSession = true,
      this.hasSession = false,
      this.isAdmin = false});
  @override
  Stream<SessionEvent> get sessionEvents => events.stream;
  @override
  Future<void> signInWithPassword(
      {required String email, required String password}) async {
    hasSession = true;
  }

  @override
  Future<bool> signUp(
      {required String email,
      required String password,
      required String fullName}) async {
    hasSession = signupSession;
    return hasSession;
  }

  @override
  Future<void> signOut() async {
    hasSession = false;
    events.add(SessionEvent.changed);
  }

  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> updatePassword(String password) async {}
}

class FakeWorkflowRepository implements WorkflowRepository {
  RegistrationStatus status = RegistrationStatus.approved;
  bool failSave = false;
  final List<String> submissions = [];
  final List<Course> courseRows = [];
  final List<Offering> offeringRows = [];
  final List<Exam> examRows = [];
  final List<Json> resultRows = [];
  @override
  Future<Json> profile() async =>
      {'full_name': 'Teacher', 'status': status.name};
  @override
  Future<List<Json>> accounts() async => [
        {
          'id': 'teacher',
          'full_name': 'Teacher',
          'email': 'teacher@example.com',
          'status': status.name
        }
      ];
  @override
  Future<void> setRegistrationStatus(
      String id, RegistrationStatus value) async {
    status = value;
  }

  @override
  Future<List<Course>> courses() async => courseRows;
  @override
  Future<void> deleteCourse(String id) async {
    if (offeringRows.any((offering) => offering.courseId == id)) {
      throw StateError('Course has offerings.');
    }
    courseRows.removeWhere((course) => course.id == id);
  }

  @override
  Future<void> saveCourse(
      {String? id,
      required String code,
      required String title,
      required List<CourseOutcome> outcomes,
      required bool archived}) async {
    courseRows.removeWhere((c) => c.id == id);
    courseRows.add(Course(
        id: id ?? 'course',
        code: code,
        title: title,
        outcomes: outcomes,
        archived: archived));
  }

  @override
  Future<List<Offering>> offerings(String courseId) async =>
      offeringRows.where((o) => o.courseId == courseId).toList();
  @override
  Future<void> addOffering(String courseId, String year, String term) async {
    offeringRows.add(Offering('offering', courseId, year, term));
  }

  final assigned = <String>[];
  @override
  Future<List<String>> assignments(String offeringId) async => assigned;
  @override
  Future<void> assign(String offeringId, String teacherId, bool value) async {
    if (value) {
      assigned.add(teacherId);
    } else {
      assigned.remove(teacherId);
    }
  }

  @override
  Future<List<Exam>> exams(String offeringId) async =>
      examRows.where((e) => e.offeringId == offeringId).toList();
  @override
  Future<void> saveExam(Exam exam) async {
    examRows.removeWhere((e) => e.id == exam.id);
    examRows.add(exam);
  }

  @override
  Future<List<Json>> results(String examId) async =>
      resultRows.where((r) => r['exam_id'] == examId).toList();
  @override
  Future<void> saveMarks(ScanContext context, String submissionId, String group,
      Map<String, Map<String, String>> marks,
      {Json? previous, List<String>? selectedQuestions}) async {
    submissions.add(submissionId);
    if (failSave) throw StateError('Network unavailable');
    final selected =
        context.exam.countedQuestions(group, selectedQuestions, marks);
    if (selected == null) {
      throw const FormatException('Select exactly three questions to count.');
    }
    final total = marks.entries
        .where((q) => selected.contains(q.key))
        .map((q) => q.value)
        .expand((parts) => parts.values)
        .fold<double>(0, (sum, mark) => sum + (double.tryParse(mark) ?? 0));
    final index = resultRows.indexWhere((row) =>
        row['exam_id'] == context.exam.id &&
        row['roll_no'] == context.rollNo &&
        row['table_type'] == group);
    if (index >= 0) {
      final saved = resultRows[index];
      if (savedResultMatches(saved,
              rollNo: context.rollNo,
              tableType: group,
              marks: marks,
              grandTotal: total) &&
          context.exam
                  .countedQuestions(
                      group, saved['selected_questions'], saved['marks'] as Map)
                  ?.join(',') ==
              selected.join(',') &&
          (saved['submission_id'] == submissionId ||
              previous?['id'] == saved['id'] &&
                  saved['revision'] == (previous!['revision'] as int) + 1)) {
        return;
      }
      if (previous?['id'] != saved['id'] ||
          previous?['revision'] != saved['revision']) {
        throw ResultConflict(Json.from(saved));
      }
    }
    final row = {
      if (index >= 0) ...resultRows[index],
      'id': index < 0
          ? 'result-${resultRows.length + 1}'
          : resultRows[index]['id'],
      'submission_id':
          index < 0 ? submissionId : resultRows[index]['submission_id'],
      'exam_id': context.exam.id,
      'roll_no': context.rollNo,
      'table_type': group,
      'selected_questions': selected,
      'marks': marks,
      'grand_total': total,
      'revision': index < 0 ? 1 : (resultRows[index]['revision'] as int) + 1
    };
    if (index < 0) {
      resultRows.add(row);
    } else {
      resultRows[index] = row;
    }
  }
}

const sampleCourse = Course(
    id: 'course',
    code: 'CSE3200',
    title: 'Software Engineering',
    outcomes: [
      CourseOutcome('CO1', 'Apply engineering principles', ['PO1'])
    ]);
const sampleOffering = Offering('offering', 'course', '2026', 'Term 1');
const sampleExam = Exam(
    id: 'exam',
    offeringId: 'offering',
    name: 'Final',
    requiredGroups: ['1-4'],
    questions: [QuestionMapping('1', 'a', 'CO1', 10)]);
FakeWorkflowRepository seededRepository() => FakeWorkflowRepository()
  ..courseRows.add(sampleCourse)
  ..offeringRows.add(sampleOffering)
  ..examRows.add(sampleExam);
