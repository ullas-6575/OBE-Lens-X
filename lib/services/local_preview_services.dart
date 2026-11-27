import 'dart:async';

import 'auth_service.dart';
import 'result_service.dart';
import '../workflow/models.dart';
import '../workflow/repository.dart';

class LocalPreviewAuthService implements AuthService {
  final _events = StreamController<SessionEvent>.broadcast();

  @override
  bool hasSession = true;

  @override
  bool get isAdmin => true;

  @override
  Stream<SessionEvent> get sessionEvents => _events.stream;

  @override
  Future<void> signOut() async {
    hasSession = false;
    _events.add(SessionEvent.changed);
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    hasSession = true;
    _events.add(SessionEvent.changed);
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    hasSession = true;
    _events.add(SessionEvent.changed);
    return true;
  }

  @override
  Future<void> resetPassword(String email) async {}

  @override
  Future<void> updatePassword(String password) async {}
}

class LocalPreviewWorkflowRepository implements WorkflowRepository {
  static const _teacherId = 'preview-teacher';
  static const _courseId = 'preview-course';
  static const _offeringId = 'preview-offering';
  static const _examId = 'preview-exam';

  final List<Course> _courses = [
    const Course(
      id: _courseId,
      code: 'CSE3200',
      title: 'Software Engineering',
      outcomes: [
        CourseOutcome('CO1', 'Apply engineering principles', ['PO1']),
        CourseOutcome('CO2', 'Design and evaluate solutions', ['PO2']),
        CourseOutcome('CO3', 'CO3', []),
        CourseOutcome('CO4', 'CO4', []),
      ],
    ),
  ];
  final List<Offering> _offerings = [
    const Offering(_offeringId, _courseId, '2026', 'Term 1'),
  ];
  final List<Exam> _exams = [
    const Exam(
      id: _examId,
      offeringId: _offeringId,
      name: 'Final',
      requiredGroups: ['1-4'],
      questions: [
        QuestionMapping('1', 'a', 'CO1', 10),
        QuestionMapping('2', 'a', 'CO2', 10),
      ],
    ),
  ];
  final Set<String> _assignedTeachers = {_teacherId};
  final List<Json> _results = [];
  int _nextId = 1;

  final List<Json> _accounts = [
    {
      'id': 'preview-teacher',
      'full_name': 'Preview Teacher',
      'email': 'teacher@example.com',
      'status': 'approved',
    },
    {
      'id': 'preview-pending',
      'full_name': 'Nadia Rahman',
      'email': 'nadia@example.com',
      'status': 'pending',
    },
  ];

  @override
  Future<Json> profile() async => {
        'id': _teacherId,
        'full_name': 'Local Preview Admin',
        'email': 'preview@example.com',
        'status': 'approved',
      };

  @override
  Future<List<Json>> accounts() async => _accounts
      .map((account) => Map<String, dynamic>.from(account))
      .toList(growable: false);

  @override
  Future<void> setRegistrationStatus(
      String id, RegistrationStatus status) async {
    for (final account in _accounts) {
      if (account['id'] == id) account['status'] = status.name;
    }
  }

  @override
  Future<List<Course>> courses() async => List.unmodifiable(_courses);

  @override
  Future<void> deleteCourse(String id) async {
    if (_offerings.any((offering) => offering.courseId == id)) {
      throw StateError(
          'This course has offerings and cannot be deleted while they exist.');
    }
    _courses.removeWhere((course) => course.id == id);
  }

  @override
  Future<void> saveCourse({
    String? id,
    required String code,
    required String title,
    required List<CourseOutcome> outcomes,
    required bool archived,
  }) async {
    final courseId = id ?? 'preview-course-${_nextId++}';
    _courses.removeWhere((course) => course.id == courseId);
    _courses.add(Course(
      id: courseId,
      code: code.trim(),
      title: title.trim(),
      outcomes: List.unmodifiable(outcomes),
      archived: archived,
    ));
  }

  @override
  Future<List<Offering>> offerings(String courseId) async => _offerings
      .where((offering) => offering.courseId == courseId)
      .toList(growable: false);

  @override
  Future<void> addOffering(String courseId, String year, String term) async {
    _offerings.add(Offering(
        'preview-offering-${_nextId++}', courseId, year.trim(), term.trim()));
  }

  @override
  Future<List<String>> assignments(String offeringId) async =>
      _assignedTeachers.toList(growable: false);

  @override
  Future<void> assign(
      String offeringId, String teacherId, bool assigned) async {
    if (assigned) {
      _assignedTeachers.add(teacherId);
    } else {
      _assignedTeachers.remove(teacherId);
    }
  }

  @override
  Future<List<Exam>> exams(String offeringId) async => _exams
      .where((exam) => exam.offeringId == offeringId)
      .toList(growable: false);

  @override
  Future<void> saveExam(Exam exam) async {
    final id = exam.id.isEmpty ? 'preview-exam-${_nextId++}' : exam.id;
    _exams.removeWhere((saved) => saved.id == id);
    _exams.add(Exam(
      id: id,
      offeringId: exam.offeringId,
      name: exam.name,
      questions: List.unmodifiable(exam.questions),
      requiredGroups: List.unmodifiable(exam.requiredGroups),
      policy: exam.policy,
      revision: exam.revision + 1,
    ));
  }

  @override
  Future<List<Json>> results(String examId) async => _results
      .where((result) => result['exam_id'] == examId)
      .map((result) => Map<String, dynamic>.from(result))
      .toList(growable: false);

  @override
  Future<void> saveMarks(ScanContext context, String submissionId, String group,
      Map<String, Map<String, String>> marks,
      {Json? previous, List<String>? selectedQuestions}) async {
    final error = context.validateMarks(group, marks);
    if (error != null) throw FormatException(error);
    final selected =
        context.exam.countedQuestions(group, selectedQuestions, marks);
    if (selected == null) {
      throw const FormatException('Select exactly three questions to count.');
    }

    final index = _results.indexWhere((result) =>
        result['exam_id'] == context.exam.id &&
        result['roll_no'] == context.rollNo &&
        result['table_type'] == group);
    var total = 0;
    for (final column in marks.entries
        .where((q) => selected.contains(q.key))
        .map((q) => q.value)) {
      for (final mark in column.values) {
        total += int.tryParse(mark) ?? 0;
      }
    }
    if (index >= 0) {
      final saved = _results[index];
      final matches = savedResultMatches(saved,
          rollNo: context.rollNo,
          tableType: group,
          marks: marks,
          grandTotal: total.toDouble());
      if (matches &&
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
        throw ResultConflict(Map<String, dynamic>.from(saved));
      }
    }
    final row = <String, dynamic>{
      'id': index < 0 ? 'preview-result-${_nextId++}' : _results[index]['id'],
      'submission_id':
          index < 0 ? submissionId : _results[index]['submission_id'],
      'exam_id': context.exam.id,
      'roll_no': context.rollNo,
      'table_type': group,
      'selected_questions': selected,
      'marks': {
        for (final entry in marks.entries)
          entry.key: Map<String, String>.from(entry.value),
      },
      'grand_total': total,
      'revision': index < 0 ? 1 : (_results[index]['revision'] as int) + 1,
    };
    if (index < 0) {
      _results.add(row);
    } else {
      _results[index] = row;
    }
  }
}
