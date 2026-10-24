import 'dart:async';
import 'package:my_app/services/auth_service.dart';
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
  bool approved = true;
  bool failSave = false;
  final List<String> submissions = [];
  final List<Course> courseRows = [];
  final List<Offering> offeringRows = [];
  final List<Exam> examRows = [];
  final List<Json> resultRows = [];
  @override
  Future<Json> profile() async =>
      {'full_name': 'Teacher', 'approved': approved};
  @override
  Future<List<Json>> teachers() async => [
        {
          'id': 'teacher',
          'full_name': 'Teacher',
          'email': 'teacher@example.com',
          'approved': approved
        }
      ];
  @override
  Future<void> approveTeacher(String id, bool value) async {
    approved = value;
  }

  @override
  Future<List<Course>> courses() async => courseRows;
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
      {String? resultId, int? revision}) async {
    submissions.add(submissionId);
    if (failSave) throw StateError('Network unavailable');
    resultRows.removeWhere((r) => r['id'] == resultId);
    resultRows.add({
      'id': resultId ?? 'result',
      'exam_id': context.exam.id,
      'roll_no': context.rollNo,
      'table_type': group,
      'marks': marks,
      'grand_total': 5,
      'revision': (revision ?? 0) + 1
    });
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
